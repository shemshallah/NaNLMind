# NAN0S layout contract — literal NaN16 `.nas` layout

**Status:** living layout contract, not a design freeze. This file pins the
current assembled layout so that Coq address constants, the source fixture,
and the transcription gate cannot drift silently. It is a snapshot of one
revision; a later `.nas` revision may move any of these addresses provided the
change procedure in [§7](#7-delta-list-for-future-layout-changes) is followed.

**Applied:** the literal-address correction in [§4](#4-applied-correction-literal-addresses)
has been applied to the Coq constants and fixture arithmetic. The pre-change
`300..304` map is retained in [§3](#3-the-104-vs-304-conflict) only as the
historical conflict record.

**Local verification (2026-11-24):** Coq 8.20.1 compiled the NaN16 VM chain
and the universality cone; `coqchk` reports `Modules were successfully
checked` for `MinskyNaN16Universality.vo`; the transcription gate passes; the
native `minsky_table` fixture reports `MTH MINSKY NATIVE PASS` (21025 steps).

**Authority:** the literal source text of
`mth/tests/mth_minsky_test.nas` and the assembler-resolved label values for
that text. The NaN16 core is the word-addressed NaN16 execution semantics; a
host `nan16.c` conformance harness, when a checkout provides one, is only a
secondary reference oracle, not the layout authority.
`third_party/nan0s/core/nan16.c` is not present at that path in this checkout;
do not use a C source file to override the assembler-resolved map below.

All addresses in this document are **NaN16 memory word indices**, not byte
offsets. `LD`/`ST` immediates and `.org` operate in words. The table's
1472 words span 1472 word addresses; do not multiply by the 8-byte word size
when comparing with a `.nas` label.

---

## 1. Pin

| Item | Value |
|---|---|
| Repository HEAD when this contract was written | `e8b2cef1ec5bae161f5a2401d70f3dfb009c6e16` |
| Source file | `mth/tests/mth_minsky_test.nas` |
| **Pinned `.nas` blob hash** (`git hash-object`) | **`b40bdbe62bde1b573fd11401eb4ee12dc307ddc8`** |
| SHA-256 of the pinned source file | `173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e` |
| Last commit touching the file | `0f770b4853a626819d401c862185ba0334b6a268` |
| Assembler | NaN0S `tools/nmk.awk` (external checkout; `$NAN0S_ROOT`) |
| Assembled size | **4366 words** (word indices `0..4365`) |

The blob hash is the pin. If `git hash-object
mth/tests/mth_minsky_test.nas` no longer equals
`b40bdbe62bde1b573fd11401eb4ee12dc307ddc8`, the address map below is stale:
re-run the assembler and update this contract before changing any Coq
constant.

### Reproducing the map

The assembler is the NaN0S scaffold, not a file in this repository. With a
NaN0S checkout available:

```sh
NAN0S_ROOT=${NAN0S_ROOT:-$HOME/nan0s}
LC_ALL=C awk -f "$NAN0S_ROOT/tools/nmk.awk" \
  -v CMD=emit \
  -v LABELS=/tmp/minsky.labels \
  mth/tests/mth_minsky_test.nas > /tmp/minsky.nan
sort -k2 -n /tmp/minsky.labels
```

`nmk.awk` writes `name word-index` lines to the `LABELS` file. It also emits
`words 4366` on stderr. The word text is not needed for this contract; the
label values are.

---

## 2. Literal address map

### 2.1 Code labels

These are words occupied by executable code, in source order.

| Label | Word address | Role |
|---|---:|---|
| `main` | 0 | entry point; initializes state/head/halt, runs 100 steps, checks result |
| `vloop` | 18 | expected-tape comparison loop |
| `run100` | 29 | 100-step driver; saves/restores `rlink` |
| `rloop` | 31 | 100-step loop body |
| `step` | 36 | one Minsky step: prelude, scan, action |
| `scan` | 47 | table scan loop |
| `mleft` | 67 | left-move branch |
| `mright` | 69 | right-move branch |
| `mdone` | 70 | move-done join |
| `step_ret` | 78 | step return path |
| `next` | 79 | scan next-row path |
| `no_trans` | 81 | no-transition path |
| `puts` | 84 | string output helper |
| `p1` | 85 | string outer loop |
| `p2` | 87 | string inner loop |
| `fail` | 96 | failure marker and halt |

### 2.2 Data labels and literal data

| Symbol / range | Word address(es) | Size in words | Initial contents / role |
|---|---:|---:|---|
| `tbase` | 99 | 1 | `.word 4096`; the cell holding the tape image base |
| `state` | 100 | 1 | `.word 0`; `main` writes initial state `5` |
| `head` | 101 | 1 | `.word 0`; `main` writes initial head `166` |
| `halt` | 102 | 1 | `.word 0`; `main` clears it, step sets it |
| `rlink` | 103 | 1 | `.word 0`; `run100` saves `r15` here (literal return link) |
| `table` | 104 | 1472 | 184 rows × 8 words; occupies `104..1575` |
| `expected` | 1576 | 73 | expected tape words; occupies `1576..1648` |
| `.org` padding | 1649..4095 | 2447 | zero padding emitted by `.org 4096` |
| tape image | 4096 | 256 | first 128 words are `2`; remaining 128 words are the tape window data; occupies `4096..4351` |
| `s_pass` | 4352 | 6 | `"MTH MINSKY NATIVE PASS"` plus NUL, padded to 24 bytes |
| zero after `s_pass` | 4358 | 1 | `.word 0` |
| `s_fail` | 4359 | 6 | `"MTH MINSKY NATIVE FAIL"` plus NUL, padded to 24 bytes |
| zero after `s_fail` | 4365 | 1 | `.word 0` |

Exclusive ends: table ends at **1576**, expected ends at **1649**, tape ends
at **4352**, and the image ends at **4366**.

The first 128 words of the tape image (immediately after `.org 4096`) are
`2`s. The source comment and `main`'s `MOVI r3,4224` define the verification
window at `4096 + 128 = 4224`; the 73-word comparison covers `4224..4296`.
Those numbers are layout-coupled even though they are not labels.

### 2.3 Literal instruction operands

The assembler resolves the `@` labels in the emitted instruction stream. For
example (word index; instruction encoding not repeated):

| Source | Resolved immediate |
|---|---:|
| `ST r1,r0,@state` | 100 |
| `ST r1,r0,@head` | 101 |
| `ST r0,r0,@halt` | 102 |
| `LD r3,r0,@tbase` | 99 |
| `MOVI r5,@table` | 104 |
| `MOVI r4,@expected` | 1576 |
| `CALL @run100` | 29 |
| `JMP[NE] @fail` | 96 |

In particular, `MOVI r5,@table` becomes `MOVI r5,104`, not `304`. The Coq
model's `table_base` parameter is the only place where a different number can
legitimately appear, and then only if a relocation theorem is supplied.

---

## 3. The 104-vs-304 conflict

### 3.1 The two maps

Literal `.nas` map:

```text
tbase 99, state 100, head 101, halt 102, rlink 103, table 104
table [104, 1576)
tape base cell address = 99; tape image base = 4096
```

Pre-correction Coq constants (retained here as the historical conflict
record; the applied values are in [§4.1](#41-applied-values)):

```text
action_head_addr  = 300
action_state_addr = 301
action_halt_addr  = 302
tape_base_addr    = 303
fixture_table_base = 304
```

### 3.2 Why this was a conflict, not a harmless naming difference

Before the correction, the model's table was placed at **304**, while the
literal table is at **104**. The model's control cells were **300..303**,
while the literal control cells are **99..102** (with `rlink` at 103).

The mapping is not a uniform shift and not a permutation that preserves the
literal order:

| Literal cell | Literal address | Coq definition | Coq address | Delta |
|---|---:|---|---:|---:|
| `tbase` | 99 | `tape_base_addr` | 303 | +204 |
| `state` | 100 | `action_state_addr` | 301 | +201 |
| `head` | 101 | `action_head_addr` | 300 | +199 |
| `halt` | 102 | `action_halt_addr` | 302 | +200 |
| `rlink` | 103 | not a `Mem` cell; modelled by `vm_link` | — | — |
| `table` | 104 | `fixture_table_base` | 304 | +200 |

A single uniform `+200` relocation would have put the literal cells at
`299/300/301/302` and the table at `304`, which is not what the old Coq
constants said either. The old control block was **reordered**, and the
literal `rlink` cell has no `Mem` representation.

### 3.3 The dangerous partial fix

Do **not** change only

```coq
Definition fixture_table_base : nat := 104.
```

while leaving `action_head_addr = 300`, `action_state_addr = 301`, and
`action_halt_addr = 302`. The literal table range `[104, 1576)` contains
addresses 300, 301, and 302, so:

- `table_control_ok` becomes false;
- `fixture_table_control_ok` fails (its proof reduces to
  `action_halt_addr < fixture_table_base`, i.e. `302 < 104`);
- `fixture_table_base_after_control` (`304 = 303 + 1`) is no longer true in
  literal form;
- the table range would overlap the control cells, so the model's
  table/control separation invariant is false (a literal run would write
  table data into the same words the control logic uses).

The table base and all control-cell constants must move together, or the
304 placement must be justified by a proved relocation.

### 3.4 Scope after the correction

The checked Coq chain still proves a statement about its **own VM model**, not
about the literal assembled `.nas` image: changing the data-cell constants
does not prove the assembler, encoding, or loader. The certificate records
that scope explicitly:

- `formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json`
  — fields `scope`, `not_proved[2]`, and
  `transcription_table_base_caveat`;
- `formal/utm/certificates/nan16-vm/README.md` — "Scope and non-claims";
- `formal/utm/certificates/nan16-table/README.md` — table-base transcription
  caveat;
- `formal/utm/UNIVERSALITY_REVIEW_LEDGER.md` — transcription table-base
  caveat.

The Coq table **data** is the correct 184×8 image (`fixture_table` equals
`map encode_nan16_words minsky_entries`); only its placement is abstract.
The current `check_minsky_nan16_step.py` compares memory operands
symbolically and deliberately does not check numeric addresses.

---

## 4. Applied correction: literal addresses

### 4.1 Applied values

The literal `.nas` addresses are now used by the Coq model:

```coq
(* formal/utm/MinskyNaN16Action.v *)
Definition action_head_addr  : nat := 101.
Definition action_state_addr : nat := 100.
Definition action_halt_addr  : nat := 102.

(* formal/utm/MinskyNaN16Prelude.v *)
Definition tape_base_addr    : nat := 99.

(* formal/utm/MinskyNaN16RunConcrete.v *)
Definition fixture_table_base : nat := 104.
Definition fixture_tape_base  : nat := 4096.   (* unchanged *)
```

`rlink` at 103 remains an unmodelled reserved word. The Coq `vm_link` field
models the return link for the modelled `iRET`; it is not a `Mem` cell. If
`rlink` is later modelled as a cell, add an explicit
`action_rlink_addr : nat := 103` and wire it into `entry_ok` and the driver
refinement; do not fold it into the table range.

This allocation is non-overlapping:

```text
control cells: 99..102   (rlink 103 reserved/unmodelled)
table:         104..1575
expected:      1576..1648
padding:       1649..4095
tape:          4096..4351
strings:       4352..4365
```

### 4.2 Why literal addresses were chosen

1. The five constants were arbitrary model identifiers. No proof needs
   `300..304` to be round; no theorem depends on a particular numeric value
   beyond the ordering/distinctness facts.
2. The literal values remove the address caveat for the modelled control and
   table cells. The model's table is now the source table at 104, and
   `entry_ok` reads the source `tbase` cell at 99.
3. The proof changes are small and local: two fixture arithmetic lemmas plus
   comments. The rest of the chain uses the constants symbolically
   (`action_head_addr`, `tape_base_addr`, `table_base`) and continues to
   work.
4. A proved 304 relocation is more expensive and still does not prove the
   assembled code/instruction encoding; it only maps data cells. It should be
   used only if the model must keep its current numeric layout for an
   external reason.

### 4.3 Applied proof and statement changes

The following were the hard changes; the old `vm_compute`/`reflexivity`
statements would otherwise have been false. All are applied in the current
revision.

| File | Constant / declaration | Applied change | Why |
|---|---|---|---|
| `formal/utm/MinskyNaN16Action.v` | `action_head_addr` | `300` → `101` | literal `head` label |
| `formal/utm/MinskyNaN16Action.v` | `action_state_addr` | `301` → `100` | literal `state` label |
| `formal/utm/MinskyNaN16Action.v` | `action_halt_addr` | `302` → `102` | literal `halt` label |
| `formal/utm/MinskyNaN16Prelude.v` | `tape_base_addr` | `303` → `99` | literal `tbase` label |
| `formal/utm/MinskyNaN16RunConcrete.v` | `fixture_table_base` | `304` → `104` | literal `table` label |
| `formal/utm/MinskyNaN16RunConcrete.v` | `fixture_table_base_after_control` | statement `= tape_base_addr + 1` → `= tape_base_addr + 5` | literal five-cell block includes `rlink` at 103; `104 = 99 + 5` |
| `formal/utm/MinskyNaN16RunConcrete.v` | `fixture_table_end` | `1776` → `1576` | `104 + 8*184 = 1576` |
| `formal/utm/MinskyNaN16RunConcrete.v` | header comment / "Addresses" section | replace `300..303`, `304..1775`, `304`, `1776` with the literal map and ranges | documentation must not contradict constants |
| `formal/utm/MinskyNaN16Universality.v` | module comment, line 10 | `fixture_table_base = 304` → `= 104` | final theorem description |
| `formal/utm/MinskyNaN16StepOk.v` | comment, line 21 | "tape-base cell 303" → "tape-base cell 99" | documentation |

For the four *modelled* cells, `fixture_table_base_after_control` could
equivalently be stated as `fixture_table_base = action_halt_addr + 2`
(`102 + 2 = 104`). The `+ 5` from `tape_base_addr` is preferred because it
records the literal five-cell block, including the unmodelled `rlink` at 103.

The following declarations are **not** hard failures under the literal
values, but should be reviewed/updated when touching them:

| File | Why review |
|---|---|
| `formal/utm/MinskyNaN16Action.v` | `smoke_mem` now uses row `400..405` and tape cell `500`, so it no longer overlaps the control cells or the table. `action_run_smoke` was updated to the new row/tape literals. |
| `formal/utm/MinskyNaN16ActionRun.v` | distinctness lemmas (`action_head_state_neq`, etc.) remain true under 101/100/102; no numeric edit needed, but rerun. |
| `formal/utm/MinskyNaN16ActionRefines.v`, `MinskyNaN16ActionSuffix.v` | row-vs-control hypotheses are symbolic; the literal values still satisfy the required inequalities. |
| `formal/utm/MinskyNaN16RunClosed.v` | `table_control_ok_of_base_above` still applies because `102 < 104`; `table_control_ok` / `tape_window_ok` are generic. |
| `formal/utm/MinskyNaN16AddressStep.v` | `action_halt_addr < table_base` is the only control/table ordering fact; literal `102 < 104` satisfies it. |
| `formal/utm/MinskyNaN16PreserveTable.v`, `MinskyNaN16PreserveHead.v` | symbolic frame modules; no numeric constants, but their disjointness premises must still be true. |
| `formal/utm/MinskyNaN16Step.v`, `StepHit.v`, `StepNone.v`, `StepSpec.v`, `StepEntrySpec.v` | symbolic; verify the full build after the constants move. |
| `formal/utm/MinskyNaN16Run.v`, `MinskyNaN16Window.v` | generic; `entry_ok` still reads `tape_base_addr` and `action_*` symbolically. |

After the change, these remain provable without statement changes (verified
by the local full-chain build):

- `fixture_table_control_ok` (`102 < 104`);
- `fixture_tape_window_ok` (all control cells and table cells below 4096);
- `fixture_table_below_tape` (`104 + 8*184 = 1576 < 4096`);
- `fixture_table_base_above_halt` (`102 < 104`);
- `fixture_table_fits_below_tape` (`1576 <= 4096`);
- `nan16_addr_mem_table`'s cell-inequality goals (table range is outside
  `99..102`).

### 4.4 First edit applied

The first edit applied was the lowest-level address block, in
`formal/utm/MinskyNaN16Action.v` (definitions at lines 21–23 as of the pinned
HEAD):

```diff
--- a/formal/utm/MinskyNaN16Action.v
+++ b/formal/utm/MinskyNaN16Action.v
@@
-Definition action_head_addr : nat := 300.
-Definition action_state_addr : nat := 301.
-Definition action_halt_addr : nat := 302.
+Definition action_head_addr : nat := 101.
+Definition action_state_addr : nat := 100.
+Definition action_halt_addr : nat := 102.
```

The applied sequence then continued with
`formal/utm/MinskyNaN16Prelude.v` (`tape_base_addr := 99`),
`formal/utm/MinskyNaN16RunConcrete.v` (`fixture_table_base := 104` and the two
fixture lemmas), the action smoke-memory relocation, and the comments and
certificate text.

---

## 5. Alternative: keep 304 and prove a faithful relocation

This is **not** the chosen correction. It is recorded so a future maintainer
can choose it deliberately rather than accidentally.

Keep:

```coq
action_head_addr = 300
action_state_addr = 301
action_halt_addr = 302
tape_base_addr = 303
fixture_table_base = 304
```

and add a new Coq module (suggested name:
`formal/utm/MinskyNaN16LayoutRelocation.v`) containing:

1. A total address map `reloc : nat -> nat` with the data-cell equations

   ```text
   reloc 300 = 101   (* head *)
   reloc 301 = 100   (* state *)
   reloc 302 = 102   (* halt *)
   reloc 303 = 99    (* tbase *)
   reloc (304 + 8*i + f) = 104 + 8*i + f
   ```

   and tape mapping consistent with `fixture_tape_base = 4096`.

2. A proof that `reloc` is injective on the union of the control cells, the
   table range, and the reachable tape window. Because the control mapping is
   **permuted**, a single `+200` shift lemma is insufficient; each control
   cell needs its own equation and disjointness proof.

3. A memory-simulation theorem, for every reachable run, of the shape

   ```text
   forall k, vm_mem model_vm (reloc k) = vm_mem literal_mem k
   ```

   with the table rows, control cells, and tape window as separate lemmas.

4. A restated final theorem/corollary in `MinskyNaN16Universality.v` that
   applies the relocation to `nan16_run_halting_equivalence_canonical`, plus
   updated certificate statement text and proof-term artifacts.

A relocation theorem only fixes **data-cell addresses**. It does not prove
that the assembled `.nas` code words, instruction encodings, or host loader
match the Coq instruction list. A full literal-image claim still needs a
code/encoding bridge. That is the main reason this option is not recommended
here.

If this option is taken, do not also change `fixture_table_base` to 104 in
isolation; keep 304 as the model address and make the relocation explicit.

---

## 6. Contract invariants

These are the invariants the current proofs rely on. They are deliberately
weaker than a fixed numeric layout, so a future revision may move addresses
without freezing the design.

| ID | Invariant | Current literal witness | Where it matters |
|---|---|---|---|
| L1 | Control cells are pairwise distinct. | `99,100,101,102` | `action_head_state_neq`, etc. |
| L2 | Every modelled control cell is below the table base. | `max(99,100,101,102) = 102 < 104` | `table_control_ok_of_base_above`, `fixture_table_base_above_halt` |
| L3 | Table range is disjoint from control cells. | `[104,1576)` vs `99..102` | `table_control_ok`, `nan16_addr_mem_table` |
| L4 | Table range ends at or below the tape image base. | `1576 <= 4096` | `fixture_table_below_tape`, `fixture_table_fits_below_tape` |
| L5 | Tape window does not hit table/control cells. | `4096..4351` vs table/control | `tape_window_ok`, `fixture_tape_window_ok` |
| L6 | `tbase` cell contains the tape image base. | cell 99 = `4096` | `entry_ok`, `prelude_ready` |
| L7 | `table` starts after all five literal data cells. | `104 = 99 + 5` | `fixture_table_base_after_control` |
| L8 | Table row length is 8 and row count is 184. | 1472 words, `[104,1576)` | `fixture_table_length`, scan loop `MOVI r6,184` |
| L9 | Expected range length is 73 and comparison starts at `tape_base + 128`. | `1576..1648`, `4224..4296` | main verification, `MOVI r3,4224`, `MOVI r5,73` |
| L10 | `rlink` is not a table/tape cell. | 103 reserved | `run100` / `vm_link` |

Do not weaken L1–L5 to make a new layout fit. Either move the constants so the
invariants hold, or add a relocation theorem; do not add axioms or
`Admitted`.

---

## 7. Delta list for future layout changes

The `.nas` file is the source of truth. Any change to code size, data labels,
`.org`, table length, expected length, or tape length can shift addresses.
Follow this checklist in order.

### 7.1 Immediate delta list (applied literal-address correction)

This table was applied in the current revision; it remains the checklist if
the layout is re-pinned later.

| # | File | Delta |
|---|---|---|
| 1 | `mth/tests/mth_minsky_test.nas` | No text change required for this correction; it remains the pinned authority. Re-run `nmk.awk` and confirm the blob hash is still `b40bdbe...` before trusting the map. |
| 2 | `formal/utm/MinskyNaN16Action.v` | `action_head_addr 300→101`, `action_state_addr 301→100`, `action_halt_addr 302→102`; header comment updated; `smoke_mem` moved to row 400/tape 500. |
| 3 | `formal/utm/MinskyNaN16Prelude.v` | `tape_base_addr 303→99`; update any comment that describes the cell. |
| 4 | `formal/utm/MinskyNaN16RunConcrete.v` | `fixture_table_base 304→104`; `fixture_table_base_after_control` `+1→+5`; `fixture_table_end` `1776→1576`; rewrite the "Addresses" header block. |
| 5 | `formal/utm/MinskyNaN16Universality.v` | Module comment `304→104`; recheck `fixture_table_base_above_halt` and `fixture_table_fits_below_tape` (both remain true). |
| 6 | `formal/utm/MinskyNaN16StepOk.v` | Comment "tape-base cell 303" → "tape-base cell 99". |
| 7 | `formal/utm/check_minsky_nan16_step.py` | Symbolic-address comment updated; further hardening (asserting the pinned label values against `nmk.awk` `LABELS` output and the Coq `Definition`s) remains a follow-up, not a proof premise. |
| 8 | `formal/utm/certificates/nan16-vm/nan16_run_halting_equivalence_canonical.certificate.json` | Regenerated and updated: `scope`, `not_proved[2]`, `transcription_table_base_caveat`, source/`.vo` hashes, and dependency hashes now reflect the literal layout. |
| 9 | `formal/utm/certificates/nan16-vm/README.md` | Scope/non-claims text and anchor hashes updated to the literal layout. |
| 10 | `formal/utm/certificates/nan16-table/README.md` | Table-base caveat and block-correspondence text updated to the literal layout. |
| 11 | `formal/utm/UNIVERSALITY_REVIEW_LEDGER.md` | Current caveat section updated; historical run entries preserved. |

This document itself does not modify Coq files. The first actual Coq edit
applied was the `MinskyNaN16Action.v` patch in
[§4.4](#44-first-edit-applied).

### 7.2 Future `.nas` layout change procedure

1. **Edit the `.nas` source.**
   - If code before `tbase` changes size, every data label moves.
   - If table rows change, `table` may stay put but `expected`, `.org`, and
     the tape/string offsets move.
   - If `.org` changes, `fixture_tape_base` and the hard-coded `4224` move.
2. **Reassemble and record the map.**
   - Run the `nmk.awk` command in [§1](#reproducing-the-map).
   - Record the new blob hash, label values, total words, and the
     table/expected/tape/string ranges in this file.
   - A change to the blob hash invalidates every address below; do not update
     only one row.
3. **Choose one Coq policy, explicitly:**
   - **Literal:** update the five constants to the new label values; update
     the fixture arithmetic lemmas.
   - **Relocation:** keep the model constants and add/extend the relocation
     theorem; update the final theorem statement.
   Never leave a partial update where the table base and control cells
   overlap.
4. **Update dependent constants and lemmas.**
   - Control cells: `MinskyNaN16Action.v`.
   - Tape-base cell: `MinskyNaN16Prelude.v`.
   - Table base and fixture ranges: `MinskyNaN16RunConcrete.v`.
   - Final-theorem docs and certificate text: `MinskyNaN16Universality.v`,
     certificate JSON/READMEs, ledger.
   - Gate: `check_minsky_nan16_step.py`.
5. **Re-run the full chain.**
   - Coq compile and `coqchk` of `MinskyNaN16Universality.v`.
   - `check_minsky_nan16_step.py`.
   - `tools/run_nan16_fixtures.py --only minsky_table` (or the CI
     equivalent) against a NaN0S checkout.
   - Regenerate certificate artifacts; do not hand-edit `coqchk` summaries.
6. **Record the delta.**
   - Add a dated row to this file's pin table or a short "revision history"
     entry. The contract is allowed to change; it is not allowed to become
     ambiguous.

### 7.3 Specific change dependencies

| Change | Must recompute / edit | Coq fallout |
|---|---|---|
| Add/remove instructions before `tbase` | All label addresses shift; re-run assembler | All five constants (literal policy) or relocation map; gate; certificate |
| Move `tbase` | `tape_base_addr` | `MinskyNaN16Prelude.v`, `entry_ok`, `prelude_ready`, `fixture_table_base_after_control` |
| Move `state` | `action_state_addr` | `MinskyNaN16Action.v`, all `Step*`/`Run*` modules that read state symbolically |
| Move `head` | `action_head_addr` | `MinskyNaN16Action.v`, action refinement/suffix, entry/run |
| Move `halt` | `action_halt_addr` | `MinskyNaN16Action.v`, no-transition and step modules, `table_control_ok` |
| Model `rlink` as a cell | New `action_rlink_addr`; update driver `entry_ok` and `action_block`/`iRET` story | New constant plus every `entry_ok` consumer; do not reuse 103 for table |
| Move `table` | `fixture_table_base`; recompute table end and expected range | `MinskyNaN16RunConcrete.v`, `MinskyNaN16Universality.v`, table/window proofs |
| Change table length | `fixture_table` list, `fixture_table_length`, `nan16_rows`, scan count `184` | `fixture_table_end`, `fixture_table_below_tape`, `table_control_ok`, certificate |
| Move `.org 4096` | `fixture_tape_base`; change hard-coded `4224` | `MinskyNaN16RunConcrete.v`, `MinskyNaN16Universality.v`, `tape_window_ok`, fixture runner |
| Change expected length | `MOVI r5,73`, expected range, tape window | `fixture_step_ok`/window bounds if the reachable window changes |
| Change strings | `s_pass`/`s_fail` addresses and image length | Host marker checks only; not Coq address constants, but update the pin table |

---

## 8. Scope and non-claims

- This contract is about the **literal `.nas` layout** and the **Coq data
  model**, not about proving the assembler, encoder, loader, or a host
  `nan16.c` reference harness correct.
- A host `nan16.c` conformance harness is a secondary reference oracle for
  word-addressed VM behavior. It is not the NaN16 core, not the source of
  `.nas` label addresses, and must not be used to override this map.
- The Coq model's `Mem := nat -> nat` is word-addressed; the constants are
  cell identifiers, not byte offsets.
- The current certified theorem remains a statement about the Coq VM until
  either the literal constants are adopted or a relocation theorem (and,
  for a full image claim, a code/encoding bridge) is proved.
- The layout is not frozen. The pin is a reproducibility device: change it
  deliberately, update the delta list, and keep the source, Coq constants,
  gate, and certificate consistent.
