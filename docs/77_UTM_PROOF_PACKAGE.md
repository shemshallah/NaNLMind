# UTM proof package

## 1. Objects

- `U_M`: the explicit 23-state, 8-symbol Minsky universal table
  (`tests/minsky_table.inc`).
- `TuringMachine`: fixed table-driven runtime in chart address registers.
- `UniversalTuringMachine`: fixed-step encoded-description interpreter.
- `compile_tm_to_binary`: source TM -> binary TM with fixed-width blocks.
- `BinaryUniversalMachine`: compact direct binary runtime.

## 2. Theorem statement

There is a fixed chart transition table `U_M` and a computable encoding `e`
such that for every finite TM `T` and input `x`, iterating `U_M` from `e(T,x)`
simulates `T` on `x` until the encoded machine halts or diverges.

This is Minsky's universality theorem for the published 23×8 machine, combined
with the implementation transcription and encoding below.

## 3. Lemmas

### L1 — table transcription

`tests/minsky_table.inc` contains all 184 state/symbol entries, including
Minsky's implicit identity quintuples. The independent Python implementation
matches the chart table for the published 100-step trace.

Evidence:

```text
PASS Minsky 23-state/8-symbol table matches Python reference
```

### L2 — encoded-description execution

The same table encoded as a `TmDescription` is loaded into the fixed-step
`UniversalTuringMachine`; it executes an encoded binary machine and matches the
table-driven reference for 100 steps.

Evidence:

```text
PASS encoded Minsky universal description runs on the chart UTM
```

### L3 — binary compiler

The source transition `(q, s) -> (q', w, m)` is represented by seven binary
microsteps over a `ceil(log2 |Γ|)`-bit block:

```text
R0: read block bit 0
R1: read block bit 1
R2: read block bit 2 and select (q, s)
W1: write block bit 1 and move to bit 0
W0: write block bit 0 and move one source cell
ML/MR: traverse the block boundary
```

Induction over one block cycle gives:

```text
source state/head/tape == decoded binary state/head/tape
```

The compiler and compact runtime preserve 20 source steps exactly.

Evidence:

```text
PASS TM-to-binary compiler preserves 20 Minsky source steps
PASS compact binary runtime preserves 20 Minsky source steps
```

### L4 — own-tape trace

The compiled binary Minsky table runs on the Minsky machine's default tape,
starting from the same source state and head. State, head, and decoded tape match
the source for the checked 100-step trace.

Evidence:

```text
PASS compiled binary Minsky table tracks the source Minsky trace
```

## 4. Composition

1. L1 gives the published universal table.
2. L3 gives a binary implementation of that table with a checked one-step
   invariant family.
3. L2 gives an encoded universal description that runs another encoded machine.
4. L4 gives the own-tape trace of the compiled implementation.

Therefore the implementation is a genuine fixed UTM construction, with the
universality component supplied by Minsky’s theorem and the implementation
component checked by the listed traces.

## 5. Honest mechanization boundary

This package is not a proof-assistant artifact. The remaining gaps are:

- no mechanized induction for L3 over all source machines;
- no completed recursive Minsky-input self-run (the 22 KB description makes the
  scanner impractical in the current test budget);
- the encoded self-description of the 23×8 table is represented at the
  description level, not as a completed self-run.

The correct claim is:

> fixed universal table + checked compiler + encoded universal description

not “mechanized UTM proof”.
