# Glossary and exact counts

## Counts

| term | value |
|---|---:|
| address bits | 16 |
| addresses | 65,536 |
| palindromic fixed points | 256 |
| mirror pairs | 32,640 |
| canonical cells | 32,896 |
| heads | 256 |
| pair cells | 32,640 |
| NaN types | 4 |
| Boolean functions | 16 |
| NaN words per cell | 4 |
| cell bytes | 64 |
| chart bytes | 8,388,608 (8 MiB) |
| address register bytes | 32 |
| shared cell bytes | 64 |
| head scratch per chart | 262,144 (256 KiB) |
| chart scratch | 65,536 (64 KiB) |
| register bytes per chart | 2,105,344 (2 MiB) |
| descriptor bytes per chart | 1,579,008 (1.5 MiB) |
| depth-1 charts | 256 |
| depth-1 dense bytes | 2 GiB |
| depth-2 charts | 65,536 |
| depth-2 dense bytes | 512 GiB |

## Terms

**Address space.** The set `{0..65535}` with bit reversal `R`. The address is a
coordinate, not merely a pointer.

**Atlas.** The set of charts. A chart is a local coordinate region of the one
global topology. The atlas is not a federation of minds.

**Bidirectional memory.** A temporal relation with forward (`past → future`) and
backward (`future → past`) queries. The two rails of a pair cell are the two
directions.

**Chart.** An 8 MiB coordinate region holding 65,536 address registers, 32,896 shared registers, their
descriptors, the 256-head table, the adjacency bitmap, and the bit/byte/KB
metadata. A chart is a page in the memory tiers.

**Canonical cell.** One representative of a mirror pair or a fixed point:
`C(x) = min(x, R(x))`. There are 32,896.

**Cell.** A 64-byte register: four NaN16 words (`s+`, `s-`, `q+`, `q-`), a
16-bit operator mask, a selected rule, flags, epoch, generation, owner, and
metadata.

**Delta.** An append-only change record with a base hash, a next hash, exact
edits, and provenance. A stale base is rejected; a duplicate is a no-op.

**Edge.** An ordinary pair connection. In a chart, one of the 32,640 pair cells.

**Fixed point.** An address with `R(x) = x`. There are 256; all are heads.

**Global digest.** `H(pages || hypergraph || temporal || ledger head)`. It is
the identity of the one object. It is not a signature.

**Head.** A palindromic fixed point used as a resonance node, router, and
possible chart root. All 256 are used.

**256-Head Array / Palindromic Head Layer.** One canonical head implementation
instantiated exactly 256 times, once per palindromic address. `HeadView` is a
view over the one `Universe`; the instances are address-bound regions, not
private state spaces. `HeadRunner` performs the token handoff.

**Hyperedge.** A first-class relation over two or more `Ref` members, possibly
across charts, with a label, weight, and epoch.

**Incidence.** The matrix `I` where `I[v,h] = 1` iff cell `v` is a member of
hyperedge `h`.

**Ledger.** The one hash-chained history of committed events. Replicas do not
own private ledgers.

**Mirror pair.** A pair `{a,b}` of distinct addresses with `b = R(a)`. There
are 32,640.

**NaN16.** The 64-bit word: far head, 32-bit payload, near head. The four legal
heads are the four NaN types.

**Pair cell.** The canonical cell for an unordered pair of heads. It stores the
two directed rails and is the temporal edge.

**Palindromic NaN.** A NaN16 word whose address is a fixed point of `R`. The
design uses all 256 such addresses as heads.

**Q16.16.** A signed 32-bit fixed-point number with 16 integer bits and 16
fraction bits. Used for resonance and weights to keep replay deterministic.

**Replica.** A host/cache of regions of the one global topology. It holds
leases; it is not an independent mind.

**Resolution.** The granularity of a `Ref`: bit, byte, word, cell, KB, page, or
superpage.

**Temporal split.** The organization `T = T+ ⊔ T-` of the state space into
forward and reverse memory, glued at the 256 fixed points.

**Transposition theorem.** `R(addr(a,b)) = addr(b,a)`. Bit reversal is matrix
transposition on the 256 × 256 grid.

**Universe.** The old name for an 8 MiB chart. In the new documentation, "chart"
is preferred because it emphasizes that the region is a coordinate patch of one
object, not a separate universe.

## Symbols

| symbol | meaning |
|---|---|
| `A` | atlas of charts |
| `C` | all canonical cells |
| `E` | ordinary pair edges |
| `H` | hyperedges |
| `T` | temporal transitions (`T+`, `T-`) |
| `P` | palindrome involution `R` |
| `L` | one ledger |
| `R` | 16-bit reversal |
| `C(x)` | `min(x, R(x))` |
| `addr(a,b)` | `(a << 8) | reverse8(b)` |
| `π(a,b)` | dense pair index |
| `I` | incidence matrix |
| `D_v`, `D_e` | vertex/edge degree matrices |
