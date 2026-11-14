# Native NaN16 source-to-Minsky compiler

## What was built

Two raw NaN16 fixtures now compile an encoded binary-machine description and
then execute the fixed 23x8 table:

- `mth/tests/mth_minsky_compiler_test.nas` is the original two-bit-state,
  fixed-input regression;
- `mth/tests/mth_minsky_compiler_general_test.nas` is the general compiler:
  it reads the state width `p`, an arbitrary finite transition list, and an
  arbitrary finite binary input tape from guest memory.

The compiler does not receive a pre-encoded Minsky tape. Host code only
assembles the guest image and checks the emitted marker string; all tape
construction, table scanning and execution are Native NaN16 instructions.

## Source contract

Source records are stored as five parallel arrays:

```text
q, read, next, write, direction
```

For a machine with `p` state bits:

- `q` and `next` are integers below `2^p`;
- `read`, `write`, and `direction` are one bit;
- direction `1` means right and `0` means left;
- the source tape is a finite binary word followed by `M`, the simulated head
  marker; cells to the right of `M` are blank zeroes.

The emitted Minsky record is

```text
X q(p) read(1) next(p) write(1) direction(1)
```

and the emitted machine condition is

```text
q(p) read(1)
```

Minsky's machine is not restricted to two state bits. The fixed seven-bit
records in the original published example are the `p = 2` instance; `p` may be
larger, as required for the 508-state binary compilation of the 23x8 table
described in `docs/74_TM_TO_BINARY_COMPILER.md`.

## Compiler behavior

The guest program:

1. clears a 256-cell tape window to blank `A` (`2`);
2. writes the source input word, `M`, the eight-cell `t` buffer, `Y`, and the
   `p + 1` condition bits;
3. writes one `X` plus the `2p + 3` instruction bits for every source record;
4. writes the closing `Y` and three trailing zeroes;
5. sets state `5` and the head to the first description `X`, namely
   `128 + p + 11 + input_length` in working-tape coordinates;
6. runs the fixed table to its halt transition;
7. verifies halting, the final head, and the complete final working tape
   against an independently generated expected image.

The general fixture uses `p = 9`, three transitions, input `1101`, and both
left and right simulated-head moves. It exercises 311,366 guest steps and ends
with the expected 94-cell image. The two-bit regression exercises 362,475
guest steps.

```text
python3 tools/run_nan16_fixtures.py --only minsky_compiler
[PASS] minsky_compiler: steps=362475 marker=MTH MINSKY NATIVE PASS

python3 tools/run_nan16_fixtures.py --only minsky_compiler_general
[PASS] minsky_compiler_general: steps=311366 marker=MTH MINSKY NATIVE PASS
```

The compiler was also cross-checked against a host-independent Python table
reference for `p = 3`, `p = 5`, and `p = 9`, with different input words and
transition lists; those generated images are not part of the committed gate.

## What this proves and what it does not

**Executable evidence:** the p-bit encoder, arbitrary finite transition lists,
arbitrary finite binary input, tape layout, fixed table, halting order, and
final tape all execute in raw NaN16 on the canonical core. This removes the
earlier "fixed two-row hand-built tape" limitation.

**Still not mechanized:** the encoder is a native program, not a Coq function
with a complete `decode (encode M) = M` and table-macro proof. The Coq source
model in `formal/utm/MinskySourceEncoding.v` proves a round trip and decoded
interpreter refinement, while `MinskyConcreteEntry.v` proves the first concrete
table macro and entry branch. They do not yet prove a complete table-executed
source instruction or arbitrary-run universality for the 23x8 table.

The next formal step is prescribed in
`docs/85_CONCRETE_UNIVERSALITY_OBLIGATION.md`: connect the encoded source
configuration to one complete table macro, then lift that macro over arbitrary
source runs. Until that is checked, the concrete table's universality remains
open.

## Evidence integration

Both compiler fixtures are in the native fixture set and the publication gate:

```text
make utm-publication
native_minsky_compiler           PASS
native_minsky_compiler_general   PASS
```
