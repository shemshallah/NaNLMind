"""Atomic nanclock lease and handoff authority for the six-slot runner ring.

The six ``nanrouter-runner-0..5`` repositories are identical hot standbys.
They do **not** receive HW addresses and they are not hardware zero points.
They are the internal BSR0..BSR5 members of MC0:0.  Exactly one slot is active
at a time.  This authority is the single atomic arbitration point:

* a monotone nanclock tick is allocated under ``BEGIN IMMEDIATE``;
* one lease row names the active slot, epoch, endpoint and expiry;
* a standby may acquire only after the previous lease expires or is released;
* every successful transition increments the epoch and appends a handoff row;
* the active slot may publish a bounded checkpoint for the next active slot.

The module performs no NaN arithmetic and stores no bearer token.  The HTTP
layer authenticates callers before invoking it.
"""
from __future__ import annotations

import hashlib
import json
import secrets
import sqlite3
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

RING_SCHEMA = "nanrouter.runner-ring-authority.v1"
SLOT_COUNT = 6
MAX_TTL_SECONDS = 300
MIN_TTL_SECONDS = 5
MAX_CHECKPOINT_BYTES = 1_048_576
DIGEST_RE = None


class RunnerRingError(ValueError):
    """The ring request is malformed or not admissible."""


class RunnerRingAuthError(RunnerRingError):
    """The caller does not hold the active slot lease."""


def _int(value: Any, name: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise RunnerRingError(f"{name} must be an integer")
    if not minimum <= value <= maximum:
        raise RunnerRingError(f"{name} must be in {minimum}..{maximum}")
    return value


def _endpoint(value: Any) -> str:
    if not isinstance(value, str) or not value or len(value) > 512:
        raise RunnerRingError("endpoint must be a bounded absolute URL")
    parts = urlsplit(value)
    if parts.scheme not in ("https", "http") or not parts.hostname:
        raise RunnerRingError("endpoint must be an http(s) URL")
    host = (parts.hostname or "").lower()
    if parts.scheme != "https" and host not in ("127.0.0.1", "localhost", "::1"):
        raise RunnerRingError("endpoint must use HTTPS except on loopback")
    return value.rstrip("/")


def _digest(value: Any) -> str:
    if not isinstance(value, str) or len(value) != 64:
        raise RunnerRingError("state_digest must be a SHA-256 hex digest")
    try:
        int(value, 16)
    except ValueError as exc:
        raise RunnerRingError("state_digest must be hexadecimal") from exc
    return value.lower()


def _canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


class RunnerRingAuthority:
    """SQLite-backed atomic nanclock and single-active-slot lease."""

    def __init__(self, database: str | Path, *, now_ns=None, ttl_max: int = MAX_TTL_SECONDS):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        if not MIN_TTL_SECONDS <= ttl_max <= MAX_TTL_SECONDS:
            raise RunnerRingError("ttl_max is outside the bounded range")
        self.ttl_max = ttl_max
        self._now_ns = now_ns or time.time_ns
        with self._connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA synchronous=FULL")
            db.execute("""CREATE TABLE IF NOT EXISTS runner_ring_meta (
                key TEXT PRIMARY KEY, value TEXT NOT NULL)""")
            db.execute("""CREATE TABLE IF NOT EXISTS runner_ring_lease (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                slot INTEGER NOT NULL,
                epoch INTEGER NOT NULL,
                lease_id TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                issued_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                nanclock_tick INTEGER NOT NULL)""")
            db.execute("""CREATE TABLE IF NOT EXISTS runner_ring_checkpoint (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                slot INTEGER NOT NULL,
                epoch INTEGER NOT NULL,
                lease_id TEXT NOT NULL,
                nanclock_tick INTEGER NOT NULL,
                state TEXT NOT NULL,
                state_digest TEXT NOT NULL,
                updated_at INTEGER NOT NULL)""")
            db.execute("""CREATE TABLE IF NOT EXISTS runner_ring_handoffs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                from_slot INTEGER,
                to_slot INTEGER NOT NULL,
                epoch INTEGER NOT NULL,
                nanclock_tick INTEGER NOT NULL,
                reason TEXT NOT NULL,
                created_at INTEGER NOT NULL)""")

    def _connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(self.database, timeout=15, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA busy_timeout=15000")
        return db

    def _now_ms(self) -> int:
        return int(self._now_ns()) // 1_000_000

    def _meta(self, db: sqlite3.Connection, key: str, default: int = 0) -> int:
        row = db.execute("SELECT value FROM runner_ring_meta WHERE key=?", (key,)).fetchone()
        return int(row["value"]) if row is not None else default

    def _set_meta(self, db: sqlite3.Connection, key: str, value: int) -> None:
        db.execute(
            "INSERT INTO runner_ring_meta(key, value) VALUES(?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, str(value)),
        )

    def _next_tick(self, db: sqlite3.Connection) -> int:
        now_tick = self._now_ms()
        last = self._meta(db, "last_nanclock_tick")
        tick = max(now_tick, last + 1)
        self._set_meta(db, "last_nanclock_tick", tick)
        return tick

    @staticmethod
    def _row(db: sqlite3.Connection):
        return db.execute("SELECT * FROM runner_ring_lease WHERE id=1").fetchone()

    @staticmethod
    def _descriptor(row, *, now_ms: int, tick: int | None = None) -> dict[str, Any]:
        if row is None:
            return {
                "active": False, "active_slot": None, "epoch": 0,
                "endpoint": None, "expires_at": 0, "lease_id": None,
                "nanclock_tick": tick or 0,
            }
        active = row["expires_at"] > now_ms
        return {
            "active": active,
            "active_slot": row["slot"] if active else None,
            "epoch": row["epoch"],
            "endpoint": row["endpoint"] if active else None,
            "expires_at": row["expires_at"],
            "lease_id": row["lease_id"] if active else None,
            "nanclock_tick": tick if tick is not None else row["nanclock_tick"],
        }

    def clock(self) -> dict[str, Any]:
        """Allocate one strictly monotone nanclock tick atomically."""
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            tick = self._next_tick(db)
            row = self._row(db)
            now_ms = self._now_ms()
            state = self._descriptor(row, now_ms=now_ms, tick=tick)
            db.execute("COMMIT")
            return {"schema": RING_SCHEMA, "nanclock_tick": tick, "now_ms": now_ms, **state}

    def status(self) -> dict[str, Any]:
        with self._connect() as db:
            row = self._row(db)
            now_ms = self._now_ms()
            state = self._descriptor(row, now_ms=now_ms)
            checkpoint = db.execute(
                "SELECT slot, epoch, nanclock_tick, state_digest, updated_at "
                "FROM runner_ring_checkpoint WHERE id=1"
            ).fetchone()
            last_tick = self._meta(db, "last_nanclock_tick")
        return {
            "schema": RING_SCHEMA,
            "nanclock_tick": last_tick,
            "now_ms": now_ms,
            **state,
            "checkpoint": None if checkpoint is None else {
                "slot": checkpoint["slot"],
                "epoch": checkpoint["epoch"],
                "nanclock_tick": checkpoint["nanclock_tick"],
                "state_digest": checkpoint["state_digest"],
                "updated_at": checkpoint["updated_at"],
            },
        }

    def lease(
        self,
        *,
        slot: int,
        base_epoch: int,
        endpoint: str,
        ttl_seconds: int = 30,
    ) -> dict[str, Any]:
        """Acquire or idempotently renew the one active lease.

        A different slot receives ``acquired=false`` while a live lease exists.
        An expired lease can be taken over; the epoch always advances.
        """
        slot = _int(slot, "slot", 0, SLOT_COUNT - 1)
        base_epoch = _int(base_epoch, "base_epoch", 0, (1 << 63) - 1)
        ttl_seconds = _int(ttl_seconds, "ttl_seconds", MIN_TTL_SECONDS, self.ttl_max)
        endpoint = _endpoint(endpoint)
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            now_ms = self._now_ms()
            tick = self._next_tick(db)
            row = self._row(db)
            if row is not None and row["expires_at"] > now_ms:
                if row["slot"] != slot:
                    db.execute("COMMIT")
                    return {
                        "schema": RING_SCHEMA, "acquired": False,
                        "reason": "another slot holds a live lease",
                        **self._descriptor(row, now_ms=now_ms, tick=tick),
                    }
                # Same slot: idempotent renewal keeps the lease id and epoch.
                db.execute(
                    "UPDATE runner_ring_lease SET endpoint=?, expires_at=?, "
                    "nanclock_tick=? WHERE id=1",
                    (endpoint, now_ms + ttl_seconds * 1000, tick),
                )
                db.execute("COMMIT")
                updated = {
                    "active": True, "active_slot": slot, "epoch": row["epoch"],
                    "endpoint": endpoint, "expires_at": now_ms + ttl_seconds * 1000,
                    "lease_id": row["lease_id"], "nanclock_tick": tick,
                }
                return {"schema": RING_SCHEMA, "acquired": True, "renewed": True, **updated}
            old_slot = row["slot"] if row is not None else None
            old_epoch = max(
                row["epoch"] if row is not None else 0,
                self._meta(db, "last_epoch"),
            )
            epoch = max(old_epoch + 1, base_epoch + 1, 1)
            self._set_meta(db, "last_epoch", epoch)
            lease_id = secrets.token_hex(16)
            expires_at = now_ms + ttl_seconds * 1000
            db.execute(
                "INSERT INTO runner_ring_lease(id, slot, epoch, lease_id, endpoint, "
                "issued_at, expires_at, nanclock_tick) VALUES(1, ?, ?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(id) DO UPDATE SET slot=excluded.slot, epoch=excluded.epoch, "
                "lease_id=excluded.lease_id, endpoint=excluded.endpoint, "
                "issued_at=excluded.issued_at, expires_at=excluded.expires_at, "
                "nanclock_tick=excluded.nanclock_tick",
                (slot, epoch, lease_id, endpoint, now_ms, expires_at, tick),
            )
            db.execute(
                "INSERT INTO runner_ring_handoffs(from_slot, to_slot, epoch, "
                "nanclock_tick, reason, created_at) VALUES(?, ?, ?, ?, ?, ?)",
                (old_slot, slot, epoch, tick,
                 "initial" if old_slot is None else "takeover", now_ms),
            )
            db.execute("COMMIT")
            return {
                "schema": RING_SCHEMA, "acquired": True, "renewed": False,
                "active": True, "active_slot": slot, "epoch": epoch,
                "endpoint": endpoint, "expires_at": expires_at,
                "lease_id": lease_id, "nanclock_tick": tick,
            }

    def renew(self, *, slot: int, lease_id: str, ttl_seconds: int = 30) -> dict[str, Any]:
        slot = _int(slot, "slot", 0, SLOT_COUNT - 1)
        ttl_seconds = _int(ttl_seconds, "ttl_seconds", MIN_TTL_SECONDS, self.ttl_max)
        if not isinstance(lease_id, str) or not 32 <= len(lease_id) <= 128:
            raise RunnerRingError("lease_id is malformed")
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            now_ms = self._now_ms()
            tick = self._next_tick(db)
            row = self._row(db)
            if (row is None or row["slot"] != slot or row["lease_id"] != lease_id
                    or row["expires_at"] <= now_ms):
                db.execute("COMMIT")
                raise RunnerRingAuthError("active lease does not match this slot")
            expires_at = now_ms + ttl_seconds * 1000
            db.execute(
                "UPDATE runner_ring_lease SET expires_at=?, nanclock_tick=? WHERE id=1",
                (expires_at, tick),
            )
            db.execute("COMMIT")
            return {
                "schema": RING_SCHEMA, "active": True, "active_slot": slot,
                "epoch": row["epoch"], "endpoint": row["endpoint"],
                "expires_at": expires_at, "lease_id": lease_id,
                "nanclock_tick": tick, "now_ms": now_ms,
            }

    def release(self, *, slot: int, lease_id: str) -> dict[str, Any]:
        slot = _int(slot, "slot", 0, SLOT_COUNT - 1)
        if not isinstance(lease_id, str) or not 32 <= len(lease_id) <= 128:
            raise RunnerRingError("lease_id is malformed")
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            now_ms = self._now_ms()
            tick = self._next_tick(db)
            row = self._row(db)
            if row is None or row["slot"] != slot or row["lease_id"] != lease_id:
                db.execute("COMMIT")
                raise RunnerRingAuthError("active lease does not match this slot")
            db.execute("DELETE FROM runner_ring_lease WHERE id=1")
            self._set_meta(db, "last_epoch", row["epoch"])
            db.execute(
                "INSERT INTO runner_ring_handoffs(from_slot, to_slot, epoch, "
                "nanclock_tick, reason, created_at) VALUES(?, ?, ?, ?, ?, ?)",
                (slot, -1, row["epoch"], tick, "released", now_ms),
            )
            db.execute("COMMIT")
            return {"schema": RING_SCHEMA, "released": True,
                    "nanclock_tick": tick, "now_ms": now_ms}

    def checkpoint(
        self,
        *,
        slot: int,
        lease_id: str,
        state: Any,
        nanclock_tick: int,
    ) -> dict[str, Any]:
        slot = _int(slot, "slot", 0, SLOT_COUNT - 1)
        if not isinstance(lease_id, str) or not 32 <= len(lease_id) <= 128:
            raise RunnerRingError("lease_id is malformed")
        nanclock_tick = _int(nanclock_tick, "nanclock_tick", 0, (1 << 63) - 1)
        raw = _canonical(state)
        if len(raw) > MAX_CHECKPOINT_BYTES:
            raise RunnerRingError("checkpoint exceeds 1 MiB")
        digest = hashlib.sha256(raw).hexdigest()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            now_ms = self._now_ms()
            tick = self._next_tick(db)
            row = self._row(db)
            if (row is None or row["slot"] != slot or row["lease_id"] != lease_id
                    or row["expires_at"] <= now_ms):
                db.execute("COMMIT")
                raise RunnerRingAuthError("active lease does not match this slot")
            db.execute(
                "INSERT INTO runner_ring_checkpoint(id, slot, epoch, lease_id, "
                "nanclock_tick, state, state_digest, updated_at) "
                "VALUES(1, ?, ?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(id) DO UPDATE SET slot=excluded.slot, epoch=excluded.epoch, "
                "lease_id=excluded.lease_id, nanclock_tick=excluded.nanclock_tick, "
                "state=excluded.state, state_digest=excluded.state_digest, "
                "updated_at=excluded.updated_at",
                (slot, row["epoch"], lease_id, nanclock_tick,
                 raw.decode("utf-8"), digest, now_ms),
            )
            db.execute("COMMIT")
            return {
                "schema": RING_SCHEMA, "checkpointed": True,
                "slot": slot, "epoch": row["epoch"],
                "state_digest": digest, "nanclock_tick": tick,
                "updated_at": now_ms,
            }

    def read_checkpoint(self) -> dict[str, Any] | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM runner_ring_checkpoint WHERE id=1").fetchone()
        if row is None:
            return None
        return {
            "schema": RING_SCHEMA, "slot": row["slot"], "epoch": row["epoch"],
            "nanclock_tick": row["nanclock_tick"], "state": json.loads(row["state"]),
            "state_digest": row["state_digest"], "updated_at": row["updated_at"],
        }

    def stats(self) -> dict[str, Any]:
        status = self.status()
        with self._connect() as db:
            handoffs = db.execute(
                "SELECT COUNT(*) AS count FROM runner_ring_handoffs"
            ).fetchone()["count"]
            recent = db.execute(
                "SELECT from_slot, to_slot, epoch, nanclock_tick, reason, created_at "
                "FROM runner_ring_handoffs ORDER BY id DESC LIMIT 16"
            ).fetchall()
        return {
            "schema": RING_SCHEMA,
            "slots": SLOT_COUNT,
            "status": status,
            "handoffs": handoffs,
            "recent_handoffs": [dict(row) for row in recent],
        }
