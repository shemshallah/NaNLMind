# General canonical q6-q11 copy cycle

Status: both the zero and one branches are kernel-checked by the fast
q15-q22 Coq job
([run 44202204105](https://github.com/shemshallah/NaNLMind/actions/runs/44202204105))
and by the independent full Minsky bridge
([run 44202554008](https://github.com/shemshallah/NaNLMind/actions/runs/44202554008)).

This module generalizes the single copy cycle to an arbitrary processed
condition prefix and an arbitrary marked record prefix.  It is one literal
cycle; the induction over all condition bits is the next obligation.

## Invariant

```text
left  = 4 :: rev (map source_bit (c :: bits')) ++ processed ++
        5 :: rev t-buffer ++ 6 :: rev data
right = region ++ 0/1 :: record_tail
```

- `processed` contains the condition bits already moved left of Y
  (`Forall q9_pass processed`).
- `region` is the marked record prefix (`Forall q6_pass` and `q7_pass`).
- `c :: bits'` is the not-yet-processed condition.
- `0/1` is the next raw record bit.

## Result

`canonical_q6_copy_zero_general` and
`canonical_q6_copy_one_general` move the next condition bit left of Y and
append the copied record mark to the region:

```text
entry_config 6
  (4 :: rev (map source_bit bits') ++ 2/3 :: processed ++
   5 :: rev t-buffer ++ 6 :: rev data)
  (region ++ 2/3 :: record_tail).
```

The exact clock is

```text
S (length region)
+ S (length (rev region ++ [4] ++ rev (map source_bit (c :: bits')) ++ processed))
+ S (length processed)
+ S (length bits').
```

This is exactly the shape needed for the recursive call with

```text
processed' = 2/3 :: processed
region'    = region ++ [2/3]
remaining' = bits'.
```

## Scope

- One generalized cycle, not the induction.
- No write/direction phase, relocation, source-row selection, or halting.
- The raw record bit must exist; the condition must be nonempty.

## Next

Induct over `(condition, record_bits)` of equal length.  The final state
should have every condition bit left of Y and the corresponding record bits
appended to `region`.  A first induction attempt hit list-shape/fuel
matching in the recursive composition and was deferred; the two generalized
cycles above are the verified input to that induction.  After the induction,
the write/direction field and the q12-q22 relocation phase can be stated
from the fully consumed condition frame.

## Induction proof-engineering blocker

The recursive step is mathematically closed by the two generalized cycles
above.  The remaining Coq friction is app/map convertibility between the
Fixpoint-unfolded inner run and the cycle theorem's LHS.  The goal keeps

```text
right = region ++ map source_bit (r :: rs) ++ record_tail
```

while the cycle theorem has

```text
right = region ++ 0/1 :: record_tail'
```

with `record_tail' = map source_bit rs ++ record_tail`.  These are
convertible, but `rewrite`/`apply` do not normalize the inner run enough to
match after the `copy_all_clock` unfolding.

A next attempt should either:

1. use `transitivity` with an explicit intermediate configuration and
   `set`/`replace` the inner run, or
2. state a cycle lemma specialized to the exact Fixpoint-unfolded shapes
   (`map source_bit (r :: rs)`, the exact fuel, and the outer recursive
   run), so the step is an exact `rewrite`.
