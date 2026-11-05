# Architecture: one global topology

## The central constraint

> There is one global topology. An 8 MiB chart is a local coordinate region of
> that object, not a separate brain. Five replicas host regions of the same
> object; they are not five minds and there is no external semantic
> coordinator.

Everything below follows from that constraint.

```text
                         one global topology G
   ┌──────────────────────────────────────────────────────────────┐
   │  atlas A          charts are coordinate regions             │
   │  cells C          32,896 canonical registers per chart      │
   │  edges E          32,640 pair cells per chart = C(256,2)    │
   │  hyperedges H     multi-cell, multi-chart relations         │
   │  time T           T+ forward, T- reverse                    │
   │  symmetry P       palindrome involution                     │
   │  ledger L         one hash-chained history                  │
   └──────────────────────────────────────────────────────────────┘
```

The initial brain is **one chart**: 65,536 addresses, 32,896 canonical cells,
256 heads, 32,640 pair cells, 8 MiB. Growth adds charts to the same atlas.

---

## 1. Why a chart is not a mind

A chart has its own 16-bit address range, but that range is a *local coordinate
patch*, exactly as a map sheet is not a separate country. The global address is:

```text
global address = (chart path, local 16-bit address, word 0..3, bit 0..63)
```

The chart path is a sequence of head indices. A path of depth `d` adds `8d`
bits. The object is the union of all charts under one address algebra, one rule
set, one hypergraph, one temporal memory, and one ledger.

Consequences:

- A head in chart X and a head in chart Y are local coordinates of the same
  global head field, not two agents that must negotiate.
- A hyperedge may connect any cells in any charts; it is one relation in the
  one object.
- A replica that goes offline loses a cache, not a mind. The object's identity
  is the global digest, not the set of live replicas.
- A chart can be migrated, snapshotted, or regenerated without changing the
  identity of the object.

---

## 2. The 256 × 256 matrix

A local chart is a 256 × 256 matrix. The mapping is:

```text
addr(a, b) = (a << 8) | reverse8(b)
reverse16(addr(a, b)) = addr(b, a)
```

- `a` is the row head, `b` the column head.
- The 256 diagonal cells `a == b` are the palindromic fixed points. **All 256
  are heads.** None is reserved.
- The 32,640 off-diagonal cells are unordered head pairs. Each is one physical
  cell with two orientations.
- The canonical address is `min(addr(a,b), addr(b,a))`; both orientations map
  to the same physical register.

The matrix is the connectome of the chart. A pair cell `(a,b)` is the relation
between head `a` and head `b`; its two rails hold the two directions.

---

## 3. The cell

Each canonical cell is exactly 64 bytes:

```text
offset  size  field
0       32    4 × NaN16 word: s+, s-, q+, q-
32      4     epoch
36      2     16-bit Boolean operator mask `ops`
38      2     generation
40      2     owner (row head)
42      2     aux
44      1     selected rule (0..15)
45      1     flags: head, pair, dual, portal, locked, dirty, checked, shadow
46      18    metadata: provenance, local tag, checksum fragment
```

The four words are the four NaN types:

| word | type | role |
|---|---|---|
| `s+` | +sNaN | forward rail; past → future |
| `s-` | −sNaN | reverse rail; future → past |
| `q+` | +qNaN | forward shadow / validation |
| `q-` | −qNaN | reverse shadow / validation |

The `ops` mask enables Boolean functions; `rule` selects one. A head starts
with all 16 functions enabled; a pair starts with a deterministic two-function
mask derived from the head pair. The mask is a 16-bit field, so self-modifying
learning can flip individual operator bits.

---

## 4. The chart as an 8 MiB full-address register file

A chart is one 8 MiB page. It stores two linked layers:

- **65,536 address registers** (32 B each, 2 MiB): one for every 16-bit
  address, including both orientations of every mirror pair. These carry the
  address-specific identity, mirror link, pair link, capabilities, and tags.
- **32,896 shared pair/head registers** (64 B each, 2 MiB): the pair state is
  stored once; the two address registers point at it.

The rest of the page holds the descriptor table and the link machinery:

```text
0x000000  header (magic, version, genome, counts, root hash)
0x001000  index table: 65,536 × u16 canonical index (128 KiB)
0x021000  canonical table: 32,896 × u16 address (64.25 KiB)
0x031100  pair table: 32,640 × u16 cell index (63.75 KiB)
0x041000  address registers: 65,536 × 32 B (2 MiB)
0x241000  descriptors: 32,896 × 48 B (1.5 MiB)
0x3C2800  shared registers: 32,896 × 64 B (2 MiB)
0x5C4800  head table: 256 × 32 B (8 KiB)
0x5C6800  adjacency bitmap: 256 × 256 bits (8 KiB)
0x5C8800  dirty cells: 32,896 bits (4,112 B)
0x5C9810  dirty addresses: 65,536 bits (8 KiB)
0x5CB810  checksums: 32,896 × u32 (128 KiB)
0x5EBA10  free / extension space (~2 MiB)
0x800000  end
```

Exact offsets are in [04_REGISTER_FILE.md](04_REGISTER_FILE.md).

The register file is **linked**, not just indexed:

- each pair descriptor stores `head_a`, `head_b`, `pair`, `next_a`, `next_b`;
- each head has a row list of its `(h,b)` pairs and a column list of its
  `(a,h)` pairs;
- an 8 KiB adjacency bitmap gives O(1) "are a and b connected?" queries;
- the 32,896 dense pair index is `pair_index(a,b)`; the inverse is
  `pair_heads(index)`.

This is the "all 32k mirror pairs mapped by address hierarchically, with the
256 points and their mirrors, all mapped and linked" requirement.

---

## 5. Hyperedges: relations across spaces

The pair cells are the ordinary graph `E`. A hyperedge is a first-class object:

```text
h = (m1, m2, ..., mk; label, weight, epoch, flags)
```

Each member `mi` is a `Ref` at a chosen resolution:

- bit, byte, 64-bit word, cell, 1 KiB block, 8 MiB page, 2 GiB superpage;
- a `Ref` carries a chart path, so members may live in different charts.

A NaN cell can therefore participate in many relations across many spaces. The
hypergraph is stored at KB resolution: a descriptor at byte resolution, a member
list in a KB block, and incidence at page resolution. This is the "resolution
of resolution" idea: use the coarsest representation that is still exact for
the relation.

The incidence structure gives a hypergraph Laplacian:

```text
L = D_v - I D_e^{-1} I^T
```

where `I` is the incidence matrix and `D_v`, `D_e` are the vertex and edge
degree diagonals. The integer implementation is a weighted diffusion: each
hyperedge distributes its weight over its members. See
[03_MATHEMATICAL_STRUCTURE.md](03_MATHEMATICAL_STRUCTURE.md).

---

## 6. The temporal split

The state space is split into two rails:

```text
S+ : past  -> future    (forward memory)
S- : future -> past     (reverse memory)
```

The 256 fixed points are the **present** anchors: `P(a) = a`. The 32,640 pair
cells are the directed past/future edges: `P(addr(a,b)) = addr(b,a)`.

A bidirectional memory link is:

```text
(past_ref, future_ref, epoch, flags, weight)
```

- `forward(past, t)` returns the future at or before epoch `t`;
- `backward(future, t)` returns the past at or before epoch `t`;
- a state may have several futures (a branch) and several pasts (a merge);
- reversible links are marked; the ledger records before/after hashes.

This is the temporally split state space: forward and reverse are not two
separate databases, they are two orientations of the same pair cells, glued
at the 256 palindromic anchors.

```text
          past ──────► future
             \  pair cell  /
              \  S+ / S-  /
               \   /   \  /
                present (fixed point, P(a)=a)
```

The R18 result that asymmetric storage preserves sequence order while symmetric
storage does not is the empirical seed of this design. Bidirectional memory
keeps the order because the two rails are independent.

---

## 7. Heads and resonance

Each chart has 256 heads, one per palindromic address. A head is a 32-byte
record:

```text
fixed_addr, edge_head, edge_count, child,
phase, energy, load, flags, genome, checksum
```

The head state is a resonance node:

- `phase` and `energy` are integer Q16.16;
- local 16 × 16 lattice edges are strong; longer Hamming-distance coupling is
  weak;
- diffusion is a discrete heat equation, not a float simulation;
- cross-chart hyperedges add coupling between charts.

The heads are not independent agents. They are local samples of one global
field. A head can:

- route activation to its row/column pair list;
- spawn a child chart (a new coordinate region);
- consolidate or sleep when load is low;
- self-modify its operator mask or rule, within a write capability and a
  ledger event;
- be relocated physically without changing its logical identity.

The canonical implementation is `HeadArray` + `HeadView` in
`include/nanlm/head.hpp`: one implementation, 256 address-bound instances, all
views over the same `Universe`. A `HeadView` owns no private semantic state; it
exposes the head record, cell, links, phase engine, runner handoff, 1 KiB
scratchpad (256 B local + 768 B work), Boolean self-modification, and local
history cache. The registry verifies that all 256 palindromic identities exist
exactly once and that no duplicate is possible.

A logical clock (`include/nanlm/clock.hpp`, from `nanclock.zip`) provides a
deterministic `(tick, phase)` stamp. It is a field of the same object, included
in the global digest; it is not a wall clock and not a second topology.

A head also carries a 2-bit **transform phase** (`I, B, BR, R`). This is the
4-phase address oscillator, distinct from the four NaN head classes. The 256
palindromic heads are 240 half-rate and 16 static anchors; the non-fixed cells
are the fast phases. See [15_PHASE_SCHEDULING.md](15_PHASE_SCHEDULING.md).

Growth and consolidation are fields of the same object. A head materializes a
child chart when its self-model error stays high or its scratchpad overflows.
Consolidation replays community scratch into a COW workspace and flips the
manifest only after the R17 base-hash checks. See
[16_GROWTH_CONSOLIDATION.md](16_GROWTH_CONSOLIDATION.md).

Homeostasis is a global scheduling policy, not a negotiation between minds:
load, energy, and fatigue determine which coordinate regions are active,
which are cached, and which are consolidated. Different layers can own
different cognitive loads; the layers are still regions of the one object.

---

## 8. Layers as coordinate responsibilities

The object can be stratified without being fragmented:

| layer | coordinate responsibility | typical structures |
|---|---|---|
| L0 reflex | bit/byte Boolean operations | operator masks, gates, bit pages |
| L1 resonance | 256 heads per chart | phase/energy, local lattice |
| L2 memory | pair cells + hyperedges | associative relations, sequences |
| L3 reasoning | program cells / VM regions | 2CM, self-modifying code |
| L4 consolidation | ledger, snapshots, generations | replay, migration, GC |
| L5 interface | language/teacher adapters | token/byte I/O, evaluation |

A layer is a region of the global topology with a characteristic resolution and
transition rule. It is not a separate state space with its own private history.

---

## 9. Self-modification and learning

A cell can change:

- one bit of a NaN word (`BitAddress`);
- its per-head scratchpad (256 B local + 768 B work);
- its 16-bit Boolean mask (`ops`) by a capability-gated XOR patch;
- one byte or one 64-bit word;
- its `ops` mask (which of the 16 Boolean functions are enabled);
- its `rule` (which enabled function is selected);
- its hyperedge membership or weight;
- its temporal link.

Every durable change should be expressible as a ledger event with before/after
hashes. The write path checks:

1. the page is present;
2. the replica has a write lease / capability;
3. the base hash matches (optimistic concurrency);
4. the change is recorded in the dirty map;
5. the event is appended to the one global ledger.

Learning is integer-only:

- count which Boolean function wins for a cell;
- adjust hyperedge weights by integer deltas;
- adjust resonance phase/energy by integer diffusion;
- evolve operator masks by search over 16 functions;
- distill teacher distributions into counts, not gradients.

This keeps replay deterministic and makes community merging a CRDT-style fold.

---

## 10. What grows, and what does not

Growth adds coordinate charts to the atlas. It does not add:

- a second address algebra;
- a second ledger;
- a second hypergraph;
- a second temporal memory;
- a second identity.

The global digest is:

```text
H( "NLMGLOB1" || pages.root_hash || hypergraph.digest
              || temporal.digest || ledger.head )
```

Two constructions that perform the same operations from the same genesis have
the same digest. A replica that returns a different digest is not a different
mind; it is a divergent cache and must be reconciled or rejected.

---

## 11. The five-replica deployment

Six head runners (`nanlm-cpu-1..6`, 7 GiB each) host regions of the one
object:

```text
                 one global ledger / one global digest
                  ▲          ▲          ▲          ▲
                  │          │          │          │
             replica 1  replica 2  replica 3  replica 4  replica 5
              charts      charts      charts      charts      charts
                  │          │          │          │
                  └──── one atlas / one hypergraph / one time ────┘
```

- chart placement is `hash(chart_path) mod 5`;
- a page write requires a lease and a base-hash match;
- a stale writer is rejected;
- a missing replica is a cache miss, not a lost mind;
- the global ledger is appended by the writer and verified by the others;
- snapshots and deltas make recovery deterministic.

See [07_DISTRIBUTED.md](07_DISTRIBUTED.md).

---

## 12. Design invariants

1. **One object.** No component may introduce an independent semantic state
   space with its own private history or coordinator.
2. **All 256 fixed points are heads.** None is reserved.
3. **All 32,640 pairs are mapped.** One canonical register per unordered pair.
4. **The chart is 8 MiB.** 65,536 address registers + 32,896 shared registers + metadata; no hidden second array.
5. **The pair is the temporal edge.** `s+` forward, `s-` reverse.
6. **The ledger is global.** Replicas append to one history.
7. **The digest is identity.** Charts, hyperedges, time, and ledger are all in
   the digest.
8. **Learning is integer and replayable.** No float in a replay-critical path.
9. **A check that cannot fail is not a check.** Every claim has a test or a
   falsification condition.

Violating any of these is an architectural bug, not a feature.
