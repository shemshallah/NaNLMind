#!/usr/bin/env python3
"""Audit both native NaN16 eight-word Minsky tables against canonical C++ rows.

This is a source-transcription and instruction-layout gate, not an ISA or
assembler proof. Coq's MinskyNaN16Words.v separately proves the abstract
eight-word scanner agrees with the six-byte chart and zipper semantics.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANONICAL = ROOT / "tests/minsky_table.inc"
FIXTURES = (
    ROOT / "mth/tests/mth_minsky_test.nas",
    ROOT / "mth/tests/mth_minsky_encoded_test.nas",
)

CANONICAL_ROW = re.compile(
    r"^\s*\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,"
    r"\s*(\d+)\s*,\s*(true|false)\s*\}\s*,?\s*$"
)
ASSEMBLY_ROW = re.compile(r"^\s*\.word\s+(\d+(?:\s*,\s*\d+){7})\s*$")


def canonical_rows(contents: str) -> list[tuple[int, ...]]:
    rows = []
    for line_number, line in enumerate(contents.splitlines(), 1):
        if not line.strip():
            continue
        match = CANONICAL_ROW.fullmatch(line)
        if not match:
            raise ValueError(f"invalid canonical row at line {line_number}: {line}")
        state, read, write, move, target = map(int, match.groups()[:5])
        halt = int(match.group(6) == "true")
        if move not in (-1, 0, 1):
            raise ValueError(f"unrepresentable movement on line {line_number}")
        rows.append((state, read, write, move + 1, target, halt, 0, 0))
    if len(rows) != 184:
        raise ValueError(f"expected 184 canonical rows, found {len(rows)}")
    return rows


def native_rows(contents: str) -> list[tuple[int, ...]]:
    lines = contents.splitlines()
    try:
        begin = lines.index("table:") + 1
        end = lines.index("expected:", begin)
    except ValueError as exc:
        raise ValueError("missing table:/expected: sentinels") from exc
    rows = []
    for number in range(begin, end):
        line = lines[number]
        if not line.strip():
            continue
        match = ASSEMBLY_ROW.fullmatch(line)
        if match is None:
            raise ValueError(f"invalid native table line {number + 1}: {line}")
        rows.append(tuple(map(int, match.group(1).split(","))))
    if len(rows) != 184:
        raise ValueError(f"expected 184 native rows, found {len(rows)}")
    return rows


def audit_native(source: str, canonical: list[tuple[int, ...]]) -> None:
    rows = native_rows(source)
    for i, (expected, actual) in enumerate(zip(canonical, rows)):
        if expected != actual:
            raise ValueError(
                f"transition row {i} ({i // 8},{i % 8}) mismatch: "
                f"canonical={expected}, native={actual}"
            )
    # Fail closed if the native loop's address calculation or decoded fields
    # change; they require a corresponding Coq bridge review.
    required = (
        "MOVI r5,@table", "MOVI r6,184", "SHL r7,r8,3",
        "ADD r7,r7,r5", "LD r9,r7,0", "LD r9,r7,1",
        "LD r9,r7,2", "LD r9,r7,3", "LD r9,r7,4",
        "LD r9,r7,5", "ST r9,r3,0", "ST r2,r0,@head",
        "ST r9,r0,@state", "ST r9,r0,@halt",
    )
    for instruction in required:
        if not re.search(r"(?m)^\s*" + re.escape(instruction) + r"\s*$", source):
            raise ValueError(f"native scanner instruction changed: {instruction}")


def main() -> int:
    canonical = canonical_rows(CANONICAL.read_text(encoding="utf-8"))
    for path in FIXTURES:
        audit_native(path.read_text(encoding="utf-8"), canonical)
        print(f"PASS {path.relative_to(ROOT)}: 184/184 canonical eight-word records")
    print("NAN16 EIGHT-WORD MINSKY TABLE TRANSCRIPTION PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
