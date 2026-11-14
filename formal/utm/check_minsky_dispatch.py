#!/usr/bin/env python3
"""Independent executable gate for the first concrete source-row branches.

Reads the frozen native table, not the Coq transcription.  Exhausts all
seven-bit fixed-width rows under both delimiter contexts, then probes
arbitrarily wider binary tails.  These checks supplement Coq; finite tests
alone cannot certify unbounded simulation or universality.
"""

from __future__ import annotations

import itertools
import random
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TABLE_FILE = ROOT / "tests/minsky_table.inc"
ENTRY = re.compile(
    r"\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,"
    r"\s*(\d+)\s*,\s*(true|false)\s*\}"
)


def load_table() -> list[tuple[int, int, int, int, int, bool]]:
    rows = [
        (int(q), int(read), int(write), int(move), int(next_q), halt == "true")
        for q, read, write, move, next_q, halt in ENTRY.findall(
            TABLE_FILE.read_text(encoding="utf-8")
        )
    ]
    if len(rows) != 184:
        raise AssertionError(f"expected 184 rows, received {len(rows)}")
    for q in range(23):
        for s in range(8):
            if rows[q * 8 + s][:2] != (q, s):
                raise AssertionError(f"invalid row-major entry {q},{s}")
    return rows


def check_branch(
    table: list[tuple[int, int, int, int, int, bool]],
    first_bit: int,
    tail: tuple[int, ...],
    next_marker: int,
) -> None:
    # The original head is on X at coordinate zero. The Y delimiter and
    # three 0-buffer cells are immediately to its left.
    tape = {-4: 5, -3: 0, -2: 0, -1: 0, 0: 4, 1: first_bit}
    tape.update({i + 2: value for i, value in enumerate(tail)})
    boundary = len(tail) + 2
    tape[boundary] = next_marker
    tape.update({-5: 6, -6: 1, -7: 3, boundary + 1: 7})
    before = tape.copy()
    state = 5
    head = 0
    halted = False
    total = (11 + len(tail)) if first_bit else 15
    for count in range(total):
        if halted:
            raise AssertionError(f"premature halt at step {count}")
        symbol = tape.get(head, 2)
        source, read, write, move, new_state, stop = table[state * 8 + symbol]
        if (source, read) != (state, symbol):
            raise AssertionError("table indexing mismatch")
        tape[head] = write
        head += move
        state = new_state
        halted = stop

    if first_bit:
        expected = (5, boundary - 1, False) if next_marker == 4 else (
            0, boundary, True
        )
        if (state, head, halted) != expected:
            raise AssertionError((first_bit, tail, next_marker, state, head, halted))
        if tape[1] != 3 or any(tape[i + 2] != bit for i, bit in enumerate(tail)):
            raise AssertionError("forward scan failed to preserve binary tail")
    else:
        if (state, head, halted) != (1, -3, False):
            raise AssertionError((first_bit, tail, next_marker, state, head, halted))
        if tape[1] != 2:
            raise AssertionError("low branch did not mark first state bit")
        if any(tape[i + 2] != bit for i, bit in enumerate(tail)):
            raise AssertionError("low branch failed to preserve binary tail")

    if [tape[i] for i in (-4, -3, -2, -1, 0)] != [5, 0, 2, 2, 4]:
        raise AssertionError("delimiter, buffer or marker altered")
    if any(tape[k] != before[k] for k in (-7, -6, -5, boundary, boundary + 1)):
        raise AssertionError("surrounding tape changed")


def main() -> None:
    table = load_table()
    cases = 0
    for bits in itertools.product((0, 1), repeat=7):
        for marker in (4, 5):
            check_branch(table, bits[0], bits[1:], marker)
            cases += 1
    rng = random.Random(0x238)
    for width in (0, 1, 2, 3, 7, 15, 32, 64, 129):
        for _ in range(40):
            bits = tuple(rng.randrange(2) for _ in range(width))
            for high, marker in itertools.product((0, 1), (4, 5)):
                check_branch(table, high, bits, marker)
                cases += 1
    print(f"MINSKY CONCRETE DISPATCH PASS ({cases} exhaustive/seeded cases)")


if __name__ == "__main__":
    main()
