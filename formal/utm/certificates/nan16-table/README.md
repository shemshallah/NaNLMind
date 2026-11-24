# Coq 23x8 table ↔ native NaN16 table image

This is **Layer 1** of a Coq ↔ NaN0S certificate. It is a real, axiom-free
kernel certificate for the table data and the native word-image step/run
semantics. It is **not** yet a certificate for the `.nas` program running on
the NaN0S VM.

## What is proved

`formal/utm/MinskyNaN16Words.v` proves, with `coqchk` and no axioms:

```text
nan16_lookup_agrees_all
  forall q s, nan16_lookup q s = scan_table q s

nan16_sixbyte_lookup_agree
  forall q s, nan16_lookup q s = chart_scan q s

nan16_address_step_refines
  forall c, nan16_address_step c = chart_scan_address_step c

nan16_address_run_refines
  forall fuel c,
    address_run fuel nan16_address_step c =
    address_run fuel chart_scan_address_step c

nan16_zipper_run_bisim
  forall fuel zip addr,
    config_bisim zip addr ->
    config_bisim (run fuel zip)
      (address_run fuel nan16_address_step addr)
```

The native eight-word table image is the exact `table:` block in
`mth/tests/mth_minsky_test.nas` and `mth_minsky_encoded_test.nas`:

```text
from, read, write, move+1, to, halt, 0, 0
```

`nan16_lookup_agrees_all` says its first-match lookup is the Coq 23×8 table
lookup for **every** state/symbol pair.

## What is checked by transcription gates

- `check_minsky_table.out`: the Coq table data matches
  `tests/minsky_table.inc` (184/184).
- `check_minsky_nan16_words.out`: the literal `.nas` `table:` blocks match
  `tests/minsky_table.inc` (184/184, both fixtures).

These are source-transcription checks, not Coq proofs of the `.nas` text.

## Raw certificate

```text
$ cat nan16_words.assumptions.txt
===== nan16_lookup_agrees_all =====
Closed under the global context
===== nan16_sixbyte_lookup_agree =====
Closed under the global context
===== nan16_address_step_refines =====
Closed under the global context
===== nan16_address_run_refines =====
Closed under the global context
===== nan16_zipper_run_bisim =====
Closed under the global context
```

```text
$ tail -18 nan16_words.coqchk.summary.txt
  checking cst:NaNLM.MinskyNaN16Words.nan16_address_run_refines
  checking cst:NaNLM.MinskyNaN16Words.nan16_zipper_run_bisim
Modules were successfully checked

CONTEXT SUMMARY
===============

* Theory: Set is predicative
  
* Theory: Rewrite rules are not allowed
  
* Axioms: <none>
  
* Constants/Inductives relying on type-in-type: <none>
  
* Constants/Inductives relying on unsafe (co)fixpoints: <none>
  
* Inductives whose positivity is assumed: <none>
```

## Anchor hashes

```text
174e5dd171446d6dd14f7523eaf39226853882fa1acd36e4a8b14d366c0d603f  MinskyNaN16Words.v
e05dae6edb8425e77b8602f686ae13bdd4e270aab9136215346a72982b5dd0aa  MinskyNaN16Words.vo
860bed5f3caac430a903668265da62e1d0e3f6685ca0baba7a44a4348bb1199b  nan16_words.statement.txt
03683dd47be8a889f30b1de43a1ced7315a8122c9bbfb7a7e51cce9e9de1d801  nan16_words.assumptions.txt
0dbba4a6301125812fc19969e8fa60382c5ccef39669b66f8ca85ea0b5a7c5b6  nan16_words.coqchk.txt.gz
```

## What is still missing for Coq ↔ NaN0S

The native fixture does not just contain a table; it contains a NaN16 program:

```text
step:
  scan the 184 eight-word rows, match (state, read),
  write tape[head], move head, update state, set halt

run100:
  call step 100 times

main:
  initialize, run100, check state/head/tape, print PASS
```

A full Coq table ↔ NaN0S certificate needs:

1. **NaN16 ISA semantics** for the instruction subset used by
   `mth_minsky_test.nas` (`MOVI`, `LD`, `ST`, `CMP`, `JMP`, `CALL`, `RET`,
   `ADD`, `SUB`, `SHL`, `HALT`, predicates).
2. **A program refinement proof** that `step` implements
   `nan16_address_step` and `run100` implements `address_run 100`.
3. **A link from the `.nas` text to the Coq instruction list** (verified
   assembler or a checked transcription gate).
4. Optionally, a refinement of `third_party/nan0s/core/nan16.c` or a
   documented trusted-ISA boundary.

Layer 1 is the table/word-image half. Layer 2 is the VM/program half; it is
not yet formalized. Executable NaN0S gates are conformance evidence, not a
Coq certificate.

## Layer 2 status (in progress)

`formal/utm/MinskyNaN16VM.v` now defines the NaN16 ISA subset used by
`mth_minsky_test.nas` (registers, memory, flags, predicates, `MOVI`/`LD`/`ST`/
`CMP`/`JMP`/`CALL`/`RET`/`ADD`/`SUB`/`SHL`/`HALT`), the exact native scan block,
the `scan_ready` loop invariant, the table-memory invariant, and the
`run_until` composition lemmas.  It passes `coqc` and `coqchk`.

It does **not** yet contain `scan_iter_hit`/`scan_iter_miss`, the scan-loop
induction, the `step` action refinement, or the `run100` refinement.  The
current engineering blocker is the symbolic execution of the 12-instruction
scan iteration: `cbn` leaves the `run_until` stop checks under nested
`exec_instr`s, while a full `vm_compute` is too expensive for the general
symbolic state.  The next step is a small-step `run_one`/`exec` rewrite
strategy that reduces each concrete PC check before the symbolic branch.

Do not cite this as a Coq table ↔ NaN0S VM certificate yet.
