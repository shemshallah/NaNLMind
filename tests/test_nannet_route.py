from __future__ import annotations

import unittest
from pathlib import Path

from tools.nannet_route_train import load_routes, route_receipt


class NannetRouteTests(unittest.TestCase):
    def test_manifest_has_actual_c256_2_objects(self):
        doc = load_routes()
        self.assertEqual(doc["canonical_universe"], "HW0::BS0")
        for route, kind in (("HW4", "hyperedge"), ("HW5", "memory")):
            spec = doc["routes"][route]
            self.assertTrue(spec["route"].startswith("nan://"))
            self.assertIn("::" + kind, spec["route"])
            self.assertEqual(spec["matrix_pairs"], 32640)
            self.assertTrue((Path(spec["object_file"])).is_file())
            receipt = route_receipt(route)
            self.assertFalse(receipt["node_instantiated"])
            self.assertEqual(receipt["route_object"]["kind"], kind)
            self.assertEqual(receipt["route_object"]["matrix_pairs"], 32640)
            self.assertGreater(receipt["route_object"]["nonzero_pairs"], 0)

    def test_receipts_are_distinct_and_hashed(self):
        a = route_receipt("HW4")
        b = route_receipt("HW5")
        self.assertNotEqual(a["receipt_digest"], b["receipt_digest"])
        self.assertEqual(len(a["corpus_sha256"]), 64)
        self.assertEqual(a["job"], "wordnet")
        self.assertEqual(b["job"], "gutenberg")


if __name__ == "__main__":
    unittest.main()
