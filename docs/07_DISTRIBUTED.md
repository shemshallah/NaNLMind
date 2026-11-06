# One object on a replica ring

## 1. The rule

> There is one global topology. Five replicas host regions of it. There is no
> external semantic coordinator and no per-replica history.

The six NaNLMind GitHub runner slots are:

```text
nanlm-cpu-1
nanlm-cpu-2
nanlm-cpu-3
nanlm-cpu-4
nanlm-cpu-5
nanlm-cpu-6
```

Each has ~7 GiB RAM and ~14 GB disk. They are disposable. They are not six
minds; they are six caches/executors of one object.

---

## 2. What is replicated, what is placed

| thing | semantics | distribution |
|---|---|---|
| address algebra | one | everywhere |
| chart set / atlas | one | placed by `hash(chart_path) mod 6` |
| hypergraph | one | descriptors + member blocks placed by page |
| temporal memory | one | links placed with their pages; epoch index replicated |
| ledger | one | append-only; every commit carries the head |
| root digest | one | recomputed from page hashes |
| page cache | per replica | LRU, not semantic |
| lease table | per epoch | one writer per page |

A replica may cache any page it reads. It may write only pages it holds a lease
for. The global object is not the union of replica states; it is the set of
committed pages under the one root.

---

## 3. Placement

A first placement rule:

```text
owner(chart_path) = fnv1a(chart_path) mod 6
```

A page is *hosted* by one replica at a time. Other replicas may hold read
copies. A write requires:

1. a lease from the current epoch;
2. the base page hash;
3. a successful compare-and-swap;
4. a ledger append;
5. a new page hash and root.

A page can migrate:

```text
old replica: release lease, publish final delta, mark page cold
new replica: fetch page + delta, verify hash, acquire lease
global ledger: append migration event
```

The head identity does not change. The chart path does not change. Only the
physical residence changes.

---

## 4. The commit protocol

```text
writer                         global ledger                 replicas
  |                                 |                           |
  |-- lease(page, base_hash) ------>|                           |
  |<-- granted ---------------------|                           |
  |-- apply bits/deltas ------------|                           |
  |-- append(delta) --------------->|                           |
  |                                 |-- verify base hash         |
  |                                 |-- append event             |
  |                                 |-- new head                 |
  |<-- commit ok -------------------|                           |
  |-- publish page @ new hash ----->|-------------------------->|
  |                                 |                           |-- verify
  |                                 |                           |-- update cache
```

Rules:

- one writer per page;
- the base hash must match the current page hash;
- a stale writer is rejected and must rebase;
- a duplicate delta is an idempotent no-op;
- an interrupted commit is not applied;
- the ledger is the total order;
- a replica that cannot verify the head refuses the page.

This is the R15/R17 branch/commit/replay design, applied to the one object.

### 4.5 Logical time, not wall time

Replicas do not share a physical clock. They share a deterministic logical
stamp from the nanclock oscillator:

```text
LogicalStamp = (tick, phase)
phase 0 = +qNaN, phase 1 = -sNaN
```

- a lease names a `lease_tick`; a writer with an older tick is rejected;
- every committed event carries the stamp;
- a replica that missed ticks calls `observe(stamp)` and replays the
  deterministic orbit;
- phase 0 is the propose/execute cadence; phase 1 is the rewrite/commit cadence;
- the host clock is used only for network timeouts, never for semantic order;
- the clock digest is included in the global digest.

This is what makes the oscillator useful for distributed spaces: it is a
single integer plus one bit, reconstructible from genesis, and independent of
how long a tick takes in nanoseconds or milliseconds. See
[14_TEMPORAL_CLOCK.md](14_TEMPORAL_CLOCK.md).

### 4.6 Wake slots and phase sync

Replicas should not wake in linear order. Assign wake slot `reverse8(i)`; any
power-of-two subset of survivors stays evenly spread. Verified max gaps with
256 slots: 8 alive = 32, 16 = 16, 32 = 8 (linear: 249, 241, 225). Five alive is
64 against an ideal of 52 because 5 is not a power of two.

The 256 phase oscillators also need the community scratch to avoid frozen
domains. Local plurality alone synchronized 1/10 runs in the reported
experiment; adding the global scratch synchronized 10/10. The scratch is a
field of the one object, so this does not introduce a coordinator. See
[15_PHASE_SCHEDULING.md](15_PHASE_SCHEDULING.md).

---

## 5. Memory budget

### Depth 0 — the initial brain

One chart = 8 MiB. A single replica can hold it many times over. This is the
starting point: **one state-space brain on GitHub**.

### Depth 1 — the first atlas

256 charts = 2 GiB dense. Five replicas × 7 GiB can hold:

- the full atlas (2 GiB) on each, or
- a placed copy (410 MiB each) + caches + history + hyperedges.

This is the first realistic multi-replica brain.

### Depth 2 — the remote tier

65,536 charts = 512 GiB dense. Five replicas cannot hold it. They hold a hot
working set (a few GiB each) and read cold pages from nanlm-ram/nanlm-vram over
HTTP Range. The 8 MiB page is the fetch unit. A page fault is a remote read, not
a lost thought.

### Depth 3+ — the distributed store

16.7M charts = 128 TiB; 4.29B charts = 32 PiB. These are S3/B2/RAM-farm
territories. The object is sparse: only written charts exist. The global digest
is a Merkle root over the live page set, so a replica can verify a subset
without downloading everything.

| depth | charts | dense | 6 × 7 GiB? | storage |
|---:|---:|---:|---|---|
| 0 | 1 | 8 MiB | yes | any |
| 1 | 256 | 2 GiB | yes | GitHub runners |
| 2 | 65,536 | 512 GiB | hot set only | nanlm-ram/nanlm-vram |
| 3 | 16.7M | 128 TiB | no | S3/B2 |
| 4 | 4.29B | 32 PiB | no | distributed store |

---

## 6. Failure modes

### Replica disappears

- uncommitted deltas are discarded;
- committed pages are re-fetched from a peer or a generation;
- the lease expires;
- the head identity and collective facts survive.

### Interrupted commit

- the delta has no ledger event; it is discarded;
- the page remains at the old hash;
- replay from the last committed head reconstructs the state.

### Duplicate delivery

- the delta key `(page, base, next)` is checked;
- a duplicate is a no-op;
- the fact count does not change.

### Stale writer

- the base hash no longer matches;
- the commit is rejected;
- the writer rebases on the new page;
- no permanent competing mind is created.

### Partition

- reads continue from cache;
- writes fail closed until a lease is obtained;
- there is no second ledger, so there is no split-brain semantic fork;
- when the partition heals, the stale cache is reconciled by hash.

### Corrupted page

- the payload hash fails;
- the page is rejected;
- a mirror or the parent generation serves the correct page;
- the failed replica is marked unhealthy.

### Disappearing head

- the head's local state is cleared;
- the logical identity (`index`, `fixed_addr`) is preserved;
- the collective facts remain;
- a new replica reconstructs the associations from the collective state and
  the ledger.

The R17 "disappearing head" test is the specification for this behavior.

---

## 7. Why this is not six little minds

A fragmented design would have:

```text
six runners × private state × private history × external coordinator
```

This design has:

```text
six caches × one atlas × one hypergraph × one time × one ledger × one digest
```

The difference is testable:

1. Kill a replica. The global digest does not change for committed state.
2. Kill the coordinator. There is no coordinator to kill.
3. Replay from genesis on a fresh replica. The digest matches.
4. Present a stale or divergent page. The hash check rejects it.
5. Move a head to another replica. Its identity and facts survive.

If a proposed feature requires a private semantic state space or a second
history, it is rejected.

---

## 8. GitHub execution

The initial deployment uses GitHub Actions as the execution and storage layer:

- one repository holds the code, manifests, and small state;
- `nanlm-ram` holds the mutable journal and live pages;
- `nanlm-vram` holds immutable generations;
- the six `nanlm-cpu-*` repositories hold runner workflows and no data;
- a dispatch job leases a page range, runs a bounded work unit, appends a
  delta, and releases the lease;
- a compaction job folds deltas into a generation and publishes a manifest;
- a verify job recomputes the global digest and rejects divergence.

The workflow is the same shape as deeprepo's ring, but the payload is a chart
and the identity is the global digest.

---

## 9. Protocol invariants

1. One ledger, one head, one global digest.
2. One writer per page via a lease.
3. A commit carries a base hash and a next hash.
4. A stale base is rejected.
5. A duplicate is a no-op.
6. An interrupted commit is discarded.
7. A page is immutable after publication.
8. A generation is published only with a manifest and a mirror.
9. A replica loss is a cache miss, not a lost mind.
10. A head identity is logical and survives relocation.
11. No private semantic state space is allowed.
12. No external semantic coordinator is allowed.

The last two are architectural invariants, not implementation details.
