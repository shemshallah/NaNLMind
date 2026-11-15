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
left and right simulated-head moves. A source-level coverage audit found that
the original fixture's first record was `(q0, read 1)` while the initial
condition was `(q0, read 0)`: it halted without executing a source instruction.
The fixture has been corrected to an initial `(q0, read 1)` condition; its three
source-level instructions now form a reachable right/left/left chain. An
independent Python execution of the unchanged 23x8 table takes 9,277 native
microsteps to halt and reproduces the updated 94-cell expected image. The
updated NaN16 guest takes 3,521,560 steps in the independent CI run; the earlier 311,366
guest-step count applied to the vacuous version. The two-bit regression
exercises 362,475 guest steps.

```text
python3 tools/run_nan16_fixtures.py --only minsky_compiler
[PASS] minsky_compiler: steps=362475 marker=MTH MINSKY NATIVE PASS

python3 tools/run_nan16_fixtures.py --only minsky_compiler_general
[PASS] minsky_compiler_general: steps=3521560 marker=MTH MINSKY NATIVE PASS

python3 formal/utm/check_minsky_source_execution.py \
  --require-steps 3 --require-both-directions --check-native-expected \
  --audit-naive-gap-decoder
# PASS: three reachable source instructions; independent 23x8 table result checked
```

The compiler was also cross-checked against a host-independent Python table
reference for `p = 3`, `p = 5`, and `p = 9`, with different input words and
transition lists.  A committed `p = 16` fixture
(`mth_minsky_compiler_p16_test.nas`) exercises a 16-bit condition and 35-bit
source records, with 4,318,871 guest steps.

### Kernel-checked p=9 trace

`formal/utm/MinskyWideFixture.v` contains the exact initial and final 94-cell
images for the committed `p = 9`, three-transition, input-`1101` fixture.  It
proves with the literal `MinskyTable.run` semantics that the fixed table
reaches the halting configuration in 9277 transitions (the last transition is
the terminal write/state update) and is not halted at 9276.  This is a
`coqchk`-checked finite trace of the generalized compiler path, not a theorem
about every compiler output.  CI job `wide-fixture.yml` first cross-checks the Coq final image against the
native fixture's expected array, then checks the trace remotely.

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
source instruction or arbitrary-run universality for the 23x8 table. The new
non-vacuity gate establishes reachability in the independent source interpreter
and a matching finite native expected-image regression, **not** an equivalence
between the two complete tape representations; the latter still requires a
formal decoder and step-commutation theorem.

The diagnostic also supplies a negative control for a *naive* decoder that
identifies the physical `M` marker with a literal gap in the ordinary source
tape. A one-instruction write-1/left case gives a different physical right-of-M
suffix from such a decoder. This does **not** disprove universality, but it
means the required concrete-to-source tape representation must account for
the interpreter's buffer/marker encoding instead of assuming a trivial gap.

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
native_minsky_compiler_p16       PASS
```
