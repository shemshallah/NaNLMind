#!/usr/bin/env python3
"""Durably fold endpoint observations before acknowledging the NANNET queue.

This writes an evidence ledger only. It does not mutate model heads or claim
that an observation is a verified training target.
"""
from __future__ import annotations
import hashlib
import json
import os
import re
import sqlite3
import sys
import urllib.request
from pathlib import Path

EVENT_ID = re.compile(r"^[a-f0-9]{64}$")
FIELDS = {"protocol", "version", "event_id", "base_generation", "active_heads", "outcome_verified"}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def validate_event(event):
    if not isinstance(event, dict) or set(event) != FIELDS:
        raise ValueError("event_schema_mismatch")
    if event["protocol"] != "nanlm.endpoint-observation" or event["version"] != 1:
        raise ValueError("unsupported_event_protocol")
    if not isinstance(event["event_id"], str) or not EVENT_ID.fullmatch(event["event_id"]):
        raise ValueError("invalid_event_id")
    generation = event["base_generation"]
    if isinstance(generation, bool) or not isinstance(generation, int) or generation < 0:
        raise ValueError("invalid_base_generation")
    heads = event["active_heads"]
    if (not isinstance(heads, list) or len(heads) > 256 or
        any(isinstance(h, bool) or not isinstance(h, int) or not 0 <= h < 256 for h in heads)):
        raise ValueError("invalid_active_heads")
    if event["outcome_verified"] is not False:
        raise ValueError("endpoint_asserted_outcome")
    return {"protocol": event["protocol"], "version": 1, "event_id": event["event_id"],
            "base_generation": generation, "active_heads": sorted(set(heads)),
            "outcome_verified": False}


class EvidenceLedger:
    def __init__(self, path):
        self.db = sqlite3.connect(str(path))
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("""CREATE TABLE IF NOT EXISTS evidence (
            event_id TEXT PRIMARY KEY, endpoint_id TEXT NOT NULL,
            received_at INTEGER NOT NULL, base_generation INTEGER NOT NULL,
            payload_sha256 TEXT NOT NULL, active_heads_json TEXT NOT NULL
        )""")
        self.db.commit()

    def fold(self, rows):
        ids = []
        with self.db:
            for row in rows:
                endpoint = row.get("source_endpoint", row.get("endpoint_id"))
                if not isinstance(endpoint, str) or not endpoint:
                    raise ValueError("missing_endpoint_provenance")
                event = validate_event(row.get("observation"))
                self.db.execute("INSERT OR IGNORE INTO evidence VALUES(?,?,?,?,?,?)", (
                    event["event_id"], endpoint, int(row.get("received_at", 0)),
                    event["base_generation"], hashlib.sha256(canonical(event)).hexdigest(),
                    json.dumps(event["active_heads"])))
                ids.append(event["event_id"])
        return ids

    def close(self):
        self.db.close()


def request(base, token, path="/internal/observations", method="GET", payload=None):
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json"}
    data = canonical(payload) if payload is not None else None
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base.rstrip("/") + path, data=data,
                                 headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        raw = response.read(1_048_577)
        if len(raw) > 1_048_576:
            raise RuntimeError("observation_response_too_large")
        return json.loads(raw) if raw else {}


def consume(base, token, ledger_path):
    batch = request(base, token)
    rows = batch.get("events")
    if not isinstance(rows, list) or len(rows) > 100:
        raise ValueError("invalid_observation_batch")
    if not rows:
        return {"folded": 0, "acknowledged": 0}
    Path(ledger_path).parent.mkdir(parents=True, exist_ok=True)
    ledger = EvidenceLedger(ledger_path)
    try:
        ids = ledger.fold(rows)
    finally:
        ledger.close()
    # FULL synchronous SQLite commit completes before the queue acknowledgement.
    ack = request(base, token, path="/internal/observations/ack", method="POST",
                  payload={"event_ids": ids})
    return {"folded": len(ids), "acknowledged": int(ack.get("folded", 0))}


def main():
    base = os.environ.get("NANNET_URL", "").rstrip("/")
    token = os.environ.get("NANLM_RUNNER_TOKEN", "")
    path = os.environ.get("NANLM_CLOCKED_EVIDENCE_DB", "state/clocked-evidence.sqlite3")
    if not base.startswith("https://") or len(token) < 32:
        print("NANNET_URL (HTTPS) and NANLM_RUNNER_TOKEN are required", file=sys.stderr)
        return 2
    print(json.dumps(consume(base, token, path), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
