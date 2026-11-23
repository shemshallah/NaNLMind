# Concrete 23x8 universality: task graph

Status: open.  `claimed` remains false.  This document is the ranked
engineering/research plan derived from the current kernel-checked tree.

## What is already closed

- The frozen 184-row table, lookup semantics, halt order and full
  signed-address/zipper bisimulation.
- Wide-source syntax, decoders and program round trips.
- The conditional arbitrary-run halting theorem
  `conditional_wide_source_native_halting_equivalence`.
- The full canonical q5-q22 phase library and both generic row-step
  packages.
- The tagged movement/dispatch, q2->q1 reentry, q1 prefetch, q12
  leftover-tail and exact q12->tagged-q15 interface lemmas.

## Source model (literature-confirmed)

The frozen table is Minsky's direct interpreter of a **2-symbol,
left-infinite-tape Turing machine with an arbitrary finite state set**.
For a fixed state width `k`, a description row is

```text
X bin_k(q) read(1) bin_k(q') write(1) direction(1)
```

and has `2k+3` symbols.  The project's 7-bit rows are exactly the
`k = 2` special case (at most four simulated states); `WideSource` with
arbitrary `p` is the correct generalisation.  The machine is a strong
UTM: it simulates one binary-TM quintuple per locate/copy/restore/perform
cycle and halts when the locate phase reaches the final `Y` without a
match.

The 7x4 tag-system machine is a different construction.  A standard
strong 4-state/2-symbol UTM is not known, so the fixed-small-UTM route is
not a shortcut.

The primary source is Minsky, *Computation: Finite and Infinite
Machines*, Ch. 7, Fig. 7.2-9, pp. 132-145.  The exact tape layout is

```text
...000 pseudo_tape M 0^b Y bin_k(q) s description Y 0...
```

with the head starting on the first `X` of the description in state 6.
The condition `bin_k(q) s` is stored to the right of `Y`; the pseudo-tape
and its `M` marker are to the left.  This separation is the key layout
constraint for the perform phase.

## Book-layout perform half is now kernel-checked

The actual fixture trace showed that Minsky's machine uses a split tape:
source data left of `Y`, condition/description right of `Y`.  The
canonical q15/q19 frames conflated these regions, which caused the
q19 premature capture.  The correct frame is now formalized in
`MinskyBookLayout.v`:

```text
q15_q22_right_to_q19_tags
q15_q22_right_to_q5_book
book_q12_restore_to_q5_right
```

These prove the complete perform half q12 -> q15 -> q16 -> q21/q22 ->
q19 -> q17/q18 -> q5 using the book layout.  The q15 rail is the marked
description record (`2/3`), not a `6/7` tag rail; q16 restores it in
place, and q19 starts on the source side and captures the new head cell.
The old q12 "tag poison" is bypassed by the correct split frame.

The right perform cycle is now closed end-to-end:

```text
book_q6_to_q12
book_q6_to_q5_right
```

`book_q6_to_q5_right` runs the literal q6 copy/direction, q12/q14
restore, q15/q16 tagged record restore, q21/q22 old-head write, q19 new
head relocation and q17/q18 return to q5, with the full book clock and
all frame/passability hypotheses.  `MinskyBookLeft.v` also proves the
general-tag left q15 -> q20/q5 perform macro.

`formal/utm/MinskyBookLeftCycle.v` now proves both the left perform
composition `book_q13_restore_to_q5_left` and the full left cycle
`book_q6_to_q5_left` (q6 -> q13 -> q14 -> q15 -> q16 -> q21/q22 -> q20
-> q17/q18 -> q5).

Both q6 -> q5 perform cycles are now closed.

`formal/utm/MinskyBookLocate.v` now proves the first genuine find step:

```text
book_q5_scan_general
book_q1_mismatch_restart
book_locate_two_rows_to_q6
book_q6_region_to_q12
book_locate_two_rows_to_q12
```

A two-row description locates the first row, mismatches, restarts, matches
the second row, and reaches the exact q6/q12 frame.  The mismatch uses a
new book-frame restart adapter because the canonical first-mismatch
theorems assume adjacent marked/raw copies; the book layout has the row
`X` delimiter between them.

`formal/utm/MinskyBookLocateRows.v` now proves the full row-list locate
phase:

```text
book_locate_failed_row
book_locate_failed_rows
book_locate_hit_row
book_locate_rows_to_q6
book_locate_rows_to_halt
book_q5_steady_to_locate_state
book_locate_rows_to_q12
book_steady_q5_locate_to_q12
```

It includes the recursive failed-row invariant, the no-match/halt path,
and the steady-state q5 entry produced by the perform cycle.  The only
remaining composition gap is the q12 `Hright` trailing-cell equation:
the next cell after the q15 rail is `X=4` or the final `Y`, not a raw
source bit.  The planned fix is to absorb the leading `X` into the q15
tag rail and use the first raw bit of the next row as the stop cell.

`formal/utm/MinskyBookEncode.v` now defines the source-row to book-row
map and proves:

```text
source_row_action_length
source_rows_cond_length
book_initial_q5_to_locate_state
```

so a nonempty encoded source program starting at the literal initial q5
frame reaches the row-list locate state.

Remaining overall: close the q12 `Hright` equation, package the full
q5 -> locate -> q12 -> q5 cycle, and build the total finite-window
encoder.

## Experimental verdict on the prefetch route

An exhaustive small-frame search and literal-table traces confirm the
current prefetch route is not repairable by reordering action bits or
raw targets:

- 32,256 prefetch endpoints checked; 19,456 q19/q20 captures, **0**
  correct intended-target captures.
- 26,624 q15-after-q12 frames checked; **0** had no `2/3` mark before
  the first raw target.
- The q12 corollary `canonical_q12_restore_to_tagged_entry` works
  exactly when the q12 start already has a `6/7` rail.  The canonical
  q6/direction phase cannot produce that rail: it always writes `2/3`,
  and the literal table has no pre-q15 `2/3 -> 6/7` conversion.

The failure is structural: q15 scans the nonempty `2/3` prefix, q16
restores it to `0/1`, and q19/q20 stop on that restored cell before the
target.  The book layout, where the pseudo-tape is left of `Y` and the
condition/description is right of `Y`, is the remaining candidate for
keeping that prefix out of the q19 scan path.

## The three concrete blockers

### Blocker A: q1 prefetch rail is not q6-copy compatible

`tagged_*_prefetch_to_q6` produces a q6 entry whose left `processed`
rail is `rev pass`.  The actual dispatch pass is

```text
right: rev (tag tags) ++ [6; 0]
left:  [6; 0] ++ rev (tag tags)
```

`canonical_q6_copy_all` requires `Forall q9_pass processed`, with
`q9_pass = {2,3}`, but `0` is in the rail.  The literal row 9/10 on `0`
writes `3/2` and leaves to q11, so this is a destructive mismatch, not a
missing case split.  `MinskyTaggedImpossibility.v` records the
interface obstruction.

### Blocker B: q12 stops at the rail's 6

`q12_pass = {0,1,2,3,4,5,7}` excludes 6.  The prefetch pass contains a
literal 6 before Y, while the intended M delimiter is after the
t-buffer.  `q12_six_exits_to_q14` makes q12 exit at the rail 6.
`canonical_q12_restore_with_leftover` only helps tags after the first 6.

### Blocker C: q6 writes 2/3, q16 restores them to raw 0/1

The q15 tagged movement consumes 6/7 tags and requires
`Forall q15_pass (rev dirs ++ 7 :: map q16_restore (rev tags))`.
If q6 produced the tags, they are 2/3, and q16 restores them to 0/1,
which is not q15-passable.  The literal table has no pre-q15
2/3 -> 6/7 conversion; 6 is first written by q19/q20 and 7 by q16.

## Ranked tasks

1. **Decide the running layout (representation).**  Either
   - a q6 phase that consumes the actual q1 rail and keeps tags out of
     the q12 scan window, or
   - a supplied q15 frame whose 6/7 tags are produced by the previous
     movement and a normalization map that closes the loop.
   This is the critical path.

2. **Prove or refute the q1-prefetch route.**  The current interface is
   formally incompatible (Blockers A/B).  A negative theorem for this
   route would redirect effort without ambiguity.

3. **Generalize the q6 copy/direction phase** to a `processed` rail
   that is q7/q9-passable for the symbols that actually occur, and
   compose it with q12.

4. **Make q12 6-free or relocate tags left-to-right.**  No native path
   currently moves the q6 left rail to the q12 right tag side.

5. **Prove the q12 -> tagged-q15 reachability premise** of
   `canonical_q12_restore_to_tagged_entry`, including the 6/7 rail and
   `source_bit old :: dirs`.

6. **Normalization.**  Map q2/q3/q5/q1 endpoints to the next running
   frame; no `normalize` function exists yet.

7. **Concrete `encode` / `macro_cost` for lookup-hit configurations.**
   Only the halt-side `wide_encode_halt` exists.

8. **Lookup invariant.**  Connect `wide_source_lookup` to the prefetched
   condition/action rail.

9. **Halt reflection for the real encoder** (both read bits), and clock
   composition into one macro cost.

10. **Source universality.**  A certified compiler from a known
    universal machine into `WideSource`; the pinned Undecidability
    Library's fixed UTM is the natural source, but no connection exists
    yet.

11. **Final composition** with
    `conditional_wide_source_native_halting_equivalence`, then the
    publication/certification gates.

## Route assessment

- **Phase relation / direct refinement (rank 1).**  Use the existing
  macros as phase lemmas under an existential layout relation.  Best
  chance to tolerate a normalization step instead of forcing brittle
  frame equalities.
- **Rail-resident control / single-action experiment (rank 2).**  Cheap
  go/no-go test: if the q12 scan window can be made passable with a
  one-bit action and an empty buffer, the bridge may be much smaller.
- **Generic source compiler (rank 3, mandatory independently).**  The
  library UTM route closes the source-universality gap but does not fix
  the native bridge.
- **Tag-system and fixed small-UTM routes (rank 4-5).**  Not on the
  critical path without provenance or an imported mechanized
  universality theorem.

## Immediate next three proofs

1. `q1_prefetch_route_incompatible` (already partly in
   `MinskyTaggedImpossibility.v`): formalize the 0/6 interface failure.
2. `q6_single_action_empty_buffer_to_q15`: the route-5' go/no-go
   experiment.
3. `q12_to_q19_tagged`: compose the exact q12->tagged interface with
   the four-prefix movement under the explicit passability hypotheses.


## November 22 macro-level status (update)

The running instruction cycle is now proved in both directions for a
nonempty next row:

```text
book_steady_q5_locate_to_q5_right
book_steady_q5_locate_to_q5_left
```

The right branch absorbs the next row's `X` into the q15 tag rail and
stops at its first raw condition bit.  The last-row case is handled by a
sentinel row:

```text
book_sentinel_restore_frame_tail
book_q5_after_perform_right_sentinel_halt
book_steady_q5_locate_perform_right_sentinel_halt
```

The remaining macro-level items are:

1. the two-boolean input-side q5->q12 adapter (`w_read` vs `w_tape`) for
   arbitrary write-bit iteration;
2. the left sentinel halt composition;
3. a computable lookup-witness compiler turning a source condition and
   row list into the `steps`/sentinel witnesses;
4. the total finite-window encoder and buffer/window invariant.

The first two are proof engineering on the established frames.  The
third is a small decision procedure.  The fourth is the remaining
representation/global-invariant problem.
