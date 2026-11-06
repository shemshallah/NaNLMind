"""Binary NANNET bridge framing and durable per-runner mailbox.

The wire word retains NaN16DE double-endian layout: far head BE, payload LE,
near head LE. Route coordinates are GM, SC, MC, BS, HW, BSR. BSR is 0..5.
"""
from __future__ import annotations

import sqlite3
import struct
import time
import zlib
from dataclasses import dataclass
from pathlib import Path

from .nan16de import NanWord

MAGIC = b"N16B"
VERSION = 1
MEDIA_TYPE = "application/vnd.nan16.n16b"
MAX_PAYLOAD = 1_048_576
MAX_PENDING_PER_ROUTE = 4096
HEADER = struct.Struct("<4sBBHI6B6BI8s")
CRC = struct.Struct("<I")


@dataclass(frozen=True)
class RunnerRoute:
    gm: int = 0
    sc: int = 0
    mc: int = 0
    bs: int = 0
    hw: int = 0
    bsr: int = 0

    def __post_init__(self):
        values = (self.gm, self.sc, self.mc, self.bs, self.hw, self.bsr)
        if any(isinstance(v, bool) or not isinstance(v, int) or not 0 <= v <= 255
               for v in values):
            raise ValueError("route coordinates must be bytes")
        if self.bsr > 5:
            raise ValueError("BSR runner index must be 0..5")

    def bytes(self) -> bytes:
        return bytes((self.gm, self.sc, self.mc, self.bs, self.hw, self.bsr))

    def text(self) -> str:
        return (f"nan://GM{self.gm}:SC{self.sc}:MC{self.mc}:"
                f"BS{self.bs}:HW{self.hw}:BSR{self.bsr}")

    @classmethod
    def parse(cls, value: str) -> "RunnerRoute":
        import re
        if not isinstance(value, str):
            raise ValueError("runner route must be text")
        m = re.fullmatch(
            r"nan://GM(\d{1,3}):SC(\d{1,3}):MC(\d{1,3}):"
            r"BS(\d{1,3}):HW(\d{1,3}):BSR([0-5])", value)
        if not m:
            raise ValueError("runner route must be nan://GM:SC:MC:BS:HW:BSR0..5")
        route = cls(*(int(x) for x in m.groups()))
        if route.text() != value:
            raise ValueError("runner route must use canonical decimal coordinates")
        return route


@dataclass(frozen=True)
class BridgeFrame:
    source: RunnerRoute
    destination: RunnerRoute
    sequence: int
    word: NanWord
    payload: bytes = b""

    @property
    def direction(self) -> str:
        return "away" if self.word.far_class in (0, 2) else "toward"

    @property
    def signaling(self) -> bool:
        return self.word.far_class in (0, 1)

    def encode(self) -> bytes:
        if isinstance(self.sequence, bool) or not isinstance(self.sequence, int) or not 0 <= self.sequence <= 0xFFFFFFFF:
            raise ValueError("sequence must be uint32")
        if not isinstance(self.source, RunnerRoute) or not isinstance(self.destination, RunnerRoute):
            raise ValueError("source and destination must be runner routes")
        if not isinstance(self.word, NanWord):
            raise ValueError("bridge word must be a NaN16 word")
        if not isinstance(self.payload, bytes):
            raise ValueError("bridge payload must be bytes")
        if len(self.payload) > MAX_PAYLOAD:
            raise ValueError("bridge payload exceeds 1 MiB")
        header = HEADER.pack(
            MAGIC, VERSION, 0, 0, self.sequence,
            *self.source.bytes(), *self.destination.bytes(),
            len(self.payload), self.word.pack())
        body = header + self.payload
        return body + CRC.pack(zlib.crc32(body) & 0xFFFFFFFF)

    @classmethod
    def decode(cls, raw: bytes) -> "BridgeFrame":
        if len(raw) < HEADER.size + CRC.size or len(raw) > HEADER.size + MAX_PAYLOAD + CRC.size:
            raise ValueError("N16B frame size rejected")
        (magic, version, flags, reserved, sequence,
         *tail) = HEADER.unpack_from(raw)
        if magic != MAGIC or version != VERSION or flags != 0 or reserved != 0:
            raise ValueError("N16B header rejected")
        src = RunnerRoute(*tail[:6])
        dst = RunnerRoute(*tail[6:12])
        length = tail[12]
        word = NanWord.unpack(tail[13])
        if length > MAX_PAYLOAD or len(raw) != HEADER.size + length + CRC.size:
            raise ValueError("N16B payload length rejected")
        expected = CRC.unpack_from(raw, len(raw) - CRC.size)[0]
        if zlib.crc32(raw[:-CRC.size]) & 0xFFFFFFFF != expected:
            raise ValueError("N16B CRC rejected")
        return cls(src, dst, sequence, word, raw[HEADER.size:-CRC.size])

    @classmethod
    def acknowledgement(cls, received: "BridgeFrame") -> "BridgeFrame":
        # -qNaN marks the reverse/return rail; payload carries acknowledged seq.
        return cls(received.destination, received.source, received.sequence,
                   NanWord.from_bits(3, 3, received.sequence), b"ACK")


class BridgeMailbox:
    """SQLite-backed store-and-forward mailboxes, safe across Koyeb restarts."""

    def __init__(self, database: str | Path):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.database) as db:
            db.execute("""CREATE TABLE IF NOT EXISTS bridge_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                destination TEXT NOT NULL,
                source TEXT NOT NULL,
                frame BLOB NOT NULL,
                created_at INTEGER NOT NULL,
                sequence INTEGER NOT NULL DEFAULT 0,
                claimed_until INTEGER NOT NULL DEFAULT 0)""")
            columns = {row[1] for row in db.execute("PRAGMA table_info(bridge_messages)")}
            if "sequence" not in columns:
                db.execute("ALTER TABLE bridge_messages ADD COLUMN sequence INTEGER NOT NULL DEFAULT 0")
            if "claimed_until" not in columns:
                db.execute("ALTER TABLE bridge_messages ADD COLUMN claimed_until INTEGER NOT NULL DEFAULT 0")
            # Migrate sequence keys for messages written by the original schema.
            for message_id, raw in db.execute(
                    "SELECT id, frame FROM bridge_messages WHERE sequence=0").fetchall():
                try:
                    sequence = BridgeFrame.decode(bytes(raw)).sequence
                    db.execute("UPDATE bridge_messages SET sequence=? WHERE id=?",
                               (sequence, message_id))
                except ValueError:
                    db.execute("DELETE FROM bridge_messages WHERE id=?", (message_id,))
            db.execute("CREATE INDEX IF NOT EXISTS bridge_destination_id "
                       "ON bridge_messages(destination, id)")
            db.execute("CREATE INDEX IF NOT EXISTS bridge_delivery_lease "
                       "ON bridge_messages(destination, claimed_until, id)")
            db.execute("CREATE INDEX IF NOT EXISTS bridge_ack_lookup "
                       "ON bridge_messages(source, destination, sequence)")

    def put(self, frame: BridgeFrame) -> None:
        raw = frame.encode()
        with sqlite3.connect(self.database, timeout=15) as db:
            db.execute("BEGIN IMMEDIATE")
            pending = db.execute("SELECT COUNT(*) FROM bridge_messages WHERE destination=?",
                                 (frame.destination.text(),)).fetchone()[0]
            if pending >= MAX_PENDING_PER_ROUTE:
                raise OverflowError("N16B destination mailbox is full")
            db.execute("INSERT INTO bridge_messages(destination,source,frame,created_at,sequence,claimed_until) "
                       "VALUES(?,?,?,?,?,0)",
                       (frame.destination.text(), frame.source.text(), raw,
                        int(time.time()), frame.sequence))

    def stats(self) -> dict:
        """Return operational counters without exposing frame contents."""
        with sqlite3.connect(self.database, timeout=15) as db:
            rows = db.execute("SELECT destination, COUNT(*) FROM bridge_messages "
                              "GROUP BY destination ORDER BY destination").fetchall()
        by_destination = {route: count for route, count in rows}
        return {"queued": sum(by_destination.values()),
                "by_destination": by_destination,
                "max_pending_per_route": MAX_PENDING_PER_ROUTE}

    def claim(self, destination: RunnerRoute, lease_seconds: int = 30) -> bytes | None:
        """Lease one frame; it is redelivered after expiry until acknowledged."""
        if isinstance(lease_seconds, bool) or not isinstance(lease_seconds, int) or not 0 <= lease_seconds <= 3600:
            raise ValueError("bridge lease must be an integer from 0 to 3600 seconds")
        now = int(time.time())
        with sqlite3.connect(self.database, timeout=15) as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT id,frame FROM bridge_messages "
                             "WHERE destination=? AND claimed_until<=? ORDER BY id LIMIT 1",
                             (destination.text(), now)).fetchone()
            if row is None:
                return None
            db.execute("UPDATE bridge_messages SET claimed_until=? WHERE id=?",
                       (now + lease_seconds, row[0]))
            return bytes(row[1])

    def acknowledge(self, source: RunnerRoute, destination: RunnerRoute, sequence: int) -> bool:
        """Delete the original delivery only after its reverse-rail receipt."""
        if not isinstance(source, RunnerRoute) or not isinstance(destination, RunnerRoute):
            raise ValueError("acknowledgement routes must be canonical runner routes")
        if isinstance(sequence, bool) or not isinstance(sequence, int) or not 0 <= sequence <= 0xFFFFFFFF:
            raise ValueError("acknowledgement sequence must be uint32")
        with sqlite3.connect(self.database, timeout=15, isolation_level="IMMEDIATE") as db:
            cursor = db.execute("DELETE FROM bridge_messages "
                                "WHERE source=? AND destination=? AND sequence=?",
                                (source.text(), destination.text(), sequence))
            return cursor.rowcount > 0

    def acknowledge_and_put(self, source: RunnerRoute, destination: RunnerRoute,
                            sequence: int, receipt: BridgeFrame) -> bool:
        """Atomically retire a delivery and enqueue its reverse-rail receipt."""
        if not isinstance(source, RunnerRoute) or not isinstance(destination, RunnerRoute):
            raise ValueError("acknowledgement routes must be canonical runner routes")
        if isinstance(sequence, bool) or not isinstance(sequence, int) or not 0 <= sequence <= 0xFFFFFFFF:
            raise ValueError("acknowledgement sequence must be uint32")
        raw = receipt.encode()
        with sqlite3.connect(self.database, timeout=15) as db:
            db.execute("BEGIN IMMEDIATE")
            pending = db.execute("SELECT COUNT(*) FROM bridge_messages WHERE destination=?",
                                 (receipt.destination.text(),)).fetchone()[0]
            if pending >= MAX_PENDING_PER_ROUTE:
                raise OverflowError("N16B destination mailbox is full")
            cursor = db.execute("DELETE FROM bridge_messages "
                                "WHERE source=? AND destination=? AND sequence=?",
                                (source.text(), destination.text(), sequence))
            db.execute("INSERT INTO bridge_messages(destination,source,frame,created_at,sequence,claimed_until) "
                       "VALUES(?,?,?,?,?,0)",
                       (receipt.destination.text(), receipt.source.text(), raw,
                        int(time.time()), receipt.sequence))
            return cursor.rowcount > 0

    def take(self, destination: RunnerRoute) -> bytes | None:
        """Compatibility destructive read; active transports should use claim/ack."""
        with sqlite3.connect(self.database, timeout=15, isolation_level="IMMEDIATE") as db:
            row = db.execute("SELECT id,frame FROM bridge_messages "
                             "WHERE destination=? ORDER BY id LIMIT 1",
                             (destination.text(),)).fetchone()
            if row is None:
                return None
            db.execute("DELETE FROM bridge_messages WHERE id=?", (row[0],))
            return bytes(row[1])


def route_for_identity(identity: str) -> RunnerRoute:
    """Resolve one of the six trusted GitHub Actions runner identities."""
    import re
    match = re.fullmatch(r"github-actions:shemshallah/nanlm-cpu-([1-6])", identity or "")
    if not match:
        raise ValueError("identity is not one of the six authorized BSR runners")
    return RunnerRoute(bsr=int(match.group(1)) - 1)
