# Canonical instruction: q5 fetch through q16 decision

Status: kernel-checked by the fast q15-q22 Coq job
([run 44429121196](https://github.com/shemshallah/NaNLMind/actions/runs/44429121196)).
Full bridge:
[run 44429619546](https://github.com/shemshallah/NaNLMind/actions/runs/44429619546).

`formal/utm/MinskyCanonicalInstruction.v` composes the canonical phases
into one literal native run:

```text
q5 match -> q6 action copy -> q9/q10 direction capture
-> q12/q13 restore -> q15 across the next X=4 -> q16 decision.
```

## Entry

One wide record with condition `bits`, action `action_init ++ [b]`, and
direction `dir`, followed by the next record's `X=4` and first raw bit:

```text
entry_config 5
  (rev (map source_bit bits) ++ 5 :: rev t-buffer ++ 6 :: rev data)
  (4 :: map source_bit bits ++
   map source_bit (action_init ++ [b]) ++
   source_bit dir :: 4 :: source_bit bit :: tail)
```

with `|action_init ++ [b]| = |bits|`, `Forall q12_pass t-buffer` and
`Forall q14_pass t-buffer`.

## Result

`canonical_q5_fetch_to_q16_decision` ends at the q21/q22 decision

```text
cfg_ml (if b then 22 else 21)
  (map q14_restore
    (rev (map match_mark action_init) ++ 5 :: rev t-buffer) ++
   (if dir then 3 else 2) :: rev data)
  (7 :: map q16_restore
    (rev (4 :: rev
      (instruction_marked bits (action_init ++ [b]) ++
       [(if dir then 3 else 2)]) ++ [4])) ++
   source_bit bit :: tail).
```

The decision bit `b` is the last action bit, restored by q14 from its
`match_mark b` record mark.  The direction bit `dir` selects q12
(mark 3, right) or q13 (mark 2, left).

## Clock

The theorem's clock is the literal sum

```text
fetch_clock bits (action_init ++ [b])
+ direction_clock
    (instruction_marked bits (action_init ++ [b]))
    (map match_mark (action_init ++ [b]))
+ restore_clock (match_mark b)
    (rev (map match_mark action_init)) t-buffer
+ S |instruction_marked bits (action_init ++ [b]) ++ mark :: [4]|
+ S |4 :: rev (instruction_marked bits (action_init ++ [b]) ++ mark) ++ [4]|
```

with `mark = if dir then 3 else 2`.

- `fetch_clock` is the q5-match plus action-copy clock.
- `direction_clock` is the q9/q10 capture clock.
- `restore_clock` is the q12/q13-to-q15 clock.
- The last two terms are the q15 scan across the next `X=4` and the q16
  backscan.

## Scope

- One record fetch/decode/action-copy/direction/restore/decision macro.
- It stops at q21/q22, before q19/q20 relocation and q17/q18 return.
- It does not prove the whole-source representation invariant, the raw
  control ordering fix, halting reflection, or universality.
- The right q19 relocation still needs the restored scan to be
  `q15_pass`; the raw canonical layout restores `2/3` to `0/1`, so the
  documented premature-raw-capture obstruction remains the critical
  open semantic issue.

## Next

Connect the q16 decision to the q19/q20 relocation under an explicit
representation invariant (or the tagged 6/7 control channel), then state
the single source step and halting reflection.
