# First-failed-bit comparison for the frozen Minsky 23×8 table

Author: Justin Howard-Stanley — Independent Researcher, Santa Cruz,
California, USA.

## Scope and provenance

This is a partial result about the literal 184-entry transition table in
`formal/utm/MinskyTableData.v`, not a complete source-instruction or
universality theorem. The new composition extends the already certified
arbitrary-length all-match and individual mismatch-restart lemmas in
`formal/utm/MinskyMatchMacro.v`.

For a finite bit prefix of length `n`, an initial q1 binary pass prefix
of length `p`, and an X-free rightward row scan of length `r`, prepare the
following canonical tape segment immediately to the right of Y:

1. `pass`: `p` raw binary cells, each 0/1;
2. `marks(prefix)`: the `n` A/B marks (2/3) encoding the successful bits;
3. `mark(failed_bit)`: one A/B mark to be compared unsuccessfully;
4. `raw(prefix)`: the same `n` source bits, each 0/1;
5. `raw(opposite(failed_bit))`: the deliberately mismatching raw bit;
6. `row_rest`: `r` symbols in `{0,1,2,3,6,7}`;
7. `X=4`, followed by an arbitrary tape suffix.

Begin in state q1 with the head at the start of this segment and Y
immediately to its left. Every successful comparison executes the real
q1→q0/q4→q2→q1 path. The first mismatching comparison executes the real
q1→q0/q4→q3→X→q5→Y path. The result returns to q1 at the **same** Y,
with no halt. The entire intervening segment is rewritten by q5
(`0→2`, `1→3`, all other permitted symbols unchanged), while `X` and
the arbitrary suffix remain in place.

The exact number of native table transitions is

\[
T(n,p,r) = 3n^2 + 2np + 7n + 2p + 2r + 6.
\]

This generalizes the separately certified all-match clock
`3n² + 2np + n`; it does not assume that the return to Y constitutes an
already selected new source instruction.

## Proof and test boundaries

- `q1_matching_prefix_then_first_mismatch` composes any matching prefix
  with either mismatch polarity while spelling out the Y-free cleanup split.
- `q5_first_mismatch_segment_valid` derives q5's admissible-symbol
  invariant from the canonical layout; no separate no-Y premise remains.
- `q1_first_mismatch_canonical_layout` gives exact concrete final tapes.
- `first_mismatch_clock_polynomial` proves the clock formula in Coq arithmetic.
- `q1_first_mismatch_exact_clock` connects that formula to the unchanged
  `MinskyTable.run`.
- `formal/utm/check_minsky_dispatch.py` tests 40,078 new exhaustive and
  seeded first-mismatch-after-matches cases, including prefixes of length
  512, against the independent native-table transcription. Earlier tests
  include 116,646 individual mismatch restarts.

Formal certification requires Coq 8.20 compilation, `coqchk`, and the
existing `minsky-coq-bridge.yml` workflow to succeed. Passing finite
regressions alone is not kernel certification.

The first composed theorem was certified on commit `28938cc` by the
successful GitHub Actions Coq bridge run `43771243886`. The expanded
regression gate passed run `43771617720`. Later canonical-layout and
erasure-preservation theorems require their own successful `coqchk` results;
these earlier runs do not certify later assertions.

## What remains open

1. Prove that **arbitrary sequences** of mismatch restarts advance through
   the intended encoded source-row candidates while preserving the full
   program, work-tape, marker and delimiter invariants.
2. Prove that a selected matching row triggers the prescribed write,
   state change, head move, and halting behavior of one decoded source
   instruction under the same frozen 184-entry table.
3. Establish an unrestricted computable source-configuration encoding and
   decoding relation, then discharge the `actual_table_macro_step` premise
   in `MinskyMacroSimulation.v` without replacing the table or assuming
   an unproved simulation step.

Until those obligations are discharged, concrete 23×8 universality is open.
