import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path

from runner.head_cortex_service import HeadCortexService, canonical


def invoke(app, path, payload):
    raw = canonical(payload)
    environ = {
        "REQUEST_METHOD": "POST", "PATH_INFO": path,
        "CONTENT_LENGTH": str(len(raw)), "wsgi.input": __import__("io").BytesIO(raw),
        "HTTP_AUTHORIZATION": "Bearer " + "t" * 40,
    }
    captured = {}
    def start_response(status, headers):
        captured["status"] = status
    body = b"".join(app(environ, start_response))
    return captured["status"], json.loads(body.decode("utf-8"))


class NativeHeadLearningIntegrationTests(unittest.TestCase):
    def test_clocked_weak_training_and_heldout_evaluation_use_native_topology(self):
        root = Path(__file__).resolve().parents[1]
        binary = root / "build" / "nanlm-universal"
        state = root / "state" / "relation-universe.nmg"
        if not binary.is_file() or not state.is_file():
            self.skipTest("native CI relation topology is not available")
        before = hashlib.sha256(state.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            candidate_dir = Path(tmp) / "candidates"
            old = os.environ.get("NANLM_HEAD_CANDIDATE_DIR")
            os.environ["NANLM_HEAD_CANDIDATE_DIR"] = str(candidate_dir)
            try:
                app = HeadCortexService(str(binary), str(state), "t" * 40)
                training = [
                    {"observation_id": "clocked-native-1", "resolution": 5,
                     "polarity": "+", "confidence": 60000,
                     "subject": "native-clocked-subject-a",
                     "predicate": "teacher_observed_claim",
                     "object": "native candidate training positive example",
                     "source_digest": "a" * 64},
                    {"observation_id": "clocked-native-2", "resolution": 5,
                     "polarity": "-", "confidence": 60000,
                     "subject": "native-clocked-subject-b",
                     "predicate": "teacher_observed_claim",
                     "object": "native candidate training negative example",
                     "source_digest": "b" * 64},
                ]
                request = {
                    "schema": "nanlm.head-learning-candidate-request/1",
                    "mutation_id": "native-integration-candidate",
                    "base_topology_digest": "0" * 64,
                    "split": "train", "teacher": "CLOCKED",
                    "teacher_outputs_are_ground_truth": False,
                    "dataset_sha256": hashlib.sha256(canonical(training)).hexdigest(),
                    "epochs": 1, "records": training,
                }
                # Obtain the real base digest through the native read-only evaluator.
                with tempfile.TemporaryDirectory() as probe_dir:
                    probe = Path(probe_dir) / "probe.n16rel"
                    probe.write_text(
                        "N16REL/1\ntest\t5\t+\t0\t70726f6265\t7374617465\t646967657374\t" + "0" * 64 + "\n",
                        encoding="ascii")
                    import subprocess, re
                    result = subprocess.run(
                        [str(binary), "relation-eval", str(probe), str(state)],
                        capture_output=True, text=True, check=True)
                    match = re.search(r"state_digest=([a-f0-9]{64})", result.stdout)
                    self.assertIsNotNone(match)
                    request["base_topology_digest"] = match.group(1)
                status, learned = invoke(app, "/v1/head-cortex/candidate/learn", request)
                self.assertEqual(status, "200 OK", learned)
                self.assertEqual(learned["status"], "candidate_only")
                self.assertFalse(learned["teacher_outputs_are_ground_truth"])
                self.assertGreater(learned["training_summary"]["changed_heads"], 0)
                self.assertNotEqual(learned["candidate_digest"], request["base_topology_digest"])

                heldout = [
                    {"resolution": 5, "polarity": "+", "subject": "heldout-subject-a",
                     "predicate": "teacher_observed_claim", "object": "independent heldout positive",
                     "source_digest": "c" * 64},
                    {"resolution": 5, "polarity": "-", "subject": "heldout-subject-b",
                     "predicate": "teacher_observed_claim", "object": "independent heldout negative",
                     "source_digest": "d" * 64},
                ]
                evaluation = {
                    "schema": "nanlm.head-candidate-evaluation-request/1",
                    "mutation_id": "native-integration-candidate", "split": "test",
                    "dataset_sha256": hashlib.sha256(canonical(heldout)).hexdigest(),
                    "records": heldout,
                }
                status, evaluated = invoke(app, "/v1/head-cortex/candidate/evaluate", evaluation)
                self.assertEqual(status, "200 OK", evaluated)
                self.assertEqual(evaluated["status"], "evaluated_candidate")
                self.assertFalse(evaluated["promotion_allowed"])
                self.assertEqual(evaluated["base_state_digest"], request["base_topology_digest"])
                self.assertEqual(evaluated["candidate_digest"], learned["candidate_digest"])
                self.assertEqual(hashlib.sha256(state.read_bytes()).hexdigest(), before)
            finally:
                if old is None:
                    os.environ.pop("NANLM_HEAD_CANDIDATE_DIR", None)
                else:
                    os.environ["NANLM_HEAD_CANDIDATE_DIR"] = old


if __name__ == "__main__":
    unittest.main()
