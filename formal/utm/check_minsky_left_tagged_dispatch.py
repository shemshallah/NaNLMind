#!/usr/bin/env python3
"""Independent native-table oracle for the 21-step guarded left macro.

The Coq theorem is the authority.  This regression checks all 16 choices
of old/next/extra/target against the literal C transition table, with
several unrelated left and right tape suffixes.  It also detects the
opposite q4 branch when the required sacrificial false guard is true.
"""
from __future__ import annotations

from itertools import product
from pathlib import Path
import re


TABLE = Path(__file__).resolve().parents[2] / "tests/minsky_table.inc"


def load_table() -> dict[tuple[int, int], tuple[int, int, int, bool]]:
    pattern = r"\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(-?\d+),\s*(\d+),\s*(true|false)\s*\}"
    rows = re.findall(pattern, TABLE.read_text())
    assert len(rows) == 184, "literal native table must contain 23*8 entries"
    return {(int(q), int(s)): (int(w), int(move), int(to), halt == "true")
            for q, s, w, move, to, halt in rows}


def run_native(table, steps, state, left, right):
    left, right = list(left), list(right)
    for _ in range(steps):
        symbol = right[0] if right else 2
        written, move, state, halted = table[state, symbol]
        if right:
            right[0] = written
        else:
            right = [written]
        if move == 1:
            left.insert(0, right.pop(0))
        elif move == -1:
            right.insert(0, left.pop(0) if left else 2)
        assert not halted, "guarded macro unexpectedly halted"
    return state, left, right


def cfg_move_left(state, left, right):
    return (state, left[1:], [left[0]] + right) if left else (state, [], [2] + right)


def main():
    table = load_table()
    samples = ([], [4], [7, 5, 2])
    checked = 0
    rejected = 0
    for old, next_bit, extra, target in product((0, 1), repeat=4):
        # Coq's source_bit is the raw natural-number bit; the stable
        # control tag maps false to 6 and true to 7.
        tags = [6 + next_bit, 6 + extra]
        for outer, tail in product(samples, repeat=2):
            initial_left = [old, 6, 5, 2, 0] + outer
            initial_right = tags + [target] + tail
            interim = run_native(table, 14, 15, initial_left, initial_right)
            assert interim == (
                5, [5, old, 6] + outer,
                [6, 2] + tags + [target] + tail
            ), ("q15->q5 shape", old, next_bit, extra, target, outer, tail, interim)

            expected_left = [extra + 6, next_bit + 6, 0, 6, 5, old, 6] + outer
            expected = ((3, [3] + expected_left, tail) if target
                        else cfg_move_left(2, expected_left, [2] + tail))
            observed = run_native(table, 21, 15, initial_left, initial_right)
            assert observed == expected, (
                "left guarded theorem", old, next_bit, extra, target, outer, tail,
                observed, expected)
            checked += 1

            # Changing just the sacrificial 0 to 1 makes q1 select q4,
            # complementing the eventual q2/q3 choice: a negative control.
            wrong = run_native(table, 21, 15,
                               [old, 6, 5, 2, 1] + outer, initial_right)
            assert wrong[0] == (2 if target else 3), (
                "true guard must reverse dispatch", old, next_bit, extra,
                target, outer, tail, wrong)
            rejected += 1
    print(f"MINSKY LEFT TAGGED NATIVE PASS: {checked} exact positive traces, "
          f"{rejected} opposite-guard negative controls; 184/184 entries")


if __name__ == "__main__":
    main()
