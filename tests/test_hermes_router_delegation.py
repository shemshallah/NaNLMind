"""Portal installation signature and delegated HERMES lease trust-boundary tests."""
import base64
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest.mock import patch

from nanlmind_nannet.auth import _unb64, generate_master_key, sign_request
from nanlmind_nannet.crypto_compat import Ed25519PrivateKey, serialization
from nanlmind_nannet.pairing import PairingAuthority
from runner import training_merge


class HermesPortalDelegationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.authority = PairingAuthority(
            Path(self.tmp.name) / "auth.sqlite", _unb64(generate_master_key()))
        self.identity = "12345678-1111-4111-8111-123456789abc"
        self.private = Ed25519PrivateKey.generate()
        pub = self.private.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        pub64 = base64.urlsafe_b64encode(pub).decode().rstrip("=")
        code = self.authority.create_pairing_code(
            ["hermes:lease", "universe:read"], role="guest")
        self.token = self.authority.pair(
            code["pairing_code"], self.identity, pub64)["token"]
        self.server = training_merge.make_server(
            "127.0.0.1", 0, Path(self.tmp.name), "t" * 48, self.authority)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.thread.join)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = "http://127.0.0.1:" + str(self.server.server_port)

    def post(self, action, payload, *, signed=True, token=None, tamper=False):
        path = "/v1/hermes/leases/" + action
        raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        headers = {"Content-Type": "application/json",
                   "Authorization": "Bearer " + (self.token if token is None else token)}
        if signed:
            envelope = sign_request(self.private, "POST", path, raw)
            headers.update({
                "X-NANNET-Timestamp": str(envelope["timestamp"]),
                "X-NANNET-Nonce": envelope["nonce"],
                "X-NANNET-Body-SHA256": envelope["body_sha256"],
                "X-NANNET-Signature": envelope["signature"],
            })
        if tamper:
            raw += b" "
        req = urllib.request.Request(
            self.base + path, data=raw, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_signed_guest_delegation_binds_claims_not_user_supplied_owner_or_point(self):
        with patch.object(training_merge, "delegate_hermes_lease",
                          return_value={"receipt": {"test": "router"}}) as adapter:
            code, result = self.post("open", {
                "request_id": "hermes-request-00000000001", "ttl_seconds": 900,
                "installation_id": "attacker", "node_point": 255})
            self.assertEqual(code, 200)
            self.assertEqual(result["receipt"], {"test": "router"})
            adapter.assert_called_once_with(
                "open", {"installation_id": "attacker", "node_point": 255,
                         "request_id": "hermes-request-00000000001",
                         "ttl_seconds": 900}, self.identity)

    def test_unauthenticated_unsigned_tampered_or_revoked_requests_are_denied(self):
        with patch.object(training_merge, "delegate_hermes_lease") as adapter:
            code, _ = self.post("open", {"request_id": "test-request-000001"}, signed=False)
            self.assertNotEqual(code, 200)
            code, _ = self.post("open", {"request_id": "test-request-000001"}, tamper=True)
            self.assertNotEqual(code, 200)
            code, _ = self.post("open", {"request_id": "test-request-000001"}, token="not-valid")
            self.assertNotEqual(code, 200)
            self.authority.revoke_token(self.token)
            code, _ = self.post("open", {"request_id": "test-request-000001"})
            self.assertNotEqual(code, 200)
            adapter.assert_not_called()

    def test_signed_request_nonce_replay_is_denied(self):
        path = "/v1/hermes/leases/resolve"
        raw = b'{"receipt":{},"head_index":1}'
        envelope = sign_request(self.private, "POST", path, raw)
        headers = {
            "Authorization": "Bearer " + self.token,
            "Content-Type": "application/json",
            "X-NANNET-Timestamp": str(envelope["timestamp"]),
            "X-NANNET-Nonce": envelope["nonce"],
            "X-NANNET-Body-SHA256": envelope["body_sha256"],
            "X-NANNET-Signature": envelope["signature"],
        }
        with patch.object(training_merge, "delegate_hermes_lease",
                          return_value={"route": {"admitted": True}}) as adapter:
            codes = []
            for _ in range(2):
                req = urllib.request.Request(
                    self.base + path, data=raw, headers=headers, method="POST")
                try:
                    with urllib.request.urlopen(req, timeout=5) as response:
                        codes.append(response.status)
                except urllib.error.HTTPError as error:
                    codes.append(error.code)
            self.assertEqual(codes[0], 200)
            self.assertEqual(codes[1], 401)
            adapter.assert_called_once()

    def test_dispatch_inspection_requires_signed_scoped_identity(self):
        request = {
            "receipt": {"placeholder": "opaque-signed-router-receipt"},
            "head_index": 254, "dispatch_id": "inspect-native-00000001",
            "installation_id": "untrusted-client-installation",
        }
        with patch.object(training_merge, "delegate_hermes_lease",
                          return_value={"state": "pending_or_ambiguous"}) as delegated:
            code, result = self.post("inspect", request)
            self.assertEqual(code, 200)
            self.assertEqual(result["state"], "pending_or_ambiguous")
            delegated.assert_called_once_with("inspect", request, self.identity)
            code, _ = self.post("inspect", request, signed=False)
            self.assertEqual(code, 401)
            code, _ = self.post("inspect", request, tamper=True)
            self.assertEqual(code, 401)
            self.assertEqual(delegated.call_count, 1)

        # A separately paired installation with only universe:read may not
        # inspect or recover another HERMES installation's N16T journal.
        guest = self.authority.create_pairing_code(["universe:read"], role="guest")
        public = self.private.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        bare = self.authority.pair(
            guest["pairing_code"], "12345678-2222-4222-8222-123456789abc",
            base64.urlsafe_b64encode(public).decode().rstrip("="))["token"]
        with patch.object(training_merge, "delegate_hermes_lease") as adapter:
            code, _ = self.post("inspect", request, token=bare)
            self.assertNotEqual(code, 200)
            adapter.assert_not_called()

    def test_missing_router_secrets_fails_closed(self):
        with patch.dict("os.environ", {"NANNET_HERMES_ROUTER_URL": "",
                                      "NANNET_HERMES_DELEGATION_TOKEN": ""}):
            code, message = self.post("open", {"request_id": "test-request-000001"})
            self.assertEqual(code, 503)
            self.assertIn("error", message)


if __name__ == "__main__":
    unittest.main()
