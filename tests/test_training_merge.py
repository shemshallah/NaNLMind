import json
import base64
import struct
import zlib
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "runner"))
import training_merge  # noqa: E402
from nanlmind_nannet.auth import _unb64, generate_master_key
from nanlmind_nannet.pairing import PairingAuthority
from nanlmind_nannet.devices import TERMS_VERSION
from nanlmind_nannet.auth import AuthError, identity_public_key
from nanlmind_nannet.crypto_compat import serialization
from nanlmind_nannet.crypto_compat import Ed25519PrivateKey


class TrainingMergeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.server = training_merge.make_server(
            "127.0.0.1", 0, Path(self.tmp.name), "test-token")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.tmp.cleanup()

    def post(self, payload, key, token="test-token"):
        req = urllib.request.Request(
            self.base + "/v1/training/merge",
            data=json.dumps(payload).encode(),
            method="POST",
            headers={
                "Authorization": "Bearer " + token,
                "Content-Type": "application/json",
                "Idempotency-Key": key,
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def payload(self, base=0, tick=10, delta=1):
        return {
            "node": 2,
            "base_generation": base,
            "nanclock_tick": tick,
            "updates": [{
                "head": 7,
                "layer": 3,
                "epoch": tick,
                "vector": [1] * 16,
                "strength_delta": delta,
                "route": {"bank": 1, "bin": 9001, "slot": 7},
            }],
        }

    def test_merge_idempotency_and_stale_base(self):
        status, body = self.post(self.payload(), "k1")
        self.assertEqual(status, 200)
        self.assertEqual(body["generation"], 1)
        self.assertEqual(body["applied"], 1)

        status, replay = self.post(self.payload(), "k1")
        self.assertEqual(status, 200)
        self.assertEqual(replay, body)

        status, stale = self.post(self.payload(base=0), "k2")
        self.assertEqual(status, 409)
        self.assertIn("stale", stale["error"])

        status, next_merge = self.post(self.payload(base=1, tick=11, delta=2), "k3")
        self.assertEqual(status, 200)
        self.assertEqual(next_merge["generation"], 2)

        status, bad_key = self.post(self.payload(base=2, tick=12), "k3")
        self.assertEqual(status, 409)

    def test_unified_authority_device_lease_routes(self):
        db = Path(self.tmp.name) / 'authority.sqlite'
        authority = PairingAuthority(db, _unb64(generate_master_key()))
        server = training_merge.make_server('127.0.0.1', 0, Path(self.tmp.name), 'test-token', authority)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = 'http://127.0.0.1:' + str(server.server_address[1])
        try:
            payload = {'device_secret': 'q' * 43, 'consent': True, 'terms_version': TERMS_VERSION, 'system_report': {'platform': 'test'}}
            req = urllib.request.Request(base + '/v1/devices/register', data=json.dumps(payload).encode(), method='POST', headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=5) as response:
                enrolled = json.loads(response.read())
                self.assertEqual(response.status, 201)
            duplicate = urllib.request.Request(base + '/v1/devices/register', data=json.dumps(payload).encode(), method='POST', headers={'Content-Type': 'application/json'})
            with self.assertRaises(urllib.error.HTTPError) as duplicate_error:
                urllib.request.urlopen(duplicate, timeout=5)
            self.assertEqual(duplicate_error.exception.code, 400)
            headers = {'Authorization': 'Bearer ' + enrolled['token'], 'Content-Type': 'application/json'}
            req = urllib.request.Request(base + '/v1/devices/rotate', data=b'{}', method='POST', headers=headers)
            with urllib.request.urlopen(req, timeout=5) as response:
                rotated = json.loads(response.read())
            self.assertEqual(rotated['address'], enrolled['address'])
            self.assertNotEqual(rotated['token'], enrolled['token'])
            self.assertEqual(authority.verify_access_token(rotated['token'][4:], "training:execute")["role"], "guest")
            with self.assertRaises(AuthError):
                authority.verify_access_token(enrolled['token'][4:], "training:execute")
            req = urllib.request.Request(base + '/v1/devices/heartbeat', data=b'{}', method='POST', headers={'Authorization': 'Bearer ' + rotated['token'], 'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=5) as response:
                renewed = json.loads(response.read())
            self.assertNotEqual(renewed['token'], rotated['token'])
            req = urllib.request.Request(base + '/v1/devices/release', data=b'{}', method='POST', headers={'Authorization': 'Bearer ' + renewed['token'], 'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=5):
                pass
            with self.assertRaises(AuthError):
                authority.verify_access_token(renewed['token'][4:], "training:execute")
            health = urllib.request.urlopen(base + '/healthz', timeout=5)
            self.assertEqual(json.loads(health.read())['nannet_authority'], 'ready')
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=2)


    def test_role_separated_pairing_and_identity_revocation(self):
        db = Path(self.tmp.name) / "roles.sqlite"
        master = _unb64(generate_master_key())
        authority = PairingAuthority(db, master)
        guest_pub = identity_public_key(master, "guest", "device-A")
        admin_pub = identity_public_key(master, "admin", "device-A")
        self.assertEqual(guest_pub, identity_public_key(master, "guest", "device-A"))
        self.assertNotEqual(guest_pub, admin_pub)
        with self.assertRaises(AuthError):
            authority.create_pairing_code(["installation:admin"], role="guest")
        guest_code = authority.create_pairing_code(["universe:read", "snapshot:read"], role="guest")
        admin_code = authority.create_pairing_code(["installation:admin", "training:execute"], role="admin")
        guest_private = Ed25519PrivateKey.generate()
        guest_public = guest_private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        admin_private = Ed25519PrivateKey.generate()
        admin_public = admin_private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        guest_id = "00000000-0000-4000-8000-000000000001"
        admin_id = "00000000-0000-4000-8000-000000000002"
        b64 = lambda value: __import__("base64").urlsafe_b64encode(value).decode().rstrip("=")
        guest = authority.pair(guest_code["pairing_code"], guest_id, b64(guest_public))
        admin = authority.pair(admin_code["pairing_code"], admin_id, b64(admin_public))
        self.assertEqual(guest["role"], "guest")
        self.assertEqual(admin["role"], "admin")
        self.assertEqual(authority.verify_access_token(guest["token"], "universe:read")["role"], "guest")
        self.assertEqual(authority.verify_access_token(admin["token"], "installation:admin")["role"], "admin")
        authority.revoke_identity("admin", admin_id)
        with self.assertRaises(AuthError):
            authority.verify_access_token(admin["token"], "installation:admin")


    def test_bsr_oidc_bootstrap_rotation_and_admin_revocation(self):
        db = Path(self.tmp.name) / "bsr.sqlite"
        authority = PairingAuthority(db, _unb64(generate_master_key()))
        server = training_merge.make_server("127.0.0.1", 0, Path(self.tmp.name), "test-token", authority)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        original_verifier = training_merge._verify_github_oidc
        training_merge._verify_github_oidc = lambda jwt, repo: {"repository": repo, "jti": "test-oidc-jti", "exp": int(__import__("time").time()) + 300, "event_name": "workflow_dispatch"}
        base = "http://127.0.0.1:" + str(server.server_address[1])
        def call(path, payload, token=None):
            headers = {"Content-Type": "application/json"}
            if token:
                headers["Authorization"] = "Bearer " + token
            request = urllib.request.Request(base + path, data=json.dumps(payload).encode(), method="POST", headers=headers)
            try:
                with urllib.request.urlopen(request, timeout=5) as response:
                    return response.status, json.loads(response.read())
            except urllib.error.HTTPError as exc:
                return exc.code, json.loads(exc.read())
        thread.start()
        try:
            status, issued = call("/v1/bootstrap/oidc", {"id_token": "mock", "slot": 0})
            self.assertEqual(status, 200)
            self.assertEqual(issued["role"], "admin")
            replay_status, _ = call("/v1/bootstrap/oidc", {"id_token": "mock", "slot": 0})
            self.assertEqual(replay_status, 401)
            identity = issued["identity"]
            status, auth = call("/v1/authorize", {"scope": "training:execute"}, issued["token"])
            self.assertEqual(status, 200)
            status, renewed = call("/v1/bootstrap/heartbeat", {}, issued["token"])
            self.assertEqual(status, 200)
            self.assertNotEqual(renewed["token"], issued["token"])
            status, denied = call("/v1/authorize", {"scope": "training:execute"}, issued["token"])
            self.assertEqual(status, 401)
            status, revoked = call("/v1/admin/identities/revoke", {"role": "admin", "identity": identity}, renewed["token"])
            self.assertEqual(status, 200)
            status, denied = call("/v1/authorize", {"scope": "training:execute"}, renewed["token"])
            self.assertEqual(status, 401)
        finally:
            training_merge._verify_github_oidc = original_verifier
            server.shutdown(); server.server_close(); thread.join(timeout=2)

    def test_n16t_hello_capabilities_and_portal_alias(self):
        session = bytes(range(1, 17))
        payload = b"\x01\x00"
        header = struct.pack("<4sHH16sII", b"N16T", 1, 1, session, 1, len(payload))
        body = header + payload
        frame = body + struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)
        for path in ("/portal", "/portal/", "/n16t", "/n16t/"):
            request = urllib.request.Request(
                self.base + path, data=frame, method="POST",
                headers={"Content-Type": "application/vnd.nan16.n16t",
                         "Accept": "application/vnd.nan16.n16t"})
            with urllib.request.urlopen(request, timeout=5) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers.get_content_type(),
                                 "application/vnd.nan16.n16t")
                peer = response.read()
            self.assertEqual(len(peer), 44)
            magic, version, kind, peer_session, sequence, length = struct.unpack_from(
                "<4sHH16sII", peer)
            self.assertEqual((magic, version, kind, peer_session, sequence, length),
                             (b"N16T", 1, 2, session, 1, 8))
            self.assertEqual(struct.unpack_from("<H6B", peer, 32), (0x000F, 0, 0, 0, 0, 0, 0))
            self.assertEqual(struct.unpack_from("<I", peer, 40)[0],
                             zlib.crc32(peer[:40]) & 0xFFFFFFFF)

        bad = bytearray(frame)
        bad[-1] ^= 0x80
        request = urllib.request.Request(
            self.base + "/n16t", data=bytes(bad), method="POST",
            headers={"Content-Type": "application/vnd.nan16.n16t"})
        with self.assertRaises(urllib.error.HTTPError) as error:
            urllib.request.urlopen(request, timeout=5)
        self.assertEqual(error.exception.code, 400)

        for path in ("/portal", "/portal/"):
            with urllib.request.urlopen(self.base + path, timeout=5) as response:
                self.assertEqual(response.status, 200)
                self.assertIn(b"POST /n16t", response.read())

    def test_auth_and_health(self):
        status, body = self.post(self.payload(), "auth", token="wrong")
        self.assertEqual(status, 401)
        with urllib.request.urlopen(self.base + "/healthz", timeout=5) as r:
            health = json.loads(r.read())
        self.assertTrue(health["ok"])
        self.assertEqual(health["nodes"], 0)


if __name__ == "__main__":
    unittest.main()
