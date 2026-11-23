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

## 7. Raw-buffer generalization (new file, kernel-checked)

`formal/utm/MinskyBookRawBuffer.v` replaces the zero buffer
`book_buf b` by an arbitrary raw list `buf : list nat` of source cells
(0/1).  It compiles with Coq 8.20.1 and passes `coqchk`; no existing file
was edited.

### 7.1 Vocabulary

```coq
Definition raw_source_cell (s : nat) : Prop := s = 0 \/ s = 1.
Definition raw_source_buffer (buf : list nat) : Prop :=
  Forall raw_source_cell buf.

Definition book_return_rail_raw (init : list bool) (buf : list nat) : list nat :=
  rev (map source_bit init) ++ [5] ++ rev buf.

Definition book_q6_left_raw
    (bits : list bool) (buf ptape : list nat) : list nat :=
  4 :: rev (map source_bit bits) ++ 5 :: rev buf ++ 6 :: rev ptape.

Definition book_q5_raw
    (init : list bool) (buf : list nat) (w_tape : bool)
    (ptape : list nat) (w_read : bool) (rows : list book_row)
    (tail : list nat) : Config :=
  cfg_ml 5
    (rev (buf ++ [5] ++ map source_bit init) ++
     6 :: source_bit w_tape :: rev ptape)
    (match_mark w_read :: 4 :: book_raw_desc rows ++ 5 :: tail).
```

`buf` is the physical list of cells strictly to the right of `M = 6`.
In `book_q5_raw`, `w_tape` is the cell immediately to the left of `M`.

### 7.2 Raw locate

```coq
book_q5_steady_to_locate_state_raw_gen :
  rows <> [] ->
  run (S (length init))
    (book_q5_raw init buf w_tape ptape w_read rows tail)
  = book_locate_state_wide (init ++ [w_read]) [] rows
      (rev buf ++ 6 :: rev (ptape ++ [source_bit w_tape])) tail.

book_locate_by_computation_from_q5_to_q6_raw :
  rows <> [] ->
  book_first_match (init ++ [w_read]) rows = book_lookup_hit steps hit after ->
  run (S (length init) + (book_failures_clock [] steps +
       book_hit_clock (init ++ [w_read]) (map bf_row steps)))
    (book_q5_raw init buf w_tape ptape w_read rows tail)
  = entry_config 6
      (4 :: rev (map source_bit (init ++ [w_read])) ++
       5 :: (rev buf ++ 6 :: rev (ptape ++ [source_bit w_tape])))
      (...).

book_locate_rows_to_q12_raw :
  ... -> run (...)
    (book_locate_state_wide src failed (map bf_row steps ++ hit :: after)
       (rev buf ++ 6 :: rev ptape) tail)
  = cfg_ml (if br_dir hit then 12 else 13)
      (rev (map match_mark (br_action hit)) ++ 5 :: rev buf ++
       6 :: rev ptape)
      (...).
```

### 7.3 Raw right perform

```coq
book_q6_to_q12_raw :
  length bits = length (init ++ [w]) ->
  run (copy_all_clock bits (init ++ [w]) [] (map match_mark bits) +
       direction_clock ...)
    (entry_config 6 (book_q6_left_raw bits buf ptape) (...)) =
  cfg_ml (if dir then 12 else 13)
    (rev (map match_mark (init ++ [w])) ++ 5 :: rev buf ++
     6 :: rev ptape)
    (...).
```

```coq
book_q6_to_q5_right_raw :
  length bits = length (init ++ [w]) ->
  buf <> [] ->
  raw_source_buffer buf ->
  Forall q15_pass (book_q15_rail bits init w 3 desc_tail) ->
  Forall q16_pass (rev (book_q15_rail bits init w 3 desc_tail) ++ [4]) ->
  run (book_right_clock_raw bits init w buf desc_tail)
    (entry_config 6 (book_q6_left_raw bits buf ptape) (...)) =
  cfg_ml 5
    (rev (tl buf ++ [5] ++ map source_bit init) ++
     6 :: source_bit w :: rev ptape)
    (match_mark (raw_to_bool (hd 0 buf)) :: 4 ::
     map q16_restore (book_q15_rail bits init w 3 desc_tail) ++
     source_bit trailing :: tail).
```

Exact update: the new head is the old `hd 0 buf`, the new q5 buffer is
`tl buf`, the new `w_tape` is the write bit `w` (the old head cell, now
immediately left of the new `M`), the new `ptape` is the old `ptape`,
and the new read mark is `match_mark (raw_to_bool (hd 0 buf))`.

### 7.4 Raw left perform

```coq
book_q6_to_q5_left_raw :
  length bits = length (init ++ [w]) ->
  raw_source_buffer buf ->
  rev ptape = source_bit target :: outer ->
  dir_head :: dir_remaining = book_return_rail_raw init buf ->
  (map match_mark bits ++ map match_mark (init ++ [w])) ++
    [2] ++ desc_tail ++ source_bit trailing :: tail =
    rev tags ++ source_bit trailing :: tail ->
  Forall q15_pass (rev tags) ->
  Forall q16_pass (tags ++ [4]) ->
  run (book_left_clock_raw bits init w buf desc_tail tags
         dir_head dir_remaining) (...)
  = cfg_ml 5
      (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++ 6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit trailing :: tail).
```

The physical source side is

```text
rev outer ++ 6 :: source_bit w :: buf ++ 5 :: map source_bit init
```

so the new buffer is exactly `source_bit w :: buf` (the write bit
prepended), and the new read bit is `target`, the old content of the new
head cell.  If `ptape = ptape_prefix ++ [source_bit target]`, then the
new `M` replaces the target cell; the new `w_tape` is the last cell of
`ptape_prefix` (or an implicit blank if `ptape_prefix = []`), the new
`ptape` is `ptape_prefix`, and the normalized q5 frame is
`book_q5_raw init (source_bit w :: buf) w_tape ptape_prefix target ...`.
The raw theorem's physical list records exactly this; the composed left
cycle below keeps the `ptape` prefix and exposes `source_bit hit_w :: buf`.
The general physical identity is also checked:

```coq
book_left_raw_physical :
  dir_head :: dir_remaining = book_return_rail_raw init buf ->
  rev (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
  = rev outer ++ 6 :: source_bit w :: buf ++
    5 :: map source_bit init.
```

### 7.5 Composed raw cycles

```coq
book_steady_q5_locate_to_q5_right_raw_gen :
  buf <> [] -> raw_source_buffer buf -> ... ->
  run (book_steady_locate_q12_clock_gen ... +
       book_q12_perform_right_clock_raw hit_init hit_w buf ...)
    (book_q5_raw init buf w_tape ptape w_read ...)
  = cfg_ml 5
      (rev (tl buf ++ [5] ++ map source_bit hit_init) ++
       6 :: source_bit hit_w :: rev (ptape ++ [source_bit w_tape]))
      (match_mark (raw_to_bool (hd 0 buf)) :: 4 :: ...).

book_steady_q5_locate_to_q5_left_raw_gen :
  raw_source_buffer buf -> ... ->
  run (book_steady_locate_q12_clock_gen ... +
       book_q13_perform_left_clock_raw hit_init hit_w buf ...)
    (book_q5_raw init buf w_tape ptape w_read ...)
  = cfg_ml 5
      (rev (source_bit hit_w :: rev (book_return_rail_raw hit_init buf)) ++
       6 :: rev ptape)
      ((if w_tape then 3 else 2) :: ...).
```

Both are q5 -> q5 over one matched row.  The right cycle consumes
`hd buf`; the left cycle prepends `hit_w`.

### 7.6 Passability and the q19/q20 question

Proved for raw 0/1 cells:

```coq
raw_source_cell_q12, raw_source_cell_q14,
raw_source_cell_q17, raw_source_cell_q21,
Forall_raw_q12, Forall_raw_q14,
Forall_raw_q17, Forall_raw_q21,
Forall_raw_*_rev, Forall_raw_rev_source_bits_q21.
```

Raw 0/1 cells are **not** q15/q16 passable:

```coq
raw_source_cell_not_q15, raw_source_cell_not_q16.
```

That is correct: q15/q16 are the marked description rail, not the
buffer.  The raw buffer enters only the q12/q14 scans and the q21/q17
return rails.  The q19 target is always the *first* raw buffer cell, so
`scanned = []` is still correct; only its bit value changes, and
`q19_to_q5_relocation` is already stated for an arbitrary `bit`.  Hence
**no new nonempty-scan q19/q20 variant is needed** for a nonblank first
buffer cell.  For the left cycle, q20's target is the last pseudo-tape
cell, not a buffer cell; the prepended write bit is scanned by the
q17/q18 return over `source_bit hit_w :: rev dirs`, which is
q17-passable because raw 0/1 and 5 pass q17.  The q15/q16 obligations are discharged on the marked description rail
by the existing `Forall_q15_cycle_rail` and
`Forall_q16_cycle_tags_snoc`; raw buffer cells never enter that rail.
The perform cores
`book_q12_restore_to_q5_right` and `book_q13_restore_to_q5_left` were
already stated for an arbitrary `tbuffer : list nat`; the new work is
the q6 frame and the passability/frame equations, not a new table trace.
The concrete theorem `raw_right_sanity` (below) exercises exactly the
nonblank first cell with `buf = [1;0]`.

### 7.7 Boundary: `buf = []`

```coq
empty_buffer_no_raw_target :
  ~ (exists bit between,
      rev (book_return_rail_raw init []) = source_bit bit :: between).

q19_crosses_y :
  step (entry_config 19 left (5 :: rest)) =
  entry_config 19 (5 :: left) rest.

q19_empty_buffer_captures_first_raw :
  run 2 (entry_config 19 left (5 :: source_bit i :: rest)) =
  entry_config (if i then 18 else 17) (6 :: 5 :: left) rest.

at_right_boundary (buf : list nat) (c : LeftInfiniteConfig) : Prop :=
  buf = [] /\ lic_head c = lic_R c.

at_right_boundary_right_move_halts :
  at_right_boundary buf c ->
  lic_halted c = false ->
  wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some row ->
  wr_right row = true ->
  lic_halted (left_infinite_step rows c) = true.
```

`empty_buffer_no_raw_target` is why the ordinary right-perform theorem
requires `buf <> []`: at `buf = []` there is no raw target, only `Y`.
`q19_crosses_y` and `q19_empty_buffer_captures_first_raw` show the native
table does not halt at `Y`; it passes it and captures the first raw
action bit.  The eventual q3/Y halt is the remaining trace obligation,
not a consequence of the raw perform lemmas.

### 7.8 Corrected global invariant and exact encoder premises

```coq
Definition raw_ptape (c : LeftInfiniteConfig) (lo : Z) : list nat :=
  map (fun k => source_bit (lic_tape c (lo + Z.of_nat k)))
      (seq 0 (Z.to_nat (lic_head c - lo))).

Definition raw_buf (c : LeftInfiniteConfig) : list nat :=
  map (fun k => source_bit (lic_tape c
                (lic_head c + 1 + Z.of_nat k)))
      (seq 0 (Z.to_nat (lic_R c - lic_head c))).

Definition book_global_source_rep
    (c : LeftInfiniteConfig) (lo : Z) (ptape buf : list nat) : Prop :=
  (lo <= lic_head c)%Z /\
  left_infinite_ok c /\
  ptape = raw_ptape c lo /\
  buf = raw_buf c.
```

Proved:

```coq
book_global_source_rep_buffer_length :
  book_global_source_rep c lo ptape buf ->
  length buf = Z.to_nat (lic_R c - lic_head c).

book_global_source_rep_buffer_nil :
  book_global_source_rep c lo ptape buf ->
  (buf = [] <-> lic_head c = lic_R c).

book_global_source_rep_boundary_right_halts :
  book_global_source_rep c lo ptape buf ->
  buf = [] ->
  lic_halted c = false ->
  wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some row ->
  wr_right row = true ->
  lic_halted (left_infinite_step rows c) = true.
```

The exact q6 encoder shape is

```coq
Definition lic_q6_encode
    (lo : Z) (c : LeftInfiniteConfig) (desc : list nat) : Config :=
  entry_config 6
    (4 :: rev (map source_bit
                 (lic_state c ++ [lic_tape c (lic_head c)])) ++
     5 :: rev (raw_buf c) ++
     6 :: rev (raw_ptape c lo))
    desc.
```

The concrete encoder obligations are therefore:

1. **Shape.**  For every running config there are `lo` and `desc` with
   `encode p rows c = lic_q6_encode lo c desc`, and the representation
   invariant is `book_global_source_rep c lo ptape (raw_buf c)`.
2. **Halt reflection.**  `c_halted (encode p rows c) = lic_halted c`.
3. **Cost positivity.**  `1 <= macro_cost p rows c`.
4. **Macro step.**  `run (macro_cost p rows c) (encode p rows c) =
   encode p rows (left_infinite_step rows c)`.

Premises 2-4 are exactly the section variables of
`conditional_left_source_native_halting_equivalence`.  The file also
exports the specialized wrapper

```coq
raw_q6_conditional_left_halting_equivalence :
  (forall p rows c, Forall (wide_row_wellformed p) rows ->
     c_halted (encode p rows c) = lic_halted c) ->
  (forall p rows c, Forall ... -> 1 <= macro_cost p rows c) ->
  (forall p rows c, Forall ... ->
     run (macro_cost p rows c) (encode p rows c) =
     encode p rows (left_infinite_step rows c)) ->
  forall p rows c, Forall ... ->
  (left_infinite_eventually_halts rows c <->
   left_native_eventually_halts encode p rows c).
```

The intended `macro_cost` is:

- locate: `book_steady_locate_q12_clock_gen` plus the hit/failure clocks;
- right move: `book_q12_perform_right_clock_raw`;
- left move: `book_q13_perform_left_clock_raw`;
- boundary `buf = []`: the q3/Y trace cost (still the exact gap).

### 7.9 Concrete sanity theorems

Right move into a nonblank first buffer cell:

```coq
raw_right_sanity :
  run (book_right_clock_raw [false] [] true [1;0] [5])
    (entry_config 6 (book_q6_left_raw [false] [1;0] [0;1])
       [2;1;1;5;0])
  = cfg_ml 5 [5;0;6;1;1;0]
      (3 :: 4 ::
       map q16_restore (book_q15_rail [false] [] true 3 [5]) ++ [0]).

raw_right_sanity_physical :
  physical tape = [0;1;1;6;0;5;3;4;0;1;1;5;0].

raw_right_sanity_buffer :
  exists P,
    physical tape =
    [0;1] ++ [1] ++ [6] ++ tl [1;0] ++ [5] ++ P.

raw_right_sanity_read :
  hd 0 (tl (t_right (c_tape raw_right_sanity_output))) = 3.
```

So `buf = [1;0]` is captured correctly: the target `1` becomes the new
read bit (mark `3`), and the new buffer is `[0] = tl [1;0]`.

Left move prepends the write bit:

```coq
raw_left_sanity :
  run (book_left_clock_raw [false] [] true [0;1] [] [2;3;2] 5 [1;0])
    (entry_config 6 (book_q6_left_raw [false] [0;1] [1])
       [2;1;0;0])
  = cfg_ml 5 [5;1;0;1;6]
      (3 :: map q16_restore (rev ([2;3;2] ++ [4])) ++ [0]).

raw_left_sanity_physical :
  physical tape = [6;1;0;1;5;3;4;0;1;0;0].

raw_left_sanity_buffer :
  exists P,
    physical tape =
    [6] ++ (source_bit true :: [0;1]) ++ [5] ++ P.
```

So the old buffer `[0;1]` becomes `[1;0;1] = source_bit true :: [0;1]`.

### 7.10 Remaining exact gap

The only native phase not yet generalized/proved is the **boundary-right
halt**: when `buf = []` and a right move is requested, the abstract
`left_infinite_step` halts in place, while the literal table passes `Y`
(`q19_crosses_y`) and then follows the q3/Y trace.  A total encoder must
prove, for every reachable `buf = []` frame and matched right-moving row,
that the literal table reaches a halted configuration in some
`boundary_cost`, and that its encode is the encode of the halted abstract
configuration.  The ledger's 46,176-step p=5 instance is the concrete
witness; no general theorem exists yet.
