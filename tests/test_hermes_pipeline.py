import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runner"))

import hermes_pipeline as hp  # noqa: E402


class HermesPipelineTests(unittest.TestCase):
    def test_prompt_maps_to_logic_stage(self):
        plan = hp.plan_for_prompt("teach deep logic and circuits")
        self.assertEqual(plan, ["deep_logic"])

    def test_prompt_without_training_is_interactive_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            pipeline = hp.HermesPipeline(tmp, str(Path(tmp) / "corpus.n16txt"))
            result = pipeline.prompt("how should we train words?", run=False)
            self.assertFalse(result["trained"])
            self.assertIn("word_choice", result["plan"])

    def test_bundle_contains_n16txt_and_layer_events(self):
        with tempfile.TemporaryDirectory() as tmp:
            pipeline = hp.HermesPipeline(tmp, str(Path(tmp) / "corpus.n16txt"),
                                         stage_seconds={"deep_logic": 0.01},
                                         slot=2, epoch=3)
            result = pipeline.train(["deep_logic"], max_samples=512)
            self.assertTrue(result["ok"])
            bundle = pipeline.write_bundle(result)
            self.assertTrue((bundle / "corpus.n16txt").read_bytes().startswith(b"N16TXT/1\n"))
            events = [json.loads(line) for line in (bundle / "discoveries.jsonl").read_text().splitlines()]
            self.assertEqual(len(events), 1)
            self.assertEqual(events[0]["layer"], 4)
            self.assertEqual(events[0]["head"], 1)
            self.assertEqual(events[0]["provenance"]["epoch"], 3)


if __name__ == "__main__":
    unittest.main()
