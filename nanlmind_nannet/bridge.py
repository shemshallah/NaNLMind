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
        m = re.fullmatch(
            r"nan://GM(\d{1,3}):SC(\d{1,3}):MC(\d{1,3}):"
            r"BS(\d{1,3}):HW(\d{1,3}):BSR([0-5])", value or "")
        if not m:
            raise ValueError("runner route must be nan://GM:SC:MC:BS:HW:BSR0..5")
        return cls(*(int(x) for x in m.groups()))


@dataclass(frozen=True)
class BridgeFrame:
    source: RunnerRoute
    destination: RunnerRoute
    sequence: int
    word: NanWord
    payload: bytes = b""

    def encode(self) -> bytes:
        if not 0 <= self.sequence <= 0xFFFFFFFF:
            raise ValueError("sequence must be uint32")
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
                created_at INTEGER NOT NULL)""")
            db.execute("CREATE INDEX IF NOT EXISTS bridge_destination_id "
                       "ON bridge_messages(destination, id)")

    def put(self, frame: BridgeFrame) -> None:
        raw = frame.encode()
        with sqlite3.connect(self.database, timeout=15) as db:
            db.execute("INSERT INTO bridge_messages(destination,source,frame,created_at) "
                       "VALUES(?,?,?,?)",
                       (frame.destination.text(), frame.source.text(), raw, int(time.time())))

    def take(self, destination: RunnerRoute) -> bytes | None:
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
