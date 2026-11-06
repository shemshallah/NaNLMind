import tempfile
import unittest
from pathlib import Path

from nanlmind_nannet.bridge import BridgeFrame, BridgeMailbox, RunnerRoute
from nanlmind_nannet.nan16de import NanWord


class BridgeTests(unittest.TestCase):
    def test_runner_route_is_canonical_and_numeric(self):
        route = RunnerRoute.parse("nan://GM0:SC0:MC0:BS0:HW0:BSR5")
        self.assertEqual(route.bsr, 5)
        self.assertEqual(route.text(), "nan://GM0:SC0:MC0:BS0:HW0:BSR5")
        with self.assertRaises(ValueError):
            RunnerRoute.parse("nan://GM0:SC0:MC0:BS0:HW0:BSR(5*)")
        with self.assertRaises(ValueError):
            RunnerRoute.parse("nan://GM00:SC0:MC0:BS0:HW0:BSR5")
        with self.assertRaises(ValueError):
            RunnerRoute.parse("nan://GM0:SC0:MC0:BS0:HW0:BSR05")
        with self.assertRaises(ValueError):
            RunnerRoute.parse(None)
        for index in range(6):
            expected = f"nan://GM0:SC0:MC0:BS0:HW0:BSR{index}"
            self.assertEqual(RunnerRoute(bsr=index).text(), expected)
            self.assertEqual(RunnerRoute.parse(expected).text(), expected)

    def test_double_endian_frame_roundtrip(self):
        src = RunnerRoute(bsr=0)
        dst = RunnerRoute(bsr=5)
        frame = BridgeFrame(src, dst, 17, NanWord.from_bits(0, 0, 0xA1B2C3D4),
                            b"NaN16 bytes")
        raw = frame.encode()
        decoded = BridgeFrame.decode(raw)
        self.assertEqual(decoded.source, src)
        self.assertEqual(decoded.destination, dst)
        self.assertEqual(decoded.word.pack(), frame.word.pack())
        self.assertEqual(decoded.payload, b"NaN16 bytes")
        self.assertEqual(decoded.direction, "away")
        self.assertTrue(decoded.signaling)
        self.assertEqual(BridgeFrame.decode(BridgeFrame.acknowledgement(decoded).encode()).word.near_class, 3)

    def test_frame_rejects_non_wire_values(self):
        route = RunnerRoute(bsr=0)
        word = NanWord.from_bits(0, 0, 1)
        with self.assertRaises(ValueError):
            BridgeFrame(route, route, True, word, b"x").encode()
        with self.assertRaises(ValueError):
            BridgeFrame(route, route, 1, word, "not bytes").encode()
        with self.assertRaises(ValueError):
            BridgeFrame(route, route, 1, object(), b"x").encode()

    def test_crc_rejects_corruption(self):
        frame = BridgeFrame(RunnerRoute(bsr=0), RunnerRoute(bsr=1), 1,
                            NanWord.from_bits(0, 0, 7), b"x")
        raw = bytearray(frame.encode())
        raw[-5] ^= 1
        with self.assertRaises(ValueError):
            BridgeFrame.decode(bytes(raw))

    def test_mailbox_routes_both_directions(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = BridgeMailbox(Path(tmp) / "bridge.sqlite")
            a, b = RunnerRoute(bsr=0), RunnerRoute(bsr=1)
            outbound = BridgeFrame(a, b, 9, NanWord.from_bits(2, 2, 9), b"forward")
            box.put(outbound)
            self.assertEqual(BridgeFrame.decode(box.take(b)).payload, b"forward")
            reply = BridgeFrame(b, a, 10, NanWord.from_bits(3, 3, 10), b"reverse")
            box.put(reply)
            self.assertEqual(BridgeFrame.decode(box.take(a)).payload, b"reverse")
            self.assertIsNone(box.take(a))
            self.assertEqual(box.stats()["queued"], 0)
            self.assertEqual(box.stats()["max_pending_per_route"], 4096)

    def test_six_runner_identities(self):
        from nanlmind_nannet.bridge import route_for_identity
        for n in range(1, 7):
            self.assertEqual(route_for_identity(f"github-actions:shemshallah/nanlm-cpu-{n}").text(),
                             f"nan://GM0:SC0:MC0:BS0:HW0:BSR{n-1}")
        with self.assertRaises(ValueError):
            route_for_identity("github-actions:shemshallah/nanlm-cpu-7")


if __name__ == "__main__":
    unittest.main()
