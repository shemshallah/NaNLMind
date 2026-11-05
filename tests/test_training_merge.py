import json
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "runner"))
import training_merge  # noqa: E402


class TrainingMergeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.server = training_merge.make_server(
            "127.0.0.1", 0, Path(self.tmp.name), "test-token")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.tmp.cleanup()

    def post(self, payload, key, token="test-token"):
        req = urllib.request.Request(
            self.base + "/v1/training/merge",
            data=json.dumps(payload).encode(),
            method="POST",
            headers={
                "Authorization": "Bearer " + token,
                "Content-Type": "application/json",
                "Idempotency-Key": key,
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def payload(self, base=0, tick=10, delta=1):
        return {
            "node": 2,
            "base_generation": base,
            "nanclock_tick": tick,
            "updates": [{
                "head": 7,
                "layer": 3,
                "epoch": tick,
                "vector": [1] * 16,
                "strength_delta": delta,
                "route": {"bank": 1, "bin": 9001, "slot": 7},
            }],
        }

    def test_merge_idempotency_and_stale_base(self):
        status, body = self.post(self.payload(), "k1")
        self.assertEqual(status, 200)
        self.assertEqual(body["generation"], 1)
        self.assertEqual(body["applied"], 1)

        status, replay = self.post(self.payload(), "k1")
        self.assertEqual(status, 200)
        self.assertEqual(replay, body)

        status, stale = self.post(self.payload(base=0), "k2")
        self.assertEqual(status, 409)
        self.assertIn("stale", stale["error"])

        status, next_merge = self.post(self.payload(base=1, tick=11, delta=2), "k3")
        self.assertEqual(status, 200)
        self.assertEqual(next_merge["generation"], 2)

        status, bad_key = self.post(self.payload(base=2, tick=12), "k3")
        self.assertEqual(status, 409)

    def test_auth_and_health(self):
        status, body = self.post(self.payload(), "auth", token="wrong")
        self.assertEqual(status, 401)
        with urllib.request.urlopen(self.base + "/healthz", timeout=5) as r:
            health = json.loads(r.read())
        self.assertTrue(health["ok"])
        self.assertEqual(health["nodes"], 0)


if __name__ == "__main__":
    unittest.main()
