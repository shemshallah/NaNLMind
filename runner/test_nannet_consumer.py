import unittest

from runner.nannet_consumer import add_features, make_updates


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


    def test_n16txt_header_and_crlf_normalize_to_same_features(self):
        from runner.nannet_consumer import TextCorpusFold
        lf = TextCorpusFold("N16TXT/1")
        lf.feed(b"N16TXT/1\\nalpha\\nbeta\\n")
        lf.finish()
        crlf = TextCorpusFold("N16TXT/1")
        crlf.feed(b"N16TXT/1\\r\\nalpha\\r\\nbeta")
        crlf.finish()
        self.assertEqual(lf.counts, crlf.counts)
        self.assertEqual(lf.record_count, 2)

    def test_n16txt_rejects_bad_header_long_records_and_controls(self):
        from runner.nannet_consumer import TextCorpusFold
        bad_header = TextCorpusFold("N16TXT/1")
        with self.assertRaises(RuntimeError):
            bad_header.feed(b"N16TXT/2\\n")
            bad_header.finish()
        long_record = TextCorpusFold("plain-text/utf8")
        with self.assertRaises(RuntimeError):
            long_record.feed(b"x" * 4098)
        controls = TextCorpusFold("plain-text/utf8")
        with self.assertRaises(RuntimeError):
            controls.feed(b"safe\\x00unsafe\\n")

    def test_plain_text_accepts_utf8_and_ignores_blank_lines(self):
        from runner.nannet_consumer import TextCorpusFold
        parser = TextCorpusFold("plain-text/utf8")
        parser.feed("café\\n\\nsecond".encode("utf-8"))
        parser.finish()
        self.assertEqual(parser.record_count, 2)


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
