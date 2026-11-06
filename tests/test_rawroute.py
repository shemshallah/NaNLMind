import unittest

from nanlmind_nannet.rawroute import RawRoute, parse_rawroute


class RawRouteTests(unittest.TestCase):
    def test_single_head_route_roundtrip(self):
        text = "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1"
        route = parse_rawroute(text)
        self.assertEqual(route.text(), text)
        self.assertEqual(route.hw_node, 0)
        self.assertEqual(len(route.definition_id), 64)

    def test_multihead_runner_ring_route(self):
        text = "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1,2,3"
        route = RawRoute.parse(text)
        self.assertEqual(route.target.heads, (1, 2, 3))
        self.assertEqual(route.text(), text)

    def test_typed_vector_and_hyperedge_associations(self):
        vector = parse_rawroute(
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1::vector1337")
        edge = parse_rawroute(
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:2::hyperedge1337")
        self.assertEqual(vector.object_ref.kind, "vector")
        self.assertEqual(vector.object_ref.object_id, 1337)
        self.assertEqual(edge.object_ref.kind, "hyperedge")
        self.assertEqual(edge.object_ref.object_id, 1337)
        self.assertNotEqual(vector.definition_id, edge.definition_id)

    def test_max_uint32_object_id(self):
        text = ("nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1::memory4294967295")
        self.assertEqual(parse_rawroute(text).object_ref.object_id, 0xFFFFFFFF)

    def test_rejects_legacy_route_as_hierarchical_address(self):
        with self.assertRaises(ValueError):
            parse_rawroute("nan://GM0:SC0:MC0:BS0:HW0:BSR0")

    def test_rejects_noncanonical_numbers_and_separators(self):
        invalid = (
            "nan://GM00:SC0:MC0:BS0:0:HW0:0::HW0:1",
            "nan://GM0:SC0:MC0:BS0:00:HW0:0::HW0:1",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0:HW0:1",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0:::HW0:1",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:01",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1,1",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:2,1",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1::vector01",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1::unknown1337",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW1:1",
        )
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    parse_rawroute(value)

    def test_rejects_out_of_range_coordinates_and_ids(self):
        invalid = (
            "nan://GM256:SC0:MC0:BS0:0:HW0:0::HW0:1",
            "nan://GM0:SC0:MC0:BS0:256:HW0:0::HW0:1",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:256",
            "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1::vector4294967296",
        )
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    parse_rawroute(value)

    def test_rejects_non_text(self):
        with self.assertRaises(ValueError):
            parse_rawroute(None)


if __name__ == "__main__":
    unittest.main()
