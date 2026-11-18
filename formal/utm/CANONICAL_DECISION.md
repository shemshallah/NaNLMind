# Canonical q16 decision, q19/q20 relocation and q5 return

Status: kernel-checked by the fast q15-q22 Coq job
([run 44408127139](https://github.com/shemshallah/NaNLMind/actions/runs/44408127139),
head `0c1a2dc`). Full bridge pending
([run 44408794555](https://github.com/shemshallah/NaNLMind/actions/runs/44408794555)).
The q16-to-q19/q20 part is also accepted by the full bridge
([run 44405995495](https://github.com/shemshallah/NaNLMind/actions/runs/44405995495),
head `0a2db5e`).

This module is the phase after `canonical_q12_restore_to_q15` and
`canonical_restore_q15_capture`.  The restore phase ends at q15 with the
left tape

```text
4 :: map q14_restore (rev T) ++ 3/2 :: rev data
```

and the right tape `marked ++ 2/3 :: source_bit bit :: tail`.

## What is proved

### Restore to q16

- `canonical_restore_q12_q15_capture` and
  `canonical_restore_q13_q15_capture`.
  q15 crosses `marked ++ [3]` (q12, right) or `marked ++ [2]` (q13,
  left), reaches the raw record bit and enters q16 with

  ```text
  cfg_ml 16
    (rev (marked ++ [m]) ++ 4 ::
     map q14_restore (rev T) ++ 3/2 :: rev data)
    (source_bit bit :: tail).
  ```

  The clock is the restore clock plus `S |marked ++ [m]|`.

- `canonical_restore_q16_decision`.
  q16 scans the q15 backscan and X=4, restores `2->0`, `3->1`, writes 7
  at the raw cell behind X=4 and selects q21 (bit 0) or q22 (bit 1):

  ```text
  cfg_ml (if old then 22 else 21) prefix
    (7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
     source_bit bit :: tail).
  ```

### Restore directly to the decision bit

- `canonical_q12_restore_to_q16_decision` and
  `canonical_q13_restore_to_q16_decision` (correct native marks: q12
  carries 3, q13 carries 2).  The `_next` variants `canonical_q12_restore_q16_decision_next`
  and `canonical_q13_restore_q16_decision_next` let the q15 scan cross the
  next record's `X=4` before reaching its first raw current bit.
  In the canonical record the last consumed mark is `match_mark b`
  (`2` for `false`, `3` for `true`).  `q14_restore (match_mark b)` is
  exactly `source_bit b`, so the decision bit is exposed without an extra
  structural hypothesis:

  ```text
  cfg_ml (if b then 22 else 21)
    (map q14_restore (rest ++ 5 :: rev t-buffer) ++ 3/2 :: rev data)
    (7 :: map q16_restore (rev (2/3 :: rev marked ++ [4])) ++
     source_bit bit :: tail).
  ```

### q21/q22 direction decision

- `canonical_q16_decision_to_q19` (marker 3, right) and
  `canonical_q16_decision_to_q20` (marker 2, left).
  q21/q22 scan the restored direction-mark block to the stored 3/2
  marker, then enter q19 or q20 with the written direction bit:

  ```text
  entry_config 19 (source_bit old :: outer)
    (rev dirs ++ 7 :: map q16_restore (rev backscan) ++
     source_bit bit :: tail)
  ```

  or the corresponding `cfg_ml 20 outer` frame.

### q19/q20 relocation and q5 return

- `canonical_q16_decision_right_to_q5`.
  q19 scans the restored block and the 7 written by q16 to the next raw
  cell, displaces it by 6 and q17/q18 return to a following 7 in q5.
  The result is

  ```text
  cfg_ml 5
    (rev between ++ 6 ::
     rev (rev dirs ++ 7 :: map q16_restore (rev backscan)) ++
     source_bit old :: outer)
    ((if bit then 3 else 2) :: final).
  ```

- `canonical_q16_decision_left_to_q5`.
  q20 steps onto the left target raw cell, writes 6, and q17/q18 scan
  back right across the stored raw bit and the direction marks to the 7
  left by q16, returning to q5 with the new `2/3` marker.

## Scope and open obligations

- These are exact native-table macro compositions.  No single source
  instruction step, no halting reflection and no universality reduction is
  claimed here.
- The right relocation requires the restored q19 scan to be entirely
  `q15_pass` (no restored 0/1), and the left branch requires the return
  scan to be `q17_pass`.  Connecting these hypotheses to a concrete
  canonical source encoding is the remaining representation-invariant
  obligation.
- The q17/q18 return theorem applied here is
  `q19_to_q5_relocation`; the left branch is composed directly from
  `q20_raw_to_m`, `q17_scan_to_marker` and `q18_scan_to_marker`.

## Next

Define the canonical mark layout that discharges the q15_pass/q17_pass
side conditions, then compose the full canonical cycle back to q5 and
state the single-source-step theorem.
