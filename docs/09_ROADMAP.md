# Roadmap

The order is deliberate: prove the object, then grow it, then distribute it,
then train it. Do not invert the order.

---

## M0 — Provenance and invariants (done)

**Deliverables**

- all 28 archives extracted under `NaNLM_statespace/archive/`;
- SHA-256 manifest;
- Round 2–23 discovery audit with demonstrated / host-driven / open status;
- clean C++20 core for address algebra, NaN16 Boolean functions, the 8 MiB
  full-address register file, bit/byte/KB paging, hypergraph, temporal memory, resonance,
  ledger, and one global topology;
- exhaustive tests and a CLI.

**Acceptance**

- `make test` passes;
- `nanlm-universal verify` passes;
- the transposition theorem, all 16 Boolean functions, the mirror law, the
  register file, COW, the ledger, the hypergraph, the temporal split, and the
  global digest are covered.

**Status:** complete. This is the starting point, not the finish line.

---

## M1 — The single-chart brain on GitHub

**Goal:** publish one state-space brain as a runnable GitHub artifact.

**Deliverables**

- the core committed and tagged `v0.1`;
- the 256-Head Array (`HeadArray`/`HeadView`) with all 256 palindromic identities, registry verification, phase engine, and runner handoff;
- a genesis manifest with the chart genome, root hash, and head pin;
- an 8 MiB `.nlmchart` binary snapshot committed or attached to a release;
- a CLI that can load, verify, query, and dump the brain;
- a GitHub Actions workflow that rebuilds the chart and checks the digest;
- a model card describing exactly what the chart is and is not.

**Acceptance**

- a fresh clone + `make` + `./build/nanlm-universal verify` reproduces the
  genesis digest;
- the 256 heads are present and the 32,640 pairs are linked;
- a bit-level mutation changes the digest;
- a snapshot round-trips to the same digest;
- the model card reports the exact counts and the host-driven caveats.

**Resource:** one CPU, 8 MiB for the chart, a few MB for code.

---

## M2 — Hypergraph and bidirectional memory

**Goal:** make cross-space relations and forward/backward memory first-class.

**Deliverables**

- hyperedge storage at KB resolution with incidence tiles;
- hyperedge creation/removal as ledger events;
- temporal link creation/removal, branch/merge, epoch slices;
- the nanclock logical oscillator as the global `(tick, phase)` stamp; runner
  handoffs and lease ticks use it;
- the transform-phase oscillator (`I, B, BR, R`) with 2 bits per head in scratch;
- bit-reversed wake slots for survivor scheduling;
- growth by self-model error / scratch overflow, and atomic scratch
  consolidation with an R17 base-hash gate;
- a cross-chart relation demo with a pairwise-only baseline;
- a sequence replay demo (forward and backward) with a symmetric-storage
  baseline;
- tests for duplicate delivery, stale base, and interrupted commit.

**Acceptance**

- a hyperedge connects cells in at least two charts;
- `forward` and `backward` reconstruct a held-out sequence;
- the asymmetric storage beats the symmetric baseline on order replay;
- the one global digest includes hyperedges and temporal links.

**Resource:** one CPU, a few charts, no remote store.

---

## M3 — NaNLMind tier prototype

**Goal:** persist the object in the rebuilt tiers.

**Deliverables**

- `NLMSTOR1` page envelope;
- append-only delta journal;
- compaction into a generation;
- manifest + root hash + parent;
- local file backend and a memory backend;
- a page cache with range reads;
- a lease table;
- corruption and tamper tests;
- a migration test: old page format → new envelope.

**Acceptance**

- write → delta → compact → publish → reload → same digest;
- a stale delta is rejected;
- a duplicate delta is a no-op;
- a corrupted page is rejected;
- a generation rollback restores the parent;
- the storage geometry fits 16 bins × 510 pages.

**Resource:** one CPU, ~32 GiB virtual sparse, a few MB actual.

---

## M4 — Five replicas, one object

**Goal:** run the one object on `nanlm-cpu-1..6`.

**Deliverables**

- placement `hash(chart_path) mod 5`;
- lease acquisition/release over the ring;
- a bounded work unit: read pages → apply a local update → emit a delta;
- a compaction job;
- a verify job that recomputes the global digest;
- failure injection: kill a replica, interrupt a commit, duplicate a delta,
  stale writer, page migration;
- a dashboard of per-replica cache, lease, and digest.

**Acceptance**

- the depth-1 brain (2 GiB) runs across six 7 GiB head runners;
- a replica failure does not change the committed digest;
- a stale writer cannot fork the object;
- a page migration preserves head identity and collective facts;
- replay from genesis on a fresh replica matches the head.

**Resource:** six GitHub runners, 7 GiB each, 2 GiB dense atlas.

---

## M5 — Training and community shards

**Goal:** learn something measurable without fragmenting the object.

**Deliverables**

- integer update rules for operator masks, pair weights, hyperedges, temporal
  links, and resonance;
- a shard format: base page hash + delta + counters + provenance;
- a merge job: verify, fold, recompute, publish;
- a teacher distillation path (counts, not gradients);
- a held-out evaluation harness with baselines and nulls;
- a volunteer guide.

**Acceptance**

- a sequence task beats a symmetric baseline;
- a hyperedge completion task beats a pairwise baseline;
- a resonance recall task beats a static matrix;
- a Boolean-mask task beats a fixed mask;
- every result has a confidence interval and a shuffled null;
- a volunteer can contribute without seeing the whole object.

**Resource:** CPU for the core, optional free GPU for the teacher.

---

## M6 — Scale to the remote tiers

**Goal:** grow beyond a single runner's memory.

**Deliverables**

- depth-2 atlas (65,536 charts, 512 GiB dense) with sparse placement;
- page cache and prefetch policy;
- S3/B2 backend adapter;
- Merkle root over the live page set;
- partial verification without a full download;
- eviction/GC policy;
- cost and latency measurements.

**Acceptance**

- a working set fits in six 7 GiB caches;
- a cold page fetch is transparent;
- the global digest is verifiable from a subset + proofs;
- a full generation can be rebuilt from the manifest and the store;
- the object remains one object.

**Resource:** nanlm-ram/nanlm-vram, S3/B2, six runners, a GPU farm optional.

---

## M7 — The universality claim

**Goal:** decide whether the pure local mirror topology is universal, or only
hosts a universal machine.

**Deliverables**

- a local-rule implementation of the two-counter machine (no `vm_step` host
  switch);
- a proof or a bounded simulation of Rule 110 / a known universal CA on the
  mirror topology;
- a separation experiment: same topology without mirrors vs with mirrors;
- a performance and energy baseline against a plain CA and a CPU;
- a formal statement of what is and is not proven.

**Acceptance**

- the local rule set, not the host, advances the machine;
- the machine halts and produces the expected outputs;
- the mirror topology is either necessary or honestly reported as a label;
- the result is reproducible on ARM64/Termux and x86-64.

**Resource:** one CPU, a lot of careful work.

---

## Cross-cutting work

### Determinism

- canonical little-endian encoding for all hashes;
- no float in replay-critical paths;
- cross-compiler (clang/gcc) and cross-architecture (ARM64/x86-64) digest
  checks;
- `-O0/-O2/-O3` chain-head equality.

### Security

- fuzz `Universe::from_bytes`;
- validate every page before mapping;
- pin the ledger head;
- never trust a replica's word for a page;
- fail closed on a hash mismatch.

### Documentation

- every claim links to a test or a falsification condition;
- every generation has a model card;
- every experiment reports its baseline, null, and sample size.

---

## What not to do

- Do not add a per-head private state space.
- Do not add an external semantic coordinator.
- Do not add a second ledger.
- Do not claim universality from a host interpreter.
- Do not claim cognition from a host symbolic test.
- Do not claim a win without a baseline.
- Do not grow the atlas before the single chart is correct.
- Do not put floats in the replay path.
- Do not publish a generation without a manifest, a root hash, and a mirror.

---

## Near-term sequence

```text
now:      M0 complete
next:     M1 single-chart brain on GitHub
then:     M2 hypergraph + bidirectional memory
then:     M3 NaNLMind tier prototype
then:     M4 six runners, one object
then:     M5 training + community shards
then:     M6 remote tiers
then:     M7 universality decision
```

The first GitHub milestone is deliberately small: one 8 MiB chart, one genesis,
one digest, one reproducible build. Everything else is growth of that object.
