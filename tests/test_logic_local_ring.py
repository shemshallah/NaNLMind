import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LogicLocalRingTests(unittest.TestCase):
    def test_parallel_slots_use_different_levels(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            # This is a local worker-ring unit test, not a portal integration
            # test. Prevent ambient CI secrets from forcing remote auth.
            env.pop("NANNET_PORTAL_API", None)
            env.pop("NANNET_BSR_TOKEN", None)
            proc = subprocess.run(
                [sys.executable, str(ROOT / "runner" / "logic_local_ring.py"),
                 "--slots", "3", "--rounds", "5",
                 "--state-root", str(Path(tmp) / "ring")],
                text=True, capture_output=True, check=False, env=env)
            self.assertEqual(proc.returncode, 0, msg=proc.stdout + "\n" + proc.stderr)
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
