# Native NaN16 source-to-Minsky compiler

## What was built

`mth/tests/mth_minsky_compiler_test.nas` is a raw NaN16 encoder.  It does not
receive a pre-encoded Minsky tape.  It receives a compact binary-machine
description and emits the tape format consumed by the fixed 23x8 table.

Source records are stored in guest memory as five parallel arrays:

```text
q, read, next, write, direction
```

For this first compiler contract:

- `q` and `next` are 2-bit state numbers;
- `read` and `write` are one-bit symbols;
- `direction` is one bit;
- the encoded transition is `X` followed by seven bits
  `q(2) read(1) next(2) write(1) direction(1)`.

The machine used by the gate is:

```text
q0, 0 -> q1, write 1, right
q1, 0 -> q2, write 1, right
q2 is undefined (halt)
```

## Encoder behavior

The guest program:

1. clears a 256-cell tape window to blank `A` (`2`);
2. writes the fixed preamble
   `000000 M 00000000 Y 000`;
3. writes one `X` plus seven bits for every source transition;
4. writes the closing `Y` and three trailing zeros;
5. sets state `5` and head `147` (logical position 19);
6. runs the fixed Minsky table to halt;
7. verifies halting, head `163` (logical 35), and the 39-cell final tape.

Result:

```text
python3 tools/run_nan16_fixtures.py --only minsky_compiler
[PASS] minsky_compiler: steps=362475 marker=MTH MINSKY NATIVE PASS
```

The final tape is:

```text
00000011M000000Y1AAXAAAABBBXA101011Y000
```

## What this proves and what it does not

**Executable evidence:** the encoder, tape layout, fixed table, halting order,
and final tape all execute in raw NaN16 on the canonical core.

**Not yet proved:** the encoder is a concrete guest program, not a Coq
function with an encoder/decoder round-trip theorem.  The source format is a
restricted 4-state/2-symbol contract with a fixed input window; it is not yet
a general finite-machine compiler.  In particular this does **not** establish
the concrete-table universality theorem.

The next formal step is to mirror this encoder as a Coq function, prove
`decode (encode M) = M` for the full source alphabet, and prove one-step
simulation of the emitted tape.  The native encoder is the executable reference
for that proof.

## Evidence integration

The compiler is part of the native fixture set and the publication gate:

```text
make utm-publication
native_minsky_compiler  PASS
```
