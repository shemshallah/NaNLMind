# Mechanized UTM equivalence

## 1. What is checked

`formal/utm/UTMEquivalence.v` is checked against the Coq Library of
Undecidability Proofs (`coq-8.20`, commit
`70dfc56f33a6e4835281044e68aa68279989047e`).  The library constructs a fixed,
single-tape, binary Turing machine:

```text
Krivine machine
  -> 5-register Minsky machine
  -> multi-tape Turing machine
  -> single-tape Turing machine
  -> binary single-tape Turing machine
```

The local theorem is:

```coq
Theorem UTM_halting_equivalence :
  exists encode : { t : L.term | Lambda.closed t } ->
                  tape (finType_CS bool),
    forall x,
      KrivineMclosed_HALT x <-> HaltUTM (encode x).
```

The machine `UTM` is fixed.  It is not selected per input.  The encoding is the
computable witness constructed by the certified reduction chain
(Krivine -> 5-register Minsky -> multi-tape TM -> single-tape TM -> binary TM).
The theorem is closed under the Coq kernel: `Print Assumptions` reports
`Closed under the global context`.

A second, self-contained file checks the step-level interpreter core:

```coq
Theorem utm_run_refines :
  forall fuel d delta c,
    graph_ok d delta ->
    utm_run fuel d c = ref_run fuel delta c.
```

This is the scanner/step refinement for a description that is a graph of an
independent reference transition function, plus a concrete binary-increment
corollary (`bin_run_refines`).

## Minsky 23x8 table

`formal/utm/MinskyTableData.v` is generated from the canonical
`tests/minsky_table.inc` and contains all 184 entries.  `formal/utm/MinskyTable.v`
gives that table a two-list tape zipper and a finite step function, then checks:

```coq
minsky_table_complete        (* every q<23, s<8 has an entry *)
minsky_step_uses_entry       (* every step is the table entry at (q, read) *)
minsky_halt_entry            (* the published halt entry is explicit *)
step_indexed_scan_agree      (* indexed lookup == literal linear scan *)
minsky_trace_100             (* kernel computation of the 100-step trace *)
minsky_trace_100_scan        (* same trace through the scan interpreter *)
minsky_trace_100_indexed_scan(* indexed and scan executions agree end-to-end *)
run_indexed_scan_agree       (* generic run lift under a state/read invariant *)
minsky_trace_head            (* state 2, head 38, final 73-cell tape *)
```

The Coq step follows the C++ `TuringMachine::step` order exactly: on a
halting entry it writes the final symbol, updates state/head, and only then sets
the halted flag.  The earlier model returned `None` before applying the halting
write/move; that semantic mismatch is fixed.  `find_entry_scan_valid` and `step_indexed_scan_agree` prove the row-major
indexed lookup and a literal linear scan agree for every valid state/symbol
pair and every valid configuration.  `run_indexed_scan_agree` lifts that
agreement to complete runs under the explicit invariant that every iterated
configuration has an in-range state and current symbol; the published
100-step execution is also checked directly by kernel computation.

The table transcription is also audited against the C++ source:

```sh
python3 formal/utm/check_minsky_table.py
# MINSKY TABLE TRANSCRIPTION PASS (184/184 entries)
```

The file also exports `UTM_halting_undecidable`, and ends with
`Print Assumptions`, so the CI log shows the theorem is closed under the global
context (no axioms, parameters, or admits introduced by this file).

## 2. Run it

Local (Coq 8.20 required):

```sh
make mechanized-utm
```

Remote / long-running:

```sh
gh workflow run mechanized-utm.yml -R shemshallah/NaNLMind
gh run watch -R shemshallah/NaNLMind
```

The NaNLMind workflow uses the `coqorg/coq:8.20` container, builds only the
fixed-UTM dependency cone, checks `UTMEquivalence.v`, the step-level
`InterpreterRefinement.v`, and the Minsky table, runs `coqchk`, and uploads the
`.vo`/`.glob` artifacts.  It is intentionally separate from the fast NaN0S TM
gate and can run for hours without blocking development.

Checked run:

```text
https://github.com/shemshallah/NaNLMind/actions/runs/43573059226
NANLM MECHANIZED UTM + MINSKY PASS
Closed under the global context
```

Artifacts are mirrored under `state/benchmarks/mechanized_utm/` (runtime
artifact, ignored by git).

## 3. Honest boundary

This is a **halting equivalence** for the fixed binary UTM, mechanized through a
universal model of computation.  It is stronger than the earlier checked-trace
harness because the theorem is closed under Coq's kernel.

It is not yet:

- a mechanized refinement of the C++ source itself: the Coq scan model and the
  table data are checked against `tests/minsky_table.inc`, and the Coq step now
  follows the C++ halting order, but the C++ `TuringMachine::step`
  implementation is not extracted from or linked to Coq;
- a full universality proof for arbitrary encoded machines through the 23x8
  table (the 100-step published trace is checked, not every input);
- a proof-assistant statement about the NaN16 guest machine.

Those remain separate refinement obligations.  Do not describe this result as
a mechanized refinement of the chart runtime until that connection is checked.
