import tempfile
import unittest
from pathlib import Path

from runner.clocked_observation_consumer import EvidenceLedger, validate_event


class ClockedEvidenceConsumerTests(unittest.TestCase):
    def event(self, event_id="a" * 64, heads=None):
        return {"protocol": "nanlm.endpoint-observation", "version": 1,
                "event_id": event_id, "base_generation": 12,
                "active_heads": [2, 2, 255] if heads is None else heads,
                "outcome_verified": False}

    def test_schema_is_strict_and_heads_are_canonical(self):
        result = validate_event(self.event())
        self.assertEqual(result["active_heads"], [2, 255])
        bad = self.event()
        bad["correct"] = True
        with self.assertRaisesRegex(ValueError, "schema_mismatch"):
            validate_event(bad)

    def test_endpoint_cannot_claim_outcome(self):
        bad = self.event()
        bad["outcome_verified"] = True
        with self.assertRaisesRegex(ValueError, "asserted_outcome"):
            validate_event(bad)

    def test_ledger_is_idempotent_and_keeps_endpoint_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "evidence.sqlite3"
            ledger = EvidenceLedger(path)
            row = {"endpoint_id": "nan://GM0:SC0:MC0:BS0:HW3",
                   "received_at": 100, "observation": self.event()}
            self.assertEqual(ledger.fold([row]), ["a" * 64])
            self.assertEqual(ledger.fold([row]), ["a" * 64])
            count = ledger.db.execute("SELECT COUNT(*) FROM evidence").fetchone()[0]
            source = ledger.db.execute("SELECT endpoint_id FROM evidence").fetchone()[0]
            ledger.close()
            self.assertEqual(count, 1)
            self.assertTrue(source.endswith("HW3"))


if __name__ == "__main__":
    unittest.main()
