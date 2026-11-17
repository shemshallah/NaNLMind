# Canonical q6-q11 first-bit copy cycle

Status: kernel-checked by the fast q15-q22 Coq job
([run 44182091042](https://github.com/shemshallah/NaNLMind/actions/runs/44182091042))
and by the independent full Minsky bridge
([run 44182096988](https://github.com/shemshallah/NaNLMind/actions/runs/44182096988)).

This is one literal copy cycle for the frozen 23x8 table.  It is not an
induction over the whole condition and not a source-instruction theorem.

## Frame

After `canonical_q5_match_to_q6`, the machine is in q6 with

```text
left  = 4 :: rev (raw condition) ++ 5 :: rev t-buffer ++ 6 :: rev data
right = marked condition-record prefix ++ first raw record bit :: rest
```

Write `condition = c :: bits'` (the condition is nonempty: it contains the
source state bits and the read bit).  The first raw record bit is the first
cell after the marked current-state/read prefix.

## What is proved

1. `q6_canonical_scan_zero_to_q10` and
   `q6_canonical_scan_one_to_q9`.
   q6 scans over the marked prefix to the first raw record bit, writes it as
   `2` or `3`, and q8/q7 return to the first `Y = 5`.  The exact scan clock is

   ```text
   S (length (map match_mark bits))
   + S (length (rev (map match_mark bits) ++ [4] ++ rev (map match_raw bits)))
   ```

   where `bits = c :: bits'`.

2. `canonical_q6_copy_zero_to_q6` and
   `canonical_q6_copy_one_to_q6`.
   q10/q9 write the copied mark into the first raw condition bit, moves it
   to the left of Y, and q11 returns over the remaining raw condition bits
   and X=4 to q6.  The complete cycle is

   ```text
   (S (length (map match_mark bits))
    + S (length (rev (map match_mark bits) ++ [4] ++ rev (map match_raw bits))))
   + (1 + S (length bits'))
   = 4 * length bits + 4
   ```

   and the result is

   ```text
   entry_config 6
     (4 :: rev (map source_bit bits') ++ 2/3 :: 5 ::
      rev t-buffer ++ 6 :: rev data)
     (map match_mark bits ++ [2/3] ++ rest).
   ```

   The first condition bit is now left of Y, marked with the copied value;
   the first record bit stays marked `2/3`; the remaining condition bits
   stay raw; the data tape, t-buffer, M=6 and Y=5 are untouched.

## Scope

- One cycle only.  There is no induction over `bits'` yet.
- The condition must be nonempty (`c :: bits'`), and the selected record
  bit must be raw `0` or `1`.
- No source-row selection or mismatch restart.
- No write/direction phase, data-head movement, or halting reflection.
- No compiled-C++/allocator/NaN16 runtime claim.

## Next canonical obligation

Induct the cycle over `bits'` so that every condition bit is moved left of
Y and the corresponding record prefix/next-state bits are marked.  Then
handle the write and direction fields, q12-q22 relocation, and the return
to q5.  Only after that can one source transition be stated as a single
table-run theorem.
