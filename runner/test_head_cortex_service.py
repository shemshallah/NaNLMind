import hashlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from runner.head_cortex_service import HeadCortexService, canonical


def invoke(app, path="/v1/head-cortex/process", method="POST", payload=None, token="t" * 40):
    raw = b"" if payload is None else canonical(payload)
    environ = {"REQUEST_METHOD": method, "PATH_INFO": path,
               "CONTENT_LENGTH": str(len(raw)), "wsgi.input": io.BytesIO(raw),
               "HTTP_AUTHORIZATION": "Bearer " + token}
    captured = {}
    def start_response(status, headers):
        captured["status"] = status
    body = b"".join(app(environ, start_response))
    return captured["status"], json.loads(body.decode("utf-8"))


def package():
    value = {
        "schema": "nanlm.hermes-evidence-package", "version": 1,
        "purpose": "EVIDENCE_COGNITION", "scratch_id": "test",
        "scratch_revision": "a" * 64, "question": "What is claimed?",
        "truth_states": ["TRUE", "FALSE", "UNKNOWN", "CONFLICT"],
        "evidence_entries": [{
            "entry_id": "entry-1", "lane": "evidence_atoms", "writer": "hermes",
            "revision": "b" * 64, "payload": {
                "subject": "source-a", "predicate": "states_claim",
                "object": "The river flows.", "source_digest": "c" * 64,
                "resolution": 5,
            },
        }],
        "result_type_semantics": {},
        "policy": {"clocked_outputs_are_teacher_observations": True,
                   "clocked_outputs_are_not_ground_truth": True,
                   "unknown_is_not_false": True, "conflict_is_not_averaged": True},
    }
    value["package_sha256"] = hashlib.sha256(canonical(value)).hexdigest()
    return value


class HeadCortexServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.state = root / "state.nmg"
        self.state.write_bytes(b"immutable-native-state")
        self.binary = root / "fake-native"
        self.binary.write_text(
            "#!/usr/bin/env python3\n"
            "print('relation_eval schema=N16REL-EVAL/1 generation=12 state_digest=' + 'd'*64 + ' rows=1')\n"
            "print('relation_eval_row index=0 head=42 votes=7 truth_state=TRUE rule=3')\n"
            "print('relation_eval_row index=1 head=43 votes=6 truth_state=TRUE rule=2')\n",
            encoding="utf-8")
        self.binary.chmod(0o755)
        self.app = HeadCortexService(str(self.binary), str(self.state), "t" * 40)
        self.before = hashlib.sha256(self.state.read_bytes()).hexdigest()

    def tearDown(self):
        self.tmp.cleanup()

    def test_read_only_inference_returns_relation_graph(self):
        status, result = invoke(self.app, payload=package())
        self.assertEqual(status, "200 OK")
        self.assertEqual(result["schema"], "nanlm.head-cortex-response")
        self.assertEqual(result["generation"], 12)
        self.assertEqual(result["truth_state"], "TRUE")
        self.assertEqual(result["relations"][0]["head_id"], 42)
        self.assertEqual(result["relations"][0]["premises"], ["entry-1"])
        self.assertTrue(result["provenance"]["read_only"])
        self.assertEqual(hashlib.sha256(self.state.read_bytes()).hexdigest(), self.before)

    def test_answer_draft_is_processed_as_native_relation_input(self):
        value = package()
        value["purpose"] = "ANSWER_VALIDATION"
        value["evidence_entries"].append({
            "entry_id": "draft-1", "lane": "hermes_synthesis", "writer": "hermes",
            "revision": "e" * 64, "payload": {"draft": "The river flows."},
        })
        unsigned = dict(value)
        unsigned.pop("package_sha256")
        value["package_sha256"] = hashlib.sha256(canonical(unsigned)).hexdigest()
        status, result = invoke(self.app, payload=value)
        self.assertEqual(status, "200 OK")
        self.assertTrue(result["provenance"]["answer_draft_processed"])
        draft_rows = [row for row in result["relations"] if row["predicate"] == "asserts_claim"]
        self.assertEqual(len(draft_rows), 1)
        self.assertEqual(draft_rows[0]["subject"], "hermes_answer")
        self.assertEqual(draft_rows[0]["coverage_signal"], "heuristic_only")

    def test_clocked_endpoint_outputs_become_boolean_relation_atoms(self):
        value = package()
        value["evidence_entries"] = [
            {"entry_id": "grounding-1", "lane": "clocked_result", "writer": "clocked",
             "revision": "1" * 64, "payload": {
                 "endpoint": "grounding", "source_id": "source-a", "status": "ok",
                 "result_type": "grounding", "result": {"verdict": "supported",
                     "fields": {"verdict": "supported", "grounded": True, "score": 0.91}},
                 "provenance": {"input_sha256": "a" * 64}}},
            {"entry_id": "compare-1", "lane": "clocked_result", "writer": "clocked",
             "revision": "2" * 64, "payload": {
                 "endpoint": "compare", "source_id": "cross-source", "status": "ok",
                 "result_type": "compare", "result": {"fields": {
                     "verdict": "partial_conflict", "agreement": 0.6,
                     "conflicts": ["claim-2"]}},
                 "provenance": {"input_sha256": "b" * 64}}},
        ]
        unsigned = dict(value)
        unsigned.pop("package_sha256")
        value["package_sha256"] = hashlib.sha256(canonical(unsigned)).hexdigest()
        status, result = invoke(self.app, payload=value)
        self.assertEqual(status, "200 OK")
        self.assertEqual(len(result["relations"]), 2)
        self.assertEqual(result["relations"][0]["predicate"], "clocked_grounding_observation")
        self.assertIn("grounded", result["relations"][0]["object"])
        self.assertEqual(result["relations"][1]["predicate"], "clocked_compare_observation")
        self.assertIn("partial_conflict", result["relations"][1]["object"])
        self.assertEqual(result["provenance"]["source_entry_ids"],
                         ["grounding-1", "compare-1"])

    def test_rejects_invalid_package_digest(self):
        value = package()
        value["question"] = "tampered"
        status, result = invoke(self.app, payload=value)
        self.assertEqual(status, "400 Bad Request")
        self.assertEqual(result["error"], "package_digest_mismatch")

    def test_candidate_endpoint_creates_isolated_head_mutation(self):
        candidate_binary = self.binary
        candidate_binary.write_text(
            "#!/usr/bin/env python3\n"
            "import json, pathlib, sys\n"
            "if sys.argv[1] == 'relation-eval':\n"
            " print('relation_eval schema=N16REL-EVAL/1 generation=12 state_digest=' + 'd'*64 + ' rows=1')\n"
            "elif sys.argv[1] == 'head-candidate':\n"
            " pathlib.Path(sys.argv[5]).write_bytes(b'candidate-state')\n"
            " print(json.dumps({'status':'candidate_only','canonical_state_modified':False,"
            "'candidate_digest':'e'*64,'boolean_mask_before':65535,'boolean_mask_after':65534,"
            "'boolean_rule_before':0,'boolean_rule_after':1}))\n",
            encoding="utf-8")
        candidate_binary.chmod(0o755)
        candidate_dir = Path(self.tmp.name) / "candidates"
        old = os.environ.get("NANLM_HEAD_CANDIDATE_DIR")
        os.environ["NANLM_HEAD_CANDIDATE_DIR"] = str(candidate_dir)
        try:
            request = {
                "schema": "nanlm.head-candidate-request/1",
                "mutation_id": "head42-patch1", "head_index": 42,
                "patch_mask": 1, "base_topology_digest": "d" * 64,
            }
            status, result = invoke(self.app, path="/v1/head-cortex/candidate",
                                    payload=request)
            self.assertEqual(status, "200 OK")
            self.assertEqual(result["status"], "candidate_only")
            self.assertEqual(result["candidate_digest"], "e" * 64)
            self.assertFalse(result["canonical_state_modified"])
            self.assertFalse(result["promotion_allowed"])
            self.assertTrue((candidate_dir / "head42-patch1.nmg").is_file())
            self.assertEqual(hashlib.sha256(self.state.read_bytes()).hexdigest(), self.before)
        finally:
            if old is None:
                os.environ.pop("NANLM_HEAD_CANDIDATE_DIR", None)
            else:
                os.environ["NANLM_HEAD_CANDIDATE_DIR"] = old

    def test_clocked_weak_supervision_trains_isolated_candidate_and_blocks_leakage(self):
        candidate_binary = self.binary
        candidate_binary.write_text(
            "#!/usr/bin/env python3\n"
            "import pathlib, sys\n"
            "if sys.argv[1] == 'relation-eval':\n"
            " candidate = 'candidates' in sys.argv[3]\n"
            " digest = 'e' if candidate else 'd'\n"
            " print('relation_eval schema=N16REL-EVAL/1 generation=12 state_digest=' + digest*64 + ' rows=1')\n"
            "elif sys.argv[1] == 'relation-train':\n"
            " pathlib.Path(sys.argv[3]).write_bytes(b'trained-candidate-state')\n"
            " print('relation_train status=updated epochs=1 train_events=2 changed_heads=3 mirror_pair_updates=6 hyperedges_added=2 state_digest_before=' + 'd'*64 + ' state_digest_after=' + 'e'*64)\n",
            encoding="utf-8")
        candidate_binary.chmod(0o755)
        candidate_dir = Path(self.tmp.name) / "candidates"
        old = os.environ.get("NANLM_HEAD_CANDIDATE_DIR")
        os.environ["NANLM_HEAD_CANDIDATE_DIR"] = str(candidate_dir)
        try:
            records = [
                {"observation_id": "clocked-1", "resolution": 5, "polarity": "+",
                 "confidence": 600, "subject": "river", "predicate": "states_claim",
                 "object": "The river flows.", "source_digest": "a" * 64},
                {"observation_id": "clocked-2", "resolution": 5, "polarity": "-",
                 "confidence": 400, "subject": "river", "predicate": "states_claim",
                 "object": "The river is dry.", "source_digest": "b" * 64},
            ]
            request = {
                "schema": "nanlm.head-learning-candidate-request/1",
                "mutation_id": "weak-learn-1", "split": "train",
                "teacher": "CLOCKED", "teacher_outputs_are_ground_truth": False,
                "dataset_sha256": hashlib.sha256(canonical(records)).hexdigest(),
                "base_topology_digest": "d" * 64, "epochs": 1, "records": records,
            }
            status, result = invoke(self.app, path="/v1/head-cortex/candidate/learn",
                                    payload=request)
            self.assertEqual(status, "200 OK")
            self.assertEqual(result["kind"], "learned_candidate")
            self.assertEqual(result["training_summary"]["changed_heads"], 3)
            self.assertFalse(result["teacher_outputs_are_ground_truth"])
            self.assertFalse(result["canonical_state_modified"])
            self.assertTrue((candidate_dir / "weak-learn-1.nmg").is_file())
            manifest = json.loads((candidate_dir / "weak-learn-1.json").read_text())
            self.assertEqual(len(manifest["training_record_fingerprints"]), 2)
            heldout = {key: records[0][key] for key in (
                "resolution", "polarity", "subject", "predicate", "object", "source_digest")}
            evaluation = {
                "schema": "nanlm.head-candidate-evaluation-request/1",
                "mutation_id": "weak-learn-1", "split": "test",
                "dataset_sha256": hashlib.sha256(canonical([heldout])).hexdigest(),
                "records": [heldout],
            }
            status, rejected = invoke(self.app, path="/v1/head-cortex/candidate/evaluate",
                                      payload=evaluation)
            self.assertEqual(status, "400 Bad Request")
            self.assertEqual(rejected["error"], "training_test_record_overlap")
            self.assertEqual(hashlib.sha256(self.state.read_bytes()).hexdigest(), self.before)
        finally:
            if old is None:
                os.environ.pop("NANLM_HEAD_CANDIDATE_DIR", None)
            else:
                os.environ["NANLM_HEAD_CANDIDATE_DIR"] = old

    def test_candidate_evaluation_compares_heldout_baseline_without_promotion(self):
        candidate_binary = self.binary
        candidate_binary.write_text(
            "#!/usr/bin/env python3\n"
            "import json, pathlib, sys\n"
            "if sys.argv[1] == 'relation-eval':\n"
            " candidate = 'candidates' in sys.argv[3]\n"
            " digest = 'e' if candidate else 'd'\n"
            " print('relation_eval schema=N16REL-EVAL/1 generation=12 state_digest=' + digest*64 + ' rows=2')\n"
            " print('relation_eval_row index=0 head=42 votes=7 truth_state=' + ('TRUE' if candidate else 'FALSE') + ' rule=3')\n"
            " print('relation_eval_row index=1 head=43 votes=1 truth_state=FALSE rule=2')\n"
            "elif sys.argv[1] == 'head-candidate':\n"
            " pathlib.Path(sys.argv[5]).write_bytes(b'candidate-state')\n"
            " print(json.dumps({'status':'candidate_only','canonical_state_modified':False,"
            "'candidate_digest':'e'*64,'boolean_mask_before':65535,'boolean_mask_after':65534,"
            "'boolean_rule_before':0,'boolean_rule_after':1}))\n",
            encoding="utf-8")
        candidate_binary.chmod(0o755)
        candidate_dir = Path(self.tmp.name) / "candidates"
        old = os.environ.get("NANLM_HEAD_CANDIDATE_DIR")
        os.environ["NANLM_HEAD_CANDIDATE_DIR"] = str(candidate_dir)
        try:
            create = {
                "schema": "nanlm.head-candidate-request/1",
                "mutation_id": "eval-candidate-1", "head_index": 42,
                "patch_mask": 1, "base_topology_digest": "d" * 64,
            }
            status, created = invoke(self.app, path="/v1/head-cortex/candidate", payload=create)
            self.assertEqual(status, "200 OK")
            records = [
                {"resolution": 5, "polarity": "+", "subject": "s1",
                 "predicate": "p", "object": "o1", "source_digest": "a" * 64},
                {"resolution": 5, "polarity": "-", "subject": "s2",
                 "predicate": "p", "object": "o2", "source_digest": "b" * 64},
            ]
            status, result = invoke(self.app, path="/v1/head-cortex/candidate/evaluate",
                payload={"schema": "nanlm.head-candidate-evaluation-request/1",
                         "mutation_id": "eval-candidate-1", "split": "test",
                         "dataset_sha256": hashlib.sha256(canonical(records)).hexdigest(),
                         "records": records})
            self.assertEqual(status, "200 OK")
            self.assertEqual(result["status"], "evaluated_candidate")
            self.assertEqual(result["split"], "test")
            self.assertEqual(result["dataset_sha256"], hashlib.sha256(canonical(records)).hexdigest())
            self.assertEqual(result["candidate"]["accuracy"], 1.0)
            self.assertEqual(result["baseline"]["accuracy"], 0.5)
            self.assertEqual(result["recommendation"], "review_candidate")
            self.assertFalse(result["promotion_allowed"])
            self.assertFalse(result["canonical_state_modified"])
            self.assertEqual(hashlib.sha256(self.state.read_bytes()).hexdigest(), self.before)
        finally:
            if old is None:
                os.environ.pop("NANLM_HEAD_CANDIDATE_DIR", None)
            else:
                os.environ["NANLM_HEAD_CANDIDATE_DIR"] = old

    def test_health_reports_canonical_immutability_and_candidate_capability(self):
        status, result = invoke(self.app, path="/healthz", method="GET")
        self.assertEqual(status, "200 OK")
        self.assertTrue(result["canonical_state_immutable"])
        self.assertTrue(result["candidate_mutations"])
        self.assertNotIn("read_only", result)

    def test_requires_scoped_bearer(self):
        status, result = invoke(self.app, payload=package(), token="wrong")
        self.assertEqual(status, "401 Unauthorized")
        self.assertEqual(result["error"], "unauthorized")


if __name__ == "__main__":
    unittest.main()
