import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from router_ring_client import RouterRingClientError, submit_heartbeat


TOKEN = "router-ring-client-test-token-32-bytes"


class RouterRingClientTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def _json(self, status, body):
                raw = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self):
                owner.requests.append(("GET", self.path, self.headers.get("Authorization")))
                self._json(200, {"registry": {
                    "generation": 9, "registry_digest": "a" * 64,
                }, "volumes": []})

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                owner.requests.append(("POST", self.path, self.headers.get("Authorization"), body))
                self._json(200, {"accepted": True, "runner_ring": {
                    "macrocluster": "MC0:0", "health": "degraded", "in_sync": 1,
                }})

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.thread.join)
        self.addCleanup(self.server.server_close)
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def test_reads_registry_then_acknowledges_exact_generation_and_digest(self):
        result = submit_heartbeat(self.base, TOKEN, 4, 1_800_000_000)
        self.assertEqual(result["macrocluster"], "MC0:0")
        self.assertEqual([r[0] for r in self.requests], ["GET", "POST"])
        self.assertEqual(self.requests[0][2], "Bearer " + TOKEN)
        self.assertEqual(self.requests[1][2], "Bearer " + TOKEN)
        self.assertEqual(self.requests[1][3], {
            "slot": 4, "runner_id": "MC0:0/R4",
            "registry_generation": 9, "registry_digest": "a" * 64,
            "nanclock_tick": 1_800_000_000,
        })

    def test_rejects_non_tls_remote_origin(self):
        with self.assertRaises(RouterRingClientError):
            submit_heartbeat("http://example.com", TOKEN, 0, 1)

    def test_rejects_invalid_slot_and_short_token(self):
        with self.assertRaises(RouterRingClientError):
            submit_heartbeat(self.base, TOKEN, 6, 1)
        with self.assertRaises(RouterRingClientError):
            submit_heartbeat(self.base, "short", 0, 1)


if __name__ == "__main__":
    unittest.main()
