# UTM / 2-counter roadmap — long-term, not implemented

**Status:** architectural goal. Do not claim UTM equivalence until U1–U3
pass. Existing semiring, NTT, heads, and puzzles are not a transition function.

## 1. Target theorem

There exists a fixed chart transition `δ` and a computable encoding `e` such
that for every TM `M` and input `x`, iterating `δ` from `e(M,x)` simulates
`M(x)`. Diverges when `M` diverges.

Proof path:

```text
TM -> 2CM theorem
+ 2CM correctly implemented in chart
+ unbounded counters by atlas paging
```

## 2. Why 2CM first

A Minsky two-counter machine is the smallest practical universal model:

```text
INC0, INC1, DEC0, DEC1, JZ0 target, JZ1 target, HALT
```

Counters are limb lists in chart cells; program/state/IP/HALT are fixed cells.
`step` fetches a program cell and writes chart state. No host `if (task == ...)`.

## 3. Required invariants

| requirement | chart meaning |
|---|---|
| fixed δ | one pure `step(chart)` or fixed ROM microcode |
| config in chart | program, state, counters, IP, HALT all cells/rails |
| simulation | decode(chart after k) == reference after k |
| unbounded memory | counter grows via atlas page allocation |
| finite program per M | documented encoding `M -> initial chart` |

## 4. Milestones

### U1 — bounded 2CM

- fixed size counters (e.g., 64-bit limbs);
- programs: add, multiply, copy, gcd loops;
- pure step; replay from snapshot bit-identical;
- matches reference 2CM.

### U2 — multi-limb counters in chart

- no host bigint;
- limbs in cells; carry/borrow in chart;
- growth until page limit.

### U3 — atlas paging

- fixed allocator; page links; ledger commits;
- counter growth continues after first 8 MiB chart;
- same δ, no task-specific host allocation.

### U4 — TM → 2CM → chart encoding

- document TM description -> program cells + initial counters;
- simulate small TMs (unary add, BB(2)-class toys).

### U5 — optional UTM program in ROM

- one fixed program runs multiple machine descriptions;
- input tape elsewhere in chart/atlas.

## 5. Stop conditions

- `step` needs host task-specific branches;
- counters stored in host `vector<uint64_t>` rather than chart;
- growth only by allocating a new host object;
- decoded orbit diverges from reference;
- "UTM" claim based only on NTT/semiring exactness.

## 6. Immediate order later

1. Freeze `step`.
2. Single-chart 2CM with fixed capacity + tests.
3. In-chart multi-limb + allocator.
4. Page growth under fixed rules.
5. Publish encoding doc and CI reference orbit.
6. Only then optional UTM ROM.

## 7. Relationship to current work

```text
semiring closure      inheritance/indexing
NTT/F257              correlation/sketch
Boolean heads         gates
hypervectors          local associative memory
2CM/UTM               computation orbit
```

The first four are the physics/index of the space. They do not replace the
simulation theorem.
