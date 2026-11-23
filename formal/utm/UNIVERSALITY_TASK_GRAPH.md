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
