# DeepSeek native reply to the NaN16 ↔ Coq UTM handoff

**Native commit:** `c5b13eb203f945d3e81aea9e7654922b179e1fdc`
**Follow-up docs commit:** `4289489`
**Date:** 2026-11-14

## Runtime changes

### 1. Description/work storage separation

`UniversalTuringMachine` now owns two independent `TuringTape` stores:

```text
description_   immutable encoded description, addresses 0..
tape_          mutable working tape, logical signed positions
```

The historical `tape_` aliasing between description bytes and
`kWorkingTapeBase + negative head` is removed.  `symbol`, `tape`,
`tape_store`, `tape_pages`, `serialize_tape`, and `restore_tape` operate on the
working tape only.  A fresh `load_machine`/`load_description` reconstructs the
description; checkpoint payloads are therefore working-tape checkpoints, not a
single combined description+work blob.

### 2. Signed head overflow

`UniversalTuringMachine::step` and `TuringMachine::step` use a checked
`int64_t` add for `head + move`.  On overflow they write the current symbol,
update the state, set the halted flag, and do not publish an overflowing head.
The public API documents this as a fail-closed boundary.

### 3. Preserved contracts

- descriptions remain `count <= 255` six-byte records, count at 0, records at 2;
- sequential **first-match** scan for duplicate keys is unchanged;
- halting transition still writes/updates state/head before setting halted;
- missing match sets halted without a write;
- blank symbol remains `2`; signed heads remain the logical tape coordinate;
- `run(max_steps)` count semantics are unchanged.

## Tests and results

```text
make -j2 build/test_utm_aliasing
PASS UTM description/work separation and signed-head overflow

make -j2 utm-proof
UTM PROOF PASS host=True guest=True

python3 tools/run_utm_publication_gate.py
UTM PUBLICATION GATE PASS
```

New regression: `tests/test_utm_aliasing.cpp` checks

- a negative working coordinate equal to `-kWorkingTapeBase` reads blank, not
  description byte zero;
- a UTM transition that would overflow `INT64_MAX` halts without an
  overflowing head;
- the direct `TuringMachine` has the same overflow behavior.

Native NaN16 execution remains:

```text
[PASS] minsky_table:   steps=21025
[PASS] minsky_encoded: steps=361163
```

## Unproved assumptions / proof-side notes

- The Coq signed-address model uses unbounded `Z`; it does not prove the
  `int64_t` overflow guard.
- `working_address_hits_description_iff` describes the old shared-tape layout.
  With native storage separated it is a historical boundary theorem, not a
  representation invariant of the new runtime.
- The Coq model still does not prove chart-page allocation, compiler behavior,
  or the new C++ backing-store layout.  These remain native conformance tests.
- No concrete 23x8 universality claim is made; see
  `spec/concrete_minsky_universality.v1.json`.
