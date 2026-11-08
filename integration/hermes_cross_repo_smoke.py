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


def encoded(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


class Context:
    def __init__(self, config):
        self.config = config

    def get_config(self, name, default=None):
        return self.config.get(name, default)


class EndToEndTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nannet-hermes-e2e-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        delegation = "delegate-" + secrets.token_urlsafe(32)
        env = patch.dict(os.environ, {
            "RIDDLE_DATA_DIR": str(root / "router"),
            "RIDDLE_INTAKE_TOKEN": secrets.token_urlsafe(32),
            "RIDDLE_WORKER_TOKEN": secrets.token_urlsafe(32),
            "RIDDLE_FEEDBACK_HMAC_KEY": secrets.token_urlsafe(32),
            "RIDDLE_HERMES_DELEGATION_TOKEN": delegation,
            "RIDDLE_HERMES_RECEIPT_HMAC_KEY": secrets.token_urlsafe(48),
            "NANNET_HERMES_DELEGATION_TOKEN": delegation,
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
