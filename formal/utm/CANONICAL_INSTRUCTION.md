# Canonical instruction: q5 fetch through q16 decision

Status: kernel-checked by the fast q15-q22 Coq job
([run 44429121196](https://github.com/shemshallah/NaNLMind/actions/runs/44429121196)).
Full bridge:
[run 44429619546](https://github.com/shemshallah/NaNLMind/actions/runs/44429619546),
SUCCESS on `1bfeb07`.

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

## Instruction to q19/q20

Two corollaries run q21/q22 from the instruction result:

- `canonical_q5_instruction_to_q19` (direction true, marker 3):

  ```text
  entry_config 19 (source_bit b :: rev data)
    (rev D ++
     7 :: map q16_restore (next-X backscan) ++
     source_bit bit :: tail)
  ```

- `canonical_q5_instruction_to_q20` (direction false, marker 2):

  ```text
  cfg_ml 20 (rev data)
    (source_bit b :: rev D ++
     7 :: map q16_restore (next-X backscan) ++
     source_bit bit :: tail)
  ```

Here

```text
D = map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev t-buffer)
```

is the restored action block.  The q21/q22 scan adds exactly
`S |D|` transitions.  The pass hypothesis `Forall q21_pass D` is derived
from `Forall q14_pass t-buffer`; q14 restores `2/3` to `0/1`, both of
which q21 accepts.

**Important limitation.**  The q19 right tape begins with `rev D`,
which normally contains restored `0/1` cells.  q19 stops at the first
such raw cell, so the next relocation target is a restored control bit
rather than the intended source bit.  This is exactly the documented
premature-raw-capture obstruction.  The q5 -> q19/q20 theorems therefore
certify the native path to the relocation phase, not a correct source
head move.  The tagged 6/7 control channel remains the repair path.

## Canonical q19 collision (kernel-checked)

`canonical_q5_instruction_q19_hits_restored_raw` makes the obstruction
explicit in the canonical frame.  Let

```text
D = map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev t-buffer).
```

If `D` contains any raw `0/1` cell, then there is a first-raw
decomposition

```text
rev D = pre ++ source_bit hit :: post,
Forall q15_pass pre
```

and q19 runs from the q5 instruction entry to

```text
entry_config (if hit then 18 else 17)
  (6 :: rev pre ++ source_bit b :: rev data)
  (post ++ 7 :: q16-backscan ++ source_bit bit :: tail)
```

in clock `instruction_q19_clock + S |pre|`.

So q19 writes its displaced-head marker 6 at a cell of the restored
action block.  It does **not** reach the intended next raw record bit
beyond the 7 written by q16.  This is the canonical premature-raw
capture; the raw layout cannot yield the intended source head move.

The premise is immediate when `action_init` is nonempty, because
`rev D` ends with the nonempty raw list `map source_bit action_init`.
It is not automatic for a one-cell action whose only action mark was
split off as the decision bit.

## Unconditional q19 collision for nonempty action prefixes

`canonical_q5_instruction_q19_hits_restored_raw_nonempty` discharges the
raw-cell premise when `action_init <> []`:

```text
action_init <> [] ->
length (action_init ++ [b]) = length bits ->
Forall q12_pass t-buffer ->
Forall q14_pass t-buffer ->
exists pre hit post,
  rev D = pre ++ source_bit hit :: post /\
  Forall q15_pass pre /\
  run (instruction_q19_clock + S |pre|) ...
    = entry_config (if hit then 18 else 17)
        (6 :: rev pre ++ source_bit b :: rev data)
        (post ++ 7 :: q16-backscan ++ source_bit bit :: tail).
```

`rev_restored_action_block_has_raw` supplies the witness: the restored
block ends with `map source_bit action_init`, a nonempty raw list.
For any source state width `p >= 1`, the action field has `p+1 >= 2`
bits, so `action_init` is nonempty and the collision is unavoidable.

## Why the raw layout fails in both directions

The q19 collision is kernel-checked.  The q20 branch fails for an
independent, equally native reason.  `q20_scan_to_m` has the explicit
premise

```text
Forall q15_pass (s :: remaining)
```

on the cells between the head and the raw target.  In the canonical raw
source frame those cells are source data bits `0/1`, while
`q15_pass = {2,3,4,5,6,7}`.  A raw head therefore triggers
`q20_raw_to_m` immediately: q20 writes the displaced-head marker `6`
on the current source cell instead of moving to the left neighbour.

So the relocation macros require a marked/tagged intervening rail in
both directions:

- q19 needs `Forall q15_pass` over the restored action block;
- q20 needs `Forall q15_pass` over the left source region.

The canonical raw layout satisfies neither.  This is an architectural
incompatibility, not a missing arithmetic lemma.  A correct total
construction must supply the marked 6/7 rail before q15/q19/q20; the
existing tagged-rail package already certifies the native behaviour once
that rail exists.

## Left branch: q20 displaces the current cell

`canonical_q5_instruction_left_branch_hits_current_cell` makes the
direction-0 failure equally explicit.  If

```text
rev data = source_bit d :: rev data'
```

then the raw q20 head is the current source cell `d`, and

```text
run (instruction_q20_clock + 1)
  (entry_config 5 ... source_bit false ...) =
  entry_config (if d then 18 else 17)
    (6 :: rev data')
    (source_bit b :: rev D ++ 7 :: q16-backscan ++ source_bit bit :: tail).
```

q20 writes the displaced-head marker `6` on the **current** cell in one
step; it never scans left, because the intervening source cells are raw
`0/1` and `q15_pass = {2,3,4,5,6,7}`.  Thus the canonical raw layout
fails in both directions:

| branch | native effect |
| --- | --- |
| q19 (right) | captures the first restored action cell |
| q20 (left) | displaces the current source cell instead of moving left |

## Canonical q5 movement and q5 -> q1 cycles (proved)

The canonical instruction phase now has four complete native cycle
theorems:

| branch | endpoint |
| --- | --- |
| right, collision hit | `q5 -> ... -> q5` |
| left, current cell | `q5 -> ... -> q5` |
| right, collision hit | `q5 -> ... -> q1` |
| left, current cell | `q5 -> ... -> q1` |

The q5 -> q5 theorems are
`canonical_q5_instruction_q19_collision_to_q5` and
`canonical_q5_instruction_left_collision_to_q5`.  They stop q19 at the
first restored action bit

```text
rev restored = pre ++ source_bit hit :: post
```

and return to the q5 rail

```text
cfg_ml 5
  (rev post ++ 6 :: rev pre ++ source_bit b :: rev data)
  ((if hit then 3 else 2) ::
   map q16_restore (...) ++ source_bit bit :: tail).
```

Composing with the native q5 scan
`canonical_q5_return_scan_to_first_five` gives the q5 -> q1 theorems
`canonical_q5_instruction_q19_collision_to_q1` and
`canonical_q5_instruction_left_collision_to_q1`.  Their input includes
the exact q5-left decomposition

```text
rev post ++ 6 :: rev pre ++ source_bit b :: rev data =
  (symbol :: remaining) ++ 5 :: prefix
```

and their output is the next q1 match entry

```text
entry_config 1 (5 :: prefix)
  (map entry_rewrite (rev (symbol :: remaining)) ++
   hit_mark :: map q16_restore (...) ++ source_bit bit :: tail).
```

This is the canonical representation interface for the next-row
q1/q0/q4 match.  The encoder must supply the q5-left decomposition and
the 7-free post-hit tail; the native cycles themselves are unconditional
apart from those explicit representation premises.

## q5 -> matched q1 (proved)

The q5 -> q1 cycles compose with the canonical wide-mark match:

- `canonical_q5_instruction_q19_collision_to_match` (right),
- `canonical_q5_instruction_left_collision_to_match` (left).

The new premise is the exact rail decomposition

```text
map entry_rewrite (rev (symbol :: remaining)) ++
  hit_mark :: map q16_restore (...) ++ source_bit bit :: tail =
  pass ++ map match_mark bits ++ done ++ map match_raw bits ++ tail
```

with `Forall q1_pass pass` and `Forall wide_mark done`.  The result is

```text
entry_config 1 (5 :: prefix)
  (pass ++ map match_raw bits ++ done ++
   map match_mark bits ++ tail).
```

This is the first verified q5-to-match composition.  The remaining
representation step is to identify this q1 entry with the next q5 fetch
entry (the q5-scan/q1-match/q6-copy half) and then close the source-step
loop.
