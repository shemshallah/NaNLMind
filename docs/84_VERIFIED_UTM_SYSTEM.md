# A verified fixed UTM with a mechanized Minsky table and native execution evidence

## Abstract

This package combines four independently checkable layers around a fixed,
binary, single-tape universal Turing machine:

1. a Coq-checked fixed-UTM halting equivalence for a universal model of
   computation;
2. a mechanized 23-state/8-symbol Minsky table, derived from the concrete table
   used by the executable runtime;
3. a signed-address refinement of the table interpreter, proved equivalent to
   the zipper model for arbitrary fuel-bounded runs;
4. independent executable evidence: a native NaN16 100-step Minsky run, an
   exhaustive 184-entry C++ chart-conformance test, and a step-by-step C++ trace
   check.

The result is a **checked construction plus executable evidence**, not a claim
of a mechanized universality theorem for the concrete 23x8 table.  The exact
scope and remaining obligations are listed below.

## Contributions

### 1. Fixed binary UTM

`formal/utm/UTMEquivalence.v` composes the pinned Coq Undecidability Library's
certified chain:

```text
Krivine -> 5-register Minsky -> multi-tape TM -> single-tape TM -> binary TM
```

and exposes:

```coq
Theorem UTM_halting_equivalence :
  exists encode : { t : L.term | Lambda.closed t } ->
                  tape (finType_CS bool),
    forall x, KrivineMclosed_HALT x <-> HaltUTM (encode x).
```

`Print Assumptions` reports **Closed under the global context**.  The theorem
is about the library's fixed binary machine; it is not automatically a theorem
about the concrete 23x8 table.

### 2. Concrete Minsky table

`formal/utm/MinskyTableData.v` contains all 184 entries generated from
`tests/minsky_table.inc`; `check_minsky_table.py` compares them entry-for-entry.

`formal/utm/MinskyTable.v` proves:

- completeness for every `q < 23`, `s < 8`;
- indexed lookup equals literal linear scan for **all** state/symbol pairs
  (`find_entry_scan_all`);
- step equality for all configurations (`step_indexed_scan_agree_all`);
- complete-run equality for every fuel-bounded run
  (`run_indexed_scan_agree_all`);
- the C++ halt order: write, update state/head, then set halted
  (`minsky_halt_updates_before_flag`);
- the native C++ description/work storage separation and signed-head
  overflow fail-closed behavior (`test_utm_aliasing`);
- the published 100-step zipper execution (`minsky_trace_100`).

### 3. Signed-address refinement

`formal/utm/MinskyAddressRefinement.v` models the C++ address tape
`Z -> nat` with a signed head and observable halted flag.  It proves:

```text
zipper_address_step_bisim      one-step bisimulation
zipper_address_run_bisim       arbitrary finite-run bisimulation
address_halt_writes_before_flag
address_trace_100              published trace in address space
```

The representation invariant relates **every** cell of the zipper tape to a
signed address, not only visited cells.  `embed_config` constructs the
address representation for any zipper and head coordinate.

### 4. Executable evidence

```text
native NaN16 Minsky fixture:
  [PASS] minsky_table: steps=21025 marker=MTH MINSKY NATIVE PASS
  [PASS] minsky_encoded: steps=361163 marker=MTH MINSKY NATIVE PASS
  [PASS] minsky_compiler: steps=362475 marker=MTH MINSKY NATIVE PASS
  [PASS] minsky_compiler_general: steps=311366 marker=MTH MINSKY NATIVE PASS

C++ runtime trace:
  MINSKY C++ TRACE CONFORMANCE PASS (100/100 steps)

C++ exhaustive chart transitions:
  PASS Minsky chart refinement: 184 entries, halting, malformed and negative tape

Coq generalized compiler trace:
  wide_fixture_halts_at_step_1979
  wide_fixture_running_at_step_1978
```

The native fixtures are `mth/tests/mth_minsky_test.nas` (published trace) and
`mth/tests/mth_minsky_encoded_test.nas` (normal encoded binary machine), and
`mth/tests/mth_minsky_compiler_test.nas` (two-bit source-to-tape encoder), and
`mth/tests/mth_minsky_compiler_general_test.nas` (p-bit, arbitrary transition
list and binary input tape), assembled and executed
by the canonical NaN0S toolchain.  It contains the table, tape, transition
scan, halt ordering and final 73-cell verification in raw NaN16.

## Reproduce

```sh
make utm-publication
```

The gate runs the native Minsky fixture, C++ trace conformance, exhaustive C++
chart conformance, and host UTM/NaN0S proof gate, and writes
`state/benchmarks/utm_publication_gate.json`.

The Coq CI job is:

```sh
gh workflow run mechanized-utm.yml -R shemshallah/NaNLMind
```

Checked run:

```text
https://github.com/shemshallah/NaNLMind/actions/runs/43663329325
NANLM MECHANIZED UTM + MINSKY ADDRESS REFINEMENT PASS

Generalized p=9 compiler trace:
https://github.com/shemshallah/NaNLMind/actions/runs/43663330215
NANLM GENERALIZED P-BIT MINSKY FIXTURE TRACE PASS
Closed under the global context
```

## Evidence table

| Layer | Evidence | Status |
|---|---|---|
| Fixed UTM | Coq halting equivalence; `Print Assumptions` closed | pass |
| Minsky table | 184/184 Coq transcription audit | pass |
| Indexed/scan | Coq equality for all state/symbol pairs and runs | pass |
| Halt order | Coq write/state/head-before-flag theorem | pass |
| Signed address | Coq zipper/address bisimulation for all finite runs | pass |
| Published trace | Coq kernel computation in both representations | pass |
| Native NaN16 | published trace and normal encoded-machine execution | pass |
| C++ alias/overflow | negative-head and INT64 boundary tests | pass |
| C++ trace | 100/100 step conformance | pass |
| C++ chart | all 184 entries, malformed/negative/repeated-halt cases | pass |

## What is not claimed

- **No full universality proof for the concrete 23x8 table.**  The table is
  checked against its source and its published trace, but no theorem says it
  simulates every encoded machine.
- **No formal refinement of the compiled C++ binary.**  The C++ test is an
  exhaustive executable conformance test, not a compiler-verification result.
- **No chart allocator or page-layout refinement.**  Signed-address semantics
  are a model of the runtime's address behavior, not the allocator.
- **No claim that the library's fixed UTM is the concrete 23x8 machine.**  They
  are separate formal objects.

## Publication strategy

The strongest honest framing is a formal-methods / verified-computation paper:

> A checked fixed-UTM construction and a mechanized, address-refined universal
> Minsky table, with native and C++ execution evidence.

Suitable venues include CPP, ITP/Rocq, CAV, or the Journal of Automated
Reasoning.  A Nature-style venue would require an independently reviewed
scientific claim and, most importantly, the missing universality theorem for
the concrete table or a formal compiler/refinement link.  The package should
not be submitted as a "proved UTM" claim until one of those is closed.

## Next theorem

The decisive next step is a **mechanized universality theorem for the concrete
23x8 table**: define an encoding of arbitrary finite machines into its tape
format, prove the decode/encode round trip, and prove the table's run simulates
the encoded machine step-for-step.  The existing fixed-UTM composition and the
23x8 table are currently separate; a compiler from the library's encoded
machines to the Minsky tape format would connect them.
