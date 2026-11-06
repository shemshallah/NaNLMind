#!/usr/bin/env python3
"""Hardware-neutral, quota-limited gateway for Clocked-backed NaNLMind demos.

The upstream Clocked credential never leaves this process. Participants receive
short-lived CLOCKED_USER_API tokens that authenticate only to this gateway.
"""
from __future__ import annotations

import hashlib
import json
import os
import secrets
import sqlite3
import time
from pathlib import Path
from typing import Any, Dict
from wsgiref.simple_server import make_server

from clocked_experience import build_pipeline, make_event

MAX_BODY = 64 * 1024
SCHEMA_VERSION = 1


def token_hash(token: str, pepper: str) -> str:
    return hashlib.sha256((pepper + token).encode("utf-8")).hexdigest()


def connect_db(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute("""
        CREATE TABLE IF NOT EXISTS demo_tokens (
            token_hash TEXT PRIMARY KEY,
            tenant_id TEXT NOT NULL,
            expires_at INTEGER NOT NULL,
            max_requests INTEGER NOT NULL,
            used_requests INTEGER NOT NULL DEFAULT 0,
            revoked INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
        )
    """)
    db.commit()
    return db


def json_response(start_response, status: str, payload: Dict[str, Any]):
    body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    start_response(status, [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
        ("X-Content-Type-Options", "nosniff"),
    ])
    return [body]


class Gateway:
    def __init__(self, db_path: str, clocked_client=None):
        self.db_path = db_path
        self.clocked_client = clocked_client

    def __call__(self, environ, start_response):
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        if method == "GET" and path == "/healthz":
            return json_response(start_response, "200 OK", {
                "status": "ok", "protocol": "nanlm.clocked-experience",
                "protocol_version": SCHEMA_VERSION,
            })
        if method == "POST" and path == "/admin/tokens":
            return self.issue_token(environ, start_response)
        if method == "POST" and path == "/v1/experience":
            return self.run_experience(environ, start_response)
        return json_response(start_response, "404 Not Found", {"error": "not_found"})

    def read_body(self, environ):
        try:
            length = int(environ.get("CONTENT_LENGTH") or "0")
        except ValueError:
            raise ValueError("invalid_content_length")
        if length <= 0 or length > MAX_BODY:
            raise ValueError("body_size_out_of_range")
        raw = environ["wsgi.input"].read(length)
        try:
            value = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise ValueError("invalid_json")
        if not isinstance(value, dict):
            raise ValueError("json_object_required")
        return value

    def issue_token(self, environ, start_response):
        admin = os.environ.get("CLOCKED_GATEWAY_ADMIN_TOKEN", "")
        pepper = os.environ.get("CLOCKED_TOKEN_PEPPER", "")
        supplied = environ.get("HTTP_AUTHORIZATION", "")
        if not admin or not pepper or not secrets.compare_digest(
            supplied, "Bearer " + admin
        ):
            return json_response(start_response, "401 Unauthorized", {"error": "unauthorized"})
        try:
            data = self.read_body(environ)
            tenant_id = str(data.get("tenant_id", "demo"))[:64]
            max_requests = int(data.get("max_requests", 25))
            ttl_seconds = int(data.get("ttl_seconds", 21600))
            if not tenant_id or not (1 <= max_requests <= 500) or not (60 <= ttl_seconds <= 86400):
                raise ValueError("token_policy_out_of_range")
        except (ValueError, TypeError) as exc:
            return json_response(start_response, "400 Bad Request", {"error": str(exc)[:64]})
        token = "clu_" + secrets.token_urlsafe(32)
        now = int(time.time())
        db = connect_db(self.db_path)
        try:
            db.execute(
                "INSERT INTO demo_tokens(token_hash,tenant_id,expires_at,max_requests,created_at) VALUES(?,?,?,?,?)",
                (token_hash(token, pepper), tenant_id, now + ttl_seconds, max_requests, now),
            )
            db.commit()
        finally:
            db.close()
        # Returned exactly once. Store only the peppered digest.
        return json_response(start_response, "201 Created", {
            "token_type": "CLOCKED_USER_API",
            "token": token,
            "tenant_id": tenant_id,
            "expires_at": now + ttl_seconds,
            "max_requests": max_requests,
        })

    def reserve_request(self, token: str):
        pepper = os.environ.get("CLOCKED_TOKEN_PEPPER", "")
        if not pepper:
            return None, "gateway_misconfigured"
        db = connect_db(self.db_path)
        try:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM demo_tokens WHERE token_hash=?",
                (token_hash(token, pepper),),
            ).fetchone()
            now = int(time.time())
            if row is None or row["revoked"] or row["expires_at"] <= now:
                db.rollback()
                return None, "unauthorized"
            if row["used_requests"] >= row["max_requests"]:
                db.rollback()
                return None, "quota_exceeded"
            db.execute(
                "UPDATE demo_tokens SET used_requests=used_requests+1 WHERE token_hash=?",
                (row["token_hash"],),
            )
            db.commit()
            return {"tenant_id": row["tenant_id"], "remaining": row["max_requests"] - row["used_requests"] - 1}, None
        finally:
            db.close()

    def run_experience(self, environ, start_response):
        auth = environ.get("HTTP_AUTHORIZATION", "")
        if not auth.startswith("Bearer ") or len(auth) > 512:
            return json_response(start_response, "401 Unauthorized", {"error": "unauthorized"})
        identity, error = self.reserve_request(auth[7:])
        if error:
            status = "429 Too Many Requests" if error == "quota_exceeded" else (
                "503 Service Unavailable" if error == "gateway_misconfigured" else "401 Unauthorized"
            )
            return json_response(start_response, status, {"error": error})
        try:
            data = self.read_body(environ)
            if data.get("protocol") not in (None, "nanlm.clocked-experience"):
                raise ValueError("unsupported_protocol")
            source_text = data.get("text")
            if not isinstance(source_text, str) or not source_text.strip():
                raise ValueError("text_required")
            if len(source_text.encode("utf-8")) > MAX_BODY:
                raise ValueError("text_too_large")
        except (ValueError, TypeError) as exc:
            return json_response(start_response, "400 Bad Request", {"error": str(exc)[:64]})

        try:
            if self.clocked_client is None:
                from clocked_sdk import Clocked
                with Clocked() as client:
                    response = client.pipeline(
                        text=source_text, steps=build_pipeline(source_text), on_error="continue"
                    )
                    event = make_event(source_text, dict(response), response)
            else:
                response = self.clocked_client.pipeline(
                    text=source_text, steps=build_pipeline(source_text), on_error="continue"
                )
                event = make_event(source_text, dict(response), response)
            # Protocol envelope is independent of CPU architecture, OS, and runner.
            event["tenant_id"] = identity["tenant_id"]
            event["protocol_version"] = SCHEMA_VERSION
            event["learning_state"] = "awaiting_nanlmind_ingest"
            return json_response(start_response, "200 OK", {
                "protocol": "nanlm.clocked-experience",
                "protocol_version": SCHEMA_VERSION,
                "event": event,
                "quota_remaining": identity["remaining"],
            })
        except Exception:
            # Never return upstream bodies, headers, exception text, or credentials.
            return json_response(start_response, "502 Bad Gateway", {"error": "upstream_unavailable"})


def main():
    if not os.environ.get("CLOCKED_API_KEY"):
        raise SystemExit("CLOCKED_API_KEY must be configured in the server secret manager")
    if not os.environ.get("CLOCKED_GATEWAY_ADMIN_TOKEN"):
        raise SystemExit("CLOCKED_GATEWAY_ADMIN_TOKEN must be configured")
    if not os.environ.get("CLOCKED_TOKEN_PEPPER"):
        raise SystemExit("CLOCKED_TOKEN_PEPPER must be configured")
    host = os.environ.get("CLOCKED_GATEWAY_HOST", "127.0.0.1")
    port = int(os.environ.get("CLOCKED_GATEWAY_PORT", "8787"))
    db_path = os.environ.get("CLOCKED_GATEWAY_DB", "clocked_gateway.sqlite3")
    # Clocked SDK reads CLOCKED_API_KEY from this server process only.
    app = Gateway(db_path)
    with make_server(host, port, app) as server:
        print("Clocked demo gateway listening on %s:%d" % (host, port), flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
