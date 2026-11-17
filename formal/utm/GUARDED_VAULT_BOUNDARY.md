# Guarded-vault right-rail boundary

Status: kernel-checked by the fast q15-q22 Coq job
([run 44147774350](https://github.com/shemshallah/NaNLMind/actions/runs/44147774350))
and independently rebuilt by the full Minsky Coq bridge
([run 44147774314](https://github.com/shemshallah/NaNLMind/actions/runs/44147774314))
at `58e7eb1`.

This note records a **negative boundary** for one proposed fix to the q19
program-collision.  It is not a universality claim and it does not assert
canonical reachability.

## The proposal under test

The earlier guarded-vault theorems keep an encoded program on the left of a
q12 entry, place a dual-safe rail on the right, and run

```text
q12 -> q14 -> q15 -> q16 -> q21/q22 -> q19 -> q17/q18 -> q5 -> q1 -> q6
```

with an exact linear clock.  The rail is accepted exactly when every scanned
cell is `4`, `6`, or `7` (`q19_q5_roundtrip_railb`).  The purpose was to let
q19 relocate the new data marker without crossing a marked program.

## What is now proved

All statements are literal `MinskyTable.run` facts for the unchanged
23-state / 8-symbol table.

1. `q12_roundtrip_no_raw_suffix_stalls_q6`.
   If the q6 return frame has no raw `0`/`1` cell to its right, q6 is a
   permanent sink: the state is 6 for every further fuel, including when the
   scan reaches the finite-tape blank.

2. `q6_guarded_rail_to_q7_or_q8`.
   With one raw bit after the `7` marker, q6 crosses the guarded rail, marks
   that bit as 2/3, and enters q8 (zero) or q7 (one).  The exact clock is
   `length scanned + 3`.

3. `q78_scan_back_to_first_five` and
   `q78_returned_vault_to_q9_or_q10`.
   q7/q8 return left to the first `Y = 5`; q9/q10 then re-enter with the
   exact preserved frame.  The return clock is `length scanned + 5`.

4. `q910_restored_four_to_q12_or_q13`.
   The next two literal transitions read 7, then read the route `4` and turn
   back left into q12 (one branch) or q13 (zero branch).  The relocated
   `M = 6` marker and the marked region remain on the **right** of the head.

5. `q6_complete_return_to_q12_or_q13`.
   The complete q6 -> q7/q8 -> q9/q10 -> q12/q13 return has exact clock
   `2 * length scanned + 10`.

6. `q12_complete_return_into_six_free_vault`.
   Starting from the guarded q12 entry, the full
   q12 -> q6 -> q7/q8 -> q9/q10 -> q12/q13 cycle has exact clock
   `6 * length scanned + 32` and preserves the stored wide program verbatim.

7. `q12_complete_vault_cycle_cannot_resume`.
   For any additional fuel, the final state stays 12 or 13.  The left
   frontier is `5 :: 0 :: encode_wide_program rows`; ordinary wide programs
   use only `4`, `0`, and `1`, so neither direction state can find the `6`
   that would trigger its q14 exit.

## Consequence

The guarded right-rail placement avoids the q19/program collision for the
movement half-cycle, but it is **not a complete instruction encoding**.  It
returns to q12/q13 with the `M = 6` marker on the wrong side.  Because an
ordinary program vault contains no `6`, the next direction phase cannot
start, regardless of how much additional fuel is supplied.

A complete encoding must either:

- keep the canonical left-data / right-program orientation and make q19's
  rightward scan avoid the program region by construction; or
- keep a left-accessible `6` marker between `Y` and the route `4`, so that
  the next q12/q13 phase can terminate.

Merely moving the program to the far left of the direction frame is
insufficient.

## What this does not prove

- No source-row dispatch, source-state matching, writeback, or source-tape
  simulation.
- No reachability of the guarded q12 entry from a canonical q5 configuration.
- No claim that the 23x8 table is non-universal.
- No compiled-C++/allocator/NaN16 runtime claim.

The result is a checked obstruction for one concrete tape layout, not a
statement about the unchanged transition table's universality.
