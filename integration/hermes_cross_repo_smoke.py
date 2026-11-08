#!/usr/bin/env python3
"""Real three-repository HERMES -> signed NANNET -> NaNROUTER HTTP smoke.

Runs three local HTTP/identity components with disposable credentials and
temporary SQLite stores, never a live Koyeb/runner service. This verifies
delegated control-plane integration only, NOT native guest execution.
"""
from __future__ import annotations

import base64
import os
import secrets
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

from runner.training_merge import make_server as make_portal
from nanlmind_nannet.pairing import PairingAuthority
from runner_riddle.http_service import RiddleService, make_handler
from nanlmind_hermes import auth_tools
from nanlmind_hermes import router_universe_client as hermes
from runner_riddle.n16t_guest import (_NaN16GuestVM, REQUEST_BASE, RESPONSE_PAYLOAD_BASE, SESSION_BASE)


def encoded(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


class Context:
    def __init__(self, config):
        self.config = config

    def get_config(self, name, default=None):
        return self.config.get(name, default)


class NativeSourceParityTests(unittest.TestCase):
    def test_lease_and_route_guest_semantics_are_byte_identical(self):
        root = Path(__file__).resolve().parents[1]
        pairs = (
            (root / "nanrouter/mth/nan16/hermes_lease.nas",
             root / "nanhermes/nanlmind_hermes/nan/hermes_lease.nas"),
            (root / "nanrouter/mth/nan16/hermes_nannet_route.nas",
             root / "nanhermes/nanlmind_hermes/nan/hermes_nannet_route.nas"),
        )
        for router_path, hermes_path in pairs:
            with self.subTest(guest=router_path.name):
                router_source = router_path.read_text(encoding="utf-8")
                hermes_source = hermes_path.read_text(encoding="utf-8")
                # Each module documents its own repo-local import path.
                normalized = router_source.replace(
                    "mth/nan16/hermes_lease.nas",
                    "nanlmind_hermes/nan/hermes_lease.nas")
                self.assertEqual(normalized, hermes_source,
                                 "native NaN16 lease authority diverged across repos")


class EndToEndTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nannet-hermes-e2e-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        delegation = "delegate-" + secrets.token_urlsafe(32)
        self.native_enabled = all(os.environ.get(k) for k in (
            "NAN16_LIBRARY", "HERMES_GUEST_IMAGE", "HERMES_GUEST_LABELS",
            "RIDDLE_HERMES_NATIVE_LIBRARY_SHA256", "RIDDLE_HERMES_NATIVE_IMAGE_SHA256",
            "N16T_GUEST_IMAGE", "N16T_GUEST_LABELS"))
        env = patch.dict(os.environ, {
            "RIDDLE_DATA_DIR": str(root / "router"),
            "RIDDLE_INTAKE_TOKEN": secrets.token_urlsafe(32),
            "RIDDLE_WORKER_TOKEN": secrets.token_urlsafe(32),
            "RIDDLE_FEEDBACK_HMAC_KEY": secrets.token_urlsafe(32),
            "RIDDLE_HERMES_DELEGATION_TOKEN": delegation,
            "RIDDLE_HERMES_RECEIPT_HMAC_KEY": secrets.token_urlsafe(48),
            "NANNET_HERMES_DELEGATION_TOKEN": delegation,
            **({"RIDDLE_N16T_SUBMIT_TOKEN": secrets.token_urlsafe(32)}
               if self.native_enabled else {}),
        })
        env.start()
        self.addCleanup(env.stop)
        router = RiddleService()
        self.addCleanup(router.close)
        router_server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(router))
        self._serve(router_server)
        os.environ["NANNET_HERMES_ROUTER_URL"] = (
            "http://127.0.0.1:" + str(router_server.server_port))
        authority = PairingAuthority(root / "authority.sqlite", secrets.token_bytes(32))
        portal = make_portal("127.0.0.1", 0, root / "portal", "merge-" +
                             secrets.token_urlsafe(32), authority)
        self._serve(portal)
        key = encoded(secrets.token_bytes(32))
        self.secret = patch.object(auth_tools, "get_secret",
                                   side_effect=lambda name: key if name == "NANNET_MASTER_KEY" else "")
        self.secret.start()
        self.addCleanup(self.secret.stop)
        self.ctx = Context({
            "state_dir": str(root / "hermes"),
            "nannet_auth_url": "http://127.0.0.1:" + str(portal.server_port),
            "nannet_issuer_public_key": authority.issuer_public_key(),
        })
        auth_tools.auth_init(self.ctx)
        code = authority.create_pairing_code(
            ["universe:read", "hermes:lease"], role="guest")
        self.paired = auth_tools.auth_pair(self.ctx, code["pairing_code"])
        self.assertTrue(self.paired["paired"])

    def _serve(self, server):
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        # Cleanup executes in reverse registration order.
        self.addCleanup(thread.join)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

    def test_real_signed_pair_open_resolve_renew_release_and_isolation(self):
        first = hermes.open_universe(self.ctx, "alpha")
        second = hermes.open_universe(self.ctx, "beta")
        self.assertNotEqual(first["universe_id"], second["universe_id"])
        self.assertNotEqual(first["slot"], second["slot"])
        self.assertEqual(first["node_point"], 3)
        self.assertEqual(second["node_point"], 3)
        resolved = hermes.resolve(self.ctx, "alpha", 254)
        self.assertTrue(resolved["admitted"])
        self.assertEqual(resolved["universe_id"], first["universe_id"])
        self.assertFalse(resolved["execution_committed"])
        with self.assertRaises(hermes.UniverseLeaseError):
            hermes.resolve(self.ctx, "alpha", 255)
        renew = hermes.renew(self.ctx, "alpha")
        self.assertEqual(renew["revision"], 2)
        again = hermes.resolve(self.ctx, "alpha", 0)
        self.assertTrue(again["admitted"])
        self.assertEqual(again["generation"], first["generation"])
        self.assertTrue(hermes.release(self.ctx, "alpha")["released"])
        self.assertTrue(hermes.resolve(self.ctx, "beta", 0)["admitted"])
        self.assertTrue(hermes.release(self.ctx, "beta")["released"])
        self.assertFalse(hermes.status(self.ctx)["leases"])

    def test_real_signed_native_n16t_dispatch_and_ack(self):
        if not self.native_enabled:
            self.skipTest("real pinned VM images not configured")
        opened = hermes.open_universe(self.ctx, "native")
        route = hermes.resolve(self.ctx, "native", 254)
        self.assertTrue(route["native_guest_activated"])
        self.assertTrue(route["execution_committed"])
        client = _NaN16GuestVM(
            os.environ["NAN16_LIBRARY"],
            os.environ["N16T_GUEST_IMAGE"],
            os.environ["N16T_GUEST_LABELS"])
        try:
            client.write_bytes(SESSION_BASE, bytes(range(1, 17)))
            client.write_bytes(RESPONSE_PAYLOAD_BASE, b"\\x01\\x00")
            client.call("n16_android_build", {
                1: REQUEST_BASE, 2: 1, 4: RESPONSE_PAYLOAD_BASE,
                5: 2, 6: SESSION_BASE})
            self.assertEqual(client.reg(3), 0)
            frame = client.read_bytes(REQUEST_BASE, client.reg(1))
            client.call("n16_android_advance")
            sent = hermes.dispatch(
                self.ctx, "native", 254, "three-repo-dispatch-000001", frame.hex())
            self.assertTrue(sent["native_guest_route_admitted"])
            self.assertTrue(sent["n16t_native_guest_exchange"])
            self.assertFalse(sent["model_training_committed"])
            self.assertFalse(sent["acknowledged"])
            repeated = hermes.dispatch(
                self.ctx, "native", 254, "three-repo-dispatch-000001", frame.hex())
            self.assertTrue(repeated["replayed_from_journal"])
            self.assertEqual(sent["response_sha256"], repeated["response_sha256"])
            acked = hermes.acknowledge(
                self.ctx, "native", 254, "three-repo-dispatch-000001",
                sent["response_sha256"])
            self.assertTrue(acked["acknowledged"])
            with self.assertRaises(hermes.UniverseLeaseError):
                hermes.acknowledge(
                    self.ctx, "native", 254, "three-repo-dispatch-000001", "0" * 64)
        finally:
            client.close()
        self.assertTrue(hermes.release(self.ctx, "native")["released"])

    def test_authority_revocation_denies_new_router_operation(self):
        first = hermes.open_universe(self.ctx, "alpha")
        self.assertTrue(first["opened"])
        auth_tools.auth_revoke(self.ctx)
        with self.assertRaises((ValueError, hermes.UniverseLeaseError)):
            hermes.resolve(self.ctx, "alpha", 0)
        # The remote router still owns lease expiry; local authentication
        # revocation denies further user-originated route authorization.


if __name__ == "__main__":
    unittest.main()
