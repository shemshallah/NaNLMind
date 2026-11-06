import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, "runner")
import nanlm_worker
from nanlmind_nannet.bridge import BridgeFrame, RunnerRoute
from nanlmind_nannet.nan16de import NanWord


class RunnerBridgeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.old_token = nanlm_worker.PORTAL_TOKEN
        self.old_route = nanlm_worker.PORTAL_ROUTE
        nanlm_worker.PORTAL_TOKEN = "test-token"

    def tearDown(self):
        nanlm_worker.PORTAL_TOKEN = self.old_token
        nanlm_worker.PORTAL_ROUTE = self.old_route

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
