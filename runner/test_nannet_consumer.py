import unittest

from nannet_consumer import add_features, make_updates


class NannetConsumerTests(unittest.TestCase):
    def test_trigram_features_are_chunk_boundary_invariant(self):
        data = b"abcdefghijk"
        whole = [[0] * 16 for _ in range(256)]
        add_features(data, b"", whole)
        split = [[0] * 16 for _ in range(256)]
        carry = add_features(data[:4], b"", split)
        carry = add_features(data[4:8], carry, split)
        add_features(data[8:], carry, split)
        self.assertEqual(whole, split)
        self.assertEqual(sum(map(sum, whole)), len(data) - 2)

    def test_updates_cover_local_heads_and_are_bounded(self):
        counts = [[0] * 16 for _ in range(256)]
        counts[0][0] = 10
        counts[255][15] = 20
        updates = make_updates(counts, 9)
        self.assertEqual([x["head"] for x in updates], [0, 255])
        self.assertEqual(updates[0]["vector"][0], 32767)
        self.assertEqual(updates[1]["strength_delta"], 20)
        self.assertEqual(len(updates[0]["vector"]), 16)


if __name__ == "__main__":
    unittest.main()
