# Canonical q12/q13 restore to q15

Status: kernel-checked by the fast q15-q22 Coq job
([run 44387137354](https://github.com/shemshallah/NaNLMind/actions/runs/44387137354)).
Full bridge pending
([run 44387853435](https://github.com/shemshallah/NaNLMind/actions/runs/44387853435)).

This is the phase after `canonical_q6_direction_capture`.  The direction
frame is decomposed as

```text
left  = s :: remaining ++ 5 :: rev t-buffer ++ 6 :: rev data
right = 4 :: marked ++ 2/3 :: record_tail
```

so `cfg_ml` exposes the head `s`.

## What is proved

- `rev_restore_scan`:
  `rev (s :: remaining ++ 5 :: rev t-buffer)`
  equals `t-buffer ++ [5] ++ rev remaining ++ [s]`.

- `canonical_q12_restore_to_q15` and
  `canonical_q13_restore_to_q15`.
  q12/q13 scan left over `s :: remaining`, Y=5 and the t-buffer to M=6;
  q14 then scans right restoring 2->0 and 3->1 until X=4, entering q15.
  The exact clock is

  ```text
  S |s :: remaining ++ 5 :: rev t-buffer|
  + S |t-buffer ++ [5] ++ rev remaining ++ [s]|
  ```

  and the result is

  ```text
  entry_config 15
    (4 :: map q14_restore
      (rev (t-buffer ++ [5] ++ rev remaining ++ [s])) ++ 3/2 :: rev data)
    (marked ++ 2/3 :: record_tail).
  ```

  The q12 branch carries the direction mark 2 and restores `3 :: rev data`;
  the q13 branch carries 3 and restores `2 :: rev data`.

## Scope

- Macro phase only.  No q15/q16 raw-bit search, q21/q22 decision,
  q19/q20 relocation, q17/q18 return, source write, or halting.
- No claim that this frame is reached by the canonical full source encoder;
  that remains the representation-invariant obligation.

## Next

Compose q15/q16 with the q21/q22 and q19/q20 relocation macros from this
q15 entry, then the q17/q18 return to q5 and the single-source-step
theorem.

## Restore corollaries

Added after the q12/q13-to-q15 theorems (fast job
[44400890924](https://github.com/shemshallah/NaNLMind/actions/runs/44400890924),
full bridge
[44402415039](https://github.com/shemshallah/NaNLMind/actions/runs/44402415039)):

- `canonical_restore_q12_q15_capture` and
  `canonical_restore_q13_q15_capture` compose the restore with the q15
  scan over `marked ++ [2]` / `marked ++ [3]`, reaching q16 with

  ```text
  cfg_ml 16
    (rev (marked ++ [m]) ++ 4 ::
     map q14_restore (rev T) ++ 3/2 :: rev data)
    (source_bit bit :: tail).
  ```

- `canonical_restore_q16_decision` continues q16 across the backscan and
  X=4, restores `2->0` / `3->1`, writes 7 at the raw cell behind X=4 and
  selects q21/q22:

  ```text
  cfg_ml (if old then 22 else 21) prefix
    (7 :: map q16_restore (rev (m :: rev marked ++ [4])) ++
     source_bit bit :: tail).
  ```

The subsequent q21/q22 and q19/q20 relocation phases are in
`MinskyCanonicalDecision.v` and `CANONICAL_DECISION.md`.
