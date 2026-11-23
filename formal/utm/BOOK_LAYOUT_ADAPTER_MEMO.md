# Book-layout frame adapter for q6 -> q12 -> q15 -> q19 -> q5

Status: design memo.  No tracked file is edited.  The untracked
`MinskyBookLayout.v` already contains the key q15/q19 and q12/q5
right-branch adapters; this memo fixes the frame vocabulary and states the
remaining q6/q12 and left-branch interfaces.

Reference layout (Minsky, *Computation: Finite and Infinite Machines*,
Ch. 7):

```text
... 000  pseudo_tape  M  0^b  Y  bin_k(q) s  description  Y  0 ...
```

with the head initially on the first `X = 4` of the description and the
simulated tape to the left of `M = 6`.  The project's executable encoder
(`check_minsky_source_execution.py`, `encoded_native_tape`) realises this
as

```text
ptape ++ [6] ++ repeat 0 b ++ [5] ++
  bin(q) ++ [s] ++ rows ++ [5] ++ zeros
```

where each row is `X bin(q) read bin(q') write direction`.

The important asymmetry is:

* source tape / `M` / `0^b` are on the **left**;
* condition and description are on the **right** of `Y = 5`;
* the `0^b` buffer is a nonempty run of **raw zeros**, immediately to the
  right of `M`.

That last point is load-bearing for q19; see section 6.

## 1. Frame vocabulary

```coq
Definition book_buf (b : nat) : list nat := repeat 0 b.

(* Scan-order rail between the restored write bit w and the direction
   mark at M.  Physical order is buf, Y, init. *)
Definition book_return_rail (init : list bool) (b : nat) : list nat :=
  rev (map source_bit init) ++ [5] ++ rev (book_buf b).

(* Physical q15 scan rail: marked current/read field, marked next/write
   field, the q6 direction mark, then the remaining marked description.
   desc_tail ends with the final Y; it does NOT contain the first raw
   trailing cell. *)
Definition book_q15_rail
    (bits init : list bool) (w : bool) (dir_mark : nat)
    (desc_tail : list nat) : list nat :=
  map match_mark bits ++ map match_mark (init ++ [w]) ++
  [dir_mark] ++ desc_tail.

Definition book_q6_left
    (bits : list bool) (b : nat) (ptape : list nat) : list nat :=
  4 :: rev (map source_bit bits) ++
  5 :: rev (book_buf b) ++ 6 :: rev ptape.
```

`bits` is the *old* condition `bin(q) ++ [read]`.  `init ++ [w]` is the
row action field `bin(q') ++ [write]`, with `w` the write bit.  The
direction bit is separate.  `desc_tail` is the marked remainder of the
description after the current row's direction bit, including the final
`Y`.

## 2. Head at q15

Physical tape:

```text
ptape ++ [dir_mark] ++ book_buf b ++ [5] ++
  map source_bit init ++ [source_bit w] ++ [4] ++
  book_q15_rail bits init w dir_mark desc_tail ++ [0] ++ tail
```

Zipper (head at the first description mark):

```text
left15  = 4 :: source_bit w ::
          rev (map source_bit init) ++ 5 :: rev (book_buf b) ++
          dir_mark :: rev ptape
right15 = book_q15_rail bits init w dir_mark desc_tail ++ [0] ++ tail
```

Here `dir_mark = 3` for a right move and `2` for a left move.  The
direction mark at `M` is written by `q12`/`q13`; the direction mark inside
`book_q15_rail` is the one written by q6 on the row's raw direction bit.
`w` is the restored write bit immediately left of `X = 4`.

## 3. Head at q19 (right branch)

After q15 has scanned `book_q15_rail` to the trailing `0`, q16 scans back
over that rail, crosses `X = 4`, restores every `2/3` to `0/1`, writes
`7` at `w`, and q21/q22 consumes the direction mark at `M`.

Physical tape immediately before the q19 step:

```text
ptape ++ [source_bit w] |   (* old M cell, rewritten by q21/q22 *)
book_buf b ++ [5] ++ map source_bit init ++ [7] ++ [4] ++
  map q16_restore (book_q15_rail bits init w dir_mark desc_tail) ++
  [0] ++ tail
```

Zipper:

```text
left19  = source_bit w :: rev ptape
right19 = book_buf b ++ [5] ++ map source_bit init ++
          7 :: 4 ::
          map q16_restore (book_q15_rail bits init w dir_mark desc_tail) ++
          source_bit trailing :: tail
```

q19's first raw cell is the head of `book_buf b`, i.e. `0`, provided
`b >= 1`.  It therefore stops with `scanned = []` and `bit = false`, and
writes the new `6` into the first buffer cell.

After q17/q18 return to the `7` and write the new read mark:

```text
left5  = rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape
right5 = 2 :: 4 ::
         map q16_restore (book_q15_rail bits init w dir_mark desc_tail) ++
         source_bit trailing :: tail
```

Physical: `ptape, w, 6, tl buf, Y, init, 2, X, restored rail, 0, tail`.
The `2` is the new read bit at the old write cell (the buffer was blank
zero).  q5 now scans left over `init` and stops at `Y`, giving the next
locate entry.

For the left branch, replace the `2 :: source_bit target :: outer` tail of
the q15 frame by the last pseudo-tape cell and use q20:

```text
left20  = source_bit w :: rev (book_return_rail init b) ++
          7 :: 4 :: map q16_restore rail ++ 0 :: tail
outer20 = rev ptape_prefix        (* ptape = prefix ++ [source_bit target] *)
```

q20 immediately displaces the last pseudo-tape cell, writes `6`, and
q17/q18 scans right over `w`, the buffer, `Y`, and `init` to the `7`.

## 4. Existing theorem disposition

| Theorem | Disposition |
| --- | --- |
| `q6_scan_zero`, `q6_scan_one`, `canonical_q6_copy_all`, `canonical_q6_copy_zero_general`, `canonical_q6_copy_one_general` | Unchanged.  The book q6 entry is the canonical entry with `tbuffer = book_buf b`, `data = ptape`. |
| `canonical_q6_direction_capture` | Unchanged.  `record_marks = map match_mark (init ++ [w])`, `tbuffer = book_buf b`, `data = ptape`. |
| `canonical_q6_copy_direction_to_q12` | Unchanged; one-line corollary of the canonical frame.  See theorem A below. |
| `q12_scan_to_m`, `q13_scan_to_m`, `q14_scan_to_x` | Unchanged. |
| `canonical_q12_restore_to_q15_mark`, `canonical_q13_restore_to_q15_mark` | Unchanged.  `s = match_mark w`, `remaining = rev (map match_mark init)`, `tbuffer = book_buf b`; the `map q14_restore` equation in section 2 is exactly the q15 left frame. |
| `q15_scan_to_raw`, `q16_restore_to_raw` | Unchanged. |
| `q15_q16_four_prefix_roundtrip_local` (`MinskyTaggedHalt.v`) | Unchanged and exact: it is the q15 scan plus the q16 backscan over `tags ++ [4]`.  This is the bridge that supplies the `X = 4` that plain `q15_q22_right_to_q19` lacks. |
| `q15_q22_right_to_q19` | **Incompatible with the reached q15 frame.**  It has no slot for the `X = 4` between the restored write bit and the q15 rail, and no `4` in the q19 right tape.  It applies only to a tagged frame whose rail abuts `old`. |
| `q15_q22_right_to_q19_tags` (untracked `MinskyBookLayout.v`) | Exact book adapter.  Generalises the above to arbitrary `tags`, with `tags ++ [4]` backscan and `7 :: 4 :: ...` output.  This is the right primitive. |
| `q15_q22_right_to_q5_book` (untracked `MinskyBookLayout.v`) | Exact right q15 -> q5 perform macro.  It splits `rev dirs = 0 :: between` and applies `q19_to_q5_relocation [] between false ...`; no full q19 scan premise. |
| `book_q12_restore_to_q5_right` (untracked `MinskyBookLayout.v`) | Exact right q12 -> q5 composition, using the `map q14_restore` frame equation. |
| `q19_to_q5_relocation` | Unchanged, but only with `scanned = []` and `bit = false` (or the analogous one-step left target).  This is the key use for the book buffer. |
| `q17_scan_to_marker`, `q18_scan_to_marker`, `q20_raw_to_m` | Unchanged.  `between = tl buf ++ [Y] ++ init` is q17-passable. |
| `canonical_q5_return_scan_to_first_five` | Unchanged.  `init ++ [Y]` is canonical-q5-return-passable; its rewrite to `2/3` prepares the next locate. |
| `q15_q22_right_relocates_to_q5`, `q15_q22_right_relocates_with_safe_encoding`, `canonical_q16_decision_right_to_q5` | **Incompatible as whole-cycle theorems.**  Their q19 full-scan hypothesis `Forall q15_pass (rev dirs ++ 7 :: restored)` fails: in the book layout `rev dirs` contains the raw `0^b` buffer and raw condition bits, so q19 stops at the buffer.  Use the empty-scan relocation instead. |
| `canonical_q5_instruction_to_q19`, `canonical_q5_instruction_to_q20`, `canonical_q5_instruction_q19_hits_restored_raw`, `..._nonempty`, `q12_right_marked_program_collision_at_q5`, `q15_q22_right_wide_program_first_hit` | **Incompatible with this frame.**  They formalise the canonical raw layout, where q19's right tape is `rev D ++ 7 :: ...`: the restored action block `D` is *before* the `7`, so q19 enters `D` and captures its first raw cell.  In the book frame q16 writes the `7` at the trailing cell `w` of the action block, and q19 starts with the `0^b` buffer; the `7` is before the restored description, not after `D`.  The theorems remain correct counterexamples for the old layout, not phases of the book cycle. |
| `q15_q22_left_four_prefix_to_q20`, `q15_q22_left_four_prefix_relocates_to_q5` | Unchanged only for the stable `6/7` tag instantiation.  The book needs the arbitrary-`2/3`-tag generalisation; the proof is the same as the right `..._tags` generalisation.  See section 5. |
| `canonical_q5_match_to_q6` | **Does not apply unchanged.**  It matches one duplicated condition against one row.  The book locate phase scans a list of description rows and exits at the matching row's `X`; that multi-row loop is a separate adapter obligation. |

## 5. Exact theorem statements

### A. q6 -> q12/q13 (book instantiation)

```coq
Corollary book_q6_to_q12 :
  forall (bits init : list bool) (w dir : bool)
         (b : nat) (ptape desc_tail : list nat)
         (trailing : bool) (tail : list nat),
    length bits = length (init ++ [w]) ->
    run (copy_all_clock bits (init ++ [w]) [] (map match_mark bits) +
         direction_clock
           (map match_mark bits ++ map match_mark (init ++ [w]))
           (map match_mark (init ++ [w])))
      (entry_config 6
        (book_q6_left bits b ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit dir :: desc_tail ++
         source_bit trailing :: tail)) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark (init ++ [w])) ++
       5 :: rev (book_buf b) ++ 6 :: rev ptape)
      (4 :: map match_mark bits ++ map match_mark (init ++ [w]) ++
            (if dir then 3 else 2) :: desc_tail ++
            source_bit trailing :: tail).
```

Proof: `exact (canonical_q6_copy_direction_to_q12
bits (init ++ [w]) (book_buf b) ptape dir
(desc_tail ++ source_bit trailing :: tail) Hlen)`.

### B. q12 -> q5, right (already in `MinskyBookLayout.v`)

The untracked file gives the raw theorem.  Its book instantiation is:

```coq
Corollary book_q12_to_q5_right :
  forall (bits init : list bool) (w : bool) (b : nat)
         (ptape desc_tail : list nat) (trailing : bool) (tail : list nat),
    let B       := book_buf b in
    let dirs    := book_return_rail init b in
    let rail    := book_q15_rail bits init w 3 desc_tail in
    let between := tl B ++ [5] ++ map source_bit init in
    b >= 1 ->
    Forall q15_pass rail ->
    Forall q16_pass (rev rail ++ [4]) ->
    Forall q21_pass dirs ->
    Forall q17_pass between ->
    Forall q12_pass
      (match_mark w :: rev (map match_mark init) ++ 5 :: rev B) ->
    Forall q14_pass
      (B ++ [5] ++ map match_mark init ++ [match_mark w]) ->
    run (restore_clock (match_mark w) (rev (map match_mark init)) B +
         (S (length rail) + S (length (rev rail ++ [4])) +
          S (length dirs)) +
         (1 + S (length between)))
      (cfg_ml 12
        (match_mark w :: rev (map match_mark init) ++
         5 :: rev B ++ 6 :: rev ptape)
        (4 :: map match_mark bits ++ map match_mark (init ++ [w]) ++
             3 :: desc_tail ++ source_bit trailing :: tail)) =
    cfg_ml 5
      (rev between ++ 6 :: source_bit w :: rev ptape)
      (2 :: 4 :: map q16_restore rail ++
       source_bit trailing :: tail).
```

The two frame equations consumed by the raw theorem are:

```coq
map q14_restore
  (rev (B ++ [5] ++ rev (rev (map match_mark init)) ++ [match_mark w]))
  = source_bit w :: book_return_rail init b.

rev (book_return_rail init b) =
  source_bit false :: (tl B ++ [5] ++ map source_bit init).   (* b >= 1 *)
```

The first is list algebra over `q14_restore`; the second is the buffer
head split.  Together they are exactly the hypotheses `Hrestored` and
`Hsplit` of `book_q12_restore_to_q5_right`.

### C. Full right perform cycle q6 -> q5

```coq
Definition book_right_clock
    (bits init : list bool) (w : bool) (b : nat)
    (desc_tail : list nat) : nat :=
  let B    := book_buf b in
  let act  := init ++ [w] in
  let rail := book_q15_rail bits init w 3 desc_tail in
  let dirs := book_return_rail init b in
  let between := tl B ++ [5] ++ map source_bit init in
  (copy_all_clock bits act [] (map match_mark bits) +
   direction_clock (map match_mark bits ++ map match_mark act)
     (map match_mark act)) +
  restore_clock (match_mark w) (rev (map match_mark init)) B +
  (S (length rail) + S (length (rev rail ++ [4])) + S (length dirs)) +
  (1 + S (length between)).
```

```coq
Theorem book_q6_to_q5_right :
  forall (bits init : list bool) (w : bool) (b : nat)
         (ptape desc_tail : list nat) (trailing : bool) (tail : list nat),
    length bits = length (init ++ [w]) ->
    b >= 1 ->
    Forall q15_pass (book_q15_rail bits init w 3 desc_tail) ->
    Forall q16_pass
      (rev (book_q15_rail bits init w 3 desc_tail) ++ [4]) ->
    Forall q21_pass (book_return_rail init b) ->
    Forall q17_pass
      (tl (book_buf b) ++ [5] ++ map source_bit init) ->
    Forall q12_pass
      (match_mark w :: rev (map match_mark init) ++
       5 :: rev (book_buf b)) ->
    Forall q14_pass
      (book_buf b ++ [5] ++ map match_mark init ++ [match_mark w]) ->
    run (book_right_clock bits init w b desc_tail)
      (entry_config 6
        (book_q6_left bits b ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit true :: desc_tail ++
         source_bit trailing :: tail)) =
    cfg_ml 5
      (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
       6 :: source_bit w :: rev ptape)
      (2 :: 4 ::
       map q16_restore (book_q15_rail bits init w 3 desc_tail) ++
       source_bit trailing :: tail).
```

Proof: `dispatch_run_add`, theorem A, theorem B.  All passability
premises are explicit; the only non-structural ones are the marked-rail
and the buffer hypotheses.

### D. Left branch q15 -> q5 (general tags; new)

The existing stable-tag left theorem is
`q15_q22_left_four_prefix_relocates_to_q5`.  Its general-tag form is:

```coq
Lemma q15_q22_left_to_q20_tags :
  forall (tags : list nat) (dirs : list nat)
         (old next target : bool) (outer suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass dirs ->
    run (S (length (rev tags)) + S (length (tags ++ [4])) +
         S (length dirs))
      (entry_config 15
        (4 :: source_bit old :: dirs ++
         2 :: source_bit target :: outer)
        (rev tags ++ source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev dirs ++
       7 :: 4 :: map q16_restore (rev tags) ++
       source_bit next :: suffix).

Lemma q15_q22_left_to_q5_book :
  forall (tags : list nat) (dirs : list nat)
         (old next target : bool) (outer suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass dirs ->
    Forall q17_pass (source_bit old :: rev dirs) ->
    run (S (length (rev tags)) + S (length (tags ++ [4])) +
         S (length dirs) +
         (1 + S (length (source_bit old :: rev dirs))))
      (entry_config 15
        (4 :: source_bit old :: dirs ++
         2 :: source_bit target :: outer)
        (rev tags ++ source_bit next :: suffix)) =
    cfg_ml 5
      (rev (source_bit old :: rev dirs) ++
       6 :: outer)
      ((if target then 3 else 2) :: 4 ::
       map q16_restore (rev tags) ++ source_bit next :: suffix).
```

Proof: copy the proof of the stable-tag left theorem but use
`q15_q16_four_prefix_roundtrip_local` with arbitrary `tags`; then
`q21_scan_to_left_direction`, `q20_raw_to_m`, and
`q17_scan_to_marker`/`q18_scan_to_marker`.  This is the left analogue of
`q15_q22_right_to_q19_tags` and `q15_q22_right_to_q5_book`.

The book instantiation is:

```coq
(* ptape = ptape_prefix ++ [source_bit target] *)
entry_config 15
  (4 :: source_bit w :: book_return_rail init b ++
   2 :: source_bit target :: rev ptape_prefix)
  (book_q15_rail bits init w 2 desc_tail ++ source_bit trailing :: tail)
```

with `Forall q17_pass (source_bit w :: rev (book_return_rail init b))`.
The final q5 frame is

```coq
cfg_ml 5
  (rev (source_bit w :: rev (book_return_rail init b)) ++
   6 :: rev ptape_prefix)
  ((if target then 3 else 2) :: 4 ::
   map q16_restore (book_q15_rail bits init w 2 desc_tail) ++
   source_bit trailing :: tail).
```

Composing with `canonical_q13_restore_to_q15_mark` gives
`book_q6_to_q5_left`; its clock is `book_q6_to_q12` with `dir = false`,
plus `restore_clock`, plus the two left lemmas above.

## 6. Can the 2/3 direction mark be kept out of the q19 path?

**Yes for the command mark; yes for the data marks; but the layout alone
does not remove the raw-0/1 capture hazard.**

1. **Direction command at `M`.**  q12/q13 writes `3`/`2` at `M`.  q21/q22
   scans left over the return rail, crosses that mark, and rewrites it to
   `source_bit w` before q19 starts.  The mark is therefore on q19's
   *left*, not in its right-scan tape.  This is true independent of the
   book layout.

2. **Row direction/data marks.**  The q6 direction mark and all `2/3`
   row marks live inside `book_q15_rail`.  q16 scans that entire rail,
   restores every `2/3` to `0/1`, and writes `7` at the restored write
   bit `w`.  The q19 right tape is

   ```text
   book_buf b ++ [5] ++ init ++ 7 :: 4 :: map q16_restore rail
   ```

   so it contains no `2/3`: `rev dirs` has only raw `0/1`, `Y`, and
   buffer zeroes, and `map q16_restore rail` has only `0/1/4/5/6/7`.
   The `4` after the `7` is the current row's `X`, not a direction mark.

3. **Raw 0/1 capture is the real hazard.**  The canonical failure is not
   caused by a `2/3` in q19's path; it is caused by q16 restoring the
   action/description cells to raw `0/1`.  In the canonical frame those
   restored cells sit immediately after the `7`, so q19 captures the
   first one.  In the book frame the first raw cell is the **buffer**,
   before `Y` and before the `7`:

   ```text
   q19 head -> 0 0 ... 0 Y init 7 X restored-description
               ^
               intended new M (blank cell of the simulated tape)
   ```

   q19 takes exactly one step and writes `6` there.  That is why
   `q19_to_q5_relocation` applies with `scanned = []` and `bit = false`.

4. **The buffer is necessary.**  If `b = 0`, q19 sees `Y` (passable),
   then the first raw condition/action bit, and captures *that* instead
   of a simulated-tape blank.  A two-step counterexample is:

   ```coq
   Lemma book_q19_empty_buffer_hits_condition :
     forall left (cond : list nat) (s : bool) tail,
       run 2
         (entry_config 19 left
           (5 :: 0 :: cond ++ [source_bit s] ++ tail)) =
       entry_config 17 (6 :: 5 :: left)
         (cond ++ [source_bit s] ++ tail).
   ```

   (q19 passes `5` in one step, then writes `6` on the first raw `0`.)
   The same happens if the first buffer cell is not a raw `0`, or if the
   q15 rail is not fully marked so q16's `7` is not at `w`.  Therefore
   the adapter's actual invariants are:

   * `b >= 1` and `book_buf b = 0 :: tl (book_buf b)`;
   * `Forall q15_pass rail` (and hence `Forall q16_pass (rail ++ [4])`);
   * `Forall q21_pass (book_return_rail init b)`;
   * `Forall q17_pass between`, `between = tl buf ++ [Y] ++ init`.

   The book's condition/action-right-of-Y, pseudo-tape-left arrangement
   is the correct architecture, but the **nonempty raw buffer** and the
   **fully marked q15 rail** are what convert the premature capture into
   the intended head move.

## 7. Remaining adapter obligations

1. **`book_locate_to_q6`.**  The q5/q1/q0/q2/q3/q4 locate loop must scan
   the row list and exit at the matching row's `X` with

   ```text
   left  = 4 :: rev (map source_bit bits) ++ 5 :: rev buf ++ 6 :: rev ptape
   right = map match_mark bits ++ map source_bit (init ++ [w]) ++
           source_bit dir :: desc_tail ++ source_bit trailing :: tail.
   ```

   `canonical_q5_match_to_q6` is the single-duplicated-condition special
   case and does not cover the book row list.  Reuse `q0_scan_*`,
   `q1_scan_pick`, `q1_all_matching_bits_wide_*`, `q2_*`, `q3_*`,
   `q4_*`, but the row-list loop is still to be stated.

2. **`book_desc_marked`.**  The q15 rail must be fully `q15_pass` at the
   reached q15 frame.  The executable trace shows the locate/compare
   phase marks the rows it traverses; the invariant "all rows from the
   matched row onward are marked (or the current row is the last) before
   the perform phase" is a representation obligation, not a consequence
   of the phase lemmas.

3. **Left general-tag theorem.**  Add `q15_q22_left_to_q20_tags` and
   `q15_q22_left_to_q5_book` (section 5D) and compose with
   `canonical_q13_restore_to_q15_mark`.

4. **Clock and assumption audit.**  The composite clock is the literal
   sum in `book_right_clock`; run `Print Assumptions` on the final
   `book_q6_to_q5_right`/`_left`.

5. **Scope.**  These are one-record perform macros, not a whole-source
   simulation.  The locate half, halt reflection, the full representation
   invariant, and the universality reduction remain open.

## 8. Minimal proof plan

1. `book_q6_to_q12`: immediate from
   `canonical_q6_copy_direction_to_q12` (theorem A).
2. `book_q12_to_q5_right`: already the raw theorem in the untracked
   `MinskyBookLayout.v`, instantiated with the two frame equations of
   section 5B.
3. `book_q6_to_q5_right`: `dispatch_run_add` + (1) + (2).
4. `q15_q22_left_to_q20_tags` / `_to_q5_book`: copy the stable-tag left
   proofs, replacing the stable-tag passability with arbitrary
   `H15 : Forall q15_pass (rev tags)` and
   `H16 : Forall q16_pass (tags ++ [4])`.
5. `book_q6_to_q5_left`: `canonical_q6_copy_direction_to_q12` with
   `dir = false`, `canonical_q13_restore_to_q15_mark`, then (4).

No closed proof of the full one-row cycle is claimed here; this memo only
fixes the frames, the hypotheses, and the exact reuse points.
