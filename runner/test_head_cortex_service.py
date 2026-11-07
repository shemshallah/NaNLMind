import hashlib
import io
import json
import os
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

    def test_requires_scoped_bearer(self):
        status, result = invoke(self.app, payload=package(), token="wrong")
        self.assertEqual(status, "401 Unauthorized")
        self.assertEqual(result["error"], "unauthorized")


if __name__ == "__main__":
    unittest.main()
