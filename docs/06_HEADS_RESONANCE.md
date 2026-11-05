# Heads, resonance, and self-modification

## 1. Every palindromic NaN is a head

A 16-bit address is palindromic iff `reverse16(a) = a`. There are exactly 256
such addresses. The design uses **all 256**; none is reserved for a special
purpose, and none is left unused.

The head at index `h` has the fixed address

```text
fixed_addr(h) = (h << 8) | reverse8(h)
```

The 8 free bits of the palindrome are exactly `h`, so the 256 heads are a
16 × 16 lattice:

```text
h = 16·row + col,   row = h >> 4,   col = h & 15.
```

The lattice is not an arbitrary visualization. It is the geometry induced by
the free bits of the address. A local lattice edge is a one-bit change in the
free pattern; a longer Hamming distance is a longer jump.

---

## 1.1 The 256-Head Array (Palindromic Head Layer)

There is one canonical head implementation, not 256 separate implementations.
It is instantiated exactly 256 times, once per palindromic address:

```text
H_i = Head(palindromic_address_i),   i = 0..255
```

The implementation is `HeadArray` + `HeadView` in
`include/nanlm/head.hpp`. A `HeadView` is a *view* over one `Universe`; it does
not own a private semantic state space. The 256 instances are address-bound
regions of the one object.

| component | responsibility | implementation |
|---|---|---|
| `HeadState` | phase, energy, load, epoch, generation | `Head` record + head `NanCell` |
| `HeadAddress` | unique palindromic 16-bit identity | `HeadAddress` |
| `PhaseEngine` | QNaN/SNaN transitions | `HeadView::phase`, `set_phase`, `phase_step` |
| `Runner` | receive, process, hand off a token | `HeadRunner::run` |
| `MirrorEngine` | palindromic orientation / counterpart | `HeadAddress`, `Universe::mirror`, pair links |
| `HeadLinks` | row/column pair links, adjacency | `HeadView::links`, `adjacent_to` |
| `HeadHistory` | local event ring (cache; ledger is authority) | `HeadHistory` |

Key rules:

- exactly 256 valid identities; the registry rejects a duplicate or a
  non-palindromic address;
- every head uses the same `kImplementationId`;
- local state is the head record/cell, not a copy;
- a runner handoff follows a real pair-cell edge (the first row link, or the
  first column link for head 255);
- the handoff preserves the epoch and phase in the token;
- a stale token is rejected;
- the 256 heads are not threads; a scheduler can run them across any number of
  cores;
- the whole array serializes and reconstructs with the chart.

The tests in `tests/test_heads.cpp` check all 256 addresses, uniqueness, the
registry, phase transitions, runner handoff, stale-token rejection, history
wrap, serialization, and the one-object view through `GlobalTopology`.

---

## 2. Head record

Each head is 32 bytes:

```text
fixed_addr   u16   the palindromic anchor
edge_head    u16   first pair index in the row list
edge_count   u16   255
child        u16   child chart pointer / id
phase        u32   Q16.16 phase
energy       u32   Q16.16 energy
load         u32   homeostasis
flags        u32   active / sleeping / consolidating / failed
genome       u32   deterministic seed
checksum     u32
```

The head is a **resonance node** and a **router**:

- resonance: phase/energy participate in the global field;
- routing: the head walks its row list `(h,b)` and column list `(a,h)`;
- growth: a head can own a child chart (a new coordinate region);
- homeostasis: load and energy decide whether the region is active;
- self-modification: the head can change its operator mask, rule, or links
  within a capability and a ledger event.

The head is not an independent agent. It is a local coordinate expression of
one global field.

---

## 3. Resonance

### 3.1 The integer equation

Let `e_i(t)` be Q16.16 energy at head `i`, and `c_ij = c_ji ≥ 0` the coupling.
The update is:

```text
e_i(t+1) = clamp( e_i(t) + (1/8) · ( Σ_j c_ij e_j(t)
                                   - e_i(t) Σ_j c_ij ) )
           · 1023/1024
```

with `c_ii = 0` and `0 ≤ e_i ≤ 2^20`. This is a discrete heat equation with a
small leak. It is integer-only, so replay is deterministic.

### 3.2 Coupling

The coupling has two parts:

- **local lattice**: Manhattan distance 1 is strong (0.80), 2 is 0.50, 3 is
  0.25, 4 is 0.125;
- **long-range**: Hamming distance 1..8 gives 0.40 down to 0.03.

The local part creates a wave that can cross the 16 × 16 lattice; the long-range
part gives weak global mixing. The coupling matrix is symmetric, zero-diagonal,
and deterministic.

### 3.3 Coherence

Coherence is the mean circular phase agreement of the top-k energy nodes:

```text
d = |phase_i - phase_j| mod 65536
d = min(d, 65536 - d)
coherence = mean(65536 - d)
```

It is an integer in `[0, 65536]`. It is a measurement, not a claim of
consciousness or synchronization in a physical sense.

### 3.4 What the R18 archive established

R18 used a float simulation and reported:

- 0 → 15 in 48 steps;
- 0 → 255 in 148 steps;
- coherence 0.992 → 0.959;
- learning within a few exposures;
- 500 facts at 100% probe accuracy;
- multi-hop depth 4;
- resonant recall.

Those are useful target behaviors. The new core uses the integer equation and a
different propagation speed (the current test reaches 0 → 255 in 7 steps with
the heat equation and threshold 0.3). The exact step count is not the claim;
the claim is that the field is deterministic and measurable.

---

## 4. Cross-chart resonance

A hyperedge may connect heads in different charts. It adds a coupling term:

```text
c_ij += w_h / (|h| - 1)   for every hyperedge h containing i and j.
```

The global field is therefore not a collection of per-chart fields. It is one
field with local lattice structure and cross-space hyperedges. A head in chart
A can influence a head in chart B through one relation, without a coordinator.

This is the resonance version of the "one global topology" constraint: the
charts are coordinate regions, and the field is global.

---

## 5. Homeostasis

Homeostasis is a scheduling policy over the one object, not a negotiation
between minds. Each head carries:

- `energy`: current resonance amplitude;
- `load`: recent routing/activation work;
- `flags`: active, sleeping, consolidating, failed;
- `child`: a child chart if the head has grown a region.

A simple policy:

| condition | action |
|---|---|
| `load > high` and `energy > threshold` | activate, prefetch child charts |
| `load < low` and `energy < threshold` | sleep, evict cold pages |
| repeated high load across epochs | spawn a child chart, split the routing |
| conflict / contested facts | keep both, mark contested, do not overwrite |
| failure | reset local state, preserve identity and collective facts |

The policy is global: it sees all charts, all replicas, and the ledger. It is
not an external semantic coordinator; it is a scheduler over one object.

---

## 6. Self-modification

A head can modify:

- one bit of a word (capability / dirty / operator bit);
- one byte (tag / head id / small counter);
- one 64-bit word (NaN rail);
- its 16-bit `ops` mask;
- its selected `rule`;
- its hyperedge membership or weight;
- its temporal links.

The write path:

1. resolve the chart and cell;
2. check the capability and lease;
3. copy-on-write if the page is shared;
4. apply the change;
5. mark the cell dirty;
6. append a ledger event with before/after hashes;
7. bump the generation.

Self-modification is not free: it costs a write, a hash, and a ledger entry.
A head cannot silently rewrite the object. The ledger is the audit trail.

### 6.1 Per-head scratchpad

Every head owns a 1 KiB scratchpad in the chart extension:

```text
0..255      local registers / small stack
256..1023   working memory: Boolean operands, truth-table patches, results
```

The scratchpad is part of the one `Universe` (`HeadScratch`), not a private
heap. `HeadView::scratch()` exposes it. The runner writes the token payload and
phase into the local area, evaluates the selected Boolean function over the
first eight bytes, and writes the 32-bit result into the work area. This gives
each head a small, local, deterministic working memory without creating a
separate address space.

The chart also has a 64 KiB shared scratch area for cross-head exchange. It is
one field of the same object.

### 6.2 Boolean self-modification

The head's `ops` field is a 16-bit truth-table mask; `rule` selects one of the
enabled functions. The archive's Boolean lineage is:

- R11 `RuleOpDispatch`: one fixed rule interprets an opcode in `aux`; the
  operation is selected by state, not by swapping rules;
- R13 `VmStoreProg`: a program writes its own program word (NOP → OUT);
- NaNLM `LAYERS.md` / `ALIEN.md`: `STW` writes the class nibble `n` of a
  `BOOL.n` slot, so the next instruction executes a different truth table.

The new head layer makes this direct:

```text
self_modify_boolean(patch)  ->  ops := ops XOR patch
                                rule := lowest enabled function
```

The operation is capability-gated (the address register must have write
permission), checksum-refreshed, and recorded in the head history. A runner
token with the high bit set applies the low 16 bits as a patch:

```text
payload = 0x8000_000F  ->  ops := ops XOR 0x000F
```

This is the smallest useful self-modifying Boolean unit: 16 bits of function
space, one XOR patch, one ledger event. It is intentionally not a claim that
the head can rewrite arbitrary code without a capability.


### Learning the mask

The operator mask has only 16 bits. A cell can learn which of the 16 Boolean
functions works by counting outcomes:

```text
score[n] += 1   if function n produced the desired bit
score[n] -= 1   otherwise
ops = { n : score[n] > threshold }
rule = argmax score[n]
```

This is an integer, replayable, mergeable learner. It is not backpropagation.
It is a search over a 16-element function space, which is small enough to
exhaust or evolve.

---

## 7. Bidirectional memory

The pair cell `(a,b)` is the temporal edge. The two rails are:

```text
s+(a,b) = forward  (a → b)
s-(a,b) = reverse  (b → a)
```

A temporal link adds an epoch and a weight:

```text
(past, future, epoch, flags, weight)
```

The query functions are:

- `forward(past, t)` → the most recent future at or before `t`;
- `backward(future, t)` → the most recent past at or before `t`;
- `futures(past)` → all futures (branch);
- `pasts(future)` → all pasts (merge).

The 256 fixed points are the present anchors. They are the only cells where the
two orientations coincide. Everything else is a directed past/future relation.

### Why the split matters

An asymmetric matrix stores order; a symmetric matrix does not. The R18
sequence-memory experiment is the empirical version of this statement. The
temporal split makes the mechanism explicit:

- a sequence `A → B → C` stores `s+(A,B)`, `s+(B,C)`, and the reverse rails
  `s-(B,A)`, `s-(C,B)`;
- forward replay walks `s+`; backward replay walks `s-`;
- a checkpoint or ledger event makes an irreversible transition reversible
  enough to reconstruct.

This is the "bidirectional memory" the state space is organized to enable.

---

## 8. Identity and relocation

A head's logical identity is its index and fixed address, not its physical page.
A page can migrate from replica 1 to replica 3; the head keeps:

- the same `fixed_addr`;
- the same row/column links (recomputed from the pair index);
- the same collective facts and provenance;
- the same ledger position.

The R16/R17 experiments already test this: head failure, physical relocation,
page migration, and the disappearing head. The new object keeps the same
principle: identity is logical, residence is physical.

---

## 9. Specialization

The 256 heads can specialize without becoming separate minds:

- specialization is a distribution over task classes per head;
- the collective state is shared;
- conflicting claims are preserved as contested;
- a head can transfer a skill without erasing its old specialty;
- a head can fail and be reconstructed from the collective state.

The R15 result (lateral inhibition, MI 2.58 bits) is the target. The new
implementation currently uses a deterministic genesis and a head-level
`special_score` placeholder; the next milestone is a substrate-only
specialization rule, not a host k-means loop.

### What would count as a real result

1. A head specialization measure that beats a shuffled null by a pre-registered
   margin.
2. The specialization survives a head reset and a page migration.
3. The same result under a fixed rule map, with only the initial state
   differing.
4. A held-out relation task where head coordination beats a no-heads baseline.

Until then, specialization is a hypothesis with a promising prototype.

---

## 10. Invariants

1. All 256 palindromic addresses are heads; none is reserved.
2. A head's row list plus column list covers 255 edges.
3. A head's identity is `(index, fixed_addr)`, independent of page location.
4. Resonance energy is bounded and integer.
5. Coupling is symmetric with zero diagonal.
6. A cross-chart hyperedge adds coupling without creating a separate field.
7. A self-modification is a ledger event with before/after hashes.
8. A failed head does not erase the collective state.
9. A temporal link has a forward and a backward query.
10. A head is a coordinate of one field, not an independent agent.
