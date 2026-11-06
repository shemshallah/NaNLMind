"""Canonical 64-bit NaN16 identities for mounted rawroute volumes.

The logical identity is stable across provider volume replacement. Provider
volume IDs and generations belong in the deployment manifest, not in this
address word.
"""
from __future__ import annotations

from dataclasses import dataclass

TIERS = {"BS0": 1, "MC0": 2, "SC0": 3, "GM0": 4}
TIER_NAMES = {value: key for key, value in TIERS.items()}
MAGIC = 0x4E
FORMAT = 1
FAR_HEAD = 0x7FF1
NEAR_HEAD = 0x7FF1
FAR_STORED = 0xF17F


def _crc8_atm(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (((crc << 1) ^ 0x07) & 0xFF) if crc & 0x80 else ((crc << 1) & 0xFF)
    return crc


@dataclass(frozen=True)
class VolumeAddress:
    tier: str
    shard: int
    raw: int

    @property
    def payload(self) -> int:
        return (self.raw >> 16) & 0xFFFFFFFF

    @property
    def path(self) -> str:
        return f"/0x{self.raw:016X}"


def make_volume_address(tier: str, shard: int = 0) -> VolumeAddress:
    if tier not in TIERS:
        raise ValueError("unknown NaN volume tier")
    if isinstance(shard, bool) or not isinstance(shard, int) or not 0 <= shard <= 255:
        raise ValueError("volume shard must be an integer in 0..255")
    upper24 = (MAGIC << 16) | (FORMAT << 12) | (TIERS[tier] << 8) | shard
    payload = (upper24 << 8) | _crc8_atm(upper24.to_bytes(3, "big"))
    # NanWord::make(+sNaN, +sNaN, payload): near head occupies the
    # high 16 bits; far head is byte-swapped into the low 16 bits.
    raw = (NEAR_HEAD << 48) | (payload << 16) | FAR_STORED
    return VolumeAddress(tier=tier, shard=shard, raw=raw)


def parse_volume_path(path: str) -> VolumeAddress:
    if not isinstance(path, str) or len(path) != 19 or not path.startswith("/0x"):
        raise ValueError("NaN volume path must be /0x followed by 16 hex digits")
    try:
        raw = int(path[3:], 16)
    except ValueError as exc:
        raise ValueError("NaN volume path contains non-hex digits") from exc
    if raw >> 48 != NEAR_HEAD or (raw & 0xFFFF) != FAR_STORED:
        raise ValueError("NaN volume address must use +sNaN at both heads")
    payload = (raw >> 16) & 0xFFFFFFFF
    upper24 = payload >> 8
    magic = (upper24 >> 16) & 0xFF
    version = (upper24 >> 12) & 0x0F
    tier_id = (upper24 >> 8) & 0x0F
    shard = upper24 & 0xFF
    crc = payload & 0xFF
    if magic != MAGIC or version != FORMAT or tier_id not in TIER_NAMES:
        raise ValueError("NaN volume address magic, format, or tier rejected")
    if crc != _crc8_atm(upper24.to_bytes(3, "big")):
        raise ValueError("NaN volume address CRC rejected")
    return VolumeAddress(TIER_NAMES[tier_id], shard, raw)
