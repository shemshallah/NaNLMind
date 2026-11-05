# Point 128, over-bootstrap, and the layer stack

**Status:** design record. This is the first coherent plan for the bootstrap
orchestrator. It does not replace the single-universe gates in
[24_ONE_UNIVERSE_TRAINING.md](24_ONE_UNIVERSE_TRAINING.md).

## Current scope

The buildable scope is only:

```text
one 8 MiB bootstrap universe (256 heads, point 128 local orchestrator)
one 2 GiB over-universe capacity (256 system slots)
slot 128 = the bootstrap system
slots 0..127 and 129..255 = 255 possible other systems, uninstantiated
```

There is **no macrocluster storage yet**. The 2 GiB over-universe is a
memory-mapped capacity on the bootstrap GitHub runner, not a populated
macrocluster. Route diffs stay local until a macrocluster exists. The 255 other
systems are reserved slots, not live storage.

---

## 0. Decision summary

```text
one 8 MiB bootstrap universe (256 heads, point 128 control)
+ one 2 GiB over-universe = 256 x 8 MiB system slots
+ slot 128 = bootstrap; 255 other slots are possible, not instantiated
+ point 128 is a per-universe control portal, not a head
+ Hopfield-style sparse routing over logical heads
+ directed pair/BPE tokens (not unordered pair tokens)
+ Android route diffs remain local; macrocluster merge is deferred
+ a separate NaNLM_128_bootstrap repository
```

Point 128 is the **local orchestrator**, not a new mind and not a 257th head.
It stores pointers to its route table; the table itself lives in the
over-bootstrap bank, not in a 1 KiB scratchpad.

---

## 1. Hard invariants

These cannot be relaxed without breaking the existing tests:

1. There are exactly **256 palindromic heads**.
2. The 256 heads are the diagonal `matrix_addr(i, i)`, not arbitrary points.
3. `32,640 = C(256,2)` mirror pairs and **32,896 canonical cells** stay fixed.
4. One global ledger and one global digest.
5. A chart is a coordinate region, not an independent mind.
6. A 1 KiB head scratchpad is local cache; it is not a routing table.

### 1.1 Point 128 is a portal, not a head

Raw point **128 = 0x0080** is not palindromic:

```text
reverse16(0x0080) = 0x0100
```

So `0x0080` and `0x0100` are the two addresses of one off-diagonal mirror pair.
Point 128 is therefore a **control portal**, not one of the 256 heads. The
orchestrator role is a capability on that portal. It may read/write head records
and route messages, but it does not vote in the head top-k.

The head **index** 128 is different:

```text
matrix_addr(128, 128) = 0x8001
```

`0x8001` is a normal palindromic head. If the intent was "head number 128",
that is `0x8001`. This design reserves raw point `0x0080` instead, preserving
"all 256 palindromic heads".

### 1.2 Heads are logical, not machines

A head is a 256-ary logical role. A runner is a process; a node is a machine.
The six-runner ring proves that 256 heads can be mapped across six runners.
"Other x86 systems" is a deployment choice, not a requirement that each head
needs one x86 box. The bootstrap bank is 2 GiB total; six runners can hold it.

---

## 2. Namespace

The 32-bit word path is:

```text
WordRef = [Universe:8][Macrocluster:8][Cluster:8][Point:8]
```

The bootstrap control path is:

```text
U0 / MC128 / C128 / P128 = 0x00 80 80 80 = 0x00808080
```

The low byte is the chart point. Point 128 (`0x80`) is reserved as the
orchestrator portal in every chart. It is a route, not a content address.

### 2.1 Point 128 mapping

```text
point 0x0080 (control)  -> RouteBin
point 0x0100 (mirror)   -> ReplyBin
```

The canonical pair cell is `0x0080`; `s+` is the request rail and `s-` is the
response rail. The 64-byte cell holds a small header and a `BankRef`; the full
route table is a formatted bin.

### 2.2 `Point128Table` schema

```text
header:
  magic, version, base_generation, epoch
  universe, macrocluster, cluster, point
  head_count = 256, table_bin, checksum

entry (one per logical head):
  head            u8
  layer           u8
  flags           u8
  active          u8
  key_hash        u32
  bank            u16
  bin             u32
  slot            u16
  strength        i16
  epoch           u64
```

256 entries at ~32 B = ~8 KiB. That is a small diff, not a 2 GiB upload.
The 1 KiB scratchpad caches 8–16 hot entries; the authoritative table is the
bin.

---

## 3. Memory model

### 3.1 Exact size identity

```text
2 GiB = 2,147,483,648 bytes
8 MiB =     8,388,608 bytes
2 GiB / 8 MiB = 256
```

The over-bootstrap is therefore exactly **256 system slots**, not 256 filled
systems. Slot 128 is the bootstrap. The other 255 slots are the possible other
systems. Only slot 128 is instantiated now; the rest are reserved capacity. This
is not an arbitrary 2 GB blob and not a macrocluster yet.

### 3.2 Runner budget

```text
7 GiB runner
- 2 GiB over-universe capacity (256 x 8 MiB slots)
- 8 MiB bootstrap working chart (slot 128's live image)
= 4.992 GiB theoretical headroom
```

Real headroom is less after the OS, compiler, Python, and page cache. Target
resident use ≤ 4 GiB, and treat 2 GiB as a sparse/memory-mapped bank rather than
a forced resident allocation.

### 3.3 Android budget

Android trains the 8 MiB bootstrap chart and its local point-128 table. It does
**not** load the 2 GiB over-universe. A route diff is written locally; upload
and merge are deferred until macrocluster storage exists.

```text
phone: 8 MiB chart + local route table + small cache
runner: 2 GiB over-universe capacity + 8 MiB bootstrap working chart
future: macrocluster merge endpoint
```

### 3.4 Bank layout

```text
bank 0: bootstrap working chart (8 MiB, slot 128 image)
bank 1: over-universe (256 x 8 MiB slots; only slot 128 active)
bank 2+: deferred until macrocluster storage exists
```

A `BankRef` is `{bank, bin, slot}`. The current `BinRef` needs one bank field to
address the over-bootstrap without changing the 8 MiB chart geometry.

---

## 4. The tokenizer ladder

| level | unit | size | storage |
|---|---|---:|---|
| L0 | bit | 2 | Boolean cell/register |
| L1 | byte | 256 | address of byte |
| L2 | directed pair | 256 + 65,536 | canonical pair cell + rail |
| L3 | word | 32-bit path | vector/bin association |
| L4+ | syntax/logic/... | paths/triples | layer domain |

### 4.1 The mirror-pair BPE correction

A mirror pair is **unordered**. If the pair cell alone is the token, `th` and
`ht` collide. Use the two rails as direction:

```text
pair cell (42,189) = C(42,189)
s+ rail = directed (42 -> 189)  // th
s- rail = directed (189 -> 42)  // ht
```

So:

- storage: 32,640 pair cells (unchanged);
- directed tokens: 65,536 orientations;
- byte tokens: 256;
- effective pair vocabulary: 65,792.

A 16-bit token id is not enough for the full directed vocabulary. Use a 32-bit
`TokenRef` (cell id + direction bit) in the NaN payload, or reserve one bit in a
17-bit token. The user-facing "256 + 32,640" is the **storage** count, not the
directed vocabulary count.

### 4.2 Natural BPE promotion

If `th` is frequent in the forward rail, promote it as a token:

```text
token th = pair_cell(42,189), direction = forward
```

The pair cell already exists; promotion changes routing/permission, not the
address space. Pair tokens never require a new cell. Merges beyond pairs become
word paths or layer-domain tokens, not new pair cells.

### 4.3 Sparse activation

Do not scan all 32,640 pair cells on every forward. Maintain per-first-token
buckets and a frequency/score index:

1. bucket candidates by first byte/token;
2. score candidates by mirror/attention/frequency;
3. keep the top **256** pair tokens active;
4. scan only those active slots.

The 256-active budget is the balance between a 32k vocabulary and phone compute.

### 4.4 Word paths

```text
WordRef = (U << 24) | (M << 16) | (C << 8) | P
```

32 bits fit the NaN payload. A word path is a **route** to a bin/association,
not a reversible encoding of the word. Two words can share a path; store a
bucket and generation in the bin.

A paragraph hash is the same pattern: hash to a 32-bit index, then map the
index to a bin in a Corpus Supercluster. The hash alone is not the content and
is not collision-free.

---

## 5. Sparse Hopfield router

### 5.1 Query

```text
input token/context -> q (16 int16 values)
```

`q` can start as a deterministic hash/one-hot projection. Later it can be
learned by the same Hebbian updates. It is not a transformer query.

### 5.2 Head activation

```text
score_h = dot(q, head_vector[h])       // 16 multiplies
active = top_k(score_h, k=8)
```

Tie-break by head index. Point 128 is excluded from `active`; it is control.

Cost: `256 * 16 = 4,096` integer multiplies.

### 5.3 Pair scan

For each active head, scan the 255 pairs involving it:

```text
8 * 255 = 2,040 pair lookups
```

Use a visited flag so a pair with two active heads is not double-counted.
Each pair exposes one or two directed rails; the layer policy chooses whether
to scan one rail or both.

### 5.4 Vote

```text
slot_score = dot(q, slot.key) * slot.strength
vote[slot.value_token] += slot_score
pred = argmax(vote)
```

Use int64 accumulation and deterministic tie-breaks. If no positive score
exists, return `abstain`, not a forced yes/no.

### 5.5 Learning

```text
if correct:
    strength = min(max_strength, strength + 1)
    key = round((99 * key + q) / 100)   // fixed-point, not float
else:
    strength = strength - 1
    if strength <= 0:
        evict the weakest slot involving the active heads
        write (key=q, value=target, strength=1)
```

Eviction tie-break: lowest strength, oldest epoch, highest canonical pair id.
No Adam, no gradients, no backprop. This is a Hebbian associative update.

### 5.6 Slot storage

The slot record is roughly:

```text
pair id (u16), direction (u8), flags (u8)
key[16] (i16 = 32 B)
value_token (u32)
strength (i16), epoch (u64)
```

One record per active slot; the full pair table is in the bank, not in the
1 KiB head scratchpad. The chart stores head records and hot pointers.

---

## 6. Layer stack: math changes by layer

Do **not** use one optimizer or one representation for every layer. The
256-ary geometry is shared; the learner is a policy.

| layer | unit | active set | memory | learner | metric |
|---|---|---|---|---|---|
| L0 bit | bit | 2 | Boolean cell | exact Boolean | bit accuracy |
| L1 byte | byte | 256 | address + pair cells | count/Boolean | BPC, top-1 |
| L2 pair/BPE | directed pair | 256 active of 65k | rails + sparse index | Hopfield | BPC, compression |
| L3 word | WordRef | top-k associations | vector bins + path | Hopfield + macro recall | word accuracy |
| L4 syntax | token sequence | window | temporal rails + hyperedges | transition/grammar | parse/next-token |
| L5 logic | triples/rules | exceptions | WordMemory/bins | rule + exception retrieval | fixed challenge |
| L6 code | AST/grammar | exact | exact cells + Boolean mod | exact rewrite + tests | test pass rate |
| L7 prose | paragraph | retrieval | corpus bins | hash + recall | recall/summary |
| L8 expertise | corpus/expertise | retrieval | Corpus Supercluster | retrieval | held-out recall |

`LayerPolicy` should be explicit:

```text
learner: Boolean | Count | Hopfield | Temporal | Rule | Exact
top_k, key_dim, slot_budget, strength_max
evict: weakest | oldest | lowest_use
route_budget, max_active_pairs
tokenizer, metric
```

The layer chooses the math; the topology only supplies address, ledger, and
storage.

---

## 7. Point-128 routing and the over-bootstrap

### 7.1 The two-level picture

```text
bootstrap universe (8 MiB, slot 128)
  256 heads (diagonal, normal)
  point 128 local control portal
  point 128 table -> 256 head routes

over-universe capacity (2 GiB)
  256 system slots (8 MiB each)
  slot 128 = bootstrap (active)
  slots 0..127,129..255 = 255 possible systems (reserved, uninstantiated)
  each active system has its own point-128 portal
```

Point 128 in the bootstrap routes to heads inside the bootstrap. Point 128 in a
future system routes inside that system. This is recursive, not a global
central mind.

### 7.2 Why 256 slots

The exact identity `2 GiB = 256 × 8 MiB` gives 256 system slots. One is the
bootstrap; 255 are possible peers. The identity describes capacity, not 256
populated systems.

### 7.3 What lives in the bank now

Only the bootstrap slot's hot data is active:

- head vectors and route-table bins;
- hot pair/slot records;
- the point-128 table;
- a small layer-policy cache.

The 255 other slots are reserved and empty. Corpus bins and cold pages wait for
storage. Not all of the 2 GiB is resident; use `mmap`/paging.

---

## 8. Android route diff (local; macrocluster deferred)

### 8.1 What the phone trains

- 8 MiB bootstrap chart;
- point 128 table (256 entries, ~8 KiB);
- hot head/slot cache;
- no 2 GiB bank.

### 8.2 Diff format

```text
{
  "universe": 0,
  "macrocluster": 128,
  "cluster": 128,
  "point": 128,
  "base_generation": 42,
  "epoch": 1234,
  "entries": [
    {"head": 17, "active": 1, "key_hash": "...",
     "bank": 1, "bin": 9001, "slot": 3,
     "strength_delta": 2, "epoch": 1234}
  ],
  "signature": "..."
}
```

Only changed entries are written locally for now. A future macrocluster would
verify the base generation and epoch before merging. A stale diff is rejected;
retry after rebasing.

### 8.3 Merge (not built)

When storage exists, the macrocluster merge will:

- reject a stale base (no fork);
- add strengths with saturation;
- take the newest epoch for key updates, then the stronger entry;
- preserve provenance;
- append one ledger event;
- publish one new generation/digest.

Until then, the diff is a local artifact for tests. There is no remote
macrocluster and no 255-system storage.

### 8.4 Privacy and bandwidth

Hashing head/key identifiers avoids uploading raw text. This is
bandwidth-limited and data-minimizing, but **not** a formal privacy guarantee.
If formal privacy is required, add explicit DP noise and an audit path.

---

## 9. Atomic HTTP clock

Each head can send:

```text
POST /v1/clock/sync
Idempotency-Key: <nonce>
If-Match: <base_generation>
{
  head, nonce, logical_tick, route_hash, lease_request
}
```

Point 128 is the single writer for the route table. It returns:

```text
{ accepted, stamp, lease, next_epoch, digest }
```

Rules:

- logical stamp is authoritative; wall time is telemetry only;
- duplicate nonce returns the previous result;
- stale base returns 409;
- one writer, no concurrent table mutation;
- a lease expires by logical tick, not wall time;
- all accepted changes append to the one global ledger.

The HTTP layer is transport. The state authority remains the topology ledger.

---

## 10. The `NaNLM_128_bootstrap` repository

Keep the bootstrap node separate from the main research monorepo:

```text
NaNLM_128_bootstrap/
  README.md
  docs/
  include/nanlm128/
    orchestrator.hpp
    route_table.hpp
    overbootstrap.hpp
    layer_policy.hpp
  src/
    orchestrator.cpp
    route_table.cpp
    overbootstrap.cpp
    layer_policy.cpp
  tests/
    test_point128.cpp
    test_route_diff.cpp
    test_hopfield.cpp
  runner/
    android_diff.py
    clock_sync.py
  Makefile
```

It depends on the core `NaNLMind` alphabet/topology via a submodule or a
versioned package. It does not fork the address algebra.

CI gates:

- build on x86 and aarch64/Termux;
- 8 MiB chart + route table + local route-diff validation;
- top-k/sparse scan correctness;
- 10-pass byte/relation warmup;
- memory guard: 2 GiB bank not fully resident;
- no raw corpus in the repository.

`NaNLM_overbootstrap_128` is the **capacity/tier name** for the 2 GiB
over-universe bank, not a second mind and not a populated macrocluster. Only slot
128 is live. Persistent storage for the other 255 slots is deferred.

---

## 11. Build order

1. **P0** point-128 portal, canonical-pair placement, route-table schema.
2. **P1** Hopfield top-k/slot/vote/learn on synthetic vectors.
3. **P2** 2 GiB over-universe capacity, slot 128 bootstrap, sparse map.
4. **P3** directed pair/BPE tokens and top-256 activation.
5. **P4** layer policies; L4/L5 logic; fixed challenge.
6. **P5** Android local route diff + atomic HTTP clock.
7. **P6** separate `NaNLM_128_bootstrap` repo and CI.
8. **P7** macrocluster merge, 255-system storage, global mesh regions —
   design only until P0–P6 have gates.

---

## 12. Process of elimination

| option | decision | reason |
|---|---|---|
| point 128 as a 257th head | **reject** | 0x0080 is not palindromic; use a control portal |
| head index 128 as orchestrator | **reject for this role** | 0x8001 is a normal head; don't consume a vote slot |
| 256 x86 systems, one head each | **reject** | heads are logical; six runners can hold the bank |
| 1 KiB scratch holds the route table | **reject** | 8 KiB table; cache hot entries, store the table in a bin |
| flat 2 GB weight blob | **reject** | 2 GiB = 256 × 8 MiB system slots; slot 128 is bootstrap, 255 are possible peers |
| instantiate 255 systems now | **reject** | no macrocluster storage yet; reserve slots only |
| dense 256 × 32,640 slot matrix | **reject** | too large for 8 MiB; sparse top-k + bank |
| unordered pair BPE | **reject** | `th` and `ht` would collide; use directed rails |
| vocab = 256 + 32,640 with 16-bit ids | **reject** | directed vocab is 65,792; use 32-bit refs |
| BPE merges create new cells | **reject** | pair cells are fixed; promotion/reuse, then word paths |
| 32-bit word = unique content | **reject** | it is a route; store a bin and collision bucket |
| hash-only paragraph address | **reject** | collisions and no reverse content; hash -> bin |
| Hopfield for every layer | **reject** | logic/code need rules/exact rewrites |
| Adam/backprop everywhere | **reject** | this layer is Hebbian; no gradients in the object |
| 2 GiB over-universe on Android | **reject** | phone holds 8 MiB + route diff; bank stays on runner |
| remote macrocluster merge now | **reject** | storage does not exist; keep diffs local |
| 9 dense layer banks at once | **reject** | 9 × 2 GiB; use policies and paging |
| one central/global mind | **reject** | local point-128 control in each chart, one ledger |
| upload full table/raw text | **reject** | upload only route deltas; hash identifiers |
| forced yes/no vote | **reject** | allow `abstain`; no false confidence |

---

## 13. Open questions

- Exact integer update for `0.99 * key + 0.01 * q` and strength saturation.
- Head-vector initialization and whether q is hashed or learned.
- One slot per pair or multiple slots per pair; capacity/eviction policy.
- How a child chart slot is assigned to a physical runner without a new ledger.
- `BankRef` field addition and migration of the current `BinRef` tests.
- Point-128 table persistence and diff authentication.
- Directed pair token encoding: 17-bit id vs 32-bit cell+direction.
- Word-path collision policy and generation semantics.
- Which layers get Hopfield versus rule/exact math.
- Memory-mapped 2 GiB layout and residency cap on a 7 GiB runner.
- When macrocluster storage exists; route-diff auth and DP noise are deferred.
- How the 6-runner ring maps the bootstrap and any future active systems; only
  slot 128 is live now.
- Global mesh region naming; do not build yet.

---

## 14. One-sentence thesis

The bootstrap is one 8 MiB universe with 256 heads and a local point-128
control portal; the 2 GiB over-universe is capacity for 256 system slots, with
slot 128 live and 255 peers reserved; sparse Hopfield routing runs inside the
bootstrap, and route diffs stay local until macrocluster storage exists.
