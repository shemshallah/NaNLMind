# Tagged source construction plan

Status: open construction.  This document fixes the exact interface that
the remaining universality proof must implement.  Nothing here is
claimed as proved.

## Target

Instantiate

- `conditional_native_arbitrary_run`, and
- `conditional_source_native_halting_equivalence`

from `MinskyMacroSimulation.v` with a concrete encoding

```text
encode : list BinarySourceRow -> BinarySourceConfig -> Config
```

and a concrete `macro_cost`, then discharge:

1. `encode_reflects_halt`
2. `macro_cost_positive`
3. `actual_table_macro_step`

The raw canonical q5-q22 chain is not a candidate: it is closed
negatively in both directions by
`canonical_q5_instruction_q19_hits_restored_raw_nonempty` and
`canonical_q5_instruction_left_branch_hits_current_cell`.

## Native cycle to target

The tagged package already proves the native movement/return half from a
supplied q15 frame:

- `q15_right_buffered_native_tagged_target_dispatch`
- `tagged_rail_left_relocates_to_q5`
- `q5_q1_q0_buffered_tagged_target_dispatch`

The right-buffered theorem starts at

```text
entry_config 15
  (source_bit old :: 5 :: 3 :: outer)
  (rev (map tag rail) ++
   source_bit sacrificial :: 2 :: 7 ::
   tag next :: tag extra :: source_bit target :: tail)
```

and ends at q3/q2 with the rail extended by `[true]` and the written
mark `[if sacrificial then 3 else 2]`.

The left branch now has a **conditional, different** native buffered
interface.  `q15_left_false_guard_native_tagged_target_dispatch` runs
exactly 21 table steps from the supplied q15 zipper through q16,
q21/q22, q20, q17, q5, q1 and q0 to q2/q3.  The input's left rail is
`source_bit old :: [6;5;2;0] ++ outer`; its right rail consists of two
6/7-tagged controls and a raw target.  The 0 is a **controlled
sacrificial false guard** consumed by q20, not the arbitrary old bit.
For any old, controls, target and stored suffix, q0 branches on the
intended target with the stored suffix behind the 5 delimiter intact.

The companion theorem `q15_left_true_guard_reverses_target_dispatch`
proves that replacing the sacrificial 0 by 1 makes q1 take q4 and
reverses the q2/q3 state.  The combined theorem
`q15_left_buffer_guard_correct_iff_false` states the exact necessary
and sufficient guard condition for **this** left frame.  These results
are not claims of entry reachability or a universal encoding.

The literal table fixes the left-gate constraint
(`canonical_left_gate_branches_on_old_bit`):

```text
q1 reads entry_rewrite (source_bit old):
  old = false  -> mark 2 -> q0   (intended gate)
  old = true   -> mark 3 -> q4   (mismatch path)
```

So a correct left buffered cycle needs a **controlled sacrificial false
bit** at the q1 stopper, not the arbitrary raw old delimiter.  The source
encoding must place or write that false guard; otherwise the left move
silently becomes the q4 mismatch path.

## Encoding intent

Use the tagged buffer as a machine-internal representation of one source
instruction:

- `target` is the source read bit at the current head;
- `sacrificial` is the source write bit;
- `next` and `extra` are the two next-state bits;
- the tag rail carries the remaining program/position information;
- `outer` and `tail` carry the source tape cells around the head;
- the direction bit selects the right-buffered or left-buffered cycle.

The q0/q3/q2 output is the encoding of the source successor, not a raw
source tape.  A normalization map must erase the transient buffer
symbols `2/5/6/7` and reposition the written marker so that the next
cycle sees the same tagged interface.

## Proof obligations

1. **Left buffered cycle (conditional native macro complete).**
   The 21-step false-guard q15→q2/q3 theorem closes the local left
   interface.  Still prove that the canonical q12 encoding can
   *construct* its `6;5;2;0` left rail and preserve the guard across
   successive instructions.  Also align its endpoint with the right
   macro's endpoint under a shared normalization map.
2. **Normalization.**  Define `normalize : Config -> Config` and prove it
   maps the q3/q2 outputs of both buffered cycles to the same tagged q15
   interface used by `encode`.
3. **Source-step correspondence.**  Prove
   `run (macro_cost rows c) (encode rows c) = encode rows (source_step rows c)`.
   The proof must handle:
   - lookup hit: write, next state, left/right head move;
   - lookup miss: source halt.
4. **Halt reflection.**  Prove `c_halted (encode rows c) = sc_halted c`.
   The native halt bit must be set exactly when `source_lookup` fails
   (or the source is already halted).
5. **Tape invariant.**  Relate `outer`/`tail`/rail to the source tape
   around the head under the normalization map.  The address-space
   bisimulation in `MinskyAddressRefinement.v` is the natural infinite
   tape model; the finite tagged lists are its visited window.

## Non-negotiable standard

No axiom, admitted lemma, or opaque hypothesis may be used to assert
universality.  Each item above must pass `coqc` and `coqchk` in the
repository workflows before the claim flag is changed.

## Native halt macro (done)

The table has exactly one halting row: state 3 reading Y=5.

- `q3_scan_to_five_halts`: q3 scans any `q3_halt_pass` list
  (`0,1,2,3,6,7`) to `5` and halts.
- `q15_left_false_guard_halt`: from the tagged left q15 entry with
  `target = true`, a passable tail followed by `5` halts in
  `21 + |tail|` native steps.

So the source-halt path is concrete: encode the end marker after the
program, dispatch `target = true`, and let q3 reach `5`.  The remaining
halt obligation is to prove the encoder selects this path exactly when
`source_lookup` fails.

## Symbol-collision constraint (kernel-checked)

`6` is overloaded in the frozen table:

- q12 on `6` writes `3` and enters q14;
- q13 on `6` writes `2` and enters q14.

So a pre-existing `6` control tag **cannot** pass through the q12/q13
restore scan; it is the M delimiter and terminates the scan.

Consequence for the source encoder: 6-valued tags must be introduced
after q12/q14 (the movement phase itself writes 6 at q19/q20 and 7 at
q16), or placed entirely outside the q12/q14 scan window.  A source
encoding that pre-loads a 6/7 rail before q12 is incompatible with the
literal table.

Lemmas: `q12_six_exits_to_q14`, `q13_six_exits_to_q14`.

## 4-prefix bridge candidate

The canonical q14 output always starts its left tape with the X marker
`4`.  The tagged q15 entry starts with a raw delimiter:

```text
tagged:    source_bit old :: left
canonical: 4 :: source_bit old :: left
```

These differ only by a leading `4`, which is q15/q16/q19/q21 passable
and q16_restore identity.  The q16 backscan can treat the `4` as part of
its scanned prefix:

```text
remaining = tags ++ [4],  raw stopper = source_bit old.
```

So a generalized tagged cycle with a q16-passable prefix can absorb the
canonical `4` and place it in the q16-restored map, where later scans
pass it.  This is the most plausible bridge between the canonical
restore frame and the tagged movement frame.

The generalized q15/q16 bridge and both q21/q22 directional continuations
are now formalized in `MinskyCanonicalInstruction.v` (pending the relevant
`coqc`/`coqchk` acceptance run).  These track the actual reversal: q15 scans
`rev tags`, pushes `tags` onto the left zipper, and q16 restores
`tags ++ [4]`, leaving the ordered right-hand fragment
`7 :: map q16_restore (rev (tags ++ [4]))`.  A separate table-driven checker
exhausts 43,200 two-direction finite traces, including non-palindromic tags.

Open: thread this bridge through q19/q20, q17/q18, q5/q1/q0.  The prefix may also be the
natural X=4 reentry to q6 for the next instruction, which would close the
loop rather than break the q1 gate.

A minimal checkpoint theorem to prove first:

```text
run (S |rev tags| + S |tags ++ [4]|)
  (entry_config 15 (4 :: source_bit old :: left)
    (rev tags ++ source_bit target :: suffix))
= cfg_ml (if old then 22 else 21) left
    (7 :: map q16_restore (rev (tags ++ [4])) ++
     source_bit target :: suffix).
```

## 4-prefix checkpoint: proved

`q15_q16_four_prefix_roundtrip` is kernel-checked:

```text
run (S |rev tags| + S |rev tags ++ [4]|)
  (entry_config 15 (4 :: source_bit old :: left)
    (rev tags ++ source_bit target :: suffix))
= cfg_ml (if old then 22 else 21) left
    (7 :: map q16_restore (rev (rev tags ++ [4])) ++
     source_bit target :: suffix).
```

The canonical `4` is absorbed as a q16-scanned cell and appears in the
restored map as `4 :: ...`.

`q1_four_to_q6` proves the loop-closing interpretation:

```text
step (entry_config 1 left (4 :: tail)) =
  entry_config 6 (4 :: left) tail
```

q1 crosses X=4 into q6, the canonical action-copy entry.  So the
4-prefix can be the next instruction's X marker, not an obstacle.

Next: thread the 4-prefix through q21/q22, q19/q20, q17/q18 and the
q5/q1 rail, then use q1_four_to_q6 as the reentry.

## 4-prefix through q22 to q19 (proved)

`q15_q22_right_four_prefix_to_q19` threads the prefix through the
direction decision:

```text
run (S |rev tags| + S |tags ++ [4]| + S |dirs|)
  (entry_config 15
    (4 :: source_bit old :: dirs ++ 3 :: outer)
    (rev tags ++ source_bit target :: suffix))
= entry_config 19 (source_bit old :: outer)
    (rev dirs ++ 7 :: 4 ::
     map q16_restore (rev tags) ++ source_bit target :: suffix).
```

The `4` sits between the q16 marker `7` and the restored tag rail.  It is
q19-passable, so it does not stop the relocation scan; the scan still
reaches the intended raw target.  This removes the leading-4 mismatch as
an obstacle for the right branch.

Next: thread the same prefix through q19/q20, q17/q18, and the q5/q1
rail, then use `q1_four_to_q6` as the next-instruction reentry.

## 4-prefix right return to q5 (proved)

`q15_q22_right_four_prefix_relocates_to_q5` composes the 4-prefix
q22-to-q19 theorem with q19 -> q17/q18 -> q5:

```text
run (q22-clock + q19-clock)
  (entry_config 15
    (4 :: source_bit old :: dirs ++ 3 :: outer)
    (rev tags ++ source_bit target :: between ++ 7 :: tail))
= cfg_ml 5
    (rev between ++ 6 :: rev scanned ++ source_bit old :: outer)
    ((if target then 3 else 2) :: tail)
```

where `scanned = rev dirs ++ 7 :: 4 :: map q16_restore (rev tags)`.
The leading `4` travels through the restored rail and does not stop
q19; the scan reaches the intended raw target.  The return lands at a
q5 frame whose rail contains the tags, `7`, and `4`.

Next: feed that q5 frame through the q1 rail.  q1 passes 6/7 tags and
`q1_four_to_q6` sends the `4` into q6, which is the canonical
next-instruction action-copy entry.

## 4-prefix q5->q1 rail (proved)

`q15_q22_right_four_prefix_q5_q1` extends the right return through the
q5 rail scan:

```text
run (q22 + q19 + q5 clocks)
  (entry_config 15
    (4 :: source_bit old :: dirs ++ 3 :: 5 :: stored)
    (rev tags ++ source_bit target :: between ++ 7 :: tail))
= entry_config 1 (5 :: stored)
    (map entry_rewrite (rev rail) ++
     (if target then 3 else 2) :: tail)
```

where

```text
rail = rev between ++ 6 ::
       rev (rev dirs ++ 7 :: 4 :: map q16_restore (rev tags)) ++
       [source_bit old].
```

The q1 head is the rewrite of the last rail cell, i.e. the old-bit
mark `2/3`.  q1 therefore dispatches q0 (mark 2) or q4 (mark 3), which
is the canonical next-row match phase; the `4` deeper in the rail is
then the X marker that leads to q6.  This is the loop structure, not a
gate failure.

## q1 dispatch into q0/q4 (proved)

`q15_q22_right_four_prefix_q1_step` adds one literal q1 step to the
q5->q1 rail:

```text
run (right-return clock + q5 clock + 1)
  (entry_config 15
    (4 :: source_bit old :: dirs ++ 3 :: 5 :: stored)
    (rev tags ++ source_bit target :: between ++ 7 :: tail))
=
if old
then entry_config 4 (1 :: 5 :: stored) (rail_tail_map ++ mark :: tail)
else entry_config 0 (0 :: 5 :: stored) (rail_tail_map ++ mark :: tail)
```

where `rail_tail_map = map entry_rewrite (rev (rev between ++ 6 ::
rev (rev dirs ++ 7 :: 4 :: map q16_restore (rev tags))))`.

This is the canonical next-row match entry: q4 for old=true, q0 for
old=false.  The `4` remains in the rail as the X marker for q6.

## q0 target dispatch over the returned rail (proved)

`q0_right_rail_target_dispatch` reads the next raw target after the
returned rail, the relocated old mark, and two stable control tags:

```text
run (|prefix ++ [mark]| + 3)
  (entry_config 0 (0 :: 5 :: stored)
    ((prefix ++ [mark]) ++ [tag c1; tag c2] ++
     source_bit read :: tail))
= if read
  then entry_config 3
    (3 :: rev ((prefix ++ [mark]) ++ [tag c1; tag c2]) ++
     0 :: 5 :: stored) tail
  else cfg_ml 2
    (rev ((prefix ++ [mark]) ++ [tag c1; tag c2]) ++
     0 :: 5 :: stored) (2 :: tail).
```

This is the q0 branch of the next-row direction/target dispatch.  The q4
branch (`old = true`) is the mirrored target dispatch and remains to be
proved.

## q4 mirrored target dispatch (proved)

`q4_right_rail_target_zero` and `q4_right_rail_target_one` complete the
other q1 branch:

- target 0 -> `entry_config 3` with the mark 2 on the left (right move);
- target 1 -> `cfg_ml 2` with the mark 3 on the right (left move).

Both read the raw target after the returned rail and the two stable
control tags.  Together with `q0_right_rail_target_dispatch`, both
`old` branches of the q1 direction decision now reach the q3/q2 target
states with the table's mirrored mapping.
