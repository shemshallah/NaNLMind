import tempfile
import unittest
from pathlib import Path

from runner.runner_ring_authority import (
    RunnerRingAuthError,
    RunnerRingAuthority,
    RunnerRingError,
)


class FakeClock:
    def __init__(self, value=1_700_000_000_000_000_000):
        self.value = value

    def __call__(self):
        return self.value

    def advance(self, milliseconds):
        self.value += milliseconds * 1_000_000


class RunnerRingAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.clock = FakeClock()
        self.authority = RunnerRingAuthority(
            Path(self.tmp.name) / "ring.sqlite", now_ns=self.clock
        )

    def test_clock_is_strictly_monotone(self):
        first = self.authority.clock()["nanclock_tick"]
        second = self.authority.clock()["nanclock_tick"]
        third = self.authority.clock()["nanclock_tick"]
        self.assertEqual((first, second, third), (first, first + 1, first + 2))

    def test_single_active_slot_and_epoch_handoff(self):
        first = self.authority.lease(
            slot=0, base_epoch=0, endpoint="https://runner-0.example", ttl_seconds=30
        )
        self.assertTrue(first["acquired"])
        self.assertEqual(first["epoch"], 1)
        blocked = self.authority.lease(
            slot=1, base_epoch=1, endpoint="https://runner-1.example", ttl_seconds=30
        )
        self.assertFalse(blocked["acquired"])
        self.assertEqual(blocked["active_slot"], 0)

        renewed = self.authority.lease(
            slot=0, base_epoch=1, endpoint="https://runner-0.example", ttl_seconds=30
        )
        self.assertTrue(renewed["renewed"])
        self.assertEqual(renewed["lease_id"], first["lease_id"])

        released = self.authority.release(slot=0, lease_id=first["lease_id"])
        self.assertTrue(released["released"])
        takeover = self.authority.lease(
            slot=1, base_epoch=1, endpoint="https://runner-1.example", ttl_seconds=30
        )
        self.assertTrue(takeover["acquired"])
        self.assertEqual(takeover["active_slot"], 1)
        self.assertEqual(takeover["epoch"], 2)
        stats = self.authority.stats()
        self.assertGreaterEqual(stats["handoffs"], 3)

    def test_expired_lease_can_be_taken_over(self):
        first = self.authority.lease(
            slot=0, base_epoch=0, endpoint="https://runner-0.example", ttl_seconds=5
        )
        self.clock.advance(6000)
        takeover = self.authority.lease(
            slot=2, base_epoch=first["epoch"], endpoint="https://runner-2.example",
            ttl_seconds=30,
        )
        self.assertTrue(takeover["acquired"])
        self.assertEqual(takeover["active_slot"], 2)
        self.assertGreater(takeover["epoch"], first["epoch"])

    def test_renew_and_release_require_the_same_lease(self):
        lease = self.authority.lease(
            slot=0, base_epoch=0, endpoint="https://runner-0.example", ttl_seconds=30
        )
        with self.assertRaises(RunnerRingAuthError):
            self.authority.renew(slot=1, lease_id=lease["lease_id"])
        with self.assertRaises(RunnerRingAuthError):
            self.authority.renew(slot=0, lease_id="0" * 32)
        with self.assertRaises(RunnerRingAuthError):
            self.authority.release(slot=1, lease_id=lease["lease_id"])

    def test_checkpoint_is_bound_to_active_lease(self):
        lease = self.authority.lease(
            slot=0, base_epoch=0, endpoint="https://runner-0.example", ttl_seconds=30
        )
        result = self.authority.checkpoint(
            slot=0, lease_id=lease["lease_id"],
            state={"last_frame_id": "f" * 64, "frames": 3},
            nanclock_tick=lease["nanclock_tick"],
        )
        self.assertTrue(result["checkpointed"])
        loaded = self.authority.read_checkpoint()
        self.assertEqual(loaded["state"]["frames"], 3)
        self.assertEqual(loaded["slot"], 0)
        with self.assertRaises(RunnerRingAuthError):
            self.authority.checkpoint(
                slot=1, lease_id="0" * 32, state={"frames": 0},
                nanclock_tick=1,
            )

    def test_rejects_bad_slots_endpoints_and_ttl(self):
        with self.assertRaises(RunnerRingError):
            self.authority.lease(
                slot=6, base_epoch=0, endpoint="https://runner.example", ttl_seconds=30
            )
        with self.assertRaises(RunnerRingError):
            self.authority.lease(
                slot=0, base_epoch=0, endpoint="http://remote.example", ttl_seconds=30
            )
        with self.assertRaises(RunnerRingError):
            self.authority.lease(
                slot=0, base_epoch=0, endpoint="https://runner.example", ttl_seconds=1
            )


if __name__ == "__main__":
    unittest.main()
