import json
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runner"))

import logic_curriculum as lc  # noqa: E402


class LogicCurriculumTests(unittest.TestCase):
    def test_graded_run_improves_and_stays_above_gate(self):
        result = lc.run_curriculum(rounds=5)
        self.assertTrue(result["ok"])
        self.assertTrue(result["improved"])
        self.assertGreaterEqual(len(result["levels"]), 4)
        for level in result["levels"]:
            self.assertGreaterEqual(level["best_accuracy"], 0.75)
            self.assertGreaterEqual(len(level["history"]), 1)

    def test_inheritance_level_starts_below_perfect(self):
        level = lc.make_level(1)
        result = lc.train_level(level, rounds=4)
        self.assertLess(result["history"][0]["accuracy"], 1.0)
        self.assertEqual(result["history"][-1]["accuracy"], 1.0)
        self.assertTrue(result["improved"])

    def test_feedback_raises_depth(self):
        memory = lc.LogicMemory()
        memory.learn(lc.make_level(1).facts)
        self.assertEqual(memory.learned_depth, 0)
        self.assertIsNone(memory.answer("emperor", "swim"))
        memory.feedback(lc.Query("emperor", "swim", True))
        self.assertGreaterEqual(memory.learned_depth, 2)
        self.assertTrue(memory.answer("emperor", "swim"))

    def test_merge_post_uses_scoped_delta(self):
        captured = {}

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                captured["path"] = self.path
                captured["auth"] = self.headers.get("Authorization")
                captured["idem"] = self.headers.get("Idempotency-Key")
                captured["body"] = json.loads(self.rfile.read(length))
                raw = b'{"accepted": true, "applied": 1}\n'
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            response = lc.post_merge(
                {"levels": [{"best_accuracy": 0.75}]},
                f"http://127.0.0.1:{server.server_port}", "secret", 3)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertTrue(response["accepted"])
        self.assertEqual(captured["path"], "/v1/training/merge")
        self.assertEqual(captured["auth"], "Bearer secret")
        self.assertTrue(captured["idem"].startswith("logic-3-"))
        self.assertEqual(captured["body"]["node"], 3)
        self.assertEqual(captured["body"]["updates"][0]["route"], "logic-curriculum")

    def test_cli_emits_json(self):
        proc = subprocess.run(
            [sys.executable, str(ROOT / "runner" / "logic_curriculum.py"),
             "--slot", "1", "--epoch", "3", "--rounds", "3"],
            text=True, capture_output=True, check=True)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["slot"], 1)
        self.assertEqual(payload["epoch"], 3)
        self.assertTrue(payload["improved"])
        self.assertIn("levels", payload)


if __name__ == "__main__":
    unittest.main()
