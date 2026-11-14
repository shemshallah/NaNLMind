#!/usr/bin/env python3
"""Check the Coq Minsky table against tests/minsky_table.inc."""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def inc_rows() -> list[tuple[int, int, int, int, int, bool]]:
    text = (ROOT / "tests/minsky_table.inc").read_text()
    rows = []
    for m in re.finditer(r"\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(-?\d+),\s*(\d+),\s*(true|false)\s*\}", text):
        q, s, w, mv, to, h = m.groups()
        rows.append((int(q), int(s), int(w), int(mv), int(to), h == "true"))
    return rows

def coq_rows() -> list[tuple[int, int, int, int, int, bool]]:
    text = (ROOT / "formal/utm/MinskyTableData.v").read_text()
    rows = []
    for m in re.finditer(r"mkEntry\s+(\d+)\s+(\d+)\s+(\d+)\s+\((-?\d+)\)%Z\s+(\d+)\s+(true|false)", text):
        q, s, w, mv, to, h = m.groups()
        rows.append((int(q), int(s), int(w), int(mv), int(to), h == "true"))
    return rows

def main() -> int:
    a, b = inc_rows(), coq_rows()
    if len(a) != 184 or len(b) != 184:
        print(f"FAIL: expected 184 entries, got inc={len(a)} coq={len(b)}")
        return 1
    if a != b:
        for i, (x, y) in enumerate(zip(a, b)):
            if x != y:
                print(f"FAIL at entry {i}: inc={x} coq={y}")
                return 1
        print("FAIL: table length mismatch")
        return 1
    print("MINSKY TABLE TRANSCRIPTION PASS (184/184 entries)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
