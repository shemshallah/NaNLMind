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

## Left-infinite correction and raw-buffer task

`MinskyLeftInfinite.v` now provides the correct one-sided source model:
a right move from the rightmost cell halts, and the conditional halting
theorem mirrors the wide-source theorem with explicit `encode`/`cost`
premises.

`MinskyLeftCycleAudit.v` proves the existing left perform cycle does not
return to a zero-buffer normal form.  Concretely, a left move with write
bit `1` produces buffer `[1;0]`, not `0^b`; the next locate cannot use
`book_buf b`.  The general identity is proved in
`book_left_output_source_frame`.

The current critical task is therefore to generalize the perform and
locate cycles from `book_buf b = 0^b` to an arbitrary raw right-buffer
`buf : list nat`, with updates:

```text
right move: target = hd buf,  new buffer = tl buf
left move:  new buffer = source_bit w :: buf
boundary:   right move with buf = [] halts
```

This is now the only macro-level representation task before the global
encoder.

## Raw-buffer cycles (proved)

`MinskyBookRawBuffer.v` removes the zero-buffer restriction:

```text
book_q6_to_q5_right_raw
book_q6_to_q5_left_raw
book_steady_q5_locate_to_q5_right_raw_gen
book_steady_q5_locate_to_q5_left_raw_gen
book_global_source_rep
raw_q6_conditional_left_halting_equivalence
```

with exact updates:

```text
right move: target = hd buf, new buffer = tl buf
left move:  new buffer = source_bit w :: buf
```

The passability audit shows q19/q20 need no new nonempty-scan variant:
the target is always the first raw buffer cell; q15/q16 remain confined
to the marked description rail.

The only remaining macro-level gap is the boundary right move at
`buf = []`.  The planned fix is to encode one extra sentinel blank cell
beyond `R`, define the boundary step to move onto it and halt, and
compose the raw right perform cycle with the already-proved sentinel
halt path.  This avoids the 46k-step q3/Y trace.

## Encoder and concrete one-step (proved)

`MinskyLeftInfiniteEncode.v` now defines the q5 encoder:

```text
lic_q5_encode
lic_q5_encode_is_book_q5_raw
lic_q5_encode_rep
lic_q5_encode_rep_global
```

and closes the restored-rail frame algebra:

```text
book_q5_raw_right_frame_eq
book_q5_raw_left_frame_eq
book_cycle_restored_raw_desc
map_q16_restore_cycle_region
book_raw_desc_append_rows
```

A fully concrete non-boundary right-hit instance is proved:

```text
p1r_first_match
p1r_start_encode
p1r_right_hit_macro
```

So the encoder, lookup compiler, perform cycle, and q5 iteration frame
compose on a real source step.

The remaining general obligations are only the window arithmetic:

```text
raw_buf_right_step / raw_buf_left_step
raw_ptape_* / raw_last_* / raw_read_*
```

the general `wide_source_lookup` ↔ `book_first_match` correspondence, and
the resulting generalized non-boundary/boundary macro step.

## Window and lookup progress

`MinskyLeftInfiniteWindow.v` proves the right-step window package:

```text
raw_buf_right_step
raw_ptape_right_step
raw_ptape_prefix_right_step
raw_last_right_step
raw_read_right_step
raw_buf_left_step
```

`MinskyLeftInfiniteLookup.v` proves the pointwise row-match equivalence and
hit extraction:

```text
source_row_to_book_matches
book_first_match_hit_is_source_row
```

`MinskyLeftInfiniteLeftCheck.v` proves the concrete left mapping is correct;
`lic_q5_encode` already handles the ptape/w_tape split.

The remaining general items are the left ptape window identity
`raw_ptape_left_step`, the full lookup prefix/failure packaging, and the
resulting generalized right/left/boundary/halt macro steps.

## Left window package complete

`MinskyLeftInfiniteWindow.v` now proves the full left window mapping:

```text
raw_buf_left_step
raw_ptape_left_step
raw_ptape_prefix_left_step
raw_last_left_step
raw_read_left_step
```

together with the right package.  `MinskyLeftInfiniteLeftCheck.v`
confirms the concrete left encoder equality.

The only remaining lookup/encoder work is the first-match packaging and
the halted/boundary frame identification.  The induction step is
definitional once `book_mismatch_ev` is known to be `Some` for a
nonmatching well-formed row.

## Full lookup packaging (proved)

`MinskyLeftInfiniteLookupFull.v` proves:

```text
wide_source_lookup_some_book_hit
wide_source_lookup_none_book_halt
book_mismatch_some_of_nonmatch
```

For a source hit it produces the computed `steps`, `hit`, `after` with
`hit = source_row_to_book r`; for a miss it produces the book halt
result and failure list.  The pointwise match and the `Some`/`None`
packaging are now both kernel-checked.

Remaining: the general non-boundary right/left macro composition
(using the raw cycles + window packages + this lookup packaging) and the
halted/boundary encoder frame identification.

## Sentinel-augmented running description (proved)

`MinskyLeftInfiniteEncoding.v` now closes the non-boundary running
description used by the final encoder:

```text
lic_sentinel_row
lic_book_rows = source_rows_to_book rows ++ [duplicate first row]
lic_book_rows_first_match_hit
lic_book_rows_first_match_halt
lic_book_rows_right_hit_step
lic_book_rows_left_hit_step
lic_book_rows_none_halt_step
```

The duplicate sentinel has the same length-`p+1` condition as a real
source row.  It therefore

- is harmless on a hit path: if its condition matches, the real first
  source row matches strictly earlier;
- supplies a genuine failure record on a no-match path, so the q5 locate
  phase still reaches the q3/Y halt frame.

The first-match append lemmas are in
`MinskyLeftInfiniteFirstMatchApp.v`:

```text
book_first_match_hit_app
book_first_match_halt_app
```

The arbitrary-description halt macro is in
`MinskyLeftInfiniteHaltBook.v`:

```text
lic_q5_encode_none_halt_book_macro
```

## Exact remaining soundness gap: empty-buffer boundary

A right move with `raw_buf c = []` is the only case not covered by the
running macros.  The sentinel-retry path is **not** sound in general:
after the perform the new condition is `wr_next hit ++ [false]`, and a
source row with that condition would be matched by the retry scan even
though `left_infinite_step` halts at the wall.

The native table does have a terminating q19/q3 path for the empty
buffer.  A concrete kernel computation (`test_row` with condition
`[false;false]`, action `[true;false]`, right move, empty buffer) halts
after 129 steps at a `dispatch_halt_at_y` frame with

```text
left  = [1;0;1;0;2;4;3;2;3;2;2;4;1;6;5;0;0]
right = [5]
```

This frame is *different* from the sentinel-retry frame
(`book_sentinel_halt_left`); the q19 path captures the first raw action
bit and relocates it to the source side.  A general theorem for this
path is the remaining boundary obligation; the 129-step trace is a guide
for an induction over the description rows, not a proof.

Claim remains false.

## Bounded-window simulation (proved)

`MinskyLeftInfiniteBounded.v` proves the unconditional finite-run core:

```text
lic_pad_cfg / lic_pad_lo / lic_pad_R
lic_bounded_ok
lic_bounded_hit_run
lic_bounded_none_halt_run
lic_bounded_native_halt_implies_source_halt
lic_bounded_source_halt_implies_native_halt
lic_pad_hit_run
lic_pad_none_halt_run
lic_pad_native_halt_implies_source_halt
```

For a window `lo = head - n - 2` and right endpoint
`R = max R (head + n + 2)`:

- an `n`-step hit-only source run is simulated exactly by the frozen
  table, at macro boundaries, with the explicit sum clock;
- a hit prefix followed by a no-match step reaches the halted encoder;
- native halting within the clock implies the padded source halts.

The one-step macros are the sentinel-augmented description macros; the
window is deep enough that neither the left edge nor the right wall is
reached during the `n` steps.

## Remaining for the fixed-configuration theorem

The bounded theorems choose the padding from the run length.  To obtain
a single `encode p rows c` for an arbitrary source configuration, two
pieces are still missing:

1. the empty-buffer right-boundary q19/q3 halt frame (general theorem);
2. the left-window shift at `lo = head - 1` (one blank pad cell).

With those, the fixed-configuration `macro_cost`/`encode` premises of
`conditional_left_source_native_halting_equivalence` can be discharged.
Claim remains false.

## Padding invariance bridge (partial)

`MinskyLeftInfinitePadding.v` proves the generic address bridge:

```text
zipper_run_halt_eq_of_embed_eq
```

If two zipper configurations have the same state/halt and their embedded
address tapes at a common head coordinate are equal, then their halt
flags agree after any fixed fuel.

The encoder-side obligation is **not** global embed equality: adding an
explicit q5 padding cell writes symbol `0` (a simulated blank), while an
absent native cell reads the native blank `2`.  The correct remaining
lemma is a *reachable-window* agreement: the frozen table's run for the
macro clock depends only on the tape cells actually scanned, and the
extra q5 padding lies beyond that scan.  The address equality above is
only a sufficient bridge once a common explicit padding is chosen.

Claim remains false.

## Padded halting-equivalence shape

The bounded-window theorems suggest the correct native side for the
padded family is **clock-bounded**, not padding-bounded:

```text
exists n t,
  t <= lic_bounded_clock rows n (lic_pad_lo c n) (lic_pad_cfg c n) /\
  c_halted (run t (lic_encode_pad rows n c)) = true
```

The forward direction is `lic_pad_source_halt_to_native` (the first halt
is at `k <= n`, and the native clock is monotone).  The converse does
**not** need `t <= n`; it needs a macro-boundary analysis inside the
clock:

- if `run clock(k)` is halted, the bounded hit-run theorem identifies it
  with `lic_q5_encode (run k c)`, so the source is halted;
- a halt strictly between `clock(k)` and `clock(k+1)` is impossible
  because the macro step theorem ends in a running q5 frame unless the
  source step itself halts;
- the first no-match/boundary step within `n` gives the source halt.

This avoids the false condition `t <= padding` and is the intended bridge
after the boundary macro and the left-window pad.

## Empty-buffer boundary macro complete

`MinskyLeftInfiniteBoundaryLocate.v` now proves the full general
empty-buffer wall halt:

```text
book_locate_state_wide_pass
book_locate_first_failed_row_pass
book_locate_failed_rows_wide_pass
book_locate_last_mismatch_halt_wide_pass
book_locate_rows_to_halt_wide_pass
q5_empty_boundary_locate_halt
book_q12_empty_boundary_halt
```

The q19 path rotates the next state:

```text
tl hit_init ++ [hd hit_init]
```

and then either hits a source row or fails.  For soundness at the wall,
the compiled state encoding must make the rotated state a no-match.
The intended fix is a two-bit marker: compile every state `s` as
`false :: true :: s`.  Then the rotated state starts with `true`, while
every lifted row condition starts with `false`, so the q19 retry always
takes the no-match halt branch.

A marker-lift module is the next boundary-side proof:
`lic_lift_row`, `lic_lift_cfg`, commutation of `left_infinite_step` and
`left_infinite_run`, and `wide_source_lookup_lifted_rotated = None`.

## Halted-frame path dependence

The boundary halt frame has the extra q5 marker `6` before the
`5 :: left` tail; the ordinary no-match frame has `extra = []`.  A total
`encode` must either

- prove the two halted source configurations cannot collide, or
- define a single canonical halted frame reachable from both paths by a
  checked post-halt run.

This is the remaining encoder-side obstruction for the fixed total
`encode`/`macro_cost` premises.

Claim remains false.

## Why a total config-to-frame encoder is impossible

The wall halt frame has `extra = [6]`; the lookup-failure frame has
`extra = []`.  The two halted source configurations can coincide:

- boundary path: state `s`, head `R`, read `0`, row matches, writes `1`,
  right at the wall -> halted state `s`, head `R`, cell `R = 1`;
- lookup-failure path: state `s`, head `R`, read `1`, no row matches ->
  halted state `s`, head `R`, cell `R = 1`.

Both halted `LeftInfiniteConfig`s are identical, but the native frames
differ.  Hence the conditional theorem's total `encode : config ->
Config` cannot be instantiated with path-dependent halt frames.

The correct final theorem should be a **run equivalence from a chosen
initial encoding**, not a total re-encoder on halted configs:

- source halts -> choose the left-depth/clock parameter `K` from the
  run, encode once, and reach the appropriate halt frame;
- native halts -> use the macro run equations up to the first halted
  macro step; no re-encoding of the halted config is needed.

The left-depth parameter should be separate from the right endpoint:
the right endpoint is the source's actual wall `R`, while the left
window is `head - K` with `K` large enough for the simulated run.  This
avoids changing the wall semantics when the run is long.

## Left-depth window and boundary premises

`MinskyLeftInfiniteLeftDepth.v` proves the run theorem with the source's
actual right wall and a separate left window `lo`:

```text
lic_left_ok
lic_left_ok_right / lic_left_ok_left / lic_left_ok_halt
lic_left_hit_run
lic_left_ok_run
lic_left_none_halt_run
```

`lic_left_hit_run` requires `head < R` for every hit step; a right move at
`R` is the boundary macro.  `lic_left_none_halt_run` handles a no-match
halt at the end of a hit prefix.

`MinskyLeftInfiniteBoundaryPremises.v` proves the q12 passability and
restored-frame block for the empty wall:

```text
book_q12_empty_boundary_premises
```

It supplies `H12`, `H14`, `Hrestored`, `H21`, `Hsplit`, `H17`, `Hright`,
`H15`, `H16` from the lifted action prefix.

The remaining boundary packaging is the exact read-bit width of the q5
retry condition (`hit_init` is the `p`-bit action prefix; book row
conditions are `p+1` bits).  The agent is resolving whether the extra
bit is `target`, `c0`, `w_read`, or `hit_w`, then composing the source
`lic_q5_encode_lifted_boundary_step`.

Claim remains false.
