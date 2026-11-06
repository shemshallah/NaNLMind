import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, "runner")
import nanlm_worker
from nanlmind_nannet.bridge import BridgeFrame, BridgeMailbox, PointZeroTranslator, RunnerRoute
from nanlmind_nannet.nan16de import NanWord


class RunnerBridgeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.old_token = nanlm_worker.PORTAL_TOKEN
        self.old_route = nanlm_worker.PORTAL_ROUTE
        self.old_translator = nanlm_worker.PORTAL_TRANSLATOR
        nanlm_worker.PORTAL_TOKEN = "test-token"

    def tearDown(self):
        nanlm_worker.PORTAL_TOKEN = self.old_token
        nanlm_worker.PORTAL_ROUTE = self.old_route
        nanlm_worker.PORTAL_TRANSLATOR = self.old_translator

    def test_native_two_phase_reverse_ack_retires_both_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            mailbox_path = str(Path(tmp) / "shared-native.sqlite")
            source, destination = RunnerRoute(bsr=0), RunnerRoute(bsr=4)
            mailbox = BridgeMailbox(mailbox_path)
            original = BridgeFrame(source, destination, 901,
                                   NanWord.from_bits(0, 0, 901), b"payload")
            mailbox.put(original)
            with patch.dict(os.environ, {"NANNET_PORTAL_API": "",
                                          "NANNET_NATIVE_MAILBOX": mailbox_path}):
                nanlm_worker.PORTAL_ROUTE = destination
                receipt = BridgeFrame(destination, source, 901,
                                      NanWord.from_bits(3, 3, 901), b"BSR_ACK")
                nanlm_worker.portal_bridge_send(receipt)
                self.assertIsNone(mailbox.claim(destination, lease_seconds=0))
                queued_receipt = BridgeFrame.decode(mailbox.claim(source, lease_seconds=0))
                self.assertEqual(queued_receipt.payload, b"BSR_ACK")
                nanlm_worker.PORTAL_ROUTE = source
                consumed = BridgeFrame(source, destination, 901,
                                       NanWord.from_bits(3, 3, 901), b"ACK")
                nanlm_worker.portal_bridge_send(consumed)
                self.assertIsNone(mailbox.claim(source, lease_seconds=0))

    def test_runner_rejects_missing_or_mismatched_point_zero_descriptor(self):
        for slot in range(6):
            nanlm_worker.PORTAL_ROUTE = RunnerRoute(bsr=slot)
            nanlm_worker.PORTAL_TRANSLATOR = PointZeroTranslator(RunnerRoute(bsr=slot))
            payload = nanlm_worker.point_zero_translator().descriptor()
            payload["route"] = RunnerRoute(bsr=slot).text()
            payload["route_bytes"] = RunnerRoute(bsr=slot).bytes().hex()
            nanlm_worker.verify_point_zero_descriptor(payload)
            bad = dict(payload)
            bad["point_zero_bytes"] = "000000000001"
            with self.assertRaises(RuntimeError):
                nanlm_worker.verify_point_zero_descriptor(bad)
            missing = dict(payload)
            del missing["point_zero_route"]
            with self.assertRaises(RuntimeError):
                nanlm_worker.verify_point_zero_descriptor(missing)

    def test_native_transport_assigns_route_and_queues_to_point_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            mailbox_path = str(Path(tmp) / "shared-native.sqlite")
            with patch.dict(os.environ, {"NANNET_PORTAL_API": "",
                                          "NANNET_NATIVE_MAILBOX": mailbox_path}):
                for slot in range(6):
                    nanlm_worker.verify_portal_identity(slot)
                    self.assertEqual(nanlm_worker.PORTAL_ROUTE, RunnerRoute(bsr=slot))
                    self.assertEqual(nanlm_worker.point_zero_translator().local_route,
                                     RunnerRoute(bsr=slot))
                    self.assertEqual(nanlm_worker.point_zero_translator().point_route,
                                     RunnerRoute(bsr=0))
                nanlm_worker.verify_portal_identity(2)
                self.assertEqual(nanlm_worker.PORTAL_ROUTE, RunnerRoute(bsr=2))
                result = nanlm_worker.portal_bridge_startup(2, 31)
                self.assertTrue(result["enabled"])
                self.assertEqual(result["transport"], "native")
                self.assertTrue(result["announced_to_root"])
                stored = BridgeMailbox(mailbox_path).take(RunnerRoute(bsr=0))
                self.assertIsNotNone(stored)
                frame = BridgeFrame.decode(stored)
                self.assertEqual(frame.source, RunnerRoute(bsr=2))
                self.assertEqual(frame.destination, RunnerRoute(bsr=0))
                self.assertEqual(frame.payload, b"BSR_ONLINE")

    def test_point_zero_drains_late_runner_announcement(self):
        with tempfile.TemporaryDirectory() as tmp:
            mailbox_path = str(Path(tmp) / "shared-native.sqlite")
            with patch.dict(os.environ, {"NANNET_PORTAL_API": "",
                                          "NANNET_NATIVE_MAILBOX": mailbox_path}):
                nanlm_worker.verify_portal_identity(0)
                root_result = nanlm_worker.portal_bridge_startup(0, 1)
                self.assertEqual(root_result["received"], 0)
                nanlm_worker.verify_portal_identity(1)
                runner_result = nanlm_worker.portal_bridge_startup(1, 2)
                self.assertTrue(runner_result["announced_to_root"])
                nanlm_worker.verify_portal_identity(0)
                self.assertEqual(nanlm_worker.portal_bridge_drain(3), 1)
                ack = BridgeFrame.decode(BridgeMailbox(mailbox_path).take(RunnerRoute(bsr=1)))
                self.assertEqual(ack.source, RunnerRoute(bsr=0))
                self.assertEqual(ack.destination, RunnerRoute(bsr=1))
                self.assertEqual(ack.payload, b"BSR_ACK")

    def test_native_transport_polls_and_returns_reverse_ack(self):
        with tempfile.TemporaryDirectory() as tmp:
            mailbox_path = str(Path(tmp) / "shared-native.sqlite")
            root, runner = RunnerRoute(bsr=0), RunnerRoute(bsr=3)
            mailbox = BridgeMailbox(mailbox_path)
            incoming = BridgeFrame(root, runner, 77,
                                   NanWord.from_bits(0, 0, 77), b"native-probe")
            mailbox.put(incoming)
            nanlm_worker.PORTAL_ROUTE = runner
            with patch.dict(os.environ, {"NANNET_PORTAL_API": "",
                                          "NANNET_NATIVE_MAILBOX": mailbox_path}):
                result = nanlm_worker.portal_bridge_startup(3, 8)
            self.assertEqual(result["transport"], "native")
            self.assertEqual(result["received"], 1)
            sent = [BridgeFrame.decode(mailbox.take(root)) for _ in range(2)]
            self.assertEqual(sent[0].payload, b"BSR_ONLINE")
            self.assertEqual(sent[1].payload, b"BSR_ACK")
            self.assertEqual(sent[1].source, runner)
            self.assertEqual(sent[1].destination, root)
            self.assertEqual(sent[1].sequence, 77)

    def test_each_non_root_runner_announces_to_point_zero(self):
        with patch.dict(os.environ, {"NANNET_PORTAL_API": "https://portal.invalid"}):
            for slot in range(1, 6):
                with self.subTest(slot=slot):
                    nanlm_worker.PORTAL_ROUTE = RunnerRoute(bsr=slot)
                    sent = []
                    with patch.object(nanlm_worker, "portal_bridge_send",
                                      side_effect=lambda frame: sent.append(frame)), \
                         patch.object(nanlm_worker, "portal_bridge_poll", return_value=None):
                        result = nanlm_worker.portal_bridge_startup(slot, 23)
                    self.assertTrue(result["enabled"])
                    self.assertTrue(result["announced_to_root"])
                    self.assertEqual(result["received"], 0)
                    self.assertEqual(len(sent), 1)
                    frame = sent[0]
                    self.assertEqual(frame.source, RunnerRoute(bsr=slot))
                    self.assertEqual(frame.destination, RunnerRoute(bsr=0))
                    self.assertEqual(frame.payload, b"BSR_ONLINE")
                    self.assertEqual((frame.word.far_class, frame.word.near_class), (0, 0))

    def test_root_is_point_zero_and_does_not_announce_to_itself(self):
        with patch.dict(os.environ, {"NANNET_PORTAL_API": "https://portal.invalid"}):
            nanlm_worker.PORTAL_ROUTE = RunnerRoute(bsr=0)
            with patch.object(nanlm_worker, "portal_bridge_send") as send, \
                 patch.object(nanlm_worker, "portal_bridge_poll", return_value=None):
                result = nanlm_worker.portal_bridge_startup(0, 23)
            self.assertFalse(result["announced_to_root"])
            send.assert_not_called()

    def test_incoming_frame_is_replied_to_on_reverse_rail(self):
        with patch.dict(os.environ, {"NANNET_PORTAL_API": "https://portal.invalid"}):
            nanlm_worker.PORTAL_ROUTE = RunnerRoute(bsr=4)
            incoming = BridgeFrame(RunnerRoute(bsr=0), RunnerRoute(bsr=4), 91,
                                   NanWord.from_bits(0, 0, 91), b"point-zero-probe")
            sent = []
            with patch.object(nanlm_worker, "portal_bridge_send",
                              side_effect=lambda frame: sent.append(frame)), \
                 patch.object(nanlm_worker, "portal_bridge_poll",
                              side_effect=[incoming, None]), \
                 patch.object(nanlm_worker, "local_path") as local_path:
                from pathlib import Path
                import tempfile
                with tempfile.TemporaryDirectory() as tmp:
                    local_path.return_value = Path(tmp)
                    result = nanlm_worker.portal_bridge_startup(4, 7)
                    inbox = Path(tmp) / "nannet_inbox_7_4.bin"
                    self.assertTrue(inbox.exists())
                    self.assertEqual(inbox.read_bytes()[4:], incoming.encode())
            self.assertEqual(result["received"], 1)
            self.assertEqual(len(sent), 2)  # startup announcement + reverse reply
            reply = sent[1]
            self.assertEqual(reply.source, RunnerRoute(bsr=4))
            self.assertEqual(reply.destination, RunnerRoute(bsr=0))
            self.assertEqual(reply.sequence, 91)
            self.assertEqual(reply.payload, b"BSR_ACK")
            self.assertEqual((reply.word.far_class, reply.word.near_class), (3, 3))


if __name__ == "__main__":
    unittest.main()
