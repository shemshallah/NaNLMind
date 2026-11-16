#!/usr/bin/env python3
"""Detect vacuous source-program tests for the fixed Minsky 23x8 table.

The native compiler fixtures emit source instructions as five parallel arrays.
This independent *source* interpreter checks that the advertised instruction
sequence is actually reachable from the supplied condition. In particular,
merely constructing a nine-bit description and halting on an absent first row
is not evidence of nine-bit instruction execution.

This is a finite executable probe, NOT a proof of UTM universality.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / "mth/tests/mth_minsky_compiler_general_test.nas"
TABLE = ROOT / "tests/minsky_table.inc"


def words(source: str, label: str) -> list[int]:
    match = re.search(r"^" + re.escape(label) + r":\s*\n\s*\.word\s+([\d,\s-]+)",
                      source, re.MULTILINE)
    if match is None:
        raise ValueError(f"missing native source array {label!r}")
    return [int(s) for s in match.group(1).split(",") if s.strip()]


def read_fixture(path: Path) -> tuple[int, int, int, list[int], list[tuple[int, int, int, int, int]]]:
    text = path.read_text(encoding="utf-8")
    width = words(text, "src_p")[0]
    q0 = words(text, "src_q0")[0]
    s0 = words(text, "src_s0")[0]
    source_tape = words(text, "src_tape")
    count = words(text, "src_n")[0]
    columns = [words(text, f"src_{part}") for part in
               ("q", "read", "next", "write", "dir")]
    if any(len(col) != count for col in columns):
        raise ValueError("native source row count disagrees with parallel arrays")
    if not (width >= 1 and 0 <= q0 < 2 ** width and s0 in (0, 1)):
        raise ValueError("initial source condition outside declared width")
    if any(value not in (0, 1) for value in source_tape):
        raise ValueError("source tape is not binary")
    rows = list(zip(*columns))
    for q, scanned, successor, written, direction in rows:
        if not (0 <= q < 2 ** width and 0 <= successor < 2 ** width
                and scanned in (0, 1) and written in (0, 1)
                and direction in (0, 1)):
            raise ValueError("source row not representable at declared width")
    return width, q0, s0, source_tape, rows


def source_trace(q0: int, s0: int, data: list[int],
                 rows: list[tuple[int, int, int, int, int]],
                 max_steps: int = 100) -> tuple[list[tuple[int, int, int, int, int, int]], int, dict[int, int]]:
    # The initial M marker denotes the head at the blank just beyond data.
    # The explicit initial condition is authoritative for first lookup.
    head = len(data)
    tape = {i: symbol for i, symbol in enumerate(data)}
    q = q0
    result = []
    for step in range(max_steps):
        read = s0 if step == 0 else tape.get(head, 0)
        row_index = next((i for i, row in enumerate(rows)
                          if row[:2] == (q, read)), None)
        if row_index is None:
            break
        _, _, qnext, write, right = rows[row_index]
        result.append((row_index, q, read, qnext, write, right))
        tape[head] = write
        head += 1 if right else -1
        q = qnext
    return result, head, tape


def bit_list(number: int, width: int) -> list[int]:
    return [(number >> i) & 1 for i in reversed(range(width))]


def encoded_native_tape(width: int, q0: int, s0: int, data: list[int],
                        rows: list[tuple[int, int, int, int, int]]) -> list[int]:
    contents = data + [6] + [0] * 8 + [5] + bit_list(q0, width) + [s0]
    for q, read, successor, written, direction in rows:
        contents += [4] + bit_list(q, width) + [read] + bit_list(successor, width) + [written, direction]
    return contents + [5, 0, 0, 0]


def native_run(contents: list[int], start_head: int, max_steps: int = 10000
               ) -> tuple[list[int], int, int, bool]:
    lines = re.findall(
        r"\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(-?\d+),\s*(\d+),\s*(true|false)\s*\}",
        TABLE.read_text(encoding="utf-8"),
    )
    if len(lines) != 184:
        raise ValueError("canonical transition table is not 23x8")
    transitions = [(int(w), int(move), int(next_q), halt == "true")
                   for _, _, w, move, next_q, halt in lines]
    tape = {i: s for i, s in enumerate(contents)}
    state = 5
    head = start_head
    for steps in range(1, max_steps + 1):
        symbol = tape.get(head, 2)
        if not (0 <= symbol <= 7 and 0 <= state <= 22):
            raise ValueError(f"invalid table key at step {steps}: {(state, symbol)}")
        write, move, new_state, halt = transitions[state * 8 + symbol]
        tape[head] = write
        head += move
        state = new_state
        if halt:
            return [tape.get(i, 2) for i in range(len(contents))], head, steps, True
    return [tape.get(i, 2) for i in range(len(contents))], head, max_steps, False


def check_naive_gap_decoder_counterexample() -> None:
    """Disprove a literal M-as-gap decoder, not the machine's universality.

    On an all-zero tape, source write-then-left-move would encode the newly
    written 1 two physical cells to the right of the new M under a direct
    logical-gap representation. The actual table leaves it immediately to
    the right. A richer Minsky representation may explain that difference.
    """
    data = [0] * 4
    program = [(0, 0, 1, 1, 0)]
    initial = encoded_native_tape(2, 0, 0, data, program)
    final, _, steps, halted = native_run(initial, len(data) + 13)
    naive_gap = [0, 0, 0, 6, 0, 1]
    native_prefix = final[:len(naive_gap)]
    if not halted or native_prefix != [0, 0, 0, 6, 1, 0]:
        raise AssertionError("one-left-instruction concrete trace unexpectedly changed")
    if native_prefix == naive_gap:
        raise AssertionError("negative control no longer differentiates decoders")
    print(f"NAIVE GAP DECODER UNSOUND: after {steps} concrete steps, "
          f"native prefix={native_prefix}, literal-gap source prefix={naive_gap}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, default=DEFAULT)
    parser.add_argument("--require-steps", type=int, default=1)
    parser.add_argument("--require-both-directions", action="store_true")
    parser.add_argument("--emit-native-expected", action="store_true")
    parser.add_argument("--check-native-expected", action="store_true")
    parser.add_argument("--audit-naive-gap-decoder", action="store_true")
    args = parser.parse_args()
    width, q0, s0, data, rows = read_fixture(args.fixture)
    trace, head, tape = source_trace(q0, s0, data, rows)
    directions = {entry[-1] for entry in trace}
    print(f"source width={width}, rows={len(rows)}, initial=(q{q0},{s0}), "
          f"simulated_steps={len(trace)}, final_source_head={head}")
    for k, (index, q, read, successor, written, right) in enumerate(trace):
        print(f"  {k:3d}: record[{index}] (q{q},{read}) -> "
              f"(q{successor},{written},{'R' if right else 'L'})")
    if args.audit_naive_gap_decoder:
        check_naive_gap_decoder_counterexample()
    if args.emit_native_expected or args.check_native_expected:
        initial = encoded_native_tape(width, q0, s0, data, rows)
        final, final_head, native_steps, native_halted = native_run(
            initial, len(data) + 11 + width,
            max_steps=max(10000, 2048 * width))
        print(f"native steps={native_steps}, halted={native_halted}, "
              f"head={final_head}, length={len(final)}")
        if args.emit_native_expected:
            print("  .word " + ",".join(map(str, final)))
        if args.check_native_expected:
            published = words(args.fixture.read_text(encoding="utf-8"), "expected")
            if not native_halted or final != published:
                print("FAIL: native table result differs from committed expected image")
                return 1
            if final.count(6) != 1 or final.index(6) != head:
                print("FAIL: final M marker disagrees with reference source head")
                return 1
            # Decode the displaced head cell from the condition field, not
            # from a fictitious binary cell beside M.  Marks A/B (2/3)
            # represent logical 0/1 in both the program and condition.
            def logical_bit(symbol: int) -> int:
                if symbol in (0, 2):
                    return 0
                if symbol in (1, 3):
                    return 1
                raise AssertionError(f"nonbinary logical symbol {symbol}")

            y_position = len(data) + 9  # M + eight buffer cells + Y
            condition_start = y_position + 1
            condition_read_position = condition_start + width
            if not (0 <= head < y_position and final[y_position] == 5):
                print("FAIL: displaced M or Y escaped the source tape frame")
                return 1
            source_state = trace[-1][3] if trace else q0
            native_state = 0
            for symbol in final[condition_start:condition_read_position]:
                native_state = 2 * native_state + logical_bit(symbol)
            if native_state != source_state:
                print("FAIL: decoded final source-control state differs")
                return 1
            for pos in range(y_position):
                physical_symbol = (final[condition_read_position]
                                   if pos == head else final[pos])
                if logical_bit(physical_symbol) != tape.get(pos, 0):
                    print(f"FAIL: full displaced-tape decoding differs at {pos}")
                    return 1
            print(f"PASS: displaced-head decoder agrees on state q{native_state}, "
                  f"head {head}, and {y_position} source-tape cells")
    if len(trace) < args.require_steps:
        print("FAIL: first source instruction is missing or insufficient steps were executed")
        return 1
    if args.require_both_directions and directions != {0, 1}:
        print("FAIL: source execution did not exercise both head directions")
        return 1
    print("PASS: actual initial source condition reaches the required instructions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
