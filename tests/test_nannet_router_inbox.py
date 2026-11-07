import hashlib
import tempfile
import unittest
from pathlib import Path

from nannet_router.inbox import InboxError, SQLiteSourceInbox


class ClockedEvidenceAckPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.inbox = SQLiteSourceInbox(Path(self.tmp.name) / "router.sqlite3")
        self.payload = b'{"schema":"nanlm.clocked-router-source.v1"}'
        self.event_id = self.inbox.enqueue(
            universe_id="BS0:0", node_point=9, head_index=17,
            source_kind="clocked-evidence", payload=self.payload,
            acl_digest="a" * 64, nanclock_tick=1800000000,
        )
        self.event = self.inbox.lease_next(
            owner="MC0:0/R2", now_tick=1800000001,
            source_kind="clocked-evidence",
        )
        self.assertIsNotNone(self.event)

    def _trace(self, **overrides):
        trace = {
            "schema": "nanrouter.trace.v1",
            "source_ref": "clocked:" + "1" * 64,
            "target_ref": "BS0:0/MC0:0/R2/HW17",
            "source_hash": self.event.source_hash,
            "acl_digest": self.event.acl_digest,
            "universe_id": "BS0:0",
            "nanclock_tick": 1800000001,
            "correct": False,
            "outcome_verified": False,
            "evidence_only": True,
        }
        trace.update(overrides)
        return trace

    def _ack(self, trace):
        digest = hashlib.sha256(repr(sorted(trace.items())).encode()).hexdigest()
        return self.inbox.ack(self.event, result_digest=digest,
                              result_generation=0, trace=trace)

    def test_clocked_ack_requires_unverified_evidence_only_trace(self):
        for bad in ({"correct": True}, {"outcome_verified": True},
                    {"evidence_only": False}, {"schema": "other"}):
            with self.subTest(bad=bad):
                with self.assertRaises(InboxError):
                    self._ack(self._trace(**bad))
        self.assertEqual(self.inbox.stats()["leased"], 1)

    def test_clocked_ack_accepts_provenance_bound_unverified_trace(self):
        self.assertTrue(self._ack(self._trace()))
        self.assertEqual(self.inbox.stats()["acked"], 1)


if __name__ == "__main__":
    unittest.main()
