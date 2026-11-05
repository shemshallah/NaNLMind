# Frame sync and inverse head computation

## 1. Forward and rollback rails

The pair cell has two independent directions:

```text
s+  forward rail   (BE / FUTURE)
s-  rollback rail  (LE / PAST)
```

A runner requests a **frame window** on one rail:

```text
FrameRequest { runner, start, delta }
target = start + delta
```

Positive `delta` = forward; negative = rollback. Two runners can meet at the
same frame even when they approach from opposite directions.

Example:

```text
runner 0: frame 0, +4  -> target 4
runner 1: frame 7, -3  -> target 4
meet at frame 4
```

The **next runner in the ring gets precedence** at the meeting frame. The
result is:

```text
FrameMeeting { ok, frame, winner, reason }
winner = next_runner
```

If the requests use the same rail, or their targets do not coincide, the
meeting fails. If they use windows rather than single targets, the earliest
overlapping frame wins; ties again go to the next runner.

This is how the ring synchronizes without a wall clock: the frame index is a
logical coordinate, the rails give the direction, and the next runner is the
precedence holder at the meeting point.

```text
runner 0  ── +4 ──► frame 4 ◄── -3 ── runner 1
                         │
                  next runner (2) has precedence
```

## 2. Using frame sync in the ring

Before a handoff:

1. each runner computes its target frame from the current clock tick and its
   local work;
2. the coordinator compares the forward and rollback requests;
3. if they meet, the next runner is granted the frame;
4. if they do not, the forward runner continues or the rollback runner replays
   to the last committed frame;
5. a missing packet forces the rollback rail, not a silent skip.

A frame meeting is recorded in the ledger with the epoch and the winner. It is
one history event, not a new state space.

## 3. Inverse head computation

A forward head step can change:

- the four NaN words (`s+`, `s-`, `q+`, `q-`);
- the `ops` mask and selected rule;
- the phase/energy/load;
- the 1 KiB scratchpad;
- the transform phase and self-model error.

A `HeadFrame` captures the exact before and after state:

```text
HeadFrame {
    head
    before_cell / after_cell
    before_head / after_head
    before_scratch / after_scratch
}
```

`capture_head()` stores the before-frame. `capture_after()` stores the
after-frame. `restore_before()` is the inverse step; `restore_after()` re-applies
the forward result. The restore updates the descriptor checksum and records an
inverse event in the head history.

This is the practical inverse: exact before-image restoration. It works for
irreversible Boolean functions because the frame keeps the missing information.
For a reversible rule, the reverse rail alone can reconstruct the prior state;
the before-frame is still the audit record.

### Reversible vs historical

| case | inverse |
|---|---|
| XOR / NOT / XNOR | apply the same (or complementary) function |
| NAND / majority / compare | ledger before-image or frame |
| sequence link | reverse rail (`s-`) or before-frame |
| scratchpad mutation | before-scratch copy |
| route write | reverse rail + before flags |

## 4. Code and tests

`include/nanlm/frame_sync.hpp`, `src/frame_sync.cpp`:

- `FrameSync::target`;
- `FrameSync::meet`;
- `FrameSync::meet_window`.

`tests/test_frame_sync.cpp`:

- runner 0 `0 +4`, runner 1 `7 -3` meet at 4;
- next runner 2 wins;
- same-rail requests fail;
- overlapping windows choose the earliest common frame;
- disjoint windows fail.

`include/nanlm/head.hpp`, `src/head.cpp`:

- `HeadFrame`;
- `capture_head`, `capture_after`, `restore_before`, `restore_after`.

`tests/test_inverse.cpp`:

- train AND, change phase, advance transform, write scratch;
- restore the exact before-frame;
- re-apply the after-frame;
- the head array remains structurally valid.

## 5. Contemplation cycle

A head can evaluate a candidate forward mutation without committing it:

```text
capture before
apply candidate forward mutation
capture after
compute_reverse_frame  -> exact before
compare before == restored before
if commit: compute_forward_frame -> after
else: leave at before
```

`capture_head`, `capture_after`, `compute_reverse_frame`, and
`compute_forward_frame` expose the primitives. `contemplate(view, mutation,
commit)` runs the whole cycle and returns:

```text
ContemplationResult {
    ok, inverse_ok, committed,
    forward_hash, inverse_hash, error
}
```

This is how a head "thinks before it writes": it simulates the forward change,
runs the inverse, verifies the exact restoration, and only then decides whether
to keep the after-frame. The test `tests/test_contemplation.cpp` checks:

- no-commit leaves the exact before-state;
- commit keeps the after-state;
- explicit forward -> reverse -> forward frame computation;
- the head array remains structurally valid.

## 6. Why this matters for the ring

The ring is a sequence of logical frames, not a sequence of wall-clock sleeps.
The forward rail lets a runner race ahead by `+N`; the rollback rail lets a
runner recover by `-M`; the meeting point is where the next runner takes
precedence. Inverse frames make the recovery exact, even for irreversible
Boolean heads.

This is the first design where **forward progress and rollback are the same
mechanism**: the pair cell's two rails, a logical frame index, and a precedence
rule.
