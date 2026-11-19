#!/usr/bin/env python3
"""Independent exhaustive small-window replay of the canonical 4-prefix bridge.

Checks actual 23x8 native table transitions, not source-level emulation.
Coq's universally quantified q15/q16/q21 lemmas remain authoritative.
"""
from __future__ import annotations

from itertools import product

from check_minsky_left_tagged_dispatch import (
    cfg_move_left,
    load_table,
    run_native,
)


def sequences(alphabet: tuple[int, ...], maximum: int, minimum: int = 0):
    for length in range(minimum, maximum + 1):
        yield from product(alphabet, repeat=length)


def main() -> None:
    table = load_table()
    # Both extreme tape windows and a mixed internal marker window.
    surroundings = ([], [4], [7, 5, 2])
    count = 0
    for tags, direction, (old, next_bit, target), outer, suffix in product(
        tuple(sequences((6, 7), 3)),
        tuple(sequences((4, 5, 6, 7), 2, 1)),
        product((0, 1), repeat=3),
        surroundings,
        surroundings,
    ):
        tags, direction = list(tags), list(direction)
        right = list(reversed(tags)) + [next_bit] + suffix
        steps = (len(tags) + 1) + (len(tags) + 2) + (len(direction) + 1)
        common_right = (list(reversed(direction)) + [7, 4] +
                        list(reversed(tags)) + [next_bit] + suffix)

        starting_right = [4, old] + direction + [3] + outer
        expected_right = (19, [old] + outer, common_right)
        actual_right = run_native(table, steps, 15, starting_right, right)
        assert actual_right == expected_right, (
            "right 4-prefix", old, target, tags, direction, outer, suffix,
            actual_right, expected_right,
        )
        count += 1

        starting_left = [4, old] + direction + [2, target] + outer
        expected_left = cfg_move_left(
            20, [target] + outer, [old] + common_right,
        )
        actual_left = run_native(table, steps, 15, starting_left, right)
        assert actual_left == expected_left, (
            "left 4-prefix", old, next_bit, target, tags, direction,
            outer, suffix, actual_left, expected_left,
        )
        count += 1

    print(f"MINSKY 4-PREFIX NATIVE PASS: {count} exact two-direction "
          "traces; 184/184 native transition entries")


if __name__ == "__main__":
    main()
