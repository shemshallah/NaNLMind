# Canonical q5 -> q6 instruction-match bridge

Status: kernel-checked by the fast q15-q22 Coq job
([run 44167307045](https://github.com/shemshallah/NaNLMind/actions/runs/44167307045))
and by the independent full Minsky bridge
([run 44167314930](https://github.com/shemshallah/NaNLMind/actions/runs/44167314930)).

This is the first canonical-layout phase theorem for the frozen 23x8 table.
It is not a source-instruction theorem and not a universality claim.

## Canonical frame

The native p-bit compiler writes

```text
source data, M=6, t-buffer, Y=5,
condition (p state bits + read bit), records (X q read next write dir)*, Y=5, tail
```

and starts the table in state 5 with the head on the first record X=4.
`MinskyCanonicalMatch.v` fixes the local frame

```text
left  = rev condition ++ 5 :: rev t-buffer ++ 6 :: rev data
right = 4 :: condition ++ record_tail
```

where `condition = map source_bit bits` and the record's first `|bits|`
cells are the matching current-state/read prefix.

## What is proved

1. `wide_mark` extends the q0/q4 comparison alphabet from `{2,3}` to
   `{2,3,4,6,7}`.  The record delimiter `X=4` may therefore sit inside
   the already-marked prefix, while `Y=5` still terminates the left
   dispatch.

2. `wide_mark_scans`, `q1_zero_match_with_wide_marks`,
   `q1_one_match_with_wide_marks`, `q1_match_one_bit_with_wide_marks`,
   `q1_all_matching_bits_wide`, and the specialized
   `q1_all_matching_bits_wide_four` lift the comparison macros to the
   extended alphabet.  These are literal `MinskyTable.run` facts.

3. `canonical_q5_scan`:
   from the canonical q5 entry, after `|bits| + 2` steps the machine has
   scanned left over the condition to Y=5 and returned q1, with the
   condition rewritten `0->2 / 1->3` on the right of the record X=4.

4. `canonical_q5_match_to_q6`:
   after the q5 scan, the q1 all-match comparison against the record's
   current-state/read prefix, and the final q1 crossing of X=4, the exact
   clock is

   ```text
   (|bits| + 2) + (matched_comparison_steps bits 0 1 + (|bits| + 1))
   ```

   and the result is the literal q6 entry

   ```text
   entry_config 6
     (4 :: rev (map match_raw bits) ++ 5 :: rev t-buffer ++ 6 :: rev data)
     (map match_mark bits ++ tail).
   ```

   The condition bits are restored raw, the record prefix bits are marked
   `2/3`, and the data tape, M=6, t-buffer, Y=5, and program tail are
   untouched.

## Scope

- The theorem assumes the condition and record prefix match.  It does not
  yet prove the mismatch/restart path or source-row selection.
- It stops at q6.  It does not prove the q6 action copy, q9/q10
  writeback, q12-q22 direction/relocation, or halting.
- The clock is exact for the stated frame; it is not a source-step cost.
- No compiled-C++/allocator/NaN16 runtime claim.

## Next canonical obligation

The q6 entry has `map match_mark bits ++ tail`, where `tail` begins with
the first raw field after current-state+read.  The next theorem must compose
the q6 action-copy branch in this exact frame, then the q9/q10 writeback and
the q12-q22 direction/relocation.  The X/Y delimiters in `tail` must be
handled explicitly: the existing action macros assume a contiguous marked
prefix and cannot be pasted in without a layout proof.
