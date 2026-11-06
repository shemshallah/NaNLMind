import json
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runner"))

from conversation_trainer import (  # noqa: E402
    ConversationConfig, ConversationTrainer, DeterministicPlanner,
    OpenAICompatibleClient, validate_stage,
)


class ScriptedModel:
    def __init__(self, stages):
        self.stages = list(stages)
        self.calls = 0

    def complete(self, messages, **kwargs):
        self.calls += 1
        if "training result" in messages[-1]["content"].lower():
            return "Reflection: repeat the next useful stage."
        stage = self.stages.pop(0) if self.stages else "inverses_boolean"
        return json.dumps({"stage": stage, "message": f"choose {stage}"})


class ConversationTrainerTests(unittest.TestCase):
    def test_loop_turns_model_intents_into_pipeline_rounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            model = ScriptedModel(["inverses_boolean", "deep_logic", "common_words"])
            config = ConversationConfig(
                rounds=3, seconds=0.01, max_samples=512, state_dir=tmp,
                slot=1, epoch=0)
            result = ConversationTrainer(model, config).run("teach logic")
            self.assertEqual(len(result["rounds"]), 3)
            self.assertEqual([r["stage"] for r in result["rounds"]],
                             ["inverses_boolean", "deep_logic", "common_words"])
            self.assertTrue(all(r["accuracy"] > 0 for r in result["rounds"]))
            transcript = Path(result["transcript"])
            self.assertTrue(transcript.exists())
            rows = [json.loads(line) for line in transcript.read_text().splitlines()]
            self.assertEqual(len(rows), 3)
            self.assertTrue(all(row["corpus_sha256"] for row in rows))
            summary = Path(tmp) / "summary_0_1.json"
            self.assertTrue(summary.exists())

    def test_invalid_model_stage_falls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            class BadModel:
                def complete(self, messages, **kwargs):
                    return "not json"
            config = ConversationConfig(
                rounds=1, seconds=0.01, max_samples=128, state_dir=tmp,
                initial_stage="deep_logic")
            result = ConversationTrainer(BadModel(), config).run()
            self.assertEqual(result["rounds"][0]["stage"], "deep_logic")

    def test_deterministic_planner_does_not_advance_on_reflection(self):
        planner = DeterministicPlanner(["a", "b", "c"])
        first = json.loads(planner.complete([{"content": "choose"}]))
        self.assertEqual(first["stage"], "a")
        reflection = planner.complete([{"content": "training result"}])
        self.assertNotIn('"stage"', reflection)
        second = json.loads(planner.complete([{"content": "choose"}]))
        self.assertEqual(second["stage"], "b")

    def test_openai_compatible_client_posts_chat_completion(self):
        captured = {}
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                captured["path"] = self.path
                captured["auth"] = self.headers.get("Authorization")
                captured["body"] = json.loads(self.rfile.read(length))
                raw = json.dumps({"choices": [{"message": {"content": "ok"}}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            client = OpenAICompatibleClient(
                f"http://127.0.0.1:{server.server_port}", "demo", "secret")
            answer = client.complete([{"role": "user", "content": "hi"}])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertEqual(answer, "ok")
        self.assertEqual(captured["path"], "/chat/completions")
        self.assertEqual(captured["auth"], "Bearer secret")
        self.assertEqual(captured["body"]["model"], "demo")

    def test_stage_validation(self):
        self.assertEqual(validate_stage("sentences"), "sentences")
        self.assertEqual(validate_stage("bogus", "deep_logic"), "deep_logic")


if __name__ == "__main__":
    unittest.main()
