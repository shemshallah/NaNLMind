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

The left branch needs the analogous buffered layout.  The existing
left relocation theorem ends at a q5 frame whose immediate successor is
the relocated 2/3 marker, so it does not directly match the buffered q5
gate; the buffered left layout must be constructed explicitly.

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

1. **Left buffered cycle.**  Construct the left analogue of
   `q15_right_buffered_native_tagged_target_dispatch`, including its
   buffer-layout lemma and q5 gate match.
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
