import tempfile
import unittest
from pathlib import Path

from nanlmind_nannet.bridge import BridgeFrame, BridgeMailbox, PointZeroTranslator, RunnerRoute
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

    def test_every_runner_universe_has_point_zero_translator(self):
        point_zero = RunnerRoute(bsr=0)
        for slot in range(6):
            local = RunnerRoute(bsr=slot)
            translator = PointZeroTranslator(local)
            descriptor = translator.descriptor()
            self.assertEqual(descriptor["universe_point"], 0)
            self.assertEqual(descriptor["translator"], "N16B/1")
            self.assertEqual(descriptor["point_zero_route"], point_zero.text())
            self.assertEqual(descriptor["point_zero_bytes"], point_zero.bytes().hex())
            self.assertEqual(descriptor["local_route"], local.text())
            self.assertEqual(
                PointZeroTranslator.route_from_wire(
                    PointZeroTranslator.route_to_wire(local)), local)
            frame = translator.make_frame(point_zero, 0xA5 + slot,
                                          NanWord.from_bits(0, 0, slot), b"point-zero")
            raw = translator.encode(frame)
            decoded = translator.decode(raw, expected_destination=point_zero)
            self.assertEqual(decoded.source, local)
            self.assertEqual(decoded.destination, point_zero)
            self.assertEqual(decoded.payload, b"point-zero")
            wrong_source = RunnerRoute(bsr=(slot + 1) % 6)
            with self.assertRaises(ValueError):
                translator.encode(BridgeFrame(wrong_source, local, 1,
                                              NanWord.from_bits(0, 0, 1), b"wrong-source"))
            with self.assertRaises(ValueError):
                translator.decode(raw, expected_destination=local)

    def test_point_zero_service_adapter_accepts_authenticated_routes(self):
        translator = PointZeroTranslator()
        for slot in range(6):
            source = RunnerRoute(bsr=slot)
            frame = BridgeFrame(source, RunnerRoute(bsr=0), slot,
                                NanWord.from_bits(0, 0, slot), b"hosted")
            wire = translator.encode(frame)
            decoded = translator.decode(wire, expected_source=source)
            self.assertEqual(decoded, frame)
        with self.assertRaises(ValueError):
            translator.decode(wire, expected_source=RunnerRoute(bsr=0))

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

    def test_leased_delivery_retries_until_reverse_ack(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = BridgeMailbox(Path(tmp) / "leased.sqlite")
            source, destination = RunnerRoute(bsr=2), RunnerRoute(bsr=0)
            frame = BridgeFrame(source, destination, 123,
                                NanWord.from_bits(0, 0, 123), b"deliver-me")
            box.put(frame)
            first = BridgeFrame.decode(box.claim(destination, lease_seconds=0))
            second = BridgeFrame.decode(box.claim(destination, lease_seconds=0))
            self.assertEqual(first.payload, b"deliver-me")
            self.assertEqual(second.sequence, 123)
            self.assertTrue(box.acknowledge(source, destination, 123))
            self.assertFalse(box.acknowledge(source, destination, 123))
            self.assertIsNone(box.claim(destination, lease_seconds=0))

    def test_duplicate_reverse_receipt_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = BridgeMailbox(Path(tmp) / "idempotent.sqlite")
            source, destination = RunnerRoute(bsr=1), RunnerRoute(bsr=5)
            original = BridgeFrame(source, destination, 0xAABBCCDD,
                                   NanWord.from_bits(0, 0, 1), b"once")
            receipt = BridgeFrame(destination, source, 0xAABBCCDD,
                                  NanWord.from_bits(3, 3, 1), b"BSR_ACK")
            box.put(original)
            self.assertTrue(box.acknowledge_and_put(
                source, destination, original.sequence, receipt))
            self.assertFalse(box.acknowledge_and_put(
                source, destination, original.sequence, receipt))
            delivered = BridgeFrame.decode(box.claim(source, lease_seconds=0))
            self.assertEqual(delivered.payload, b"BSR_ACK")
            self.assertEqual(box.stats()["queued"], 1)

    def test_mailbox_applies_per_runner_backpressure(self):
        from nanlmind_nannet.bridge import MAX_PENDING_PER_ROUTE
        with tempfile.TemporaryDirectory() as tmp:
            box = BridgeMailbox(Path(tmp) / "bounded.sqlite")
            source, destination = RunnerRoute(bsr=0), RunnerRoute(bsr=5)
            for sequence in range(MAX_PENDING_PER_ROUTE):
                box.put(BridgeFrame(source, destination, sequence,
                                    NanWord.from_bits(0, 0, sequence), b"x"))
            self.assertEqual(box.stats()["queued"], MAX_PENDING_PER_ROUTE)
            with self.assertRaises(OverflowError):
                box.put(BridgeFrame(source, destination, MAX_PENDING_PER_ROUTE,
                                    NanWord.from_bits(0, 0, 0), b"overflow"))

    def test_six_runner_identities(self):
        from nanlmind_nannet.bridge import route_for_identity
        for n in range(1, 7):
            self.assertEqual(route_for_identity(f"github-actions:shemshallah/nanlm-cpu-{n}").text(),
                             f"nan://GM0:SC0:MC0:BS0:HW0:BSR{n-1}")
        with self.assertRaises(ValueError):
            route_for_identity("github-actions:shemshallah/nanlm-cpu-7")


if __name__ == "__main__":
    unittest.main()
