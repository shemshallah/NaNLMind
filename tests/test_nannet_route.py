from __future__ import annotations

import unittest

from tools.nannet_route_train import load_routes, route_receipt


class NannetRouteTests(unittest.TestCase):
    def test_manifest_keeps_canonical_universe_and_both_jobs(self):
        doc = load_routes()
        self.assertEqual(doc["canonical_universe"], "HW0::BS0")
        self.assertEqual(set(doc["routes"]), {"HW4", "HW5"})
        self.assertFalse(route_receipt("HW4")["node_instantiated"])
        self.assertFalse(route_receipt("HW5")["node_instantiated"])

    def test_receipts_are_distinct_and_hashed(self):
        a = route_receipt("HW4")
        b = route_receipt("HW5")
        self.assertNotEqual(a["receipt_digest"], b["receipt_digest"])
        self.assertEqual(len(a["corpus_sha256"]), 64)
        self.assertEqual(a["job"], "wordnet")
        self.assertEqual(b["job"], "gutenberg")


if __name__ == "__main__":
    unittest.main()
