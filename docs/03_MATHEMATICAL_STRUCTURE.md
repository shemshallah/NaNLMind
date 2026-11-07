# Mathematical structure

This document states the object precisely. The implementation is a concrete
integer realization; the definitions are the contract.

---

## 1. Local address algebra

Let

```text
A = {0, 1}^16,   |A| = 65,536.
```

Define bit reversal `R : A → A` by reversing the 16-bit word, and byte swap
`B : A → A` by swapping the two bytes. Define canonicalization:

```text
C(x) = min(x, R(x)).
```

`R` and `B` are involutions and commute. The group

```text
K = {I, B, R, B∘R} ≅ Z_2 × Z_2
```

acts on `A`. The action has orbits of size 1, 2, or 4. Exhaustive enumeration
gives 16,576 four-transform orbits, with 16 addresses fixed by all four
transformations.

### Proposition 1 (fixed points)

`R(x) = x` iff bit `i` equals bit `15-i` for all `i`. There are 8 free bits, so

```text
|Fix(R)| = 2^8 = 256.
```

### Proposition 2 (mirror pairs and canonical classes)

```text
non-fixed addresses       = 65,536 - 256 = 65,280
mirror pairs              = 65,280 / 2   = 32,640
canonical classes         = 32,640 + 256 = 32,896.
```

### Proposition 3 (transposition theorem)

Define the matrix address

```text
addr(a, b) = (a << 8) | reverse8(b),   a,b ∈ {0..255}.
```

Then

```text
R(addr(a, b)) = addr(b, a).
```

**Proof.** Reversing the 16-bit word reverses each byte and swaps their order:

```text
R((a << 8) | reverse8(b))
  = reverse8(reverse8(b)) << 8 | reverse8(a)
  = b << 8 | reverse8(a)
  = addr(b, a). ∎
```

Thus bit reversal is matrix transposition on a 256 × 256 grid. The diagonal
`a = b` is exactly the 256 fixed points. The off-diagonal cells are the
unordered pairs.

### Proposition 4 (the pair count is C(256,2))

```text
|{{a,b} : 0 ≤ a < b ≤ 255}| = 256·255/2 = 32,640.
```

The 32,640 mirror pairs and the unordered head pairs are the same set. This is
an identity, not a coincidence.

### Pair index

For `a < b`, the dense index is

```text
π(a,b) = 255a - a(a-1)/2 + (b - a - 1),   0 ≤ π < 32,640.
```

Its inverse is:

```text
find the unique a such that
  Σ_{i=0}^{a-1} (255 - i) ≤ index < Σ_{i=0}^{a} (255 - i)
then b = a + 1 + index - Σ_{i=0}^{a-1}(255 - i).
```

The implementation uses this inverse in `pair_heads()` and verifies it for all
32,640 indices.

---

## 2. Cell state and the 16 Boolean functions

A NaN16 word is 64 bits:

```text
b0 b1      far head, big-endian
b2..b5     payload, little-endian
b6 b7      near head, little-endian
```

The four legal heads are the four NaN types:

| class | head | name |
|---:|---|---|
| 0 | `7FF1` | +sNaN |
| 1 | `FFF1` | −sNaN |
| 2 | `7FF8` | +qNaN |
| 3 | `FFF8` | −qNaN |

The class nibble is

```text
n = (near_class << 2) | far_class,   n ∈ {0..15}.
```

For `BOOL`, bit `k` of `n` is the output for input pair `(a,b)` with
`k = 2a + b`:

```text
BOOL.n(A,B)_lane = n[2A_lane + B_lane].
```

The lane identity is

```text
BOOL.n(0xCCCCCCCC, 0xAAAAAAAA) = n · 0x11111111.
```

The 16 functions are:

| n | function | n | function |
|---:|---|---:|---|
| 0 | constant 0 | 8 | AND |
| 1 | NOR | 9 | XNOR |
| 2 | `~A & B` | 10 | B |
| 3 | NOT A | 11 | `~A | B` |
| 4 | `A & ~B` | 12 | A |
| 5 | NOT B | 13 | `A | ~B` |
| 6 | XOR | 14 | OR |
| 7 | NAND | 15 | constant 1 |

### Mirror law

`BSWAPM` reverses all eight bytes, which rotates the class nibble:

```text
rot2(n) = ((n & 3) << 2) | (n >> 2).
```

Then

```text
BOOL.rot2(n)(A,B) = BOOL.n(~A,B).
```

**Proof.** `BSWAPM` swaps the faces, so the near class becomes the old far
class and the far class the old near class. The truth-table index `2a+b`
becomes `2(~a)+b` under the rotated nibble. Checking the four cases gives the
identity. The implementation tests it for all 16 functions. ∎

### The four rails

A cell stores four words:

```text
s+ = +sNaN    forward rail
s- = -sNaN    reverse rail
q+ = +qNaN    forward shadow / validation
q- = -qNaN    reverse shadow / validation
```

The `ops` field is a 16-bit mask of enabled functions; `rule` selects one. A
head starts with all 16 enabled. A pair starts with a deterministic mask
derived from the two head identities. The mask is itself bit-addressable, so
learning can flip individual operator bits.

---

## 3. The global object

Let `A` be an atlas of charts. A chart `α ∈ A` has a local address space
`A_α ≅ Z_2^16`. The global cell set is

```text
C = ⊔_{α ∈ A} C_α,    C_α = A_α / P,
```

where `P(x) = R(x)` is the palindrome involution and `C_α` is the set of
canonical cells (32,896 per chart).

The one global topology is

```text
G = (A, C, E, H, T, P, L)
```

with:

| component | definition |
|---|---|
| `A` | atlas of coordinate charts; a chart is a local region, not a mind |
| `C` | all canonical NaN cells (32,896 per chart) |
| `E` | ordinary pair edges: `{a,b} ⊂ {0..255}` per chart, 32,640 per chart |
| `H` | hyperedges `h = (m1..mk; label, weight, epoch)`, `mi ∈ C` |
| `T` | temporal transitions, `T = T+ ⊔ T-` |
| `P` | palindrome involution on each chart; `P(α,x) = (α,R(x))` |
| `L` | one hash-chained ledger |

The global address is

```text
(α, x, w, b),   α ∈ A, x ∈ A_α, w ∈ {0..3}, b ∈ {0..63}.
```

A path of `d` head indices gives `|A| = 256^d` charts and a global address

```text
8d + 16 + 2 + 6 = 8d + 24 bits
```

for a cell bit (chart path + local address + word + bit). The initial brain is
`d = 0`: one chart, a 24-bit bit-addressable space, 2 MiB of shared register
payload plus 2 MiB of address registers.

### Why charts are not separate topologies

A chart is a **coordinate patch**. The global object is the union of the
patches under one `P`, one `E`, one `H`, one `T`, and one `L`. A chart has no
private ledger, no private hypergraph, no private identity. Its local 16-bit
coordinates are like coordinates on a map sheet; the country is the atlas.

---

## 4. Ordinary graph and hypergraph

### 4.1 Ordinary graph

Per chart, `E` is the complete graph `K_256` quotiented by the pair cell:

```text
E = {{a,b} : 0 ≤ a < b ≤ 255},   |E| = 32,640.
```

The adjacency matrix `A` is 256 × 256 bits = 8 KiB. It is symmetric with zero
diagonal. The pair cell `(a,b)` carries the two directed weights:

```text
s+(a,b) = W[a][b],    s-(a,b) = W[b][a].
```

For an arbitrary asymmetric matrix `W`, the 32,640 cells round-trip `W`
exactly. The diagonal cells are the 256 head states.

### 4.2 Hypergraph

A hyperedge is

```text
h = (m1, ..., mk; λ, w, τ),   k ≥ 2,
```

where each `mi` is a global `Ref`, `λ` is a label, `w` a Q16.16 weight, and
`τ` an epoch. The incidence matrix is

```text
I ∈ {0,1}^{|C| × |H|},   I_{v,h} = 1 iff v ∈ h.
```

The vertex and edge degrees are

```text
d_v = Σ_h I_{v,h},    d_h = Σ_v I_{v,h} = |h|.
```

The hypergraph Laplacian is

```text
L = D_v - I D_e^{-1} I^T.
```

A single NaN cell can therefore have a meaningful relation with many cells in
many charts. The relation is one hyperedge, not a bundle of pairwise edges.
The integer diffusion step uses the same incidence: each hyperedge distributes
its weight over its members.

---

## 5. Temporal split and bidirectional memory

The temporal structure is a pair of relations:

```text
T+ ⊆ C × C × Z    forward  (past  → future)
T- ⊆ C × C × Z    reverse  (future → past)
```

A temporal link is `(past, future, epoch, flags, weight)`. The link is
**reversible** if the transition function is invertible or if the ledger has
enough before-image history to reconstruct the past.

### 5.1 The two rails

For a pair cell `(a,b)`:

```text
s+ = state of a → b
s- = state of b → a
```

The two rails are independent storage. A forward write touches `s+`; a reverse
write touches `s-`. The fixed-point cells `(a,a)` are the present anchors: `P`
maps them to themselves and they synchronize the two directions.

### 5.2 Bidirectional queries

Given a reference `v` and time `t`:

```text
F(v,t) = { u : (v,u,τ) ∈ T+, τ ≤ t }
B(v,t) = { u : (u,v,τ) ∈ T+, τ ≤ t }
```

`F` is the future set; `B` is the past set. The implementation exposes
`forward`, `backward`, `futures`, and `pasts`. A state may have multiple
futures (a branch) or multiple pasts (a merge).

### 5.3 Reversibility

If a transition is reversible, `T-` is the transpose of `T+`:

```text
(v,u,τ) ∈ T+  ⇔  (u,v,τ) ∈ T-.
```

If it is irreversible, `T-` requires a before-image or a ledger checkpoint.
The R7/R8/R10 reversibility audit already classifies rules as `FULL`, `COND`,
`IRREV`, or `HIST`. The temporal layer uses the same classification.

### 5.4 Sequence memory

An asymmetric 256 × 256 matrix stores an ordered sequence; a symmetric matrix
cannot replay order. This is the R18 sequence-memory result. The temporal split
makes the reason explicit: order lives in the asymmetry between `s+` and `s-`.

---

## 6.1 Logical clock

The clock is a deterministic oscillator over 64 cells with a LE/PAST boundary
at address 0 and a BE/FUTURE boundary at address 63. Its orbit is

```text
HALT -> +qNaN -> LOOP -> -sNaN -> HALT -> ...
```

with a period of 2. The useful object is the stamp

```text
LogicalStamp = (tick, phase),   phase 0 = +qNaN, 1 = -sNaN.
```

The stamp is logical time, not wall time. It orders events, paces commits,
expires leases in ticks, and is reconstructible by replaying the tick. See
[14_TEMPORAL_CLOCK.md](14_TEMPORAL_CLOCK.md).

## 6. Resonance dynamics

The 256 heads form a 16 × 16 lattice. Let `e_i(t)` be the integer Q16.16 energy
at head `i`, and `c_ij = c_ji ≥ 0` the coupling. The update is a discrete heat
equation with a small leak:

```text
e_i(t+1) = clamp( e_i(t) + (1/8) · ( Σ_j c_ij e_j(t)
                                   - e_i(t) Σ_j c_ij ) )
           · 1023/1024
```

with `c_ii = 0`, `0 ≤ e_i ≤ 2^20`. Local lattice neighbors get strong coupling;
long-range Hamming neighbors get weak coupling. The clamp and the leak keep the
field bounded without float arithmetic.

The coupling matrix is symmetric and deterministic. The phase advances by
`e_i(t) / 4096` per step modulo 65536. Coherence is the mean circular phase
agreement of the top-k energy nodes. All operations are integer, so a replay is
bit-identical across compilers.

---

## 7. The palindrome quotient

`P(x) = R(x)` is an involution. Its quotient

```text
C_α = A_α / P
```

has 32,896 classes. The quotient is not a loss of information: each class
stores both orientations in `s+` and `s-`, plus the two shadows. The orientation
is a direction, not a second address.

For a global address `(α,x)`, the mirror is

```text
P(α,x) = (α, R(x)).
```

`P` does not cross charts. Cross-chart relations are hyperedges, not mirrors.
This keeps the local address algebra exact while allowing arbitrary global
relations.

---

## 8. Identity

The global identity is

```text
Digest(G) = H( "NLMGLOB1"
             || Digest(pages)
             || Digest(hypergraph)
             || Digest(temporal)
             || Head(ledger) ).
```

`Digest(pages)` is the Merkle-style hash of all chart digests (sorted by chart
path). `Digest(hypergraph)` serializes every hyperedge in id order, including
members, flags, weight, label, and epoch. `Digest(temporal)` serializes every
link in epoch/id order. `Head(ledger)` is the SHA-256 chain head.

Two constructions that start from the same genesis and apply the same operations
have the same digest. A replica with a different digest is divergent; it must be
reconciled or rejected. The digest is identity, not a signature; publishing the
head is the trust anchor.

---

## 9. State-space size

Per chart:

```text
cells           32,896
canonical bytes 32,896 × 64 = 2,105,344 B  (2 MiB)
payload bits    32,896 × 256 = 8,421,376 bits (1 MiB)
operator bits   32,896 × 16  = 526,336 bits (64 KiB)
address regs    65,536 × 32 B = 2 MiB (every address, both mirrors)
full page       8 MiB
```

At depth `d` (a path of `d` heads, `256^d` charts):

| quantity | formula | d=0 | d=1 | d=2 |
|---|---:|---:|---:|---:|
| charts | `256^d` | 1 | 256 | 65,536 |
| addresses | `65,536·256^d` | 65,536 | 16,777,216 | 4,294,967,296 |
| canonical cells | `32,896·256^d` | 32,896 | 8,421,376 | 2,155,872,256 |
| mirror pairs | `32,640·256^d` | 32,640 | 8,355,840 | 2,139,095,040 |
| payload bits | `2^23·256^d` | 8.4M | 2.15G | 550G |
| full pages | `8 MiB·256^d` | 8 MiB | 2 GiB | 512 GiB |

The combinatorial configuration count is vast but not a performance claim. The
useful measure is the number of live, reachable states under a rule set, which
is an empirical question.

---

## 10. Invariants

The implementation verifies:

1. `R(R(x)) = x` for all 65,536 addresses.
2. `C(C(x)) = C(x)`, `C(x) ≤ x`, `C(x) ≤ R(x)`.
3. Exactly 256 fixed points.
4. Exactly 32,640 pairs; pair index is a bijection.
5. `R(addr(a,b)) = addr(b,a)` for all 65,536 pairs.
6. All 16 Boolean functions match their truth tables.
7. `BOOL.rot2(n)(A,B) = BOOL.n(~A,B)` for all 16 functions.
8. Each chart has 256 heads and 32,640 edges.
9. Every pair descriptor links the correct two heads and the adjacency bitmap
   is symmetric.
10. Bit addressing round-trips through the compact encoding.
11. Copy-on-write aliases do not mutate the original page.
12. A tampered ledger event is rejected.
13. A stale replica commit is rejected.
14. A hyperedge across charts is one relation in the one object.
15. A temporal link supports forward and backward lookup.
16. The global digest is deterministic.

A claim that cannot be expressed as one of these invariants is not yet a claim.


---

## 11. Graph-spectral foundation

The reusable graph-wave, inverse-square void operator, pair-space product graph, eigensystem, pattern-analysis, NaN16/MTH, runner, and NaNNet contracts are specified in [GRAPH_SPECTRAL_FOUNDATION.md](GRAPH_SPECTRAL_FOUNDATION.md). That specification explicitly distinguishes directed W from symmetric coupling A/L and does not infer centrosymmetry from address reversal.
