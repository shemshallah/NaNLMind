import hashlib
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from clocked_router_consumer import consume_clocked_sources

TOKEN = "clocked-router-consumer-test-token-32-bytes"


class ClockedRouterConsumerTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        self.payload = {
            "schema": "nanlm.clocked-router-source.v1",
            "clocked_event_id": "1" * 64,
            "source_endpoint": "clocked_demo",
            "nannet_address": "nan://GM0:SC0:MC0:BS0:HW3",
            "node_point": 9,
            "input_sha256": "2" * 64,
            "response_sha256": "3" * 64,
            "base_generation": 5,
            "outcome_verified": False,
            "raw_text_persisted": False,
        }
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def respond(self, status, body):
                raw = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                owner.requests.append((self.path, self.headers.get("Authorization"), body))
                if self.path == "/v1/riddle/lease":
                    if sum(1 for item in owner.requests if item[0] == self.path) > 1:
                        return self.respond(200, {"event": None})
                    payload = owner.payload if owner.payload is not None else b"invalid"
                    if isinstance(payload, dict):
                        payload = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
                    event = {
                        "event_id": "4" * 64, "universe_id": "BS0:0",
                        "node_point": 9, "head_index": 17,
                        "source_kind": "clocked-evidence",
                        "source_hash": "5" * 64, "payload_hex": payload.hex(),
                        "acl_digest": "6" * 64, "nanclock_tick": 1800000000,
                        "lease_owner": body["owner"], "attempts": 1,
                    }
                    return self.respond(200, event)
                if self.path == "/v1/riddle/ack":
                    return self.respond(200, {"acknowledged": True, "event_id": body["event_id"]})
                if self.path == "/v1/riddle/retry":
                    return self.respond(200, {"event_id": body["event_id"], "state": "queued"})
                return self.respond(404, {"error": "not_found"})

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.thread.join)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def test_valid_clocked_receipt_is_leased_and_acked_as_unverified(self):
        result = consume_clocked_sources(self.base, TOKEN, 2, 1800000001, max_events=4)
        self.assertEqual(result["processed"], 1)
        self.assertEqual(result["failed"], 0)
        self.assertFalse(result["model_update"])
        lease = next(item for item in self.requests if item[0] == "/v1/riddle/lease")
        self.assertEqual(lease[1], "Bearer " + TOKEN)
        self.assertEqual(lease[2]["owner"], "HW0::BS0/R2")
        self.assertEqual(lease[2]["source_kind"], "clocked-evidence")
        ack = next(item for item in self.requests if item[0] == "/v1/riddle/ack")
        self.assertEqual(ack[2]["result_generation"], 5)
        self.assertFalse(ack[2]["trace"]["correct"])
        self.assertFalse(ack[2]["trace"]["outcome_verified"])
        self.assertEqual(ack[2]["trace"]["source_hash"], "5" * 64)

    def test_invalid_clocked_receipt_is_retried_not_acked(self):
        self.payload = b"invalid"
        result = consume_clocked_sources(self.base, TOKEN, 0, 1800000001, max_events=1)
        self.assertEqual(result["processed"], 0)
        self.assertEqual(result["failed"], 1)
        self.assertTrue(any(item[0] == "/v1/riddle/retry" for item in self.requests))
        self.assertFalse(any(item[0] == "/v1/riddle/ack" for item in self.requests))


if __name__ == "__main__":
    unittest.main()
