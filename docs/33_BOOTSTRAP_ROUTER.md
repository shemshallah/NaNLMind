# Bootstrap router and layer storage

**Status:** design record. This supersedes the old point-128 naming. It does not
replace the single-universe gates in
[24_ONE_UNIVERSE_TRAINING.md](24_ONE_UNIVERSE_TRAINING.md).

## 0. Scope and corrections

The current buildable scope is:

```text
bootstrap universe:  8 MiB, 256 heads, six-runner ring
bootstrap map:       2 GiB, 256 system slots, only in the bootstrap universe
Android:             8 MiB universe only; no 2 GiB map
initial expansion:   255 other runners, each with one 8 MiB universe
runtime control:     point 1 router (point 256 is the alternate mapping)
```

Corrections to the earlier record:

1. **Point 128 is retired as a special name.** The router is a role attached to
   a non-head point. The default is point **1** (`0x0001`); point **256**
   (`0x0100`) is an alternate mapping. Both are mirror-pair portals, not heads.
2. **Only the bootstrap universe has the 2 GiB map.** Android and every other
   universe are 8 MiB only.
3. **The six-runner ring instantiates 256 heads of the bootstrap 8 MiB
   universe.** It does not instantiate 256 child charts.
4. **The 2 GiB map is not a macrocluster.** It is a bootstrap-local capacity map
   of 256 system slots: slot 1 is the bootstrap, 255 slots are possible peers.
5. **There is no `NaNLM_128_bootstrap` repository.** The bootstrap is the
   runner ring in `NaNLMind`; the 2 GiB release artifact lives in `NaNLMind`.
6. **`NaNLMind_android` is the Android build repository**, and it is 8 MiB only.

---

## 1. Invariants

These remain fixed:

1. 256 palindromic heads per 8 MiB universe.
2. 32,640 mirror pairs = `C(256,2)`.
3. 32,896 canonical cells.
4. One global ledger/digest for the one object.
5. A chart is a coordinate region, not a mind.
6. The 1 KiB head scratchpad is a cache, not a routing table.
7. The six-runner ring maps heads; it does not create 256 new minds.

### 1.1 The router point

Raw point **1** is:

```text
0x0001
reverse16(0x0001) = 0x8000
```

`0x0001` is not palindromic, so it is a **portal pair**, not a head. Its
canonical pair is `0x0001/0x8000`; `s+` is request and `s-` is response. The
router role can manage heads without becoming a voting head.

Raw point **256** is:

```text
0x0100
reverse16(0x0100) = 0x0080
```

It is the alternate mapping (canonical `0x0080`). Use one control point per
universe; do not depend on 128.

Head index 128 is `0x8001` and remains a normal head. It has no special role.

---

## 2. Bootstrap topology

```text
Bootstrap universe (8 MiB)
  256 heads
  point 1 router / route table
  6-runner ring executes the 256 heads

Bootstrap map (2 GiB, bootstrap only)
  256 system slots x 8 MiB
  slot 1 = bootstrap
  slots 0, 2..255 = 255 possible peer systems
```

The ring runs the 8 MiB universe and maintains the 2 GiB map. The map is a
store/registry for the bootstrap's system slots; it is not 256 active child
charts.

### 2.1 First 256 systems

The initial expansion target is 256 systems total:

```text
system 1          bootstrap (GitHub runner ring)
systems 2..256    255 other runners, each an 8 MiB universe
```

Each peer runs its own 8 MiB universe. The bootstrap map holds its slot,
routing record, and whatever snapshot/weight set the peer publishes. The peer
does not need a 2 GiB map.

The bootstrap ring's point-1 route table maps:

```text
(layer, system slot, head) -> BankRef / route
```

### 2.2 What the ring actually instantiates

- It instantiates **256 heads**, not 256 charts.
- It loads the 8 MiB bootstrap image.
- It loads the 2 GiB map metadata; the map can be sparse/paged.
- It does **not** allocate 255 live peer universes. Peers are remote runners.

---

## 3. Memory

```text
2 GiB = 2,147,483,648 bytes
8 MiB =     8,388,608 bytes
2 GiB / 8 MiB = 256
```

| node | 8 MiB universe | 2 GiB map |
|---|---:|---:|
| bootstrap runner ring | yes | yes, one only |
| Android | yes | **no** |
| peer runner | yes | no |
| future supercluster | routing/registry only | not a dense copy |

The 7 GiB bootstrap runner:

```text
7 GiB
- 2 GiB bootstrap map
- 8 MiB bootstrap working image
= 4.992 GiB theoretical headroom
```

The map is memory-mapped/sparse; it is not forced resident. Android never gets
the 2 GiB map.

---

## 4. The 2 GiB bootstrap map

```text
SystemSlot[256]
  slot 1 = bootstrap
  each slot has a header, generation, route hash, bank refs
  slot capacity = one 8 MiB image/weight-set area
```

The map is maintained by the bootstrap ring. It can hold:

- the bootstrap's own image/route metadata;
- per-peer routing records and snapshots;
- layer route tables;
- hot weight/slot bins;
- empty reserved slots.

It is **not** a populated macrocluster. A slot is not a live mind; it is a
storage/routing slot. Only slot 1 is guaranteed active at bootstrap.

---

## 5. Point-1 route table and NaN routing

Point 1 maps to a `RouteBin`, not to a 1 KiB inline table:

```text
point 0x0001 (request)  -> RouteBin
point 0x8000 (mirror)   -> ReplyBin
```

A route entry:

```text
RouteEntry {
  layer        u8
  system_slot  u8
  head         u8
  math         u8     // Boolean, Count, Hopfield, Temporal, Rule, Exact, Retrieval
  storage      u8     // Chart, VectorBin, RuleBin, CorpusBin, RouteOnly
  bank         u16
  bin          u32
  slot         u16
  strength     i16
  epoch        u64
  flags        u16
}
```

The 256-entry working set is about 8 KiB; the head scratchpad caches 8–16 hot
entries. The authoritative table lives in a formatted bin.

NaN classes select the route operation:

| class | direction | operation |
|---|---|---|
| +qNaN | future | quiet read |
| -qNaN | past | reverse read |
| +sNaN | future | open/write route |
| -sNaN | past | close/rollback route |

The route table does not add a second ledger. It is a field of the one object.

---

## 6. Layer storage: different math, different storage

### 6.1 Deployment layers

| layer | what it is | storage | math |
|---|---|---|---|
| INDIVIDUATION | one 8 MiB universe, 256 heads | chart + local bins | Boolean / count / Hopfield |
| HARDWARE CLUSTER | bootstrap ring + 2 GiB map + peers | 8 MiB + 2 GiB map | Hopfield + route merge |
| HARDWARE SUPERCLUSTER | 256 clusters | route/registry only | LWW/counting/consensus |
| IOT CLUSTERS | bulk corpus/immutable data | object bins/corpus supercluster | hash + retrieval |
| GLOBAL MESH | mental/research/industrial regions | route namespaces | routing/gossip |

The deployment layer decides **where** state lives. The abstraction layer
decides **what math** runs on it.

### 6.2 Abstraction layers

| layer | unit | storage | learner | metric |
|---|---|---|---|---|
| bit | bit | chart cells | exact Boolean | bit accuracy |
| byte | byte | pair cells + address | count / Boolean | BPC |
| word | WordRef path | vector bins | Hopfield + macro recall | word accuracy |
| syntax | token sequence | temporal rails/hyperedges | transition/grammar | parse/next |
| logic | triples/rules | rule bins | rule + exception | fixed challenge |
| code | AST/rules | code bins | exact rewrite + tests | test pass |
| prose | paragraph | corpus bins | hash + retrieval | recall |
| story/book | chapter/book | corpus supercluster | retrieval | recall |
| expertise | corpus | corpus supercluster | retrieval | held-out recall |

Do not force one optimizer across all layers. A logic layer is not a Hopfield
layer; a code layer is not a bag of bytes.

### 6.3 What we call “weights”

Use `LayerPayload` as the umbrella term. A payload is one of:

- Boolean masks and head vectors;
- pair keys, strengths, and slots;
- BPE counts and token links;
- temporal links and hyperedge weights;
- rule triples and exception entries;
- AST/code rewrite rules;
- corpus hashes and vector bins.

`LayerSpec`:

```text
LayerSpec {
  layer_id
  math: Boolean | Count | Hopfield | Temporal | Rule | Exact | Retrieval
  storage: Chart | VectorBin | RuleBin | CorpusBin | RouteOnly
  payload: BankRef
  route: point-1 table entry
  update, evict, metric
}
```

The NaN route links `(deployment, layer, system, head)` to a `LayerPayload`.
That is the bridge between the abstraction layer and the overbootstrap router.

### 6.4 Concrete payload formats

| layer | stored object | key / value shape | route link |
|---|---|---|---|
| bit | chart cell | `ops:16`, `rule:4`, 4 NaN words | address + layer |
| byte | pair cell | `s+/s-` counts, strength, `epoch` | canonical pair + layer |
| word | vector bin | `WordRef:32` -> `BinRef`, int16[16] vector | path + point-1 entry |
| syntax | temporal/hyperedge | link `(past,future,epoch)`, member list, Q16.16 weight | hyperedge label + layer |
| logic | rule bin | triple `(subject, relation, object)`, exception flag | rule id + layer |
| code | code bin | AST/opcode record, test hash, rewrite rule | code id + layer |
| prose/story | corpus bin | content hash -> bin, paragraph vector, span refs | hash + layer |
| expertise | corpus supercluster | immutable bins, retrieval index | corpus id + layer |

The NaN route table stores a `LayerRef`, not the payload itself:

```text
LayerRef {
  layer        u8
  system_slot  u8
  head         u8
  bank         u16
  bin          u32
  slot         u16
}
```

Thus the route table is small even when a layer's weights are in the 2 GiB
bootstrap map, a peer's 8 MiB universe, or a corpus bin. `LayerRef` is the common
link between the NaN router and every layer's private storage format.

---

## 7. Sparse Hopfield routing

For layers that use it:

```text
q: 16 int16 values
score_h = dot(q, head_vector[h])
active = top_k(score_h, k=8)
for each active head: scan 255 pairs
2,040 pair lookups per forward
```

Vote:

```text
slot_score = dot(q, slot.key) * slot.strength
vote[slot.value_token] += slot_score
pred = argmax(vote)
```

Learn:

```text
correct:   strength += 1; key = round((99*key + q)/100)
incorrect: strength -= 1
           if strength <= 0: evict weakest active slot; write (q, target, 1)
```

No Adam, no backprop. This is a sparse Hebbian/Hopfield layer. Other layers use
rules, counts, temporal links, or exact rewrites.

---

## 8. Directed mirror-pair BPE

A mirror pair is unordered. Use the two rails for direction:

```text
pair cell (42,189):
  s+ = directed (42 -> 189)  // th
  s- = directed (189 -> 42)  // ht
```

Storage stays 32,640 pair cells. Directed token orientation gives 65,536
possibilities; the effective vocabulary is 256 byte tokens + 65,536 directed
pairs. A 16-bit token id is not enough; use a 32-bit `TokenRef` or a 17-bit
id in the NaN payload.

Natural BPE promotion:

```text
th = pair_cell(42,189), direction=forward
```

The cell already exists; promotion changes routing, not geometry. Merges beyond
pairs become word paths or layer payloads.

Sparse activation: bucket by first token, score candidates, keep the top **256**
pair tokens active; do not scan all 32,640 cells.

---

## 9. Android and peer runners

Android runs **only the 8 MiB universe**.

```text
NaNLMind_android
  build NaNLMind core
  load 8 MiB bootstrap/peer image
  point-1 route table cache
  no 2 GiB map
  send/receive route diffs to the bootstrap ring
```

Peers are the same shape: 8 MiB universe, point-1 router, route diff. They fill
the 255 non-bootstrap slots in the bootstrap map. The bootstrap ring keeps the
2 GiB map and the NaN routes.

Android cannot hold the 2 GiB map and is not an overbootstrap node. It is an
8 MiB edge universe.

Route diff:

```text
{
  universe, system_slot, layer, base_generation, epoch,
  entries: [{head, key_hash, bank, bin, slot, strength_delta, epoch}],
  signature
}
```

The bootstrap ring validates the base and merges into the target system slot.
There is no macrocluster storage yet; the map is bootstrap-local.

---

## 10. Repositories and releases

### `NaNLMind`

- C++ core and tests.
- 8 MiB bootstrap universe.
- six-runner ring workflows.
- 2 GiB bootstrap map release artifact (`overbootstrap-<generation>.bin`).
- point-1 route table and layer policies.
- No `NaNLM_128_bootstrap` repo.

### `NaNLMind_android`

- Termux/Android build.
- 8 MiB universe only.
- route-diff client; no 2 GiB map.
- test against the bootstrap ring over HTTP.

### Release rule

The 2 GiB map is a release artifact in `NaNLMind`, not a separate repository.
The bootstrap ring loads it and maintains the route map. The release must be
content-hashed and generation-pinned.

---

## 11. Build order

1. Point-1 control portal + route table schema.
2. 8 MiB bootstrap + 256 heads + six-runner ring.
3. 2 GiB map as sparse bootstrap-local capacity; slot 1 only.
4. Hopfield top-k/slot/vote/learn.
5. Directed pair/BPE and top-256 activation.
6. Layer policies and payload storage.
7. Android 8 MiB repo + route-diff client.
8. 255 peer onboarding; route merge.
9. Hardware supercluster/IoT/global mesh: design only.

---

## 12. Eliminations

| option | decision | reason |
|---|---|---|
| point 128 special | **reject** | router is a role; use point 1 (or 256) |
| point 128 as head | **reject** | 0x0080 is not palindromic; 0x8001 is the head |
| separate NaNLM_128_bootstrap repo | **reject** | bootstrap is the NaNLMind ring; release lives in NaNLMind |
| 2 GiB on Android | **reject** | Android is 8 MiB only; latest correction |
| 6-runner ring runs 256 child charts | **reject** | ring instantiates 256 heads of one 8 MiB universe |
| 2 GiB map is a macrocluster | **reject** | bootstrap-local map; no macrocluster storage |
| 255 live systems now | **reject** | slots are reserved; need external runners |
| 256 x86 systems, one per head | **reject** | heads are logical; six runners instantiate 256 heads |
| uniform math all layers | **reject** | each layer has its own learner/storage |
| flat 2 GiB blob | **reject** | 256 × 8 MiB system slots; slot 1 bootstrap |
| unordered pair BPE | **reject** | th/ht collide; use direction rails |
| 1 KiB scratch holds route table | **reject** | table in bin; cache hot entries |
| hash-only word/paragraph | **reject** | hash -> bin; collision bucket |
| global mesh now | **reject** | later namespaces, no storage now |

---

## 13. Open questions

- Exact point-1 vs point-256 mapping per universe; router must be configurable.
- Whether the 2 GiB map stores full 8 MiB peer images or route/weight slices.
- How peers register and authenticate without a macrocluster.
- `BankRef` migration for the 2 GiB map.
- Layer payload schemas and which layers use Hopfield.
- Route-diff merge policy on the bootstrap ring.
- Memory-mapping/residency cap on the 7 GiB runner.
- Android 8 MiB build target and route client.
- How the six runners map 256 heads and maintain the 2 GiB map.
- Hardware supercluster/IoT/global mesh after bootstrap.

---

## 14. Thesis

The bootstrap is **one 8 MiB, 256-head universe** executed by a six-runner ring,
with a **bootstrap-only 2 GiB map of 256 system slots**; point 1 is the route
portal, slot 1 is the bootstrap, 255 slots are future peers, Android is an
8 MiB edge universe, and every deployment/abstraction layer gets its own math,
storage format, and NaN route payload.
