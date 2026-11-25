# Coq 23x8 table ↔ native NaN16 table image

**Final status (2026-11-24).** Layer 2 is closed at the Coq VM-model level.
`formal/utm/MinskyNaN16Universality.v` proves the final theorem

```text
nan16_run_halting_equivalence_canonical
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    left_infinite_eventually_halts rows c <->
    exists K t, K >= t /\
      nan16_vm_halted
        (vm_run t
          (nan16_vm_of_addr K (embed_config (lic_native_init rows c K) 0))
          fixture_table fixture_table_base)
```

with `Print Assumptions` closed under the global context and `coqchk`
reporting `Modules were successfully checked`.  The raw VM certificate is
in [`../nan16-vm/`](../nan16-vm/).

This does **not** remove the transcription caveat below: the final theorem
is about the Coq VM model.  Its data-cell constants are now pinned to the
literal `.nas` labels: `tbase` 99, `state` 100, `head` 101, `halt` 102,
`table` 104, with `rlink` 103 reserved and unmodelled.  The theorem still
does not prove the assembled code, instruction encodings, or loader; the
transcription gate compares memory operands symbolically.

This is **Layer 1** of a Coq ↔ NaN0S certificate. It is a real, axiom-free
kernel certificate for the table data and the native word-image step/run
semantics. It is **not** a certificate for the `.nas` program running on
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

Layer 1 is the table/word-image half. Layer 2 is the VM/program half.  The
final Layer 2 theorem is now proved at the Coq VM-model level (see the
status banner at the top and the closing section); it still does not refine
the literal assembled NaN0S image.  Executable NaN0S gates are conformance
evidence, not a Coq certificate.

## Layer 2 history (earlier checkpoint; superseded)

The material below records the proof construction as it stood before the
final theorem.  Statements such as "not yet formalized" are historical and
are superseded by the final status at the top and the closing section.

`formal/utm/MinskyNaN16VM.v` defines the NaN16 ISA subset used by
`mth_minsky_test.nas` (registers, memory, flags, predicates, `MOVI`/`LD`/`ST`/
`CMP`/`JMP`/`CALL`/`RET`/`ADD`/`SUB`/`SHL`/`HALT`), the exact native scan block,
the `scan_ready` loop invariant, the table-memory invariant, and the
`run_until` composition lemmas.  It passes `coqc` and `coqchk`.

At this checkpoint it did **not** yet contain `scan_iter_hit`/`scan_iter_miss`,
the scan-loop induction, the `step` action refinement, or the `run100`
refinement.  The engineering blocker at the time was the symbolic execution
of the 12-instruction scan iteration: `cbn` left the `run_until` stop checks
under nested `exec_instr`s, while a full `vm_compute` was too expensive for
the general symbolic state.  The next step at that checkpoint was a
small-step `run_one`/`exec` rewrite
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

MinskyNaN16StepEntrySpec.v
  restart / step_entry
  step_entry_spec (prelude -> native step, refines nstep)
```

`Print Assumptions prelude_ready`, `prelude_halted`,
`native_step_spec_active`, and `action_run_frame` are closed under the
global context.

The dedicated runner passed compile + `coqchk` for the chain through
`MinskyNaN16StepSpec.v`:

```text
run 45493008714  compile/coqchk success
```

`step_entry_spec` is closed under the global context.  The key engineering
fix was to make `native_step` and `nstep` **opaque** and compose only
through their proved specifications; the previous transparent composition
was the 83-minute reduction blowup.

The signed-tape window encoding is checked locally:

```text
MinskyNaN16Window.v
  win_addr / win_mem / injectivity
  win_mem_addr / win_mem_write / win_mem_write_at
```

It is the start of the `AddressConfig` ↔ flat-memory bridge, not yet a
step refinement.

Remaining for the `.nas` step/run100 certificate:

1. prove the global table/tape separation facts (`table_control_ok`,
   `tape_window_ok`) for the concrete fixture and kernel-check the
   `MinskyNaN16RunClosed.v` chain; the older `vm_run_refines` still has an
   explicit `step_ok` hypothesis;
2. the source address/tape refinement connecting `nstep` to
   `nan16_address_step`/`MinskyTable.step` through the window lemmas;
3. the assembler/ISA link (the Coq `exec_instr` model is a trusted
   boundary, not a refinement of `third_party/nan0s/core/nan16.c`);
4. the final VM-level certificate.  The new
   `check_minsky_nan16_step.py` gate is only a source-text transcription
   check, not a proof of this refinement.

## Layer 2: literal step/run100 transcription gate (scaffolding)

`formal/utm/check_minsky_nan16_step.py` is the source-text gate for the four
Coq mnemonic blocks.  It reads both the literal `.nas` text and the Coq
`Definition ... : list Instr` bodies, applies only the block-relative
normalization listed below, and fails closed on any opcode, predicate,
register, immediate, or symbolic memory-cell change.  It does **not** compile
Coq and does **not** promote Layer 2 to a certificate.

```text
$ python3 formal/utm/check_minsky_nan16_step.py
PASS mth/tests/mth_minsky_test.nas: literal step prelude/scan/action/no_trans order
PASS prelude_block <-> MinskyNaN16Prelude.v: 11/11 instructions
PASS scan_block <-> MinskyNaN16VM.v: 15/15 instructions
PASS action_block <-> MinskyNaN16Action.v: 23/23 instructions
PASS no_trans_block <-> MinskyNaN16StepNone.v: 3/3 instructions
PASS run100: literal 100-iteration CALL @step driver (main sets r13=1 and calls @run100 once)
PASS Coq step_entry/vm_run structure: prelude_block -> native_step, vm_run -> step_entry
PASS vm_run_refines remains conditional on step_ok (no admitted proof in the checked files)
PASS closed-run chain keeps table_control_ok/tape_window_ok explicit (step_ok_of_layout, vm_run_refines_closed, vm_run_refines_window)
PASS theorem prelude_ready (MinskyNaN16PreludeReady.v)
PASS theorem prelude_halted (MinskyNaN16PreludeReady.v)
PASS theorem action_refines (MinskyNaN16ActionRefines.v)
PASS theorem action_run_frame (MinskyNaN16ActionRun.v)
PASS theorem scan_loop (MinskyNaN16ScanLoop.v)
PASS theorem scan_phase (MinskyNaN16ScanPhase.v)
PASS theorem step_hit_phase (MinskyNaN16StepHit.v)
PASS theorem no_trans_run (MinskyNaN16StepNone.v)
PASS theorem step_none_phase (MinskyNaN16StepNone.v)
PASS theorem native_step_refines (MinskyNaN16Step.v)
PASS theorem native_step_spec_active (MinskyNaN16StepSpec.v)
PASS theorem step_entry_spec (MinskyNaN16StepEntrySpec.v)
PASS theorem vm_run_refines (MinskyNaN16Run.v)
PASS theorem step_ok_of_layout (MinskyNaN16StepOk.v)
PASS theorem vm_run_refines_closed (MinskyNaN16RunClosed.v)
PASS theorem vm_run_refines_window (MinskyNaN16RunClosed.v)
NAN16 STEP/RUN100 TRANSCRIPTION PASS (source-text gate only; not a VM refinement certificate)
```

### Block correspondence checked by the gate

| Coq block | Coq file | Literal `.nas` source | Block-relative normalization |
|---|---|---|---|
| `prelude_block` | `MinskyNaN16Prelude.v` | `step:` through `MOVI r8,0` (11 instructions) | `@step_ret` is the standalone prelude exit at pc 11 |
| `scan_block` | `MinskyNaN16VM.v` | `scan:` first 10 instructions plus `next:` (2 instructions) | `@no_trans` -> `scan_none_pc` (13), `@next` -> 11, match fallthrough -> `scan_match_pc` (14); two model `HALT` sentinels are appended |
| `action_block` | `MinskyNaN16Action.v` | `LD r9,r7,2` fallthrough through `step_ret: RET` (22 instructions) | `@mleft` -> 10, `@mright` -> 12, `@mdone` -> 14, `@step_ret` -> 22; one `JMP[ALWAYS] 14` is synthesized for the literal right-branch fallthrough into `mdone` |
| `no_trans_block` | `MinskyNaN16StepNone.v` | `no_trans:` through `RET` (3 instructions) | none |

Memory operands are compared symbolically, not by assembled address:

```text
@head  <-> action_head_addr
@state <-> action_state_addr
@halt  <-> action_halt_addr
@tbase <-> tape_base_addr
@table <-> table_base
```

The Coq constants `action_head_addr = 101`, `action_state_addr = 100`,
`action_halt_addr = 102`, `tape_base_addr = 99`, and
`fixture_table_base = 104` are pinned to the literal `.nas` data labels;
`rlink` 103 is reserved and unmodelled.  The gate still does not check
instruction encoding or the assembled/loaded image.

`run100` is checked as a literal driver shape: save `r15` in `@rlink`,
`MOVI r11,100`, `CALL @step`, `SUB r11,r11,r13`, `JMP[NE] @rloop`, restore
`r15`, `RET`; `main` sets `r13=1` and calls `@run100` exactly once.  The Coq
side is checked structurally only: `step_entry` still composes
`prelude_block` with `native_step`, and `vm_run` still iterates `step_entry`.
There is no Coq theorem that instantiates the literal 100 or the final
`main` state/head/tape assertions.

### Exact Coq declarations checked for presence

The gate checks these exact fully qualified declarations (module and short
name); it does not re-prove them:

```text
NaNLM.MinskyNaN16PreludeReady.prelude_ready
NaNLM.MinskyNaN16PreludeReady.prelude_halted
NaNLM.MinskyNaN16ActionRefines.action_refines
NaNLM.MinskyNaN16ActionRun.action_run_frame
NaNLM.MinskyNaN16ScanLoop.scan_loop
NaNLM.MinskyNaN16ScanPhase.scan_phase
NaNLM.MinskyNaN16StepHit.step_hit_phase
NaNLM.MinskyNaN16StepNone.no_trans_run
NaNLM.MinskyNaN16StepNone.step_none_phase
NaNLM.MinskyNaN16Step.native_step_refines
NaNLM.MinskyNaN16StepSpec.native_step_spec_active
NaNLM.MinskyNaN16StepEntrySpec.step_entry_spec
NaNLM.MinskyNaN16Run.vm_run_refines
NaNLM.MinskyNaN16StepOk.step_ok_of_layout
NaNLM.MinskyNaN16RunClosed.vm_run_refines_closed
NaNLM.MinskyNaN16RunClosed.vm_run_refines_window
```

Workflow status of those declarations:

| Declaration | Module | Workflow status |
|---|---|---|
| `prelude_ready` | `MinskyNaN16PreludeReady.v` | `coqc` + `coqchk` |
| `prelude_halted` | `MinskyNaN16PreludeReady.v` | `coqc` + `coqchk` |
| `action_refines` | `MinskyNaN16ActionRefines.v` | `coqc` + `coqchk` |
| `action_run_frame` | `MinskyNaN16ActionRun.v` | `coqc` + `coqchk` |
| `scan_loop` | `MinskyNaN16ScanLoop.v` | `coqc` + `coqchk` |
| `scan_phase` | `MinskyNaN16ScanPhase.v` | `coqc` + `coqchk` |
| `step_hit_phase` | `MinskyNaN16StepHit.v` | `coqc` + `coqchk` |
| `no_trans_run` | `MinskyNaN16StepNone.v` | `coqc` + `coqchk` |
| `step_none_phase` | `MinskyNaN16StepNone.v` | `coqc` + `coqchk` |
| `native_step_refines` | `MinskyNaN16Step.v` | `coqc` + `coqchk` |
| `native_step_spec_active` | `MinskyNaN16StepSpec.v` | `coqc` + `coqchk` |
| `step_entry_spec` | `MinskyNaN16StepEntrySpec.v` | `coqc` only; not in the workflow kernel-check loop |
| `vm_run_refines` | `MinskyNaN16Run.v` | `coqc` only; conditional on the explicit `step_ok` hypothesis |
| `step_ok_of_layout` | `MinskyNaN16StepOk.v` | `coqc` only; not in the workflow kernel-check loop |
| `vm_run_refines_closed` | `MinskyNaN16RunClosed.v` | `coqc` only; `table_control_ok`/`tape_window_ok` and a window bound remain explicit |
| `vm_run_refines_window` | `MinskyNaN16RunClosed.v` | `coqc` only; `table_control_ok`/`tape_window_ok` remain explicit |

The newer closed-run modules are compile-wired but not kernel-checked.  Their
`Print Assumptions` directives run during `coqc`, but the workflow neither
parses nor enforces that output, and the `coqchk` loop still stops at
`MinskyNaN16PreludeReady.v`.

### Remaining assumptions and non-claims

1. `vm_run_refines` remains conditional on
   `(forall vm, entry_ok vm table table_base tbase ->
   step_ok vm table table_base tbase)`.  The newer
   `MinskyNaN16StepOk.v` + `MinskyNaN16RunClosed.v` chain textually
   discharges that hypothesis through `step_ok_of_layout`,
   `vm_run_refines_closed`, and `vm_run_refines_window`, but only by adding
   the global `table_control_ok` and `tape_window_ok` separation assumptions
   (plus the window bound for `vm_run_refines_closed`).  Those separation
   facts are not proved for the concrete fixture, and the workflow only
   compiles these modules; it does not `coqchk` them.  This gate checks that
   their statements keep the assumptions explicit, not their proofs.
2. `step_entry_spec` and `native_step_spec_active` retain their explicit
   table hypotheses: `length table = 184`, the `Forall` row-shape conditions,
   `table_mem_at table_base table m`, and per-row tape/table-cell
   disjointness.  The gate checks the instruction text, not these semantic
   premises for the concrete fixture.
3. The gate compares normalized mnemonic tuples, not bytes.  The scan `HALT`
   sentinels, the scan match-fallthrough jump, and the action right-branch
   fallthrough jump are explicit model/normalization constructs.  The gate
   does not prove that the assembler emits those exact addresses or opcodes.
4. The NaN16 ISA semantics in `MinskyNaN16VM.exec_instr` remain a trusted
   model boundary.  Nothing here refines `third_party/nan0s/core/nan16.c` or
   the NaN16 encoder/loader.
5. The literal `run100` loop count (100) and `main`'s final state/head/tape
   checks are source-text facts.  Coq's `vm_run` is generic in `n`; no
   theorem specializes it to 100 or proves the fixture's `PASS` path.
6. `MinskyNaN16StepEntrySpec.v`, `MinskyNaN16Run.v`, `MinskyNaN16StepOk.v`,
   and `MinskyNaN16RunClosed.v` are compiled by the dedicated workflow but
   are not included in its `coqchk` loop.  The existing local
   `Print Assumptions` reports are not a substitute for a CI kernel check.
7. This section does not modify `nan16_words.certificate.json`, does not add
   a new certificate claim, and does not make Layer 2 a Coq ↔ NaN0S VM
   certificate.  It only records the new transcription gate and the exact
   declarations it touches.

## Layer 2 final status (2026-11-24)

The Coq VM half is now closed by
`formal/utm/MinskyNaN16Universality.v`:

```text
NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical
```

The exact statement is reproduced in
[`../nan16-vm/README.md`](../nan16-vm/README.md).  For every finite state
width `p`, nonempty well-formed row list, and well-formed left-infinite
source configuration, the source halts iff

```text
exists K t, K >= t /\
  nan16_vm_halted
    (vm_run t
      (nan16_vm_of_addr K (embed_config (lic_native_init rows c K) 0))
      fixture_table fixture_table_base)
```

The theorem and its supporting direction theorems
`nan16_source_halt_to_vm` and `nan16_vm_halt_to_source` all report
`Closed under the global context`; `coqchk` reports
`Modules were successfully checked`.  The raw certificate, proof term,
assumptions, and `coqchk` transcript are in
[`../nan16-vm/`](../nan16-vm/).

`K` is existential and may grow with the native run time `t`.  The window
premise `K >= t` is inside the theorem, not a separate bridge hypothesis.
A total run-time-independent encoder is still not claimed.

### Transcription table-base caveat

The final theorem is a statement about the **Coq VM model**, not about the
literal assembled `.nas` image:

- the Coq VM data-cell constants are pinned to the literal labels:
  `action_head_addr = 101`, `action_state_addr = 100`,
  `action_halt_addr = 102`, `tape_base_addr = 99`, and
  `fixture_table_base = 104`; `rlink` 103 is reserved and unmodelled;
- the literal `.nas` labels are `tbase`/`state`/`head`/`halt`/`rlink`/
  `table` at `99..104`, and the table starts at `104`;
- `check_minsky_nan16_step.py` maps `@head`, `@state`, `@halt`, `@tbase`,
  and `@table` to those symbolic Coq names and compares normalized
  mnemonic tuples.  It does not check instruction encodings or the loader.

Accordingly, the theorem does not refine a host `nan16.c` reference harness
or any external NaN0S VM, and it does not prove that the assembler emits the
exact instruction addresses or opcodes used by the Coq model.  Those remain
separate bridge obligations.
