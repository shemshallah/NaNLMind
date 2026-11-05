# Rebuilding reporam and repovram

The old `reporam`/`repovram` tiers were built for a 30B MoE: 4 MiB pages,
16 release bins of ~1.99 GiB, page ranges over HTTP, append-only deltas, and a
compaction job. That geometry is still good. What changes is the object it
serves:

> The tiers store regions of **one global topology**, not independent models
> or independent minds. A page is a chart; a chart is a local coordinate
> region. A replica hosts pages and holds leases; it does not own a history.

---

## 1. Two tiers, one object

| tier | old role | new role |
|---|---|---|
| **reporam** | KV cache + registers + scratch | mutable live state: charts, dirty pages, hyperedges, temporal links, mailboxes, leases, journal |
| **repovram** | tiled GGUF weights | immutable generations: compiled charts, snapshots, manifests, genome, evaluation cards, cold hyperedge blocks |

Both tiers use the same page geometry and the same content hash. The difference
is mutability:

- **reporam** is append-only at the object level. A write creates a delta; a
  compaction folds deltas into a new generation. Readers see a consistent
  generation; writers append.
- **repovram** is write-once per generation. A published generation is
  immutable. A new generation gets a new manifest and a new root hash.

A generation is a complete description of a global object at an epoch:

```text
generation = (manifest, chart set, hypergraph blocks, temporal blocks,
              ledger head, evaluation card, parent generation)
```

---

## 2. Page = one chart = 8 MiB

The page is 8 MiB because one chart is exactly 8 MiB:

```text
65,536 address registers × 32 B = 2 MiB
32,896 shared registers × 64 B = 2 MiB
32,896 descriptors × 48 B = 1.5 MiB
tables + adjacency + heads + dirty + checksums ≈ 0.5 MiB
head scratchpads (256 × 1 KiB) = 256 KiB
chart scratch = 64 KiB
extension (hyperedges, mailboxes, capability tables) ≈ 1.77 MiB
```

A page is the atomic unit of:

- allocation;
- placement on a replica;
- copy-on-write;
- migration;
- snapshot;
- hash verification;
- cache eviction.

A chart path is the page key:

```text
PageId = (depth, path[0..3])
```

Depth 0 is the root chart. Depth 1 is a child of a root head. Depth 2 is a
grandchild. The current 64-bit `BitAddress` encoding supports depth 0..4; a
128-bit encoding extends the same scheme to depth 12.

---

## 3. Geometry

### 3.1 Compatibility geometry

The existing deeprepo geometry is:

```text
16 bins × 255 pages × 8 MiB = 31.9 GiB virtual per tier
```

This is enough for:

- the whole depth-1 brain (256 charts = 2 GiB) in two bins;
- a large working set of depth-2 charts;
- history, deltas, hyperedges, and temporal links;
- five replicas with independent caches.

### 3.2 Symbolic geometry

A second geometry is available for the pair-indexed object:

```text
64 bins × 510 pages = 32,640 pages = 255 GiB virtual per tier
```

32,640 is the number of mirror pairs. That is a useful symbolic geometry: one
page per mirror pair, if a deployment ever wants to map the storage layout
directly onto the pair structure. It is **not** a requirement; the semantic
object is still one topology, and a page is still a chart.

### 3.3 Sparse rule

An unwritten page reads as zeros and is not stored. The virtual size is not a
disk cost. The real cost is the number of live pages plus the journal.

---

## 4. What is stored where

### 4.1 reporam (mutable)

| region | contents |
|---|---|
| `charts/` | live chart pages; dirty / sealed / read-only |
| `journal/` | append-only deltas: `d-<seq>.dlt` |
| `manifest/` | current generation pointer, parent, page set root |
| `leases/` | writer leases: page range, replica id, expiry, base hash |
| `hyper/` | hyperedge blocks, incidence tiles, labels, weights |
| `time/` | temporal links, epoch index, reversible history |
| `mail/` | head inboxes / outboxes (8 KiB per head) |
| `regs/` | global registers: genesis, head pin, budget, ring health |
| `metrics/` | throughput, page faults, dirty counts, replay time |

### 4.2 repovram (immutable)

| region | contents |
|---|---|
| `manifest/` | generation manifest, root hash, parent, eval card |
| `charts/` | immutable chart pages for the generation |
| `hyper/` | immutable hyperedge blocks |
| `time/` | immutable temporal blocks |
| `snap/` | full-object snapshots |
| `genome/` | the seed / genome that generates the genesis |
| `card/` | evaluation and provenance |
| `mirror/` | optional mirror locators (S3/B2/IPFS) |

A generation is published only when:

1. the manifest is committed;
2. every page hash is present;
3. the global digest is recomputed and matches;
4. at least one independent mirror exists;
5. the evaluation card passes the gates.

---

## 5. Page format

The 8 MiB chart body is specified in [04_REGISTER_FILE.md](04_REGISTER_FILE.md).
The storage envelope adds:

| field | size | purpose |
|---|---:|---|
| magic | 8 | `NLMSTOR1` |
| version | u32 | envelope version |
| kind | u8 | chart / hyper / temporal / snapshot / manifest |
| flags | u8 | compressed / encrypted / sealed / delta |
| chart_path | 5 | depth + path |
| epoch | u64 | generation epoch |
| payload_hash | 32 | SHA-256 of the body |
| parent_hash | 32 | previous page hash |
| body_len | u32 | uncompressed length |
| body | variable | chart body or block |
| trailer | 32 | optional page checksum |

The envelope is content-addressed. The page key is
`H(kind || chart_path || epoch || payload_hash)`. Two pages with the same key
are the same page; a writer never modifies a published page in place.

---

## 6. Delta journal

A delta is a small, append-only record:

```text
Delta {
  page: PageId
  base: Hash256        // hash of the page before the delta
  next: Hash256        // hash after applying the delta
  epoch: u64
  cells_changed: u32
  ops: [ (cell, word, bit, old, new) ]  // exact bit-level edits
  hyper_ops: [ add/remove/update ]
  time_ops: [ link/unlink ]
  actor: u8
  parent_event: u32
}
```

Rules:

- apply is idempotent by `(page, base, next)`;
- a stale `base` is rejected (optimistic concurrency);
- a delta is committed only if the base hash matches the current page;
- a duplicate delivery is a no-op;
- an interrupted delta is uncommitted and discarded;
- the ledger records the event, the before/after hashes, and the actor.

Compaction:

1. collect a consistent generation;
2. apply all deltas to the base pages;
3. write new trimmed pages;
4. compute the new root;
5. write a manifest;
6. publish the generation;
7. delete consumed deltas and old pages;
8. keep the previous generation for rollback.

This is the same append-only + compaction pattern as the old reporam, but the
payload is a chart, not a KV row.

---

## 7. Leases and capabilities

A write is a capability, not an implicit right:

```text
Lease {
  page: PageId
  replica: u8
  epoch: u64
  base_hash: Hash256
  expires: u64
  mode: read | write | execute | own
}
```

Rules:

- one writer per page at a time;
- the lease carries the base hash;
- a write without a lease is rejected;
- a stale lease is rejected;
- a page can have many readers;
- a page can be copied-on-write by a reader with a write lease on the copy;
- the global ledger is the single history; a replica never has a private one.

A capability is a bit-level mask:

```text
R = read, W = write, X = execute, O = own, S = seal, M = migrate
```

Capabilities can be attached to a page, a KB block, a cell, or a bit. The
bit-level capability is the finest resolution; the page-level capability is the
coarsest.

---

## 8. Hyperedges and temporal blocks at KB resolution

A hyperedge descriptor is small (id, flags, weight, label, epoch, arity). Its
member list can be large and may cross charts. Store:

- descriptor at byte resolution in the chart's descriptor area;
- member list in 1 KiB blocks in `hyper/`;
- incidence tile (which hyperedges touch a page) at page resolution;
- label/weight table at KB resolution.

A temporal link is small enough for a 32-byte record. Store links in `time/`
with an epoch index; a range query `[t0,t1)` scans the epoch index, not the
whole object.

The rule is: **do not inflate a bit into a page**. A 1-bit capability is a bit;
a 256-member hyperedge is a KB block; a chart is a page. The resolution is part
of the data model.

---

## 9. API contract

A backend only has to provide:

```text
read(key, offset, length) -> bytes
write(key, bytes) -> hash
contains(key) -> bool
list(prefix) -> keys
hash(key) -> Hash256
```

Transactional helpers:

```text
lease(page, replica, base_hash, ttl) -> Lease
append(delta) -> CommitResult
commit(delta) -> CommitResult
snapshot(epoch) -> PageSet
compact(epoch) -> Generation
verify(manifest) -> bool
```

The object layer (`GlobalTopology`) does not know whether the backend is a
local file, a GitHub release, S3, B2, or a volunteer RAM farm. The manifest is
the contract; the hash is the identity.

---

## 10. Lifecycle

```text
allocate chart
  -> map into the atlas
  -> write bits / hyperedges / temporal links
  -> mark dirty
  -> flush to a delta
  -> commit to the ledger
  -> compact into a generation
  -> publish to repovram
  -> keep the parent for rollback
  -> evict cold pages to remote storage
```

A replica can disappear at any step:

- before commit: the delta is discarded; the state is unchanged;
- after commit, before compaction: replay the journal;
- after compaction, before publish: the new generation is not visible; the old
  generation still serves;
- after publish: the generation is immutable and can be mirrored.

---

## 11. Failure modes

| failure | response |
|---|---|
| stale writer | reject the delta; reread the page; rebase |
| duplicate delta | idempotent no-op |
| interrupted commit | discard uncommitted delta; replay from the last committed head |
| corrupted page | reject by payload hash; fetch from a mirror |
| missing page | read as zeros; rehydrate from a generation or a peer |
| replica partition | reads continue from cache; writes fail closed until a lease is obtained |
| split brain | impossible by construction: one ledger + base-hash leases; a divergent cache is rejected |
| deleted release asset | fetch the same hash from a mirror |
| manifest mismatch | refuse the generation; keep the parent |
| tampered ledger | locate the first bad event; restore from a pinned head |

The one-object rule is what makes split brain impossible: there is no second
semantic object to fork. There can be stale caches, but not two minds.

---

## 12. Migration from the old tiers

The old tiers are not thrown away. They are repurposed:

1. keep the 8 MiB page size and the 16-bin × 255-page geometry;
2. replace the GGUF/KV payload with chart/hyper/time blocks;
3. keep the append-only delta + compaction mechanics;
4. keep the range-read page cache;
5. replace the model manifest with a global-topology manifest;
6. keep the budget/lease/ring control plane;
7. add a `NLMSTOR1` envelope and a `NLMGLOB1` global digest.

The deeprepo runner ring remains the execution layer. The new object uses the
same five slots, the same 7 GiB budget, and the same GitHub release backends.

---

## 13. Invariants

1. A page is one chart; a chart is a coordinate region of one object.
2. A published page is immutable.
3. A delta has a base hash and a next hash; a stale base is rejected.
4. A duplicate delta is a no-op.
5. A lease is required for a write; a stale lease is rejected.
6. The global ledger is the only history; replicas do not own one.
7. A generation is published only with a manifest, a root hash, and a mirror.
8. An unwritten page reads as zeros and costs nothing.
9. A bit capability is stored as a bit; a KB hyperedge list is stored as a KB
   block; a chart is stored as a page.
10. A replica loss is a cache miss, not a lost mind.
