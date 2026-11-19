# Canonical fetch: q5 match, action copy and direction capture

Status: kernel-checked by the fast q15-q22 Coq job
([run 44417282186](https://github.com/shemshallah/NaNLMind/actions/runs/44417282186)).
Full bridge:
[run 44417941360](https://github.com/shemshallah/NaNLMind/actions/runs/44417941360),
SUCCESS on `ea2ae34`.

`formal/utm/MinskyCanonicalFetch.v` is the first theorem that joins three
canonical phases end to end:

1. `canonical_q5_match_to_q6`,
2. `canonical_q6_copy_all`,
3. `canonical_q6_direction_capture`.

## Frame

The entry is the canonical q5 frame for one wide record

```text
left  = rev condition ++ 5 :: rev t-buffer ++ 6 :: rev data
right = 4 :: condition ++ action ++ dir :: tail
```

where

- `condition` is the current-state/read prefix,
- `action` is the next-state/write field with `|action| = |condition|`,
- `dir` is the direction bit.

## Result

`canonical_q5_match_copy_direction` runs the literal q5 match, the full
q6 action copy, and the q9/q10 direction capture.  It ends at

```text
cfg_ml (if dir then 12 else 13)
  (rev (map match_mark action) ++ 5 :: rev t-buffer ++ 6 :: rev data)
  (4 :: ((map match_mark condition ++ map match_mark action) ++
         ((if dir then 3 else 2) :: tail))).
```

The exact clock is

```text
(length condition + 2)
+ (matched_comparison_steps condition 0 1 + (length condition + 1))
+ copy_all_clock condition action [] (map match_mark condition)
+ S |map match_mark condition ++ map match_mark action|
+ (S |rev (map match_mark condition ++ map match_mark action) ++
       [4] ++ rev (map match_mark action)|
   + S |map match_mark action|).
```

All `Forall` premises are derived inside the proof from the record marks
being `2/3`.  No extra passability hypothesis is required for this phase.

## Scope

- One record fetch/decode/capture, not a whole instruction step.
- It stops at q12/q13, before restore, q15/q16, q21/q22, writeback or
  relocation.
- It does not address the raw-control ordering obstruction or the tagged
  control representation.
- No halting reflection or universality claim.

## Next

Done in `MinskyCanonicalInstruction.v` (`canonical_q5_fetch_to_q16_decision`):
the q15 scan crosses the next record's `X=4` and the composition reaches
the q21/q22 decision.  See `CANONICAL_INSTRUCTION.md`.
