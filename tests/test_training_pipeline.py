import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runner"))

import training_corpus as corpus  # noqa: E402
import training_pipeline as pipeline  # noqa: E402


class TrainingPipelineTests(unittest.TestCase):
    def test_n16txt_is_strict_and_diverse(self):
        data = corpus.build_n16txt(max_bytes=1_000_000)
        self.assertTrue(data.startswith(b"N16TXT/1\n"))
        lines = data.splitlines()[1:]
        self.assertGreater(len(lines), 100)
        kinds = set()
        for line in lines:
            text = line.decode()
            if " is " in text or "isa " in text:
                kinds.add("logic")
            if "choose:" in text:
                kinds.add("choice")
            if " next:" in text:
                kinds.add("sentence")
        self.assertEqual(kinds, {"logic", "choice", "sentence"})

    def test_single_stage_reports_budget_and_corpus(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = pipeline.PipelineConfig(
                stage_seconds={"deep_logic": 0.01},
                single_stage="deep_logic",
                state_dir=tmp,
                corpus_path=str(Path(tmp) / "curriculum.n16txt"),
                max_samples=512)
            result = pipeline.run_pipeline(config)
            self.assertTrue(result["ok"])
            self.assertEqual(len(result["stages"]), 1)
            self.assertEqual(result["stages"][0]["name"], "deep_logic")
            self.assertEqual(result["stages"][0]["seconds"], 0.01)
            self.assertTrue(Path(result["corpus_path"]).exists())
            self.assertTrue(result["corpus_path"].endswith(".n16txt"))
            self.assertEqual(len(result["corpus_sha256"]), 64)

    def test_full_demo_pipeline_promotes_all_stages(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = pipeline.PipelineConfig(
                stage_seconds={stage.name: 0.01 for stage in corpus.STAGES},
                state_dir=tmp,
                corpus_path=str(Path(tmp) / "curriculum.n16txt"),
                max_samples=512)
            result = pipeline.run_pipeline(config)
            self.assertTrue(result["ok"])
            self.assertEqual(len(result["stages"]), len(corpus.STAGES))
            for stage in result["stages"]:
                self.assertTrue(stage["passed"], stage)
                self.assertGreater(stage["test_samples"], 0)


if __name__ == "__main__":
    unittest.main()
