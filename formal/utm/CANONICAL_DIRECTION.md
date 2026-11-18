# Canonical direction-bit capture

Status: kernel-checked by the fast q15-q22 Coq job
([run 44376789679](https://github.com/shemshallah/NaNLMind/actions/runs/44376789679)).
Full bridge pending
([run 44377481394](https://github.com/shemshallah/NaNLMind/actions/runs/44377481394)).

This module is the phase after `canonical_q6_copy_all`.  The condition bits
have all been consumed and the corresponding next-state/write bits are
marked in `record_marks`; the next raw record bit is the direction bit.

## What is proved

- `q9_scan_marked_to_q12` and `q10_scan_marked_to_q13`.
  q9/q10 scan a marked prefix to `X=4`, write 4, and move left into q12/q13.
  The correct result is a `cfg_ml` frame with the head on the cell left of
  X, not X's former slot.

- `q8_reversed_frame`.
  The q7/q8 reversal produces

  ```text
  ((record_marks ++ [4]) ++ marked) ++ x :: record_tail
  ```

  and this lemma normalizes it to

  ```text
  record_marks ++ 4 :: marked ++ x :: record_tail
  ```

  so the q9/q10 scans apply.

- `canonical_q6_direction_capture`.
  q6 captures the raw direction bit, q7/q8 return to Y, and q9/q10 scan the
  copied record marks to X=4 and enter q12/q13:

  ```text
  run (S |marked| + (S |rev marked ++ [4] ++ rev record_marks| + S |record_marks|))
    (entry_config 6
      (4 :: rev record_marks ++ 5 :: rev t-buffer ++ 6 :: rev data)
      (marked ++ source_bit dir :: record_tail))
  =
  cfg_ml (if dir then 12 else 13)
    (rev record_marks ++ 5 :: rev t-buffer ++ 6 :: rev data)
    (4 :: marked ++ (if dir then 3 else 2) :: record_tail).
  ```

  The direction bit value selects q12 (right) or q13 (left), exactly as the
  table's q9/q10 pairing does.

## Scope

- Direction-bit capture only.  No q12-q22 relocation, source write, head
  movement, or halting reflection.
- No assertion that the q12/q13 `cfg_ml` frame is the canonical full-source
  frame; that reachability remains part of the larger representation
  invariant.

## Next

Compose q12-q13 with the existing direction/relocation macros from this
captured frame, then return to q5 and the single-source-step theorem.
