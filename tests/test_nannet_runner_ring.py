import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, "runner")
from nannet_router.ring import RING_SLOTS, RunnerRing, RunnerRingError


class CanonicalRunnerRingTests(unittest.TestCase):
    def test_six_slots_are_internal_bs0_processes_not_mc0_or_hw_addresses(self):
        self.assertEqual(RING_SLOTS, tuple(f"HW0::BS0/R{i}" for i in range(6)))
        self.assertTrue(all(not name.startswith("MC0:0") for name in RING_SLOTS))
        self.assertEqual(len(set(RING_SLOTS)), 6)

    def test_heartbeat_and_snapshot_keep_bs0_as_ring_owner(self):
        with tempfile.TemporaryDirectory() as tmp:
            ring = RunnerRing(Path(tmp) / "ring.sqlite3")
            digest = "a" * 64
            for slot in range(6):
                snapshot = ring.heartbeat(
                    slot=slot, runner_id=f"HW0::BS0/R{slot}",
                    registry_generation=3, registry_digest=digest,
                    nanclock_tick=100 + slot,
                    expected_generation=3, expected_digest=digest,
                )
            self.assertEqual(snapshot["macrocluster"], "HW0::BS0")
            self.assertEqual(snapshot["slot_count"], 6)
            self.assertEqual(snapshot["health"], "green")
            self.assertEqual([item["runner_id"] for item in snapshot["slots"]],
                             list(RING_SLOTS))

    def test_rejects_downstream_mc0_runner_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            ring = RunnerRing(Path(tmp) / "ring.sqlite3")
            with self.assertRaises(RunnerRingError):
                ring.heartbeat(
                    slot=0, runner_id="MC0:0/R0",
                    registry_generation=1, registry_digest="b" * 64,
                    nanclock_tick=1, expected_generation=1,
                    expected_digest="b" * 64,
                )


if __name__ == "__main__":
    unittest.main()
