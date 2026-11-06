import http.client
import json
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from training_merge import make_server


class RawRouteApiTests(unittest.TestCase):
    ROUTE = "nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1,2,3::vector1337"

    def test_authenticated_health_commit_and_resolve(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mounts = {
                namespace: [str(root / namespace.lower())]
                for namespace in ("BS0", "MC0", "SC0", "GM0")
            }
            with patch.dict(os.environ, {"NANLM_RAWROUTE_MOUNTS": json.dumps(mounts)}):
                server = make_server("127.0.0.1", 0, root / "service", "test-merge-token")
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=5)
            headers = {"Authorization": "Bearer test-merge-token",
                       "Content-Type": "application/json"}
            try:
                connection.request("GET", "/v1/rawroute/health",
                                   headers={"Authorization": headers["Authorization"]})
                response = connection.getresponse()
                health = json.loads(response.read())
                self.assertEqual(response.status, 200)
                self.assertEqual(set(health["namespaces"]), {"BS0", "MC0", "SC0", "GM0"})
                self.assertEqual(health["namespaces"]["BS0"]["quota_bytes"], 9_500_000_000)

                payload = {
                    "namespace": "BS0",
                    "route": self.ROUTE,
                    "base_generation": 0,
                    "nanclock_tick": 44,
                    "idempotency_key": "api-route-commit-1",
                }
                connection.request("POST", "/v1/rawroute/commit",
                                   body=json.dumps(payload), headers=headers)
                response = connection.getresponse()
                committed = json.loads(response.read())
                self.assertEqual(response.status, 202)
                self.assertEqual(committed["generation"], 1)
                self.assertEqual(committed["namespace"], "BS0")

                from urllib.parse import quote
                target = "/v1/rawroute/resolve?namespace=BS0&route=" + quote(self.ROUTE, safe="")
                connection.request("GET", target,
                                   headers={"Authorization": headers["Authorization"]})
                response = connection.getresponse()
                resolved = json.loads(response.read())
                self.assertEqual(response.status, 200)
                self.assertTrue(resolved["found"])
                self.assertEqual(resolved["route"]["generation"], 1)

                reverse = "/v1/rawroute/reverse?namespace=BS0&target_kind=vector&target_id=1337"
                connection.request("GET", reverse,
                                   headers={"Authorization": headers["Authorization"]})
                response = connection.getresponse()
                reverse_result = json.loads(response.read())
                self.assertEqual(response.status, 200)
                self.assertEqual(reverse_result["routes"], [self.ROUTE])

                replay_payload = dict(payload)
                replay_payload["idempotency_key"] = "api-route-commit-1"
                connection.request("POST", "/v1/rawroute/commit",
                                   body=json.dumps(replay_payload), headers=headers)
                response = connection.getresponse()
                replay_result = json.loads(response.read())
                self.assertEqual(response.status, 202)
                self.assertTrue(replay_result["replay"])

                payload["base_generation"] = 0
                payload["nanclock_tick"] = 45
                payload["idempotency_key"] = "api-route-stale-commit"
                connection.request("POST", "/v1/rawroute/commit",
                                   body=json.dumps(payload), headers=headers)
                response = connection.getresponse()
                response.read()
                self.assertEqual(response.status, 409)

                connection.request("GET", "/v1/rawroute/health")
                response = connection.getresponse()
                response.read()
                self.assertEqual(response.status, 401)
            finally:
                connection.close()
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
