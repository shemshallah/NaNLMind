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

### 7.10 Remaining exact gap (superseded by section 8)

The only native phase not yet generalized/proved in this zero-buffer
account is the **boundary-right halt**: when `buf = []` and a right move
is requested, the abstract `left_infinite_step` halts in place, while the
literal table passes `Y` (`q19_crosses_y`) and then follows the q3/Y
trace.  Section 8 avoids this trace by always encoding one extra
sentinel blank cell beyond `R` and using the existing sentinel-halt
theorem.  The remaining sentinel-side gap is the running-case encoder
representation, not the boundary run equation.

## 8. Sentinel boundary (new file, kernel-checked)

`formal/utm/MinskyLeftInfiniteSentinel.v` implements the sentinel-cell
approach: always encode one extra blank cell beyond `R`, and let the
boundary right move consume it and halt.  It compiles with Coq 8.20.1 and
passes `coqchk`; no existing file was edited.

This avoids the q3/Y trace entirely.  The native boundary macro is a
direct corollary of the existing

```coq
book_steady_q5_locate_perform_right_sentinel_halt_gen
```

with `b = 2`: the q5 input buffer is `tl (book_buf 2) = [0]`, the one
sentinel blank.  The right perform consumes it, the new condition is
`hit_init ++ [false]`, the sentinel description row mismatches at bit 0,
and the machine reaches `dispatch_halt_at_y`.

### 8.1 The sentinel step

```coq
Definition source_blank_at (t : Z -> bool) (h : Z) : Z -> bool :=
  fun z => if Z.eqb z h then false else t z.

Definition left_infinite_step_sentinel
    (rows : list WideSourceRow) (c : LeftInfiniteConfig)
    : LeftInfiniteConfig :=
  if lic_halted c then c else
  match wide_source_lookup rows (lic_state c)
                          (lic_tape c (lic_head c)) with
  | None => (* halt as before *) ...
  | Some row =>
      if left_infinite_right_blocked c row then
        {| lic_state := wr_next row;
           lic_head := (lic_head c + 1)%Z;
           lic_tape := source_blank_at
             (source_write_at (lic_tape c) (lic_head c) (wr_write row))
             (lic_head c + 1)%Z;
           lic_R := (lic_R c + 1)%Z;
           lic_halted := true |}
      else (* normal step *) ...
  end.
```

Proved:

```coq
left_infinite_step_sentinel_halted
left_infinite_step_sentinel_boundary_fields
left_infinite_step_sentinel_boundary_blank
left_infinite_step_sentinel_boundary_head_eq_R
left_infinite_step_sentinel_ok
sentinel_boundary_step_halts :
  ... blocked right row ... ->
  lic_halted (left_infinite_step_sentinel rows c) = true /\
  lic_head (left_infinite_step_sentinel rows c) = head c + 1 /\
  lic_R (left_infinite_step_sentinel rows c) = R c + 1 /\
  lic_tape (left_infinite_step_sentinel rows c) (head c + 1) = false.
```

So the final source head is `R+1`, the new `R` is `R+1`, the new head
cell is blank, and `halted = true`.

### 8.2 Sentinel-augmented invariant

```coq
Definition raw_buf_sentinel (c : LeftInfiniteConfig) : list nat :=
  raw_buf c ++ [0].

Definition book_global_source_rep_sentinel
    (c : LeftInfiniteConfig) (lo : Z) (ptape buf : list nat) : Prop :=
  (lo <= lic_head c)%Z /\
  left_infinite_ok c /\
  ptape = raw_ptape c lo /\
  buf = raw_buf_sentinel c.
```

Proved:

```coq
raw_buf_sentinel_length :
  left_infinite_ok c ->
  length (raw_buf_sentinel c) =
  S (Z.to_nat (lic_R c - lic_head c)).

raw_buf_sentinel_at_boundary :
  lic_head c = lic_R c -> raw_buf_sentinel c = [0].

book_global_source_rep_sentinel_boundary :
  book_global_source_rep_sentinel c lo ptape buf ->
  (buf = [0] <-> lic_head c = lic_R c).

book_global_source_rep_sentinel_buffer_length.
```

So a boundary config is exactly the one whose encoded raw buffer is the
single sentinel `[0]`.

### 8.3 Boundary macro step and encoder

```coq
Definition boundary_sentinel_sf (hit_init creast : list bool) : book_failure :=
  book_sentinel_failure (hit_init ++ [false]) creast
    (app_singleton_bool_neq_nil hit_init false).

Definition boundary_sentinel_pre_frame ... : Config :=
  cfg_ml 5
    (rev (tl (book_buf 2) ++ [5] ++ map source_bit init) ++
     6 :: source_bit w_tape :: rev ptape)
    (match_mark w_read :: 4 ::
     book_raw_desc
       (map bf_row steps ++ hit ::
        [book_sentinel_row (hit_init ++ [false]) creast]) ++
     5 :: tail).

Definition boundary_sentinel_halt_frame ... : Config :=
  dispatch_halt_at_y
    (book_sentinel_halt_left retry_steps
       (boundary_sentinel_sf hit_init creast)
       0 (ptape ++ [source_bit w_tape] ++ [source_bit hit_w]) tail) tail.

Definition boundary_right_sentinel_cost
    (init : list bool) (w_read w_tape : bool)
    (steps : list book_failure) (hit : book_row)
    (hit_init : list bool) (hit_w : bool)
    (retry_steps : list book_failure) (creast : list bool) : nat :=
  book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
  book_q12_perform_right_clock hit_init hit_w 2
    (book_cycle_tags steps (init ++ [w_read]) hit)
    (tl (book_buf (2 - 1)) ++ [5] ++ map source_bit hit_init) +
  (S (length hit_init) +
   (book_failures_clock [] retry_steps +
    book_halt_clock (map bf_row retry_steps)
      (boundary_sentinel_sf hit_init creast))).
```

The sentinel row's mismatch is explicit:

```coq
boundary_sentinel_row_mismatch :
  br_cond (book_sentinel_row (hit_init ++ [false]) creast) <>
  hit_init ++ [false].
```

The exact boundary theorem:

```coq
Theorem boundary_right_sentinel_macro_step :
  forall init w_read w_tape ptape tail steps hit hit_init hit_w creast
         retry_steps,
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    Forall (fun st => bf_src st = hit_init ++ [false]) retry_steps ->
    map bf_row (retry_steps ++ [boundary_sentinel_sf hit_init creast]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [false]) creast] ->
    run (boundary_right_sentinel_cost init w_read w_tape steps hit
           hit_init hit_w retry_steps creast)
      (boundary_sentinel_pre_frame init w_read w_tape ptape tail
        steps hit hit_init creast) =
    boundary_sentinel_halt_frame ptape w_tape hit_w tail retry_steps
      hit_init creast.
```

Halt reflection:

```coq
Definition encode_sentinel
    (pre halt : LeftInfiniteConfig -> Config)
    (c : LeftInfiniteConfig) : Config :=
  if lic_halted c then halt c else pre c.

Lemma encode_sentinel_reflects_halt :
  (forall c, lic_halted c = false -> c_halted (pre c) = false) ->
  (forall c, c_halted (halt c) = true) ->
  c_halted (encode_sentinel pre halt c) = lic_halted c.

Corollary encode_sentinel_halt_frame_reflects :
  ... ->
  c_halted (encode_sentinel pre
    (fun _ => boundary_sentinel_halt_frame ...) c) = lic_halted c.
```

The halted branch is exactly the `dispatch_halt_at_y` frame, so
`c_halted` is `true`.

### 8.4 Concrete p=1 full boundary macro

```coq
Definition p1_start : LeftInfiniteConfig := ...
Definition p1_row : WideSourceRow := ...
Definition p1_encode_running : Config := ...
Definition p1_encode_halted : Config := ...
Definition p1_encode (c : LeftInfiniteConfig) : Config :=
  if lic_halted c then p1_encode_halted else p1_encode_running.

Example p1_encode_reflects_halt :
  forall c, c_halted (p1_encode c) = lic_halted c.

Example p1_boundary_step_fields :
  lic_halted (left_infinite_step_sentinel [p1_row] p1_start) = true /\
  lic_head  ... = 1%Z /\
  lic_R     ... = 1%Z /\
  lic_tape  ... 1%Z = false.

Example p1_boundary_macro :
  run (boundary_right_sentinel_cost [false] false false [] p1_hit
         [true] false [p1_retry_failure] [])
      (p1_encode p1_start) =
  p1_encode (left_infinite_step_sentinel [p1_row] p1_start).
```

All are `Closed under the global context`.

### 8.5 Remaining exact gap: running-case encoder representation

The frame-level boundary macro step is complete.  A total encoder still
has to prove the running-case representation connection:

For every reachable boundary configuration `c` with `raw_buf_sentinel c
= [0]` and a matched right-moving row, there must be witnesses

```text
init, w_read, w_tape, ptape, tail,
steps, hit, hit_init, hit_w, creast, retry_steps
```

such that

1. `encode p rows c = boundary_sentinel_pre_frame ...`;
2. the description is the actual source program followed by the sentinel
   row: the seventh hypothesis
   ```coq
   map bf_row (retry_steps ++ [boundary_sentinel_sf hit_init creast]) =
   map bf_row steps ++ hit ::
     [book_sentinel_row (hit_init ++ [false]) creast];
   ```
3. `hit` is the row matching the current condition and its action is
   `hit_init ++ [hit_w]`;
4. `retry_steps` are the locate failures for the new condition
   `hit_init ++ [false]`;
5. `encode p rows (left_infinite_step_sentinel rows c)` is
   `boundary_sentinel_halt_frame ...`.

Condition 2 is the first exact blocking goal: it is the computable
lookup-witness decomposition

```coq
map bf_row (retry_steps ++ [boundary_sentinel_sf hit_init creast]) =
map bf_row steps ++ hit ::
  [book_sentinel_row (hit_init ++ [false]) creast]
```

for the actual program and the new condition.  It is a finite lookup
computation (`book_first_match` gives the witnesses), not a 46k-step
table trace.  The p=1 example shows the concrete witness shape; the
remaining work is to package the general `book_first_match`-to-
`boundary_sentinel_pre_frame` adapter and the halt-frame equality.

### 8.6 Fresh sentinel state: removing the real-row match obstruction

The first sentinel step kept the performed row's next state.  A real row
with that state and read bit `0` could then match the new condition, so
the native locate phase would execute it instead of halting.  This was
the first blocking invariant.

The fresh variant removes it:

```coq
Definition sentinel_state (p : nat) : list bool :=
  repeat false (S p).

Lemma sentinel_state_length :
  forall p, length (sentinel_state p) = S p.

Lemma sentinel_state_neq_current :
  wide_row_wellformed p r -> wr_current r <> sentinel_state p.

Lemma sentinel_state_no_match_row :
  wide_row_wellformed p r ->
  wide_row_matches r (sentinel_state p) bit = false.

Lemma sentinel_state_no_match :
  Forall (wide_row_wellformed p) rows ->
  wide_source_lookup rows (sentinel_state p) bit = None.
```

The boundary step variant is

```coq
Definition left_infinite_step_sentinel_fresh
    (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig)
    : LeftInfiniteConfig :=
  ... boundary case:
    lic_state := sentinel_state p;
    lic_head := head c + 1;
    lic_tape := source_blank_at (source_write_at ...) (head c + 1);
    lic_R := R c + 1;
    lic_halted := true.
```

Proved:

```coq
left_infinite_step_sentinel_fresh_halted
left_infinite_step_sentinel_fresh_boundary_fields
left_infinite_step_sentinel_fresh_boundary_blank
left_infinite_step_sentinel_fresh_boundary_head_eq_R
left_infinite_step_sentinel_fresh_ok

fresh_boundary_new_condition_no_match :
  Forall (wide_row_wellformed p) rows ->
  lic_halted c = false ->
  wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some row ->
  left_infinite_right_blocked c row = true ->
  wide_source_lookup rows
    (lic_state (left_infinite_step_sentinel_fresh p rows c))
    (lic_tape (left_infinite_step_sentinel_fresh p rows c)
       (lic_head (left_infinite_step_sentinel_fresh p rows c))) = None.
```

Because the new state has width `p+1` and all program rows have width
`p`, the new condition `sentinel_state p ++ [false]` cannot match any
real row.  The locate phase therefore fails on every real row by the
length check and must reach the description sentinel row.

This is the version to use for a total encoder.  The remaining gap is
now only the computable lookup-witness packaging:

```coq
book_first_match (sentinel_state p ++ [false])
  (source_rows_to_book rows ++ [book_sentinel_row (sentinel_state p ++ [false]) creast])
= book_lookup_halt retry_steps last
```

and the resulting equality

```coq
map bf_row
  (retry_steps ++ [book_sentinel_failure (sentinel_state p ++ [false]) creast ...])
=
map bf_row steps ++ hit ::
  [book_sentinel_row (sentinel_state p ++ [false]) creast]
```

needed by `boundary_right_sentinel_macro_step` with
`hit_init = sentinel_state p`.  `sentinel_state_no_match` guarantees the
lookup-failure side is true; the packaging is finite computation over
the row list, not a table trace.  The concrete p=1 instance
`p1_boundary_macro` is the executed witness of this shape.

## 9. Iteration frames and the q5 encoder (new file, kernel-checked)

`formal/utm/MinskyLeftInfiniteEncode.v` closes the frame equalities that
turn the raw cycle outputs into the next `book_q5_raw` frame, defines
`lic_q5_encode`, and proves a concrete non-boundary right-hit macro step.
It compiles with Coq 8.20.1 and passes `coqchk`; no existing file was
edited.

### 9.1 Restored-rail algebra

```coq
book_cycle_restored_raw_desc :
  br_cond hit = bits ->
  br_cond next = c0 :: creast ->
  map q16_restore (rev (book_cycle_tags steps bits hit)) ++
    source_bit c0 :: book_after_suffix creast next rest
  = book_raw_desc (map bf_row steps ++ hit :: next :: rest).

book_cycle_restored_raw_desc_tail :
  ... ->
  map q16_restore (rev (book_cycle_tags steps bits hit)) ++
    source_bit c0 :: (book_after_suffix creast next rest ++ tail)
  = book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++ tail.

book_cycle_restored_raw_desc_left :
  ... ->
  map q16_restore (rev (book_cycle_tags steps bits hit ++ [4])) ++
    source_bit c0 :: (book_after_suffix creast next rest ++ tail)
  = 4 :: (book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++ tail).
```

Supporting lemmas: `map_q16_restore_marked_prefix`,
`map_q16_restore_cycle_region`, `book_raw_desc_append_rows`,
`book_raw_desc_nil_prefix`.

### 9.2 Frame equalities

Right:

```coq
book_q5_raw_right_frame_eq :
  br_cond hit = init ++ [w_read] ->
  br_action hit = hit_init ++ [hit_w] ->
  br_cond next = c0 :: creast ->
  book_q5_raw hit_init (tl buf) hit_w
    (ptape ++ [source_bit w_tape])
    (raw_to_bool (hd 0 buf))
    (map bf_row steps ++ hit :: next :: rest) tail
  = cfg_ml 5
      (rev (tl buf ++ [5] ++ map source_bit hit_init) ++
       6 :: source_bit hit_w :: rev (ptape ++ [source_bit w_tape]))
      (match_mark (raw_to_bool (hd 0 buf)) :: 4 ::
       map q16_restore
         (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ++
       source_bit c0 :: book_after_suffix creast next rest ++ 5 :: tail).
```

This is the exact right raw cycle output of
`book_steady_q5_locate_to_q5_right_raw_gen`, with the next `book_q5_raw`
frame on the left: new buffer `tl buf`, new `w_tape = hit_w`, new ptape
`ptape ++ [source_bit w_tape]`, new read bit
`raw_to_bool (hd 0 buf)`, and full row list
`map bf_row steps ++ hit :: next :: rest`.

Left:

```coq
book_q5_raw_left_frame_eq :
  br_cond hit = init ++ [w_read] ->
  br_action hit = hit_init ++ [hit_w] ->
  br_cond next = c0 :: creast ->
  book_q5_raw init (source_bit hit_w :: buf) w_tape
    ptape_prefix w_tape
    (map bf_row steps ++ hit :: next :: rest) tail
  = cfg_ml 5
      (rev (source_bit hit_w :: rev (book_return_rail_raw init buf)) ++
       6 :: rev (ptape_prefix ++ [source_bit w_tape]))
      (match_mark w_tape :: 4 ::
       map q16_restore
         (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ++
       source_bit c0 :: book_after_suffix creast next rest ++ 5 :: tail).
```

The right-tape equality is also exported as
`book_q5_raw_left_right_tape`.  The left frame has new buffer
`source_bit hit_w :: buf`, new `w_tape = w_tape` (the last cell of the
input ptape), and new read bit `w_tape`.

### 9.3 The q5 encoder

```coq
Definition raw_ptape_prefix (c) (lo) : list nat := ...
Definition raw_last (c) (lo) : bool := ...

Definition lic_q5_encode
    (lo : Z) (c : LeftInfiniteConfig) (rows : list book_row)
    (tail : list nat) : Config :=
  book_q5_raw (lic_state c) (raw_buf c) (raw_last c lo)
    (raw_ptape_prefix c lo) (lic_tape c (lic_head c)) rows tail.

Lemma lic_q5_encode_is_book_q5_raw.
```

Representation:

```coq
Definition book_q5_source_rep (c) (lo) (ptape) (w_tape) (buf) : Prop :=
  (lo < lic_head c)%Z /\
  left_infinite_ok c /\
  ptape ++ [source_bit w_tape] = raw_ptape c lo /\
  buf = raw_buf c.

lic_q5_encode_rep :
  (lo < lic_head c)%Z -> left_infinite_ok c ->
  book_q5_source_rep c lo (raw_ptape_prefix c lo)
    (raw_last c lo) (raw_buf c).

lic_q5_encode_rep_global :
  (lo < lic_head c)%Z -> left_infinite_ok c ->
  book_global_source_rep c lo (raw_ptape c lo) (raw_buf c).
```

`raw_ptape_nonempty` and `raw_ptape_prefix_last` prove the split
`raw_ptape c lo = raw_ptape_prefix c lo ++
 [source_bit (raw_last c lo)]` when `lo < head`.  The hypothesis
`lo < head` is essential: at `lo = head` the q5 frame needs an implicit
blank cell to the left of `M`, which is the left-boundary case.

### 9.4 Concrete non-boundary right-hit instance

```coq
p1r_r1, p1r_r2 : WideSourceRow
p1r_rows = [p1r_r1; p1r_r2]
p1r_book_rows = source_rows_to_book p1r_rows
p1r_start = {| state = [false]; head = 0; tape = fun _ => false;
               R = 2; halted = false |}

p1r_first_match :
  book_first_match ([false] ++ [false]) p1r_book_rows =
  book_lookup_hit [] (source_row_to_book p1r_r1)
    [source_row_to_book p1r_r2].

p1r_start_encode :
  lic_q5_encode (-1) p1r_start p1r_book_rows [] =
  book_q5_raw [false] [0;0] false [] false p1r_book_rows [].

p1r_right_hit_macro :
  run (book_steady_locate_q12_clock_gen [false] false false []
         (source_row_to_book p1r_r1) +
       book_q12_perform_right_clock_raw [false] false [0;0]
         (book_cycle_tags [] ([false] ++ [false])
            (source_row_to_book p1r_r1))
         (tl [0;0] ++ [5] ++ map source_bit [false]))
      (lic_q5_encode (-1) p1r_start p1r_book_rows []) =
  lic_q5_encode (-1) (left_infinite_step p1r_rows p1r_start)
    p1r_book_rows [].
```

This is the full non-boundary right-hit macro for p=1: the buffer
`[0;0]` becomes `[0]`, the ptape becomes `[0]`, `w_tape` is the write
bit `false`, and the new read bit is `false`.

### 9.5 First remaining gap: general step-to-window mapping

The frame equalities and the encoder are complete.  The general
non-boundary right-hit macro needs the following mapping lemmas, which
are the first exact gap:

```coq
raw_buf_right_step :
  wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
  wr_right r = true ->
  lic_head c < lic_R c ->
  raw_buf (left_infinite_step rows c) = tl (raw_buf c).

raw_ptape_right_step :
  ... ->
  lo <= lic_head c ->
  raw_ptape (left_infinite_step rows c) lo =
  raw_ptape c lo ++ [source_bit (wr_write r)].

raw_ptape_prefix_right_step :
  ... ->
  raw_ptape_prefix (left_infinite_step rows c) lo =
  raw_ptape c lo.

raw_last_right_step :
  ... ->
  raw_last (left_infinite_step rows c) lo = wr_write r.

raw_read_right_step :
  ... ->
  lic_tape (left_infinite_step rows c) (lic_head c + 1) =
  raw_to_bool (hd 0 (raw_buf c)).
```

These are `seq`/`Z.to_nat` arithmetic identities, not table traces.
`raw_buf_right_step` is the first blocking one: it is the list identity

```text
  map (fun k => tape (head + 1 + k)) (seq 0 (R - head))
= tail (map (fun k => tape (head + 1 + k))
          (seq 0 (R - head)))
```

under `head < R`, i.e. `Z.to_nat (R - head) =
S (Z.to_nat (R - (head+1)))`.  The analogous left-step package is

```coq
raw_buf_left_step :
  ... ->
  raw_buf (left_infinite_step rows c) = source_bit (wr_write r) :: raw_buf c.
```

and the left ptape prefix drops its last cell.

The second gap is the source-lookup/book-first-match correspondence:

```coq
wide_source_lookup rows state bit = Some r
<->
book_first_match (state ++ [bit]) (source_rows_to_book rows) =
  book_lookup_hit steps (source_row_to_book r) after
```

with the failure witnesses.  `p1r_first_match` is the concrete p=1
instance; the general compiler is the remaining lookup packaging.

Boundary and halt cases are treated separately:

- boundary right: `MinskyLeftInfiniteSentinel.v`,
  `left_infinite_step_sentinel` / `_fresh`, and
  `boundary_right_sentinel_macro_step`;
- lookup failure: `left_infinite_step` halts, so the encoder must use a
  halted frame (the `encode_sentinel`/`wide_encode_halt` pattern);
- left move: the left frame equality is proved, but the left
  step-to-window mapping package is the analogue of the right gap.

## 10. Window arithmetic (new file, kernel-checked)

`formal/utm/MinskyLeftInfiniteWindow.v` proves the right-step window
mapping and the left buffer update.  It compiles with Coq 8.20.1 and
passes `coqchk`.

### 10.1 Right step (`head < R`, `wr_right r = true`)

```coq
raw_buf_right_step :
  lic_halted c = false ->
  wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
  wr_right r = true ->
  lic_head c < lic_R c ->
  raw_buf (left_infinite_step rows c) = tl (raw_buf c).

raw_ptape_right_step :
  ... -> lo <= lic_head c ->
  raw_ptape (left_infinite_step rows c) lo =
  raw_ptape c lo ++ [source_bit (wr_write r)].

raw_ptape_prefix_right_step :
  ... -> lo <= lic_head c ->
  raw_ptape_prefix (left_infinite_step rows c) lo = raw_ptape c lo.

raw_last_right_step :
  ... -> lo <= lic_head c ->
  raw_last (left_infinite_step rows c) lo = wr_write r.

raw_read_right_step :
  ... ->
  lic_tape (left_infinite_step rows c) (lic_head c + 1) =
  raw_to_bool (hd 0 (raw_buf c)).
```

Supporting lemmas: `tail_map_seq`, `map_seq_snoc`,
`Z_to_nat_sub_succ`, `Z_to_nat_succ_sub`, `Z_to_nat_add_one`,
`raw_buf_nonempty`, `raw_buf_hd`, `source_write_at_below`,
`raw_to_bool_source_bit_bool`.

### 10.2 Left buffer

```coq
raw_buf_left_step :
  lic_halted c = false ->
  wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
  wr_right r = false ->
  lic_head c <= lic_R c ->
  raw_buf (left_infinite_step rows c) =
  source_bit (wr_write r) :: raw_buf c.
```

This is the exact left buffer prepend.

### 10.3 Remaining left ptape package

Not yet proved:

```coq
raw_ptape_left_step :
  ... -> lo <= lic_head c ->
  raw_ptape (left_infinite_step rows c) lo = raw_ptape_prefix c lo.

raw_ptape_prefix_left_step :
  ... -> raw_ptape_prefix (left_infinite_step rows c) lo =
           (drop-last of raw_ptape_prefix c lo).

raw_last_left_step :
  ... -> raw_last (left_infinite_step rows c) lo = ...
```

The first blocking case is `raw_ptape_left_step`; it needs the
`seq`/`Z.to_nat` identity for the left window `head - 1 - lo`, plus the
`removelast`/`rev` list identity.  The right package and the left buffer
are closed.

## 11. Row-match/lookup progress (new file, kernel-checked)

`formal/utm/MinskyLeftInfiniteLookup.v` proves the pointwise source/book
match equivalence:

```coq
source_row_to_book_matches :
  wide_row_matches r state bit =
  book_row_matches (state ++ [bit]) (source_row_to_book r).
```

and extracts a source hit from a book hit:

```coq
book_first_match_hit_is_source_row :
  book_first_match (state ++ [bit]) (source_rows_to_book rows) =
  book_lookup_hit steps hit after ->
  exists r,
    In r rows /\
    hit = source_row_to_book r /\
    wide_row_matches r state bit = true.
```

Supporting lemmas: `app_singleton_inj`, `app_singleton_neq`,
`book_mismatch_ev_some_of_neq`.

### 11.1 Remaining exact lookup gap

The full first-match correspondence is not yet packaged:

```coq
wide_source_lookup rows state bit = Some r
<->
exists steps hit after,
  book_first_match (state ++ [bit]) (source_rows_to_book rows) =
    book_lookup_hit steps hit after /\
  hit = source_row_to_book r /\
  source_rows_to_book rows = map bf_row steps ++ hit :: after /\
  Forall (fun st => bf_src st = state ++ [bit]) steps
```

and the None/halt analogue with `book_lookup_halt steps last` and the
failure witnesses.  The pointwise match equivalence and the hit
extraction are proved; the remaining work is the prefix-order/failure
witness packaging (the first exact goal).  `p1r_first_match` in
`MinskyLeftInfiniteEncode.v` is the concrete p=1 witness.

## 12. General macro composition status

The frame equalities (`book_q5_raw_right_frame_eq`,
`book_q5_raw_left_frame_eq`), the encoder (`lic_q5_encode`,
`lic_q5_encode_rep`), the right window package, the left buffer update,
and the concrete p=1 right-hit macro (`p1r_right_hit_macro`) are
kernel-checked.

The general right-hit macro still needs the full lookup packaging of
section 11.1 and the left ptape package of section 10.3.  The general
left macro additionally needs the window update: for a left step, if
`lo < head - 1`, keep `lo`; if `lo = head - 1`, use `lo - 1` (one extra
blank cell to the left) so the new q5 ptape is nonempty.  The exact
remaining frame is:

```coq
raw_ptape_left_step :
  ... -> lo <= lic_head c ->
  raw_ptape (left_infinite_step rows c) lo = raw_ptape_prefix c lo.
```

Boundary/halt: `MinskyLeftInfiniteSentinel.v` proves
`left_infinite_step_sentinel_fresh`,
`fresh_boundary_new_condition_no_match`, and
`boundary_right_sentinel_macro_step`.  Connecting that halt frame to
`lic_q5_encode` is the remaining encoder frame; the sentinel theorem
already produces the exact `dispatch_halt_at_y` frame.

## 13. Concrete left-window check: the frame is correct

`formal/utm/MinskyLeftInfiniteLeftCheck.v` tests the exact configuration:

```text
head = 2, R = 2, lo = 0, tape all false, state = [false]
raw_ptape_prefix = [cell0], raw_last = cell1, raw_buf = []
```

with a left row writing `true` and next state `[false]`.  It compiles
with Coq 8.20.1 and passes `coqchk`.

### 13.1 Input and successor encodes

```coq
lg_input_encode :
  lic_q5_encode 0 lg_start (source_rows_to_book lg_rows) [] =
  book_q5_raw [false] [] false [0] false
    (source_rows_to_book lg_rows) [].

lg_successor_encode :
  lic_q5_encode 0 (left_infinite_step lg_rows lg_start)
    (source_rows_to_book lg_rows) [] =
  book_q5_raw [false] [1] false [] false
    (source_rows_to_book lg_rows) [].
```

The successor has buffer `[true]`, ptape `[]`, and `w_tape = cell0`.
The input q5 ptape is `[cell0]`, and the input q5 `w_tape` is `cell1`.

### 13.2 The frame instance

```coq
lg_left_frame :
  book_q5_raw [false] [1] false [] false
    (source_rows_to_book lg_rows) []
  = cfg_ml 5
      (rev (source_bit true ::
            rev (book_return_rail_raw [false] [])) ++
       6 :: rev ([] ++ [source_bit false]))
      (...).

lg_successor_matches_frame :
  lic_q5_encode 0 (left_infinite_step lg_rows lg_start)
    (source_rows_to_book lg_rows) [] =
  cfg_ml 5 ... .
```

So the left output frame **does** equal
`lic_q5_encode 0 (left_infinite_step lg_rows lg_start)` for this
instance.

### 13.3 Resolution of the apparent off-by-one

The apparent mismatch comes from reading the parameters of
`book_q5_raw_left_frame_eq` as if `ptape_prefix` were the *input* q5
ptape and `w_tape_left` were the *input* q5 `w_tape`.

In the lemma:

```coq
book_q5_raw init (source_bit hit_w :: buf) w_tape_left
  ptape_prefix w_read ...
```

the output q5 frame is `ptape_prefix` / `w_tape_left`.  The cycle
output's **input** q5 ptape appears as

```text
ptape_prefix ++ [source_bit w_tape_left]
```

in the physical tape.  For the input ptape `[cell0]`, the only correct
split is

```text
ptape_prefix = [],   w_tape_left = cell0.
```

The old q5 `w_tape` (cell1) is not the new `w_tape`; it is the new read
bit `w_read` (the content of the new head cell).  Thus the output is

```text
book_q5_raw [false] [true] false [] false rows tail,
```

exactly the successor encode.

Therefore the fix is **neither (a) nor (b)**: `lic_q5_encode` is already
correct for the left frame, and no left q5 normalization is needed.  The
remaining left one-step gap is the separate `raw_ptape_left_step` window
identity of section 10.3, not the frame equality.
