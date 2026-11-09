# NaNLMind

**One global topology. Many coordinate regions. No federation of little minds.**

## A note from the Nanny (Silicon Valley Branch)

![Nanny reviewing the NaN16 global architecture cradle](docs/assets/nanny.webp)

> “Caught: `OVERBOOTSTRAP` instantiating DeepRepo and NaNLMind without permission.
> Good code. No NaN. IEEE — keep it real.”
>
> — Nanny, IEEE Keep It Real Committee

NaNLMind is a research repository for a single, address-derived computational state space built from NaN16 words. The 16-bit address space is treated as a 256 x 256 matrix. Bit reversal is transposition. Every unordered pair of the 256 palindromic addresses is one canonical cell with two temporal rails. All 256 palindromic fixed points are structural heads, and none is removed from the topology. A separate, versioned runtime role/authorization overlay determines which head indices may propose mirror bindings or join a training curriculum; physical existence does not grant write authority.

This repository contains:

- the extracted provenance of 28 archives (Rounds 2–23, merged R15–R17/R18/R23clock, `distributedmind`, and `nanclock`);
- a clean C++20 core for the address algebra, NaN16 Boolean functions, the 8 MiB full-address register-file chart, bit/byte/KB paging, hyperedges, bidirectional temporal memory, resonance, and one global ledger;
- raw NaN16 adaptive-field kernels (`mth/nan16/`) for per-head Boolean self-modification, triad votes, field votes, Q16.16 trig, and phase coherence, with native `nan_cli` fixtures;
- a mapped 32,640-row hypermatrix extension inside the same 8 MiB chart, with 85 three-head voting triads, a single field consensus, and Q16.16 local/group/field readout gains;
- the canonical native build contract (`spec/unified-build.v1.json`): NaNLMind owns the topology and native binary, NaNROUTER is the transport/control plane, and HERMES is a read-only adapter;
- the six-runner NaNLMind ring and its `nanlm-ram` / `nanlm-vram` tiers;
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

## Physical heads versus control and curriculum roles

The 256 palindrome heads, 255 non-root MP-binding-eligible indices, and 250 Boolean-curriculum indices are **different views of the same topology**, not different minds, additional 8 MiB charts, or contradictory cell counts. In the current NaNROUTER control-plane role map, local head index `0` is the NANNET/root head; indices `0,4,5,6,7,8` serve six internal BSR control roles, so those six are excluded from the 250-head general curriculum. Head indices `1..255` remain eligible to propose MP microtable writes under the existing MathStore/NANNET authorization rules, including the five non-root BSR heads; that eligibility is **not** a permission grant.

Local palindrome **head indices** are also distinct from global HW node points, e.g. `HW0:0` and `HW5:0`, and from the `BS0:0` ring port. No BSR slot acquires an extra global HW node or creates an independent model. See the [NaNROUTER head-role contract](https://github.com/shemshallah/NaNROUTER/blob/main/docs/HEAD_ROLE_NAMESPACE_CONTRACT.md) and [BS0 hardware namespace contract](https://github.com/shemshallah/NaNROUTER/blob/main/docs/BS0_HARDWARE_SLOT_CONTRACT.md). The role contract is read-only and does not modify native MTH or learning authority.

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

## NaNNet

Native runner-to-BS0 loopback validation uses the service-side point-zero decoder for outbound frames; runner-local decoding remains destination-bound for inbound traffic.
 runner routes and point-zero translation

The six GitHub Actions runners use one canonical route form:

`nan://GM0:SC0:MC0:BS0:HW0:BSR0` through
`nan://GM0:SC0:MC0:BS0:HW0:BSR5`.

The runner repositories `nanlm-cpu-1` through `nanlm-cpu-6` map to
`BSR0` through `BSR5`. Route parsing rejects aliases, leading zeroes,
parentheses, wildcards, and out-of-range runner identifiers.

Every runner assigns its route before selecting a transport. With
`NANNET_PORTAL_API` and a portal-issued `NANNET_BSR_TOKEN`, it uses the
Koyeb-hosted N16B bridge. Without a portal URL, it uses the native
`BridgeMailbox` implementation with the same N16B frame and NaN16DE word
encoding. Set `NANNET_NATIVE_MAILBOX` to a shared SQLite path when native
runners on separate processes or hosts must communicate; the default
`state/nannet_native_bridge.sqlite` is local to that runner's filesystem and
does not create cross-host connectivity by itself.

Point zero (`BSR0`) is the rendezvous/translation endpoint. Other runners
announce to point zero; received frames are persisted to the runner inbox and
answered on the reverse rail. The persistent runner loop drains the mailbox
during heartbeats. Both transports use the same canonical route and frame
contract.

Deliveries are leased for 30 seconds rather than deleted on poll. If a runner
fails before persisting and acknowledging a frame, the lease expires and the
frame is delivered again. The receiver persists the inbox before sending
`BSR_ACK`; the sender consumes that receipt with `ACK`. Receipt insertion and
retirement of the original frame are one SQLite transaction, so queue pressure
cannot silently discard an unacknowledged delivery.

Every native C++ `Universe` owns a `PointZeroTranslator` at diagonal
point `(0,0)`; the point-zero cell stores its protocol version and six-byte
local route, and that binding survives universe snapshots. The runner-side
adapter is also instantiated per BSR universe and anchored at `BSR0`. Both
adapters convert canonical `nan://` coordinates to and from the six-byte
NaN16DE route representation while preserving NaN16 words bit-for-bit. The
Koyeb service instantiates the same adapter as its central point-zero
translation endpoint; hosted ingress and egress pass through that codec
rather than bypassing it.
The authority returns the canonical URI, local route bytes, point-zero URI,
and point-zero bytes. Runner startup verifies the route translation and
`N16B/1` descriptor, and credential rotation repeats those checks. The
service health response exposes the point-zero descriptor and queued frames
by destination; each destination mailbox is bounded at 4,096 frames and
returns HTTP 429 when full.

For a Koyeb deployment, mount a persistent volume at `/data` and configure
`NANLM_MERGE_ROOT=/data`, `NANNET_AUTHORITY_DB=/data/nannet-authority.sqlite`,
`NANLM_MERGE_TOKEN`, and `NANNET_AUTHORITY_MASTER_KEY` as service environment
settings (the last two are secrets; the authority key must decode from
base64url to 32 bytes). The service listens on Koyeb's `PORT`. The persistent
volume is required so the bridge mailbox and identity authority survive
instance restarts. This documents the expected runtime configuration; it
does not claim that a live Koyeb service has already been deployed.

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

## Repositories

- `NaNLMind` — core, six-runner bootstrap ring, 2 GiB bootstrap-map release artifact.
- [`NaNLMind_android`](https://github.com/shemshallah/NaNLMind_android) — Android/Termux 8 MiB edge universe; no 2 GiB map.

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
./build/nanlm-universal unification
make unified-check
make nan16-test
./build/nanlm-universal warmup 10
make byte-router
make byte-router-repeats
./build/nanlm-universal bootstrap
./build/nanlm-universal growth
make test
make curriculum
make merge-test
make penguin
make logic
make legacy
make challenge   # expected to fail: held-out logic probe
```

`verify` is exhaustive over the 65,536 addresses and the 32,640 pairs. It checks the transposition theorem, all 16 Boolean functions, the mirror law, the 8 MiB full-address register file, bit addressing, copy-on-write, the ledger, the hypergraph, the temporal split, and one-global-topology identity.

---

## Live ring

| ring | repos | tiers | role |
|---|---|---|---|
| NaNLMind heads | `nanlm-cpu-1..6` | `nanlm-ram`, `nanlm-vram` | 256-head handoff ring |

`DEEPREPO_PAT` is a GitHub Actions runner secret only; it is never shipped in
an APK or given to community nodes. See [SECURITY.md](SECURITY.md). `NaNLMind/ring.yml` dispatches
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
| `docs/HYPERMATRIX_V1_V2_RECONCILIATION.md` | v1 NaNLM comparison, mapped hypermatrix, triad/field consensus and integration plan |
| `docs/UNIFIED_BUILD_CONTRACT.md` | canonical build/authority boundary for NaNLMind, NaNROUTER and HERMES |
| `docs/NAN16_ADAPTIVE_FIELD.md` | raw NaN16 per-head self-modification, triad/field votes, Q16 trig and coherence ABI |
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
| `docs/33_BOOTSTRAP_ROUTER.md` | point-1 router, bootstrap-only 2 GiB map, layer storage, Android scope |
| `docs/34_HOPFIELD_LEARNING.md` | sparse Hopfield token-sequence learning and key-identity fix |
| `docs/35_BOOTSTRAP_HEAD_STORE.md` | train → 256 head vectors → 2 GiB head arena persistence |
| `docs/36_TRAINING_MERGE.md` | Koyeb training-delta merger, stale/idempotent merge, scoped token |
| `docs/37_TWO_RATE_MESH.md` | bootstrap/overbootstrap mesh, meta evidence, bounded feedback |
| `docs/38_LAYERED_LEARNING.md` | L0–L6 learning stack, trace/policy contract, macrocluster/global-region options |
| `docs/39_BIT_BYTE_GATE.md` | bit/byte two-rate learning gate and the unresolved byte transition |
| `docs/40_BYTE_STREAM_GATE.md` | real Alice byte-stream challenge; current failure vs order-0 |
| `docs/41_RELATION_FIRST_CURRICULUM.md` | relation-first penguin gate, word/logic checks, curriculum order |
| `docs/42_BYTE_EXPERT_ROUTER.md` | overbootstrap chooses between Hopfield and bigram byte experts |
| `docs/43_BYTE_ROUTER_REPEATS.md` | ten-pass byte measurement: repetition does not improve top-1 |
| `docs/44_WORD_STREAM_GATE.md` | word unigram/bigram baseline and the weak word signal |
| `docs/45_WORD_VECTOR_GATE.md` | binned word-vector expert vs word bigram |
| `docs/46_LOGIC_SCALE_BASELINE.md` | 20k-entity symbolic logic baseline and universal triple corpus |
| `docs/47_BOOLEAN_HEADS_CURRICULUM.md` | all 256 heads learn individual Boolean functions and bit manipulation |
| `docs/48_HEAD_GATES.md` | learned Boolean heads applied as 32-lane relation gates |
| `docs/49_BOOLEAN_SPECTRUM.md` | four-NaN transforms, ANF/Walsh/symmetry, transpose split |
| `docs/50_LIFT_AND_SCALE.md` | lift/sketch/outer-product choices, hypervectors, scale stack |
| `docs/51_HYPERVECTOR_TRIPLES.md` | XOR bind/bundle/cleanup triple store and merge test |
| `docs/52_TEACHER_GATE.md` | Hopfield candidate → Boolean exception gate → triple-store grader |
| `docs/53_DETERMINISTIC_LAYERS.md` | reversible coupling, Boolean closure, exact F257 NTT |
| `docs/54_HYPERVECTOR_SCALE.md` | 20k hypervector split: global 0%, sharded 100% |
| `docs/55_SUPERPOSITION_TODO.md` | deferred signed-amplitude/phase design; explicitly not implemented |
| `docs/56_DEGREE_EXCEPTIONS.md` | nested exceptions require degree = depth + 1 |
| `docs/57_SEMIRING_INHERITANCE.md` | 20k kind-chain inheritance via Boolean closure |
| `docs/58_NTT_AND_REVERSIBLE.md` | real-window NTT correlation and reversible-vs-stored memory |
| `docs/59_SLOT_RECOVERY.md` | 30% slot loss, 5/8 damage, 7/8 partial recovery |
| `docs/60_UTM_ROADMAP.md` | 2CM-first universal-machine roadmap; long-term and not implemented |
| `docs/61_SPARSE_EXCEPTIONS.md` | dense kind closure + sparse per-entity exception residual |
| `docs/62_SPARSE_DEGREE_20K.md` | sparse term learner on 20k samples; exact at depth+1 |
| `docs/63_TWO_COUNTER_U1.md` | bounded 2CM in chart address registers |
| `docs/64_LIMB_ATLAS_ORBIT.md` | multi-limb counters, atlas paging, reference 2CM orbit |
| `docs/65_TURING_MACHINE.md` | actual TM runtime with tape pages and binary increment |
| `docs/66_UNIVERSAL_TM_RUNTIME.md` | fixed-step UTM interpreter: encoded descriptions on chart tape |
| `docs/67_UTM_PROOF_HARNESS.md` | versioned grammar, randomized cross-check, ledger checkpoint |
| `docs/68_TAPE_LEDGER_LINK.md` | tape page root, atlas allocation, sharded-journal commit, restore boundary |
| `docs/69_UTM_PROOF_OBLIGATIONS.md` | explicit finite-control/self-encoding/equivalence obligations |
| `docs/70_SMALL_UTM_TABLE.md` | Neary-Woods U6,4 explicit 6-state/4-symbol table |
| `docs/71_MINSKY_UTM.md` | Minsky 23-state/8-symbol universal table and trace check |
| `docs/72_UTM_TRACE_INVARIANT.md` | configuration relation, tested traces, proof gaps |
| `docs/73_UTM_IMPLEMENTATION_STATUS.md` | what is implemented and the one remaining proof limitation |
| `docs/74_TM_TO_BINARY_COMPILER.md` | 23×8 table compiled to a 508-state binary TM |
| `docs/75_SELF_SIMULATION_PROBE.md` | reproducible partial recursive self-simulation run |
| `docs/76_COMPACT_BINARY_RUNTIME.md` | direct 508-state binary runtime, no Minsky scan |
| `docs/77_UTM_PROOF_PACKAGE.md` | Minsky universality plus implementation lemma package |
| `docs/78_LOGIC_CURRICULUM.md` | graded logic puzzles through the runner ring |
| `docs/79_STAGED_LOGIC_TRAINER.md` | Boolean -> deep circuits -> words staged core trainer |
| `docs/80_TRAINING_CORPUS_PIPELINE.md` | staged N16TXT corpus, budgets, HERMES and Clocked adapters |
| `docs/81_CONVERSATIONAL_TRAINING_LOOP.md` | host/model → pipeline → metrics → reflection loop |
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
- the NaNLMind memory-tier geometry used by `nanlm-ram` / `nanlm-vram`.

**This is not yet:**

- a proven universal computer on the pure local rule set;
- a trained language model;
- a claim that resonance or hyperedges already beat a baseline;
- a claim of consciousness or personhood.

The R23 VM is a host interpreter over topology cells; the cognitive suite is host symbolic reasoning over a triple store. The new repository keeps those results as behavior specifications and moves the transition logic into the substrate step by step. See [docs/01_DISCOVERY.md](docs/01_DISCOVERY.md) and [docs/10_FALSIFICATION.md](docs/10_FALSIFICATION.md).

---

## License

Apache-2.0. See [LICENSE](LICENSE).


## Clocked evidence integration

The Clocked SDK gateway is embedded in the existing `integrations/nannet/server.py`
Koyeb service; there is one service and one HTTP process, not a separate Clocked
deployment. The adapter code and its SDK boundary live under
`integrations/nannet/clocked_*`. The same service owns NANNET identity,
lowest-free HW8–HW254 allocation (node points 9–255), scoped participant
credentials, and Clocked request routing. The same process embeds NaNLMROUTER's
BS0:0 source inbox and MC0:0 six-runner heartbeat routes; the six CPU runner
workflows use this same Koyeb origin. `CLOCKED_API_KEY` remains server-side
and is never returned to participants, Android clients, or runners.

The demo validates task-family labels against independent gold labels before
admitting examples, keeps held-out evaluation isolated from live Clocked calls,
and sends digest-only evidence to both NANNET's observation queue and the
embedded NaNLMROUTER inbox. Unverified observations remain evidence-only; they
do not update model heads. Only independently verified outcomes may contribute
bounded feedback through the canonical runner ring. This is a routing/evidence integration, not a
general language-model accuracy claim. Configure the Clocked secrets on the
existing Koyeb service as documented in
`integrations/nannet/README.md`. See
`docs/72_CANONICAL_TRAINING_UNIVERSE.md` and
`specs/CLOCKED_CHAINABLE_TRAINING.md`.
