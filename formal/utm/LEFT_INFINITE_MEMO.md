# Left-infinite source model and book-buffer audit

Status: new files only. No tracked file was edited.

New files:

- `formal/utm/MinskyLeftInfinite.v` — `LeftInfiniteConfig`, a total
  boundary-halting step, buffer arithmetic, and the conditional
  halting-equivalence theorem.  Compiles with Coq 8.20.1 and `coqchk`.
- `formal/utm/MinskyLeftCycleAudit.v` — a mechanically checked concrete
  counterexample to the zero-buffer reading of the existing left cycle.
  Compiles with Coq 8.20.1 and `coqchk`.

Compile commands used inside the proot Debian guest:

```text
coqc -Q formal/utm NaNLM formal/utm/MinskyLeftInfinite.v
coqc -Q formal/utm NaNLM formal/utm/MinskyLeftCycleAudit.v
coqchk -Q formal/utm NaNLM formal/utm/MinskyLeftInfinite.vo
coqchk -Q formal/utm NaNLM formal/utm/MinskyLeftCycleAudit.vo
```

`Print Assumptions conditional_left_source_native_halting_equivalence`
and the audit theorems all report `Closed under the global context`.

## 1. The model

```coq
Record LeftInfiniteConfig := {
  lic_state : list bool;
  lic_head : Z;
  lic_tape : Z -> bool;
  lic_R : Z;                 (* rightmost existing cell *)
  lic_halted : bool
}.

Definition left_infinite_ok (c : LeftInfiniteConfig) : Prop :=
  (lic_head c <= lic_R c)%Z /\
  (forall z, (lic_R c < z)%Z -> lic_tape c z = false).
```

The step is total:

```coq
Definition left_infinite_step (rows : list WideSourceRow)
    (c : LeftInfiniteConfig) : LeftInfiniteConfig :=
  if lic_halted c then c else
  match wide_source_lookup rows (lic_state c)
                          (lic_tape c (lic_head c)) with
  | None => (* lookup failure: halt *)
      {| lic_state := lic_state c; lic_head := lic_head c;
         lic_tape := lic_tape c; lic_R := lic_R c;
         lic_halted := true |}
  | Some row =>
      if andb (wr_right row) (Z.eqb (lic_head c) (lic_R c))
      then (* right move at R: perform write, then halt in place *)
        {| lic_state := lic_state c; lic_head := lic_head c;
           lic_tape := source_write_at (lic_tape c) (lic_head c)
                                        (wr_write row);
           lic_R := lic_R c; lic_halted := true |}
      else (* normal lookup/write/move *)
        {| lic_state := wr_next row;
           lic_head := (lic_head c +
                        (if wr_right row then 1 else -1))%Z;
           lic_tape := source_write_at (lic_tape c) (lic_head c)
                                        (wr_write row);
           lic_R := lic_R c; lic_halted := false |}
  end.

Fixpoint left_infinite_run (fuel : nat) (rows : list WideSourceRow)
    (c : LeftInfiniteConfig) : LeftInfiniteConfig :=
  match fuel with
  | 0 => c
  | S n => left_infinite_run n rows (left_infinite_step rows c)
  end.
```

Key proved facts:

```coq
left_infinite_step_halted :
  lic_halted c = true -> left_infinite_step rows c = c.

left_infinite_step_lookup_none :
  lic_halted c = false ->
  wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = None ->
  lic_halted (left_infinite_step rows c) = true.

left_infinite_step_right_blocked_halts :
  lic_halted c = false ->
  wide_source_lookup ... = Some row ->
  wr_right row = true ->
  lic_head c = lic_R c ->
  lic_halted (left_infinite_step rows c) = true.

left_infinite_step_ok :
  left_infinite_ok c -> left_infinite_ok (left_infinite_step rows c).

left_infinite_run_ok :
  left_infinite_ok c -> left_infinite_ok (left_infinite_run fuel rows c).
```

This is the intended source semantics: the head may move left forever
(the tape is left-infinite), but a right move from `R` is blocked and
halts instead of creating cell `R+1`.

## 2. Conditional halting equivalence (exact statement)

The section variables and the three premises are the direct analogues of
`MinskyWideMacroSimulation.v`:

```coq
Variable encode :
  nat -> list WideSourceRow -> LeftInfiniteConfig -> Config.
Variable macro_cost :
  nat -> list WideSourceRow -> LeftInfiniteConfig -> nat.

Hypothesis lic_encode_reflects_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    c_halted (encode p rows c) = lic_halted c.

Hypothesis lic_macro_cost_positive :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    1 <= macro_cost p rows c.

Hypothesis lic_actual_table_macro_step :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    run (macro_cost p rows c) (encode p rows c) =
    encode p rows (left_infinite_step rows c).
```

The clock and run theorem are the same construction:

```coq
Fixpoint left_macro_clock (n p : nat) (rows : list WideSourceRow)
    (c : LeftInfiniteConfig) : nat :=
  match n with
  | 0 => 0
  | S k => macro_cost p rows c +
           left_macro_clock k p rows (left_infinite_step rows c)
  end.

Theorem conditional_left_native_arbitrary_run :
  forall n p rows c,
    Forall (wide_row_wellformed p) rows ->
    run (left_macro_clock n p rows c) (encode p rows c) =
    encode p rows (left_infinite_run n rows c).
```

The halt predicates and the equivalence are:

```coq
Definition left_infinite_eventually_halts
    (rows : list WideSourceRow) (c : LeftInfiniteConfig) : Prop :=
  exists n, lic_halted (left_infinite_run n rows c) = true.

Definition left_native_eventually_halts
    (p : nat) (rows : list WideSourceRow)
    (c : LeftInfiniteConfig) : Prop :=
  exists n, c_halted (run n (encode p rows c)) = true.

Theorem conditional_left_source_native_halting_equivalence :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    (left_infinite_eventually_halts rows c <->
     left_native_eventually_halts p rows c).
```

The two directions are also exported separately:

```coq
conditional_left_source_halt_implies_native_halt
conditional_left_native_halt_implies_source_halt
```

None of the three premises is proved by this file.  In particular this is
not an unconditional universality theorem.  The predicate
`left_infinite_ok` (head `<= R` and all cells above `R` blank) is proved
preserved by `left_infinite_step`, but it is deliberately not a fourth
premise; a concrete encoder includes it in its representation invariant,
while the abstract equivalence remains stated for all configurations,
exactly as `conditional_wide_source_native_halting_equivalence` is.

## 3. Exact intended encoder/cost instantiation

For a fixed left window `lo : Z` with `lo <= lic_head c`, the natural
q6-level frames are:

```text
ptape(c, lo) = [ tape(lo), ..., tape(head-1) ]
rawbuf(c)    = [ tape(head+1), ..., tape(R) ]

physical source side:
  ptape(c, lo) ++ [6] ++ rawbuf(c) ++ [5] ++ condition ++ description
```

The book layout has implicit zeros to the left of `ptape`; the encoder
must choose `lo` below the nonblank support of the tape.  This is an
encoder-side window invariant, not a condition of the abstract step:
`left_infinite_ok` deliberately allows an arbitrary left-infinite tape,
so left moves are always defined.

Here `6` marks the head cell; the cell's content is the read bit in the
condition block.  The number of cells strictly right of the head is

```text
b = R - head = length (rawbuf(c)).
```

The q6 zero-buffer frame of the existing book layout is the special case
`rawbuf(c) = 0^b`.  `book_q6_left` corresponds to this with
`b = buf` and `ptape = ptape`.

The intended `macro_cost` is a sum of the locate cost and the perform
cost (plus the boundary halt trace in the blocked case):

- **initial q5.**  `book_q5_scan_general` already accepts an arbitrary
  `tbuffer : list nat`, not just `book_buf buf`.  Its statement is
  `rev (map source_bit src) ++ 5 :: rev tbuffer ++ 6 :: rev data ->
  5 :: rev tbuffer ++ 6 :: rev data`, so a raw buffer list can replace
  the zero buffer in `book_initial_frame` without changing the scan
  proof.
- **lookup hit, right move, `head < R`.**  Reuse
  `book_q6_to_q5_right` and `book_locate_by_computation_from_q5_to_q6`,
  or the composed `book_steady_q5_locate_to_q5_right`.  The q6 buffer
  goes `b -> b-1`; the cell read at the new head is the first raw buffer
  cell.  The `1 <= b` hypothesis of `book_q6_to_q5_right` is exactly
  `head < R`, so the theorem covers precisely the non-boundary case; the
  blocked case `b = 0` is where the new model halts.  The existing
  theorem covers the blank buffer cell `0`; if a previous left move wrote
  `1`, the analogous q19 relocation with a nonempty captured cell/bit is
  needed (the underlying q19/q20 relocation lemmas are stated for
  arbitrary `scanned`/`bit`, but the book right adapter currently
  specializes to `scanned = []`, `bit = false`).
- **lookup hit, left move.**  Reuse `book_q6_to_q5_left` and then the
  generalized locate `book_locate_state_wide` /
  `book_locate_rows_to_q6_wide`, or the composed
  `book_steady_q5_locate_to_q5_left`.  The q6 buffer goes
  `b -> b+1` and its new first cell is the source write bit.
- **lookup failure.**  Reuse the locate/halt path of
  `book_locate_by_computation_from_q5_to_halt` or
  `book_steady_q5_locate_perform_*_sentinel_halt`.  The abstract step is
  already halted.
- **lookup hit, right move, `head = R`.**  This is the new boundary
  case.  The abstract step halts.  The native table passes `Y` in q19
  and eventually halts at q3/Y; the ledger's concrete instance takes
  46,176 steps.  There is no general native theorem for this trace yet,
  so it is exactly the part of the third premise that remains open.

The second premise is positive because each locate/perform clock is a
sum of `S ...` terms (or `copy_all_clock`/`direction_clock`, which are
positive for the actual nonempty frames).  The first premise is the
halt-side encoder obligation; its concrete shape is the same as
`wide_encode_halt` in `MinskyWideMacroSimulation.v`, with
`lic_halted` in place of `wc_halted`.

## 4. Buffer accounting and the left-cycle counterexample

### 4.1 The arithmetic

The book q6 frame is

```text
ptape ++ [6] ++ 0^b ++ [5] ++ ...
```

so, with the head at the marker cell and `R` the last cell before `Y`,

```text
b = R - head.
```

The file proves:

```coq
book_buffer_right_move_Z :
  b = R - head -> b - 1 = R - (head + 1).

book_buffer_left_move_Z :
  b = R - head -> b + 1 = R - (head - 1).
```

So the right perform `b -> b-1` is exactly moving toward the boundary,
and the left perform must be `b -> b+1`.  A left perform also writes the
source bit `w` into the old head cell, which becomes the first cell to
the right of the new head:

```text
old:  ptape_prefix ++ [target] ++ [6] ++ 0^b
new:  ptape_prefix ++ [6] ++ [w] ++ 0^b
```

Thus the new raw buffer is `w :: 0^b`, of length `b+1`, and the new
q5-steady parameter (the frame that reserves the cell immediately left
of `6` as `w_tape`) is `b+2`; equivalently the next q6 buffer is `b+1`.
It is not `0^(b+1)` in general.

### 4.2 The concrete counterexample

`MinskyLeftCycleAudit.v` instantiates `book_q6_to_q5_left` with

```text
bits = [false], init = [], w = true, b = 1,
ptape = [1], target = true, desc_tail = [], tags = [2;3;2].
```

The literal run is computed by the existing kernel-checked theorem:

```coq
audit_left_cycle_run :
  run (book_left_clock [false] [] true 1 [] [2;3;2] 5 [0])
    (entry_config 6 (book_q6_left [false] 1 [1]) [2;1;0;0])
  = cfg_ml 5 [5;0;1;6]
      (3 :: map q16_restore (rev ([2;3;2] ++ [4])) ++ [0]).
```

The output physical tape is

```text
6 1 0 5 3 4 0 1 0 0
```

i.e. `M = 6`, write bit `1`, one blank buffer cell `0`, `Y = 5`, the
next read mark `3`, and the restored description.  The source side is
therefore

```text
6 :: 1 :: 0 :: 5 :: ...
```

whereas every zero-buffer q6/q5 frame has the source side

```text
P ++ 6 :: 0^B ++ 5 :: ...
```

with `P` a list of raw source bits `0/1`.  The audit proves

```coq
audit_left_output_not_zero_buffer_frame :
  forall P B,
    Forall (fun x => x = 0 \/ x = 1) P ->
    P ++ 6 :: book_buf B ++ 5 :: [3;4;0;1;0;0]
    <> [6;1;0;5;3;4;0;1;0;0].

audit_left_cycle_output_not_zero_buffer :
  forall P B,
    Forall (fun x => x = 0 \/ x = 1) P ->
    P ++ 6 :: book_buf B ++ 5 :: [3;4;0;1;0;0]
    <> rev (t_left (c_tape audit_output)) ++
       t_right (c_tape audit_output).
```

So the current left-cycle output is a correct literal table execution,
but it is **not** a zero-buffer frame and has no `book_buf` preimage when
the source write bit is `true`.  With `b` denoting the q6 buffer (the
number of cells strictly right of the old head), the correct accounting
is

```text
q6 buffer:    b -> b+1
q5 parameter: b+1 -> b+2
raw buffer:   w :: 0^b   (length b+1)
```

not `b`, not `b-1`, and not `0^(b+1)` unless `w = false`.  (The q5
parameter is one larger than the q6 buffer because the q5 steady frame
reserves the cell immediately left of `6` as `w_tape`.)

The general frame identity is also checked:

```coq
book_left_output_source_frame :
  dir_head :: dir_remaining = book_return_rail init b ->
  rev (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
  = rev outer ++ 6 :: source_bit w :: book_buf b ++
    5 :: map source_bit init.
```

The existing `book_q13_perform_left_clock` / `book_left_clock` use
`book_buf (b-1)` only as the **input** tbuffer of the restore/perform
phase.  Reusing that number as the post-state buffer is wrong by two for
the concrete `b = 1` instance (`b-1 = 0`, actual `b+1 = 2`).

## 5. Which existing book theorems can be reused

| Phase | Reuse point | Caveat |
| --- | --- | --- |
| initial q5 | `book_q5_scan_general` (`MinskyBookLocate.v`), `book_initial_q5_to_locate_state` (`MinskyBookEncode.v`) | `book_q5_scan_general` already takes an arbitrary `tbuffer : list nat`; only `book_initial_frame` names a `buf : nat` |
| q5 steady to locate | `book_q5_steady_to_locate_state_gen` (`MinskyBookLocateCycle.v`) | standard zero-buffer frame only; use `book_locate_state_wide` for the left output |
| locate hit | `book_locate_by_computation_from_q5_to_q6` (`MinskyBookLocateLookup.v`) | q5 buffer `b -> q6 buffer b-1` |
| locate halt | `book_locate_by_computation_from_q5_to_halt` | no-match halt; `dispatch_halt_at_y` |
| right perform | `book_q6_to_q5_right` (`MinskyBookCycle.v`) | requires `1 <= b`; consumes the first raw cell as the new head; blank-case only |
| right full cycle | `book_steady_q5_locate_to_q5_right` (`MinskyBookLocateCycle.v`) | q5 parameter unchanged, next q6 buffer `b-1` |
| left perform | `book_q6_to_q5_left` (`MinskyBookLeftCycle.v`) | correct literal output `w :: 0^b`; **not** a zero-buffer frame |
| left full cycle | `book_steady_q5_locate_to_q5_left_gen` | same caveat; use the generalized left suffix locate |
| left generalized locate | `book_locate_state_wide`, `book_locate_rows_to_q6_wide` (`MinskyBookLocateWide.v`) | accepts an arbitrary left suffix; this is what makes the raw-buffer left output reusable |
| sentinel halts | `book_steady_q5_locate_perform_right_sentinel_halt`, `..._left_sentinel_halt` (`MinskyBookLocateCycle.v`) | halt-path composition; check the left buffer suffix |

The one missing native phase is the **boundary-right halt**.  All other
phases are already kernel-checked; the new file supplies the abstract
source model and the conditional equivalence that the encoder must
instantiate.

## 6. Relation to the ledger's 46,176-step counterexample

The ledger's p=5 always-right program has a two-sided source run that
never halts, while the literal book table halts after 46,176 steps at
q3/Y.  The new left-infinite model halts at the first right move from
`R`; for the abstract all-zero tape with `R = 2` and initial head `0`,
the file proves

```coq
left_infinite_always_right_halts_at_boundary :
  lic_halted (left_infinite_run 3 always_right_rows
    lic_always_right_start) = true.

wide_always_right_never_halts :
  forall n,
    wc_halted (wide_source_run n always_right_rows
      wide_always_right_start) = false.
```

Thus the new model is qualitatively consistent with the native halt
(buffer exhausted), while the two-sided model is not.  The 46,176 is the
native table's cost of reaching q3/Y, not a source-level step count; the
conditional theorem accounts for it in `macro_cost` and does not assume
the boundary trace is already proved.
