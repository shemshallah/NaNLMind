#!/usr/bin/env python3
"""Check the actual C++ Minsky runtime trace against the table source."""
from __future__ import annotations
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "build" / "minsky-trace-dump"
INC = ROOT / "tests" / "minsky_table.inc"

def parse_table():
    text = INC.read_text()
    return {
        (int(q), int(s)): (int(w), int(mv), int(to), h == "true")
        for q, s, w, mv, to, h in re.findall(
            r"\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(-?\d+),\s*(\d+),\s*(true|false)\s*\}", text
        )
    }

def main() -> int:
    if not TOOL.is_file():
        print(f"missing {TOOL}; run make build/minsky-trace-dump", file=sys.stderr)
        return 2
    table = parse_table()
    out = subprocess.check_output([str(TOOL)], text=True)
    lines = [line.split() for line in out.splitlines() if line.startswith("TRACE ")]
    if len(lines) != 101:
        print(f"FAIL: expected 101 trace lines, got {len(lines)}")
        return 1
    cells = [int(x) for x in lines[0][5:]]
    state, head = int(lines[0][2]), int(lines[0][3])
    for index, fields in enumerate(lines):
        got_state, got_head = int(fields[2]), int(fields[3])
        got_cells = [int(x) for x in fields[5:]]
        if (got_state, got_head, got_cells) != (state, head, cells):
            print(f"FAIL: C++ trace diverges from table simulation at step {index}")
            return 1
        if index == 100:
            break
        key = (state, cells[head])
        if key not in table:
            print(f"FAIL: no table entry at step {index} for {key}")
            return 1
        write, move, to, halt = table[key]
        cells = list(cells)
        cells[head] = write
        state = to
        head += move
        if halt:
            if index != 99:
                print(f"FAIL: unexpected early halt at step {index}")
                return 1
    if (state, head, cells) != (2, 38, [int(x) for x in lines[-1][5:]]):
        print("FAIL: final configuration mismatch")
        return 1
    print("MINSKY C++ TRACE CONFORMANCE PASS (100/100 steps)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
