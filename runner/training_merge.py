#!/usr/bin/env python3
"""Training-delta merge service for the bootstrap ring.

This service is intentionally small. It does not hold the 2 GiB bootstrap map.
It merges scoped head/route deltas from Android/peer runners and returns a
generation + nanclock stamp. The bootstrap runner applies the merged manifest to
the 2 GiB map.

Deploy on Koyeb with a persistent volume at /data and a scoped
NANLM_MERGE_TOKEN. Never use DEEPREPO_PAT here.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from nanlmind_nannet.auth import AuthError, _unb64, issue_token
from nanlmind_nannet.pairing import PairingAuthority
from nanlmind_nannet.devices import DeviceRegistry


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


class MergeStore:
    def __init__(self, root: Path, token: str) -> None:
        self.root = root
        self.token = token
        self.path = root / "training_merge.json"
        self.lock = threading.Lock()
        self.root.mkdir(parents=True, exist_ok=True)
        if self.path.exists():
            self.state = json.loads(self.path.read_text())
        else:
            self.state = {"nodes": {}, "idempotency": {}}

    def _save(self) -> None:
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, sort_keys=True, indent=2) + "\n")
        os.replace(tmp, self.path)

    def digest(self) -> str:
        return hashlib.sha256(canonical(self.state["nodes"])).hexdigest()

    def health(self) -> dict[str, Any]:
        with self.lock:
            return {
                "ok": True,
                "nodes": len(self.state["nodes"]),
                "digest": self.digest(),
            }

    def merge(self, payload: dict[str, Any], idempotency: str) -> tuple[int, dict[str, Any]]:
        if not idempotency:
            return HTTPStatus.BAD_REQUEST, {"error": "Idempotency-Key required"}
        with self.lock:
            prior = self.state["idempotency"].get(idempotency)
            body_hash = hashlib.sha256(canonical(payload)).hexdigest()
            if prior:
                if prior.get("body") != body_hash:
                    return HTTPStatus.CONFLICT, {"error": "idempotency key reused"}
                return HTTPStatus.OK, prior["response"]

            try:
                node = int(payload["node"])
                base = int(payload["base_generation"])
                tick = int(payload.get("nanclock_tick", 0))
                updates = payload.get("updates", [])
                if not 1 <= node <= 256:
                    raise ValueError("node out of range")
                if not isinstance(updates, list) or len(updates) > 4096:
                    raise ValueError("invalid updates")
            except (KeyError, TypeError, ValueError) as exc:
                return HTTPStatus.BAD_REQUEST, {"error": str(exc)}

            nkey = str(node)
            ns = self.state["nodes"].setdefault(nkey, {
                "generation": 0, "last_clock": 0, "heads": {}
            })
            if base != ns["generation"]:
                return HTTPStatus.CONFLICT, {
                    "error": "stale base generation",
                    "generation": ns["generation"],
                }
            if tick < ns["last_clock"]:
                return HTTPStatus.CONFLICT, {
                    "error": "stale nanclock tick",
                    "nanclock_tick": ns["last_clock"],
                }

            applied = 0
            for u in updates:
                try:
                    head = int(u["head"])
                    layer = int(u.get("layer", 0))
                    epoch = int(u.get("epoch", tick))
                    delta = int(u.get("strength_delta", 0))
                    vector = u.get("vector")
                    if not 0 <= head < 256 or not 0 <= layer < 256:
                        raise ValueError("head/layer out of range")
                    if vector is not None:
                        if not isinstance(vector, list) or len(vector) != 16:
                            raise ValueError("vector must have 16 values")
                        vector = [max(-32768, min(32767, int(x))) for x in vector]
                except (KeyError, TypeError, ValueError) as exc:
                    return HTTPStatus.BAD_REQUEST, {"error": str(exc)}

                key = f"{layer}:{head}"
                old = ns["heads"].get(key, {
                    "vector": [0] * 16, "strength": 0, "epoch": 0, "route": None
                })
                if epoch >= int(old.get("epoch", 0)):
                    if vector is not None:
                        old["vector"] = vector
                    old["strength"] = max(-32768, min(32767,
                        int(old.get("strength", 0)) + delta))
                    old["epoch"] = epoch
                    if u.get("route") is not None:
                        old["route"] = u["route"]
                ns["heads"][key] = old
                applied += 1

            ns["generation"] += 1
            ns["last_clock"] = tick
            response = {
                "accepted": True,
                "node": node,
                "generation": ns["generation"],
                "nanclock_tick": tick,
                "applied": applied,
                "digest": self.digest(),
            }
            self.state["idempotency"][idempotency] = {
                "body": body_hash,
                "response": response,
            }
            # Keep the replay table bounded; old keys can be retried after expiry.
            if len(self.state["idempotency"]) > 4096:
                for k in list(self.state["idempotency"])[:1024]:
                    del self.state["idempotency"][k]
            self._save()
            return HTTPStatus.OK, response



def _verify_github_oidc(jwt: str, expected_repository: str) -> dict[str, Any]:
    """Verify a GitHub Actions OIDC JWT against GitHub's published JWKS."""
    import base64
    import urllib.request
    from cryptography.hazmat.primitives.asymmetric import padding, rsa
    from cryptography.hazmat.primitives import hashes
    try:
        head, body, signature = jwt.split(".")
        dec = lambda value: base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
        header, claims = json.loads(dec(head)), json.loads(dec(body))
        if header.get("alg") != "RS256" or not header.get("kid"):
            raise ValueError("unsupported OIDC signing header")
        with urllib.request.urlopen("https://token.actions.githubusercontent.com/.well-known/jwks", timeout=5) as response:
            keys = json.loads(response.read(65536)).get("keys", [])
        jwk = next((item for item in keys if item.get("kid") == header["kid"]), None)
        if not jwk or jwk.get("kty") != "RSA":
            raise ValueError("unknown OIDC signing key")
        n, e = int.from_bytes(dec(jwk["n"]), "big"), int.from_bytes(dec(jwk["e"]), "big")
        public = rsa.RSAPublicNumbers(e, n).public_key()
        public.verify(dec(signature), (head + "." + body).encode("ascii"), padding.PKCS1v15(), hashes.SHA256())
        now = int(time.time())
        if claims.get("iss") != "https://token.actions.githubusercontent.com":
            raise ValueError("wrong OIDC issuer")
        if claims.get("aud") not in ("nannet-portal", ["nannet-portal"]):
            raise ValueError("wrong OIDC audience")
        if int(claims.get("exp", 0)) <= now or int(claims.get("nbf", 0)) > now + 30:
            raise ValueError("OIDC token expired or not yet valid")
        if claims.get("repository") != expected_repository or claims.get("ref") != "refs/heads/main":
            raise ValueError("runner repository or ref is not authorized")
        if claims.get("workflow_ref") != expected_repository + "/.github/workflows/runner.yml@refs/heads/main":
            raise ValueError("workflow identity is not authorized")
        return claims
    except Exception as exc:
        raise AuthError("GitHub Actions identity rejected") from exc


def make_server(host: str, port: int, root: Path, token: str, authority: PairingAuthority | None = None) -> ThreadingHTTPServer:
    store = MergeStore(root, token)
    devices = DeviceRegistry(authority.database) if authority else None

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            # Never log authorization headers or bodies.
            print(f"merge {self.address_string()} {fmt % args}", flush=True)

        def _json(self, status: int, body: dict[str, Any]) -> None:
            raw = (json.dumps(body, sort_keys=True) + "\n").encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)

        def _auth(self) -> bool:
            header = self.headers.get("Authorization", "")
            if not header.startswith("Bearer "):
                return False
            return hmac.compare_digest(header[7:], store.token)

        def do_GET(self) -> None:
            if self.path == "/healthz":
                health = store.health()
                health["nannet_authority"] = "ready" if authority else "disabled"
                self._json(HTTPStatus.OK, health)
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

        def _body(self, limit: int = 1048576) -> dict[str, Any]:
            try: length = int(self.headers.get('Content-Length', '0'))
            except ValueError: length = 0
            if length <= 0 or length > limit: raise ValueError('bad body')
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict): raise ValueError('JSON object required')
            return payload
        def _bearer(self) -> str:
            header = self.headers.get('Authorization', '')
            return header[7:] if header.startswith('Bearer ') else ''
        def do_POST(self) -> None:
            if self.path == '/v1/bootstrap/oidc':
                try:
                    payload = self._body(16384)
                    slot = payload.get("slot")
                    if isinstance(slot, bool) or not isinstance(slot, int) or not 0 <= slot < 6:
                        raise AuthError("invalid bootstrap slot")
                    repository = f"shemshallah/nanlm-cpu-{slot + 1}"
                    _verify_github_oidc(payload.get("id_token", ""), repository)
                    identity = "github-actions:" + repository
                    scopes = ["training:execute", "universe:read", "universe:register", "snapshot:read", "snapshot:write", "corpus:write", "installation:admin"]
                    token = issue_token(authority._private_key(), identity, scopes, 900, role="admin")
                    self._json(HTTPStatus.OK, {"token": token, "token_type": "Bearer", "expires_in": 900, "identity": identity, "role": "admin", "scopes": scopes})
                except (ValueError, KeyError, TypeError, AuthError) as exc:
                    self._json(HTTPStatus.UNAUTHORIZED, {"error": str(exc)[:160]})
                return
            if self.path == '/v1/training/merge':
                if not self._auth():
                    self._json(HTTPStatus.UNAUTHORIZED, {'error': 'unauthorized'}); return
                try: payload = self._body()
                except (ValueError, UnicodeDecodeError):
                    self._json(HTTPStatus.BAD_REQUEST, {'error': 'invalid json'}); return
                status, body = store.merge(payload, self.headers.get('Idempotency-Key', ''))
                self._json(status, body); return
            if authority is None or devices is None:
                self._json(HTTPStatus.SERVICE_UNAVAILABLE, {'error': 'nannet authority disabled'}); return
            try:
                if self.path == '/v1/devices/register':
                    self._json(HTTPStatus.CREATED, devices.register(self._body(8192))); return
                if self.path in ('/v1/devices/heartbeat', '/v1/devices/rotate', '/v1/devices/release', '/v1/devices/report'):
                    bearer = self._bearer()
                    if not bearer: self._json(HTTPStatus.UNAUTHORIZED, {'error': 'bearer_required'}); return
                    payload = self._body(8192) if self.path.endswith('/report') else self._body(1024)
                    if self.path.endswith('/heartbeat'): result = devices.heartbeat(bearer)
                    elif self.path.endswith('/rotate'): result = devices.rotate(bearer)
                    elif self.path.endswith('/release'): result = devices.release(bearer)
                    else: result = devices.report(bearer, payload)
                    self._json(HTTPStatus.OK, result); return
                if self.path == '/v1/pair':
                    p = self._body(16384)
                    result = authority.pair(p['pairing_code'], p['installation_id'], p['public_key'])
                    self._json(HTTPStatus.OK, result); return
                if self.path == '/v1/authorize':
                    bearer = self._bearer(); scope = self._body(4096).get('scope')
                    if not bearer or not isinstance(scope, str):
                        self._json(HTTPStatus.UNAUTHORIZED, {'error': 'bearer_or_scope_required'}); return
                    claims = authority.verify_access_token(bearer, required_scope=scope)
                    self._json(HTTPStatus.OK, {'authorized': True, 'installation_id': claims['sub'], 'scope': scope, 'expires_at': claims['exp']}); return
                if self.path == '/v1/revoke':
                    bearer = self._bearer()
                    if not bearer: self._json(HTTPStatus.UNAUTHORIZED, {'error': 'bearer_required'}); return
                    self._json(HTTPStatus.OK, authority.revoke_token(bearer)); return
                self._json(HTTPStatus.NOT_FOUND, {'error': 'not found'})
            except (ValueError, KeyError, TypeError, UnicodeDecodeError, AuthError) as exc:
                self._json(HTTPStatus.BAD_REQUEST, {'error': str(exc)[:160]})

    return ThreadingHTTPServer((host, port), Handler)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.environ.get("NANLM_MERGE_ROOT", "state"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8080")))
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()
    token = os.environ.get("NANLM_MERGE_TOKEN", "")
    if not token:
        print("NANLM_MERGE_TOKEN is required; DEEPREPO_PAT is never used", flush=True)
        return 2
    root = Path(args.root)
    authority = None
    authority_key = os.environ.get('NANNET_AUTHORITY_MASTER_KEY', '')
    if authority_key:
        try: raw_key = _unb64(authority_key)
        except Exception:
            print('NANNET_AUTHORITY_MASTER_KEY must be base64url encoded', flush=True); return 2
        if len(raw_key) != 32:
            print('NANNET_AUTHORITY_MASTER_KEY must decode to exactly 32 bytes', flush=True); return 2
        authority = PairingAuthority(os.environ.get('NANNET_AUTHORITY_DB', str(root / 'nannet-authority.sqlite')), raw_key)
    server = make_server(args.host, args.port, root, token, authority)
    print('training merge + NANNET authority listening on ' + args.host + ':' + str(args.port) + ' root=' + args.root + ' nannet=' + ('enabled' if authority else 'disabled'), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
