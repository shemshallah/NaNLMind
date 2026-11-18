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

## All-condition copy induction (checked)

Accepted on `main` at `2fe2425` by the fast q15-q22 job
([44234713900](https://github.com/shemshallah/NaNLMind/actions/runs/44234713900)),
the independent full Minsky bridge
([44234713887](https://github.com/shemshallah/NaNLMind/actions/runs/44234713887)),
and the mechanized UTM job
([44234714060](https://github.com/shemshallah/NaNLMind/actions/runs/44234714060)).

`canonical_q6_copy_all` closes the induction.  For condition bits `bits`
and record bits `record_bits` of equal length, any tape sides `left`/`right`
satisfying the canonical shape premises, and any processed prefix / marked
region satisfying the pass predicates:

```text
run (copy_all_clock bits record_bits processed region)
  (entry_config 6 left right) =
  entry_config 6
    (4 :: rev (map match_mark record_bits) ++ processed ++
     5 :: rev t-buffer ++ 6 :: rev data)
    (region ++ map match_mark record_bits ++ record_tail).
```

So every condition bit is consumed, the corresponding record bits are
marked and appended to `region`, and the final frame is the fully consumed
condition frame.

The proof parameterizes the theorem over the whole left and right tape
lists, so the recursive IH matches the cycle output by construction.  The
only genuine append/snoc witness is discharged by `region_snoc_cons`.
This removed the associativity mismatch described in earlier drafts.

## Next

From the fully consumed condition frame, the remaining canonical phases are:

1. write/direction field handling;
2. q12-q22 relocation;
3. return to q5 and the single source-step theorem;
4. halting reflection;
5. the universality reduction.
