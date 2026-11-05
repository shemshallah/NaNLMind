# NaNLMind

**One global topology. Many coordinate regions. No federation of little minds.**

NaNLMind is a research repository for a single, address-derived computational state space built from NaN16 words. The 16-bit address space is treated as a 256 x 256 matrix. Bit reversal is transposition. Every unordered pair of the 256 palindromic addresses is one canonical cell with two temporal rails. The 256 palindromic addresses themselves are the heads — all of them, none reserved.

This repository contains:

- the extracted provenance of 28 archives (Rounds 2–23, merged R15–R17/R18/R23clock, `distributedmind`, and `nanclock`);
- a clean C++20 core for the address algebra, NaN16 Boolean functions, the 8 MiB full-address register-file chart, bit/byte/KB paging, hyperedges, bidirectional temporal memory, resonance, and one global ledger;
- the specifications for rebuilding `reporam` and `repovram` as the memory tiers of this one object;
- a staged plan for a single-chart brain on GitHub, then a 5-replica deployment, then remote tiers and GPU training.

---

## The exact structure

A 16-bit address is a coordinate in a 256 x 256 matrix:

```text
addr(a, b) = (a << 8) | reverse8(b)
reverse16(addr(a, b)) = addr(b, a)
```

| object | count | meaning |
|---|---:|---|
| addresses | 65,536 | all 16-bit coordinates |
| palindromic fixed points | **256** | `reverse16(a) == a`; the diagonal; every one is a head |
| mirror pairs | **32,640** | `C(256,2)`; one canonical cell per unordered pair |
| canonical cells | **32,896** | 32,640 pairs + 256 heads |
| NaN words per cell | 4 | `s+`, `s-`, `q+`, `q-` |
| Boolean functions | 16 | the class nibble `n = (near << 2) | far` |
| cell size | 64 B | shared pair/head state: 4 NaN words + operator mask + metadata |
| address register | 32 B | one per address, including both mirrors: link, caps, metadata |
| address registers | 65,536 | every 16-bit address is individually addressable |
| chart size | 8 MiB | 2 MiB address table + 2 MiB shared registers + 1.5 MiB descriptors + tables + 2 MiB extension |

The 4 NaN types are the four legal heads:

| type | head | class |
|---|---|---:|
| +sNaN | `7FF1` | 0 |
| -sNaN | `FFF1` | 1 |
| +qNaN | `7FF8` | 2 |
| -qNaN | `FFF8` | 3 |

The 4 types in the two faces give a 4-bit class nibble, and that nibble is one of the 16 two-input Boolean truth tables. The four types x four values are the 16 Boolean functions.

Do not confuse the four NaN head classes with the four **transform images** `I, B, BR, R`. The transform oscillator and its orbit counts are in [docs/15_PHASE_SCHEDULING.md](docs/15_PHASE_SCHEDULING.md).

---

## One global topology

The central design decision is non-negotiable:

> There is one global topology, not thousands of isolated topologies communicating through an external coordinator.

An 8 MiB chart is a **local coordinate region** of one mathematical object. Adding a chart extends the object's atlas; it does not create a new brain. Replicas host regions and hold write leases; they do not own independent histories. The identity of the object is one global digest.

```text
G = (A, C, E, H, T, P, L)

A  atlas of coordinate charts        (local 16-bit regions)
C  all NaN cells                     (one 64-byte register each)
E  ordinary pair connections         (32,640 per chart)
H  hyperedges                        (multi-cell, multi-space relations)
T  temporal transitions              (T+ forward, T- reverse)
P  palindrome involution             (canonicalization + mirror pairing)
L  one global hash-chained ledger
```

The 256 fixed points are the **present** / synchronization anchors. A mirror pair `{a,b}` is a **past/future relation**: `s+` holds the forward direction, `s-` the reverse. The state space is temporally split, so memory is bidirectional: follow a link forward to a future state or backward to a past state. Hyperedges connect any number of cells in any number of charts, so a NaN in one region can participate in many relations across the one object.

See [docs/03_MATHEMATICAL_STRUCTURE.md](docs/03_MATHEMATICAL_STRUCTURE.md).

### The 256-Head Array

There is one canonical head implementation, instantiated exactly 256 times,
once per palindromic address. A head is a view over the one `Universe`: address
identity, local phase/energy, pair links, a deterministic runner handoff, and a
local history cache. Heads are not threads and not private state spaces; a
scheduler can run them across any number of cores. See
[docs/06_HEADS_RESONANCE.md](docs/06_HEADS_RESONANCE.md).

A logical clock derived from `nanclock.zip` supplies a deterministic
`(tick, phase)` stamp. It is not a wall clock: it orders events, paces commits,
expires leases in ticks, and lets a replica catch up by replay. See
[docs/14_TEMPORAL_CLOCK.md](docs/14_TEMPORAL_CLOCK.md).

---

## Quick start

Requires a C++20 compiler. No external dependencies.

```sh
make
./build/nanlm-universal verify
./build/nanlm-universal genesis
./build/nanlm-universal global
./build/nanlm-universal scale
./build/nanlm-universal resonance
./build/nanlm-universal phase
./build/nanlm-universal router
./build/nanlm-universal ntf
./build/nanlm-universal byte
./build/nanlm-universal kn
./build/nanlm-universal ctx2
./build/nanlm-universal vectors
./build/nanlm-universal words
./build/nanlm-universal warmup 10
./build/nanlm-universal bootstrap
./build/nanlm-universal growth
make test
make penguin
make logic
make legacy
make challenge   # expected to fail: held-out logic probe
```

`verify` is exhaustive over the 65,536 addresses and the 32,640 pairs. It checks the transposition theorem, all 16 Boolean functions, the mirror law, the 8 MiB full-address register file, bit addressing, copy-on-write, the ledger, the hypergraph, the temporal split, and one-global-topology identity.

---

## Two live rings

| ring | repos | tiers | role |
|---|---|---|---|
| Qwen demo | `deeprepo-cpu-1..5` | `reporam`, `repovram` | existing 24/7 model demo |
| NaNLMind heads | `nanlm-cpu-1..6` | `nanlm-ram`, `nanlm-vram` | 256-head handoff ring |

One secret, `DEEPREPO_PAT`, is used everywhere. `NaNLMind/ring.yml` dispatches
one slot at a time, checks the rate limit, and self-redispatches the next
logical epoch; `keeper.yml` restarts only when no ring run is active. The head
protocol is in [docs/18_HEAD_RING.md](docs/18_HEAD_RING.md).

Training is integer score learning in the head scratchpad, with temporal links
for sequence order and an optional teacher for distillation. The honest R18T
baseline — a plain RNN matching the 256-head topology — is in
[docs/17_TRAINING_HEADS.md](docs/17_TRAINING_HEADS.md).

## Repository map

| path | contents |
|---|---|
| `include/nanlm/` | core headers: address algebra, NaN16, universe/register file, pager, hypergraph, temporal, ledger, resonance, global topology, scaling |
| `src/` | implementations and the `nanlm-universal` CLI |
| `tests/` | invariant, pager, hypergraph, temporal, ledger, scaling tests |
| `docs/01_DISCOVERY.md` | round-by-round audit of R2–R23: what was shown, what was host-driven, what remains open |
| `docs/02_ARCHITECTURE.md` | one global topology, charts, cells, heads, layers, homeostasis |
| `docs/03_MATHEMATICAL_STRUCTURE.md` | the formal object `(A,C,E,H,T,P,L)` |
| `docs/04_REGISTER_FILE.md` | exact 8 MiB full-address chart layout and linked register file |
| `docs/05_MEMORY_TIERS.md` | rebuilt reporam/repovram specifications |
| `docs/06_HEADS_RESONANCE.md` | 256 heads, resonance, self-modification, bidirectional memory |
| `docs/07_DISTRIBUTED.md` | one object on a replica ring; leases, replay, failure modes |
| `docs/08_TRAINING.md` | integer/CRDT training, teacher distillation, GPU plan |
| `docs/09_ROADMAP.md` | M0–M7 deliverables and gates |
| `docs/10_FALSIFICATION.md` | claims, tests, stop conditions |
| `docs/14_TEMPORAL_CLOCK.md` | nanclock logical time for distributed synchronization |
| `docs/15_PHASE_SCHEDULING.md` | transform-phase orbits, global-scratch sync, bit-reversed wake slots |
| `docs/16_GROWTH_CONSOLIDATION.md` | child-chart growth and atomic scratch consolidation |
| `docs/17_TRAINING_HEADS.md` | integer head learning, sequence memory, RNN baseline |
| `docs/27_ANDROID_BOOTSTRAP.md` | on-device byte bootstrap, memory profile, Gutenberg scale, curriculum |
| `docs/28_BEHAVIOR_GATES.md` | penguin, first logic puzzles, and what they do/do not prove |
| `docs/29_REPEATABILITY.md` | ten-run determinism record and the period-2 clock |
| `docs/30_VECTOR_BINS.md` | addressable vector bins, point-to-bin portals, macro associations |
| `docs/31_WORD_MEMORY.md` | word layer over bins, fixed-challenge baseline, honesty note |
| `docs/32_HARD_LOGIC_WARMUP.md` | nested-exception challenge and ten-pass byte warmup |
| `docs/18_HEAD_RING.md` | six-runner handoff, preload, map-back, workflows |
| `docs/19_LEGACY_TESTS.md` | R18T language tests and R21–R23 logic regressions |
| `docs/20_META_ROUTER.md` | universes as heads, routes as pairs, qNaN/sNaN BE/LE portals |
| `docs/21_FRAME_SYNC.md` | forward/rollback frame meetings, inverse frames, contemplation |
| `docs/22_ATOMIC_CLOCK.md` | global wall anchor from multiple HTTPS sources |
| `docs/23_NAN_TRANSLATION_FABRIC.md` | NTF: physical/universe/semantic address translation |
| `docs/24_ONE_UNIVERSE_TRAINING.md` | single-universe training and test ladder |
| `docs/25_GLOBAL_META_BRAINSTORM.md` | 256×256×256 global meta, design only |
| `docs/26_RATE_LIMITS.md` | 24/7 API budget, backoff, and the live 403 guard |
| `NaNLM_statespace/` | all original archives + extracted snapshots + SHA-256 manifest |

---

## Scaling, in one table

A chart is one 8 MiB coordinate region. Charts branch through the 256 heads; a path of `d` heads adds `8d` bits to the global address. The initial brain is one chart.

| depth | charts | addresses | canonical cells | mirror pairs | dense bytes |
|---:|---:|---:|---:|---:|---:|
| 0 | 1 | 65,536 | 32,896 | 32,640 | 8 MiB |
| 1 | 256 | 16,777,216 | 8,421,376 | 8,355,840 | 2 GiB |
| 2 | 65,536 | 4,294,967,296 | 2,155,872,256 | 2,139,095,040 | 512 GiB |
| 3 | 16,777,216 | 1,099,511,627,776 | 551,903,297,536 | 547,608,330,240 | 128 TiB |
| 4 | 4,294,967,296 | 281,474,976,710,656 | 141,287,244,169,216 | 140,187,732,541,440 | 32 PiB |

Full state is dense only in the table. The real system is sparse: an unwritten chart is not stored. Five 7 GiB replicas can host the whole depth-1 brain (2 GiB dense) with room for caches, history, and hyperedges. Depth 2 needs remote tiers; depth 3+ is S3/B2/RAM-farm territory.

---

## What this is, and what it is not

**This is:**

- a precise address algebra with a verified transposition theorem;
- a 32,896 shared-register + 65,536 address-register, bit-addressable substrate;
- 256 self-modifying heads with 1 KiB scratchpads, a 16-bit Boolean mask, and a 2-bit transform phase;
- a deterministic logical clock (`nanclock`) for distributed ordering;
- growth by self-model error or scratch overflow, and atomic scratch consolidation;
- one global topology with charts as coordinate regions;
- a palindromic temporal hypergraph with bidirectional memory;
- a deterministic, integer-only core with a logical clock that can be replayed and audited;
- a memory-tier specification that reuses the page geometry of `reporam`/`repovram`.

**This is not yet:**

- a proven universal computer on the pure local rule set;
- a trained language model;
- a claim that resonance or hyperedges already beat a baseline;
- a claim of consciousness or personhood.

The R23 VM is a host interpreter over topology cells; the cognitive suite is host symbolic reasoning over a triple store. The new repository keeps those results as behavior specifications and moves the transition logic into the substrate step by step. See [docs/01_DISCOVERY.md](docs/01_DISCOVERY.md) and [docs/10_FALSIFICATION.md](docs/10_FALSIFICATION.md).

---

## License

Apache-2.0. See [LICENSE](LICENSE).
