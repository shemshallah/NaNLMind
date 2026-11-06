"""Persistent, quota-aware NaN rawroute registries for the four network layers.

SQLite is the durable implementation substrate for the Koyeb control plane.
The records and identities are NaN rawroutes; SQLite is not the address space.
Each namespace is independent, append-only for committed events, and rebuilds
its indexes from the durable route definitions/events.
"""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import time
from pathlib import Path
from typing import Optional

from .bridge import RunnerRoute
from .rawroute import RawRoute

NAMESPACE_FILES = {
    "BS0": "bs0db.sqlite3",
    "MC0": "mc0db.sqlite3",
    "SC0": "sc0db.sqlite3",
    "GM0": "gm0db.sqlite3",
}
DEFAULT_QUOTA_BYTES = 10 * 1024 * 1024 * 1024
SCHEMA_VERSION = 1


class RouteConflict(RuntimeError):
    """A stale generation, idempotency collision, or non-monotonic clock."""


class RouteQuotaExceeded(RuntimeError):
    """The namespace's logical record quota would be exceeded."""


def _uint(value: int, label: str, maximum: int = (1 << 63) - 1) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= maximum:
        raise ValueError(f"{label} must be an unsigned integer")
    return value


class RawRouteDB:
    def __init__(self, path: str | Path, namespace: str,
                 quota_bytes: int = DEFAULT_QUOTA_BYTES):
        if namespace not in NAMESPACE_FILES:
            raise ValueError("unknown NaN route namespace")
        self.path = Path(path)
        self.namespace = namespace
        self.quota_bytes = _uint(quota_bytes, "quota_bytes")
        if self.quota_bytes == 0:
            raise ValueError("quota_bytes must be greater than zero")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        db = sqlite3.connect(str(self.path), timeout=30)
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA busy_timeout=30000")
        return db

    def _initialize(self) -> None:
        with self._connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA synchronous=FULL")
            db.execute("""CREATE TABLE IF NOT EXISTS namespace_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS route_definitions (
                route_id TEXT PRIMARY KEY,
                canonical TEXT NOT NULL UNIQUE,
                target_hw INTEGER NOT NULL,
                target_heads_json TEXT NOT NULL,
                object_kind TEXT,
                object_id INTEGER,
                generation INTEGER NOT NULL,
                status TEXT NOT NULL,
                transport_route TEXT,
                content_digest TEXT NOT NULL,
                record_bytes INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS route_instances (
                route_id TEXT PRIMARY KEY REFERENCES route_definitions(route_id),
                transport_route TEXT NOT NULL,
                runner_identity TEXT,
                generation INTEGER NOT NULL,
                active INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS route_events (
                event_id TEXT PRIMARY KEY,
                route_id TEXT NOT NULL,
                base_generation INTEGER NOT NULL,
                generation INTEGER NOT NULL,
                nanclock_tick INTEGER NOT NULL,
                event_type TEXT NOT NULL,
                payload_sha256 TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )""")
            db.execute("""CREATE TABLE IF NOT EXISTS reverse_lookup (
                target_kind TEXT NOT NULL,
                target_id TEXT NOT NULL,
                route_id TEXT NOT NULL REFERENCES route_definitions(route_id),
                generation INTEGER NOT NULL,
                PRIMARY KEY(target_kind, target_id, route_id)
            )""")
            db.execute("CREATE INDEX IF NOT EXISTS route_events_by_route "
                       "ON route_events(route_id, generation)")
            db.execute("CREATE INDEX IF NOT EXISTS reverse_lookup_by_route "
                       "ON reverse_lookup(route_id)")
            db.execute("CREATE INDEX IF NOT EXISTS route_instances_by_transport "
                       "ON route_instances(transport_route, active)")
            defaults = {
                "schema_version": str(SCHEMA_VERSION),
                "namespace": self.namespace,
                "quota_bytes": str(self.quota_bytes),
                "used_bytes": "0",
                "generation": "0",
                "last_nanclock_tick": "0",
            }
            for key, value in defaults.items():
                db.execute("INSERT OR IGNORE INTO namespace_meta(key,value) VALUES(?,?)",
                           (key, value))
            stored_ns = db.execute(
                "SELECT value FROM namespace_meta WHERE key='namespace'").fetchone()[0]
            if stored_ns != self.namespace:
                raise ValueError("database namespace identity mismatch")
            stored_version = int(db.execute(
                "SELECT value FROM namespace_meta WHERE key='schema_version'").fetchone()[0])
            if stored_version != SCHEMA_VERSION:
                raise ValueError("unsupported rawroute database schema version")
            used = int(db.execute(
                "SELECT value FROM namespace_meta WHERE key='used_bytes'").fetchone()[0])
            if used > self.quota_bytes:
                raise RouteQuotaExceeded("configured quota is below existing logical usage")
            db.execute("UPDATE namespace_meta SET value=? WHERE key='quota_bytes'",
                       (str(self.quota_bytes),))

    def _meta(self, db: sqlite3.Connection, key: str) -> str:
        row = db.execute("SELECT value FROM namespace_meta WHERE key=?", (key,)).fetchone()
        if row is None:
            raise RuntimeError("missing namespace metadata: " + key)
        return row[0]

    def commit(self, route: RawRoute | str, base_generation: int,
               nanclock_tick: int, transport_route: RunnerRoute | str | None = None,
               runner_identity: str | None = None,
               idempotency_key: str | None = None) -> dict:
        if isinstance(route, str):
            route = RawRoute.parse(route)
        if not isinstance(route, RawRoute):
            raise ValueError("route must be a RawRoute or canonical rawroute string")
        base_generation = _uint(base_generation, "base_generation")
        nanclock_tick = _uint(nanclock_tick, "nanclock_tick")
        if transport_route is not None:
            if isinstance(transport_route, str):
                transport_route = RunnerRoute.parse(transport_route)
            if not isinstance(transport_route, RunnerRoute):
                raise ValueError("transport_route must be a canonical N16B RunnerRoute")
            transport_text = transport_route.text()
        else:
            transport_text = None
        if runner_identity is not None and (not isinstance(runner_identity, str) or not runner_identity):
            raise ValueError("runner_identity must be non-empty text")
        if idempotency_key is not None and (
            not isinstance(idempotency_key, str) or not idempotency_key or len(idempotency_key) > 256
        ):
            raise ValueError("idempotency_key must be 1..256 characters")

        now = int(time.time())
        route_id = route.definition_id
        object_kind = route.object_ref.kind if route.object_ref else None
        object_id = route.object_ref.object_id if route.object_ref else None
        payload = {
            "namespace": self.namespace,
            "route_id": route_id,
            "canonical": route.text(),
            "target_hw": route.target.hardware_kind,
            "target_heads": list(route.target.heads),
            "object_kind": object_kind,
            "object_id": object_id,
            "transport_route": transport_text,
            "runner_identity": runner_identity,
            "base_generation": base_generation,
            "nanclock_tick": nanclock_tick,
        }
        payload_json = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        payload_sha = hashlib.sha256(payload_json.encode("utf-8")).hexdigest()
        event_id = hashlib.sha256(
            (self.namespace + "|" + (idempotency_key or
             (route_id + "|" + str(base_generation) + "|" + str(nanclock_tick) + "|" + payload_sha)))
            .encode("utf-8")
        ).hexdigest()
        record_bytes = len(payload_json.encode("utf-8")) + len(route.text().encode("ascii")) + 256

        with self._connect() as db:
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            prior = db.execute(
                "SELECT payload_sha256,generation FROM route_events WHERE event_id=?",
                (event_id,)).fetchone()
            if prior is not None:
                if prior[0] != payload_sha:
                    raise RouteConflict("idempotency key reused with a different route payload")
                return {"accepted": True, "replay": True, "route_id": route_id,
                        "generation": prior[1], "digest": payload_sha}

            current = db.execute(
                "SELECT generation,record_bytes FROM route_definitions WHERE route_id=?",
                (route_id,)).fetchone()
            current_generation = current[0] if current else 0
            old_bytes = current[1] if current else 0
            if current_generation != base_generation:
                raise RouteConflict("stale base generation")
            last_tick = int(self._meta(db, "last_nanclock_tick"))
            if nanclock_tick < last_tick:
                raise RouteConflict("nanclock tick moved backwards")

            used = int(self._meta(db, "used_bytes"))
            event_bytes = len(payload_json.encode("utf-8")) + 128
            next_used = used - old_bytes + record_bytes + event_bytes
            if next_used > self.quota_bytes:
                raise RouteQuotaExceeded("namespace logical quota exceeded")
            generation = current_generation + 1

            db.execute("""INSERT INTO route_definitions(
                route_id,canonical,target_hw,target_heads_json,object_kind,object_id,
                generation,status,transport_route,content_digest,record_bytes,created_at,updated_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(route_id) DO UPDATE SET
                canonical=excluded.canonical,
                target_hw=excluded.target_hw,
                target_heads_json=excluded.target_heads_json,
                object_kind=excluded.object_kind,
                object_id=excluded.object_id,
                generation=excluded.generation,
                status=excluded.status,
                transport_route=excluded.transport_route,
                content_digest=excluded.content_digest,
                record_bytes=excluded.record_bytes,
                updated_at=excluded.updated_at""",
                (route_id, route.text(), route.target.hardware_kind,
                 json.dumps(list(route.target.heads), separators=(",", ":")),
                 object_kind, object_id, generation, "committed", transport_text,
                 payload_sha, record_bytes, now, now))

            if transport_text is None:
                db.execute("DELETE FROM route_instances WHERE route_id=?", (route_id,))
            else:
                db.execute("""INSERT INTO route_instances(
                    route_id,transport_route,runner_identity,generation,active,updated_at
                ) VALUES(?,?,?,?,1,?)
                ON CONFLICT(route_id) DO UPDATE SET
                    transport_route=excluded.transport_route,
                    runner_identity=excluded.runner_identity,
                    generation=excluded.generation,
                    active=1,
                    updated_at=excluded.updated_at""",
                    (route_id, transport_text, runner_identity, generation, now))

            db.execute("DELETE FROM reverse_lookup WHERE route_id=?", (route_id,))
            for head in route.target.heads:
                db.execute("INSERT INTO reverse_lookup VALUES(?,?,?,?)",
                           ("head", str(head), route_id, generation))
            if object_kind is not None:
                db.execute("INSERT INTO reverse_lookup VALUES(?,?,?,?)",
                           (object_kind, str(object_id), route_id, generation))

            db.execute("""INSERT INTO route_events(
                event_id,route_id,base_generation,generation,nanclock_tick,event_type,
                payload_sha256,payload_json,created_at
            ) VALUES(?,?,?,?,?,?,?,?,?)""",
                (event_id, route_id, base_generation, generation, nanclock_tick,
                 "route_commit", payload_sha, payload_json, now))
            db.execute("UPDATE namespace_meta SET value=? WHERE key='used_bytes'",
                       (str(next_used),))
            db.execute("UPDATE namespace_meta SET value=? WHERE key='generation'",
                       (str(max(int(self._meta(db, "generation")), generation)),))
            db.execute("UPDATE namespace_meta SET value=? WHERE key='last_nanclock_tick'",
                       (str(nanclock_tick),))
            return {"accepted": True, "replay": False, "route_id": route_id,
                    "generation": generation, "digest": payload_sha}

    def resolve(self, route: RawRoute | str) -> Optional[dict]:
        if isinstance(route, str):
            route = RawRoute.parse(route)
        if not isinstance(route, RawRoute):
            raise ValueError("route must be a RawRoute or canonical rawroute string")
        with self._connect() as db:
            row = db.execute("""SELECT d.route_id,d.canonical,d.generation,d.status,
                d.transport_route,d.content_digest,i.runner_identity
                FROM route_definitions d LEFT JOIN route_instances i
                ON i.route_id=d.route_id AND i.active=1
                WHERE d.route_id=?""", (route.definition_id,)).fetchone()
        if row is None:
            return None
        return {
            "route_id": row[0], "canonical": row[1], "generation": row[2],
            "status": row[3], "transport_route": row[4],
            "resolved": row[4] is not None, "digest": row[5],
            "runner_identity": row[6],
        }

    def reverse_lookup(self, target_kind: str, target_id: int | str) -> list[str]:
        if not isinstance(target_kind, str) or not target_kind:
            raise ValueError("target_kind must be non-empty text")
        with self._connect() as db:
            rows = db.execute("""SELECT d.canonical FROM reverse_lookup r
                JOIN route_definitions d ON d.route_id=r.route_id
                WHERE r.target_kind=? AND r.target_id=? AND d.status='committed'
                ORDER BY d.canonical""", (target_kind, str(target_id))).fetchall()
        return [row[0] for row in rows]

    def health(self) -> dict:
        with self._connect() as db:
            record_count = db.execute("SELECT COUNT(*) FROM route_definitions").fetchone()[0]
            event_count = db.execute("SELECT COUNT(*) FROM route_events").fetchone()[0]
            digest = hashlib.sha256()
            for row in db.execute(
                "SELECT route_id,canonical,generation,content_digest FROM route_definitions ORDER BY route_id"
            ):
                digest.update("|".join(str(part) for part in row).encode("utf-8"))
            values = {key: self._meta(db, key) for key in
                      ("schema_version", "quota_bytes", "used_bytes", "generation",
                       "last_nanclock_tick")}
        physical = 0
        for candidate in (self.path, Path(str(self.path) + "-wal"), Path(str(self.path) + "-shm")):
            try:
                physical += candidate.stat().st_size
            except FileNotFoundError:
                pass
        return {
            "namespace": self.namespace,
            "schema_version": int(values["schema_version"]),
            "quota_bytes": int(values["quota_bytes"]),
            "logical_used_bytes": int(values["used_bytes"]),
            "logical_free_bytes": max(0, int(values["quota_bytes"]) - int(values["used_bytes"])),
            "physical_bytes": physical,
            "route_count": record_count,
            "event_count": event_count,
            "generation": int(values["generation"]),
            "last_nanclock_tick": int(values["last_nanclock_tick"]),
            "digest": digest.hexdigest(),
            "status": "ready",
        }


class RawRouteMesh:
    """Four independently quota-controlled databases on one persistent mount."""

    def __init__(self, root: str | Path,
                 quota_bytes: int = DEFAULT_QUOTA_BYTES):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.quota_bytes = _uint(quota_bytes, "quota_bytes")
        if self.quota_bytes == 0:
            raise ValueError("quota_bytes must be greater than zero")
        self.databases = {
            namespace: RawRouteDB(self.root / filename, namespace, self.quota_bytes)
            for namespace, filename in NAMESPACE_FILES.items()
        }

    def __getitem__(self, namespace: str) -> RawRouteDB:
        try:
            return self.databases[namespace]
        except KeyError as exc:
            raise ValueError("unknown NaN route namespace") from exc

    def health(self) -> dict:
        return {namespace: database.health()
                for namespace, database in self.databases.items()}
