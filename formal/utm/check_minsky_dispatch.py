#!/usr/bin/env python3
"""Independent executable gate for concrete source-row and buffer branches.

Reads the frozen native table, not the Coq transcription.  Exhausts all
seven-bit fixed-width rows under both delimiter contexts, then probes
arbitrarily wider binary tails and positive buffer widths.  The zero-width
case is explicitly excluded from the Coq variable-buffer macro.  These
checks supplement Coq; finite tests cannot prove unbounded universality.
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
    buffer_width: int = 3,
) -> None:
    if buffer_width < 1:
        raise ValueError("the variable-buffer macro requires a positive width")
    # The original head is on X at coordinate zero. The Y delimiter and
    # buffer_width zero cells are immediately to its left.
    delimiter = -buffer_width - 1
    tape = {delimiter: 5, 0: 4, 1: first_bit}
    tape.update({p: 0 for p in range(-buffer_width, 0)})
    tape.update({i + 2: value for i, value in enumerate(tail)})
    boundary = len(tail) + 2
    tape[boundary] = next_marker
    tape.update({delimiter - 1: 6, delimiter - 2: 1,
                 delimiter - 3: 3, boundary + 1: 7})
    before = tape.copy()
    state = 5
    head = 0
    halted = False
    total = (2 * buffer_width + 5 + len(tail)) if first_bit else (
        3 * buffer_width + 6
    )
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
        if (state, head, halted) != (1, -buffer_width, False):
            raise AssertionError(
                (buffer_width, first_bit, tail, next_marker, state, head, halted)
            )
        if tape[1] != 2:
            raise AssertionError("low branch did not mark first state bit")
        if any(tape[i + 2] != bit for i, bit in enumerate(tail)):
            raise AssertionError("low branch failed to preserve binary tail")

    expected_prefix = [5, 0] + [2] * (buffer_width - 1) + [4]
    if [tape[i] for i in range(delimiter, 1)] != expected_prefix:
        raise AssertionError("delimiter, buffer or marker altered")
    outer = (delimiter - 3, delimiter - 2, delimiter - 1,
             boundary, boundary + 1)
    if any(tape[k] != before[k] for k in outer):
        raise AssertionError("surrounding tape changed")


def check_zero_buffer_exception(
    table: list[tuple[int, int, int, int, int, bool]],
) -> None:
    # At width 0 the native table does not reach state 2/3 in four steps.
    # This counterexample makes the positive-width theorem precondition
    # observable in the regression gate.
    for first_bit, expected_state in ((0, 8), (1, 7)):
        tape = {-1: 5, 0: 4, 1: first_bit}
        state, head, halted = 5, 0, False
        for _ in range(4):
            symbol = tape.get(head, 2)
            _, _, written, movement, state, halted = table[state * 8 + symbol]
            tape[head] = written
            head += movement
        if (state, head, halted) != (expected_state, 0, False):
            raise AssertionError("unexpected zero-buffer control path")


def main() -> None:
    table = load_table()
    check_zero_buffer_exception(table)
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
    for buffer_width in (1, 2, 4, 5, 7, 16, 32, 65, 129):
        for tail_width in (0, 1, 2, 7, 17):
            for _ in range(8):
                bits = tuple(rng.randrange(2) for _ in range(tail_width))
                for high, marker in itertools.product((0, 1), (4, 5)):
                    check_branch(table, high, bits, marker, buffer_width)
                    cases += 1
    print(f"MINSKY CONCRETE DISPATCH PASS ({cases} exhaustive/seeded cases; "
          "positive buffers 1..129 and zero-buffer counterexample)")


if __name__ == "__main__":
    main()
