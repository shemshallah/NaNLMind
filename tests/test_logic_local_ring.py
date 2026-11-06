import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LogicLocalRingTests(unittest.TestCase):
    def test_parallel_slots_use_different_levels(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = subprocess.run(
                [sys.executable, str(ROOT / "runner" / "logic_local_ring.py"),
                 "--slots", "3", "--rounds", "3",
                 "--state-root", str(Path(tmp) / "ring")],
                text=True, capture_output=True, check=False)
            self.assertEqual(proc.returncode, 0,
                             f"logic ring failed\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")
            payload = json.loads(proc.stdout)
            self.assertTrue(payload["ok"])
            self.assertTrue(payload["improved"])
            self.assertEqual([s["slot"] for s in payload["results"]], [1, 2, 3])
            self.assertEqual([s["start_level"] for s in payload["results"]], [0, 1, 2])
            for slot in payload["results"]:
                self.assertTrue(slot["ok"])
                self.assertGreaterEqual(slot["record"]["levels"][0]["best_accuracy"], 0.75)


if __name__ == "__main__":
    unittest.main()
