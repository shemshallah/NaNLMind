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

## Layer 2 progress after the scaffold

`MinskyNaN16VM.v` now also contains the explicit small-step reductions:

```text
run_one_false
exec_instr_pc
exec_instr_CMP_zf
exec_instr_CMP_lf
exec_instr_not_halted
```

These are the pieces needed to execute the 12-instruction scan iteration
without a monolithic `vm_compute`.  The next proof is the 5-step scan prefix
(`pc 0 -> 5`, `r7 = start + 8*i`, `r9 = m (start + 8*i)`), then the hit/miss
iteration lemmas and the scan-loop induction.  The full `step`/`run100`
refinement and the VM-level certificate are still open.

## Layer 2 progress: computed five-step prefix

`MinskyNaN16VM.v` now also proves:

```coq
scan_prefix5_never_pc :
  forall i state sym start m,
    i < 184 ->
    vm_pc (run_until 5 scan_block never_stop
      (scan_init i state sym start m)) = 5.
```

This is a fully computed prefix of the native scan block (CMP, JMP, SHL, ADD,
LD) with the two initial branch conditions resolved.  The next proof is the
same prefix with the real `scan_stop`, then the hit/miss iteration and the
184-row induction.  The full `step`/`run100` and VM-level certificate are still
open.

## Layer 2 progress: real five-step prefix

`MinskyNaN16VM.v` now proves the prefix with the real `scan_stop`:

```coq
scan_prefix5_stop_pc :
  i < 184 ->
  vm_pc (run_until 5 scan_block scan_stop (scan_init i state sym start m)) = 5

scan_prefix5_stop_vm :
  vm_pc ... = 5 /\
  vm_reg ... 7 = start + 8*i /\
  vm_reg ... 9 = m (start + 8*i) /\
  vm_reg ... 1 = state /\
  vm_reg ... 4 = sym /\
  vm_reg ... 8 = i /\
  vm_mem ... = m /\
  vm_halted ... = false
```

The next step is to expose the prefix VM to the outer 7-step hit suffix
(`pc 5 -> 14`) and then the miss suffix (`pc 5 -> 0`).  The full
`step`/`run100` and VM-level certificate are still open.

## Layer 2 progress: hit-suffix projections

`MinskyNaN16VM.v` now has the step projections for the outer hit suffix:

```text
scan_pc_after_5 .. scan_pc_after_10
scan_zf_after_5 / scan_lf_after_5
scan_zf_after_8 / scan_lf_after_8
scan_reg9_after_7
```

These cover `pc 5 -> 14`: `CMP r9,r1`, `JMP[NE]`, `LD r9,r7,1`,
`CMP r9,r4`, `JMP[NE]`, `JMP 14`.  The next lemma is the 7-step
`scan_hit_suffix` using `run_one_false` plus these projections.  The full
`step`/`run100` and VM-level certificate are still open.

## Layer 2: hit suffix proved

`MinskyNaN16VM.v` now contains the complete hit suffix:

```coq
scan_hit_suffix :
  vm_pc vm = 5 ->
  vm_reg vm 7 = start + 8*i ->
  vm_reg vm 9 = m (start + 8*i) ->
  vm_reg vm 1 = state ->
  vm_reg vm 4 = sym ->
  vm_mem vm = m ->
  vm_halted vm = false ->
  table_mem_at (start + 8*i) (row::rest) m ->
  0 < length row -> 1 < length row ->
  nth 0 row 0 = state ->
  nth 1 row 0 = sym ->
  vm_pc (run_until 7 scan_block scan_stop vm) = 14.
```

This is the full `CMP -> JMP[NE] -> LD -> CMP -> JMP[NE] -> JMP 14`
path, with the memory/register projections for every step.  Next is the
miss suffix (`pc 5 -> 0`) and the generic `scan_ready` prefix, then the
184-row scan induction and the action/`run100` phases.

## Layer 2: first miss path proved

`MinskyNaN16VM.v` now proves `scan_miss_from`: when the row's `from`
field does not match the source state, the native scan runs

```text
pc 5 CMP r9,r1
pc 6 JMP[NE] 11
pc 11 ADD r8,r8,1
pc 12 JMP 0
```

and returns a VM satisfying `scan_ready (S i) state sym start m` at
`pc=0`, with `r8=i+1`.  The register/memory preservation lemmas for the
miss path are included.

Next: the second miss path (`from` matches, `read` does not), then the
generic `scan_ready` prefix, the 184-row induction, the action phase,
and `run100`.

## Layer 2: both miss paths proved

`MinskyNaN16VM.v` now proves:

```text
scan_miss_from   (* row.from <> state: pc 5 -> 11 -> 12 -> 0 *)
scan_miss_read   (* row.from = state, row.read <> sym:
                    pc 5 -> 6 -> 7 -> 8 -> 9 -> 11 -> 12 -> 0 *)
```

Both return a VM satisfying `scan_ready (S i) state sym start m` at
`pc=0`, with `r8=i+1`.  The hit suffix, both miss paths, all step
projections, and the register/memory preservation lemmas are now checked.

Next: the generic `scan_ready` five-step prefix, the 184-row scan
induction, the action phase, and `run100`.

## Layer 2: the full scan iteration is proved

`MinskyNaN16VM.v` now contains the generic five-step prefix and the
three complete iteration outcomes:

```text
scan_prefix5_ready      (* scan_ready vm -> vm5 projections *)
scan_iter_hit           (* 12 steps -> pc 14 *)
scan_iter_miss_from     (* 9 steps -> scan_ready at i+1 *)
scan_iter_miss_read     (* 12 steps -> scan_ready at i+1 *)
```

The hit and both miss paths are composed from the checked step
projections.  This is the complete control flow of one scan iteration.
Next: the 184-row loop induction (`scan_none_at_end` + monotone fuel),
then the action phase, `step`, `run100`, and the transcription gate.

## Layer 2: scan end and fuel extension

`MinskyNaN16VM.v` now also proves:

```text
scan_none_at_end          (* r8 = 184 -> pc 13 in two steps *)
run_until_extend_stopped  (* extra fuel after a stop is harmless *)
```

The complete scan block now has:
- the generic five-step prefix,
- the hit iteration,
- both miss iterations,
- the no-match end.

The remaining scan proof is the 184-row loop induction, which composes
these with `run_until_extend_stopped`.  Then the action phase, `step`,
`run100`, and the transcription gate.

## Layer 2: the 184-row scan loop is certified

`formal/utm/MinskyNaN16ScanLoop.v` now proves, with `coqc` and `coqchk`:

```coq
scan_loop :
  i + length table = 184 ->
  Forall (fun row => 0 < length row /\ 1 < length row) table ->
  table_mem_at (start + 8*i) table m ->
  scan_ready vm i state sym start m ->
  exists vm',
    run_until (12*length table + 14) scan_block scan_stop vm = vm' /\
    match scan_index_from i state sym table with
    | Some (j,row) =>
        vm_pc vm' = 14 /\ vm_reg vm' 7 = start + 8*j /\ vm_reg vm' 8 = j
    | None => vm_pc vm' = 13 /\ vm_reg vm' 8 = 184
    end.
```

The GitHub dedicated runner passed:

```text
run 45461981748  success
```

A separate local `coqc -time` trace showed the proof now checks in under a
second after replacing a whole-goal `simpl` with a local
`scan_index_from` equality.

## Layer 2: action phase started

`formal/utm/MinskyNaN16Action.v` models the `.nas` `match:` block:

```text
LD r9,r7,2 ; ST r9,r3,0       (* write *)
LD r9,r7,3 ; move decision    (* -1 / 0 / +1 *)
ST r2,r0,@head
LD r9,r7,4 ; ST r9,r0,@state
LD r9,r7,5 ; halt decision ; ST r9,r0,@halt
RET
```

with a concrete `vm_compute` smoke test for the write/right/halt path.  The
action refinement theorem, `step` setup/halt check, `run100`, and the
`.nas` transcription gate remain open.

## Layer 2: action specification certified

The dedicated runner passed:

```text
run 45463919006  success
```

for:

```text
MinskyNaN16Action.v
  action_block / action_stop / action_init
  row_at / set_mem / action_ready
  action_new_head / action_run
  concrete action smoke test
```

The next theorem is `action_refines`: execute the 24-instruction
`action_block` symbolically and prove it realizes `action_run` (moved
head, written tape cell, stored head/state/halt cells).

## Layer 2: action prefix proof (in progress)

`formal/utm/MinskyNaN16ActionPrefix.v` proves the common five-step action
prefix:

```text
pc 0 LD r9,r7,2      (* write symbol *)
pc 1 ST r9,r3,0      (* tape[head] := write *)
pc 2 LD r9,r7,3      (* move+1 *)
pc 3 MOVI r10,0
pc 4 CMP r9,r10      (* move decision flags *)
```

using `row_at`, `set_mem`, and the one-step action preservation lemmas:

```text
action_reg_preserved_ST/CMP/JMP/LD/MOVI/SUB/ADD
action_mem_preserved_LD/MOVI/CMP/JMP/SUB/ADD
```

The dedicated runner is checking the prefix module.  The next steps are the
pc5 move branch, the common pc14..22 suffix, full `action_refines`,
`step_refines`, `run100`, and the `.nas` transcription gate.

## Layer 2: action block pieces checked

Checked pieces:

```text
MinskyNaN16Action.v
  action_block / action_run / set_mem / row_at
  action_exec_pc / CMP flags / data-path projections
  action_reg_preserved_* / action_mem_preserved_*
  row_at_set_mem_neq

MinskyNaN16ActionPrefix.v
  action_prefix5  (pc0 -> pc5, write/tape/move field)

MinskyNaN16ActionMove.v
  action_move_zero / action_move_right / action_move_other / action_move
  (pc5 -> pc14, head-1 / head+1 / head)

MinskyNaN16ActionSuffix.v
  action_suffix_prefix  (pc14 -> pc19)
  action_suffix         (pc14 -> pc22, both halt branches)
```

The action composition is now closed locally:

```text
MinskyNaN16ActionRefines.v
  action_refines (pc 0 -> 22, exact move fuel, pointwise action_run memory)
```

`Print Assumptions action_refines` is closed under the global context.

## Layer 2: scan frame and step phases checked

```text
MinskyNaN16ScanFrame.v
  scan_exec/run frame for r0, r2, r3, r13, memory, halted

MinskyNaN16ScanPhase.v
  scan_phase (scan loop + frame conditions + hit/no-match exits)

MinskyNaN16Lookup.v
  nan16_rows = map encode_nan16_words minsky_entries
  scan_index_from hit -> nan16_lookup hit (and the None direction)

MinskyNaN16StepHit.v
  step_hit_phase (scan -> action -> pc 22, memory = action_run)

MinskyNaN16StepNone.v
  no_trans_block / no_trans_run
  step_none_phase (scan -> halt cell := 1, pc 2)
```

Both phase theorems are closed under the global context.

The step entry is now partly assembled:

```text
MinskyNaN16Step.v
  native_step / native_step_refines (hit and no-match branches)

MinskyNaN16Prelude.v
  literal prelude_block, LD/ADD/MOVI/CMP projections, frame lemmas

MinskyNaN16PreludeReady.v
  prelude_ready  (halt cell 0 -> loaded scan registers, pc 11)
  prelude_halted (halt cell nonzero -> return point, pc 11)

MinskyNaN16ActionRun.v
  action_run head/tape/state/head-cell/halt-cell/frame projections

MinskyNaN16StepSpec.v
  NState / vm_to_nstate / nstep / nstate_rel
  native_step_spec_active (native_step refines nstep pointwise)
```

`Print Assumptions prelude_ready`, `prelude_halted`,
`native_step_spec_active`, and `action_run_frame` are closed under the
global context.  A step-entry composition (`MinskyNaN16StepEntrySpec.v`)
is WIP: the local proot runs out of memory on the large composed goal, so
it is not part of the checked chain.

Remaining for the `.nas` step/run100 certificate:

1. a literal `step` program/prelude assembly (or checked block transcription)
   tying the scan/action/no-trans phases to the `.nas` text;
2. `run100` iteration of the step routine;
3. the source address/tape refinement connecting the VM state to
   `nan16_address_step`/`MinskyTable.step`;
4. the checked `.nas` transcription gate and the final VM-level certificate.
