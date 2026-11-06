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

ENDPOINTS = {"bootstrap", "my_android", "hermes_demo", "clocked_demo"}


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


class MergeStore:
    def __init__(self, root: Path, tokens: dict[str, str]) -> None:
        self.root = root
        self.tokens = {k: v for k, v in tokens.items() if k in ENDPOINTS and v}
        self.path = root / "training_merge.json"
        self.lock = threading.Lock()
        self.root.mkdir(parents=True, exist_ok=True)
        if self.path.exists():
            self.state = json.loads(self.path.read_text())
        else:
            self.state = {"nodes": {}, "idempotency": {}}

    def _save(self) -> None:
        tmp = self.path.with_suffix(".tmp")
        with tmp.open("w", encoding="utf-8") as stream:
            stream.write(json.dumps(self.state, sort_keys=True, indent=2) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, self.path)
        try:
            fd = os.open(str(self.root), os.O_RDONLY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        except OSError:
            pass

    def digest(self) -> str:
        return hashlib.sha256(canonical(self.state["nodes"])).hexdigest()

    def snapshot(self, node: int) -> dict[str, Any]:
        if not 1 <= node <= 256:
            raise ValueError("node out of range")
        with self.lock:
            state = self.state["nodes"].get(str(node), {})
            return {
                "node": node,
                "generation": int(state.get("generation", 0)),
                "nanclock_tick": int(state.get("last_clock", 0)),
                "heads": len(state.get("heads", {})),
                "digest": self.digest(),
            }

    def receipt(self, idempotency: str) -> dict[str, Any] | None:
        with self.lock:
            item = self.state["idempotency"].get(idempotency)
            return item.get("response") if item else None

    def health(self) -> dict[str, Any]:
        with self.lock:
            return {
                "ok": True,
                "nodes": len(self.state["nodes"]),
                "digest": self.digest(),
            }

    def status(self) -> dict[str, Any]:
        with self.lock:
            nodes = {
                key: {
                    "generation": int(value.get("generation", 0)),
                    "nanclock_tick": int(value.get("last_clock", 0)),
                    "heads": len(value.get("heads", {})),
                }
                for key, value in self.state["nodes"].items()
            }
            return {
                "nodes": nodes,
                "node_count": len(nodes),
                "corpus_receipts": sum(
                    1 for item in self.state["idempotency"].values()
                    if item.get("response", {}).get("dataset_id")
                ),
                "digest": self.digest(),
            }

    def merge(self, payload: dict[str, Any], idempotency: str, source_endpoint: str) -> tuple[int, dict[str, Any]]:
        if not idempotency:
            return HTTPStatus.BAD_REQUEST, {"error": "Idempotency-Key required"}
        with self.lock:
            prior = self.state["idempotency"].get(idempotency)
            if source_endpoint not in ENDPOINTS:
                return HTTPStatus.BAD_REQUEST, {"error": "invalid source endpoint"}
            claimed_source = payload.get("source_endpoint")
            if claimed_source != source_endpoint:
                return HTTPStatus.FORBIDDEN, {"error": "endpoint identity mismatch"}
            body_hash = hashlib.sha256(canonical({"source_endpoint": source_endpoint, "payload": payload})).hexdigest()
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
                "generation": 0, "last_clock": 0, "heads": {}, "sources": {}
            })
            ns.setdefault("sources", {})
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
            ns["sources"][source_endpoint] = int(ns["sources"].get(source_endpoint, 0)) + 1
            response = {
                "accepted": True,
                "node": node,
                "source_endpoint": source_endpoint,
                "dataset_id": payload.get("dataset_id"),
                "dataset_sha256": payload.get("dataset_sha256"),
                "feature_schema": payload.get("feature_schema"),
                "source_observations": ns["sources"][source_endpoint],
                "generation": ns["generation"],
                "nanclock_tick": tick,
                "applied": applied,
                "digest": self.digest(),
            }
            self.state["idempotency"][idempotency] = {
                "body": body_hash,
                "response": response,
            }
            # Corpus commits are permanent audit/idempotency records: a retry
            # after staging cleanup must never apply the same dataset twice.
            # Only generic short-lived request keys are eligible for pruning.
            if len(self.state["idempotency"]) > 4096:
                candidates = [
                    k for k, item in self.state["idempotency"].items()
                    if not item.get("response", {}).get("dataset_id")
                ]
                for k in candidates[:1024]:
                    del self.state["idempotency"][k]
            self._save()
            return HTTPStatus.OK, response


def make_server(host: str, port: int, root: Path, tokens: dict[str, str] | str) -> ThreadingHTTPServer:
    if isinstance(tokens, str):
        tokens = {"my_android": tokens}
    store = MergeStore(root, tokens)

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

        def _auth(self, endpoint: str) -> bool:
            header = self.headers.get("Authorization", "")
            expected = store.tokens.get(endpoint, "")
            if not expected or not header.startswith("Bearer "):
                return False
            return hmac.compare_digest(header[7:], expected)

        def do_GET(self) -> None:
            if self.path == "/healthz":
                self._json(HTTPStatus.OK, store.health())
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

        def do_POST(self) -> None:
            if self.path != "/v1/training/merge":
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            endpoint = self.headers.get("X-NaNLM-Endpoint", "")
            if endpoint not in ENDPOINTS or not self._auth(endpoint):
                self._json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            if length <= 0 or length > 1_048_576:
                self._json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "bad body"})
                return
            try:
                payload = json.loads(self.rfile.read(length))
            except (ValueError, UnicodeDecodeError):
                self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid json"})
                return
            if not isinstance(payload, dict):
                self._json(HTTPStatus.BAD_REQUEST, {"error": "json object required"})
                return
            status, body = store.merge(payload, self.headers.get("Idempotency-Key", ""), endpoint)
            self._json(status, body)

    return ThreadingHTTPServer((host, port), Handler)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.environ.get("NANLM_MERGE_ROOT", "state"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8080")))
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()
    tokens = {}
    for endpoint, env_name in {
        "my_android": "NANLM_MERGE_TOKEN",
        "hermes_demo": "NANLM_HERMES_TOKEN",
        "clocked_demo": "NANLM_CLOCKED_TOKEN",
        "bootstrap": "NANLM_BOOTSTRAP_TOKEN",
    }.items():
        value = os.environ.get(env_name, "")
        if value:
            tokens[endpoint] = value
    if not tokens:
        print("At least one NANLM endpoint token is required; DEEPREPO_PAT is never used", flush=True)
        return 2
    server = make_server(args.host, args.port, Path(args.root), tokens)
    print(f"training merge listening on {args.host}:{args.port} root={args.root}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
