# The 6-runner head ring

## 1. One object, six slots

The head ring is six disposable GitHub runners:

```text
nanlm-cpu-1 .. nanlm-cpu-6
```

They host regions of the one `NaNLMind` object. They do not own private
histories. `NaNLMind` is the idle orchestrator/storage repository. It is the
only ring; the retired Qwen demo and its tiers are gone.

```text
NaNLMind (orchestrator, manifests, docs)
   │  ring.yml / keeper.yml
   ▼
nanlm-cpu-1..6  ──►  nanlm-ram (packets, clock, lease, manifest)
   │                 nanlm-vram (immutable generations)
   └─ one global ledger / one digest
```

Only the NaNLMind ring remains. The `deeprepo` repository is retained as the
engine dependency; there is no second writer journal.

---

## 2. Head map

```text
owner(head) = head mod 6
```

| runner | heads | count |
|---|---:|---:|
| 0 | 0, 6, 12, …, 252 | 43 |
| 1 | 1, 7, 13, …, 253 | 43 |
| 2 | 2, 8, 14, …, 254 | 43 |
| 3 | 3, 9, 15, …, 255 | 43 |
| 4 | 4, 10, 16, …, 250 | 42 |
| 5 | 5, 11, 17, …, 251 | 42 |

The map is implemented in `HeadMap` (`include/nanlm/handoff.hpp`), and the
registry verifies every one of the 256 heads appears exactly once.

---

## 3. One epoch

An epoch is a logical clock tick. It has two phases:

| phase | signal | meaning |
|---:|---|---|
| 0 | `+qNaN` | prepare / preload: read the committed page, warm head cells, scratch, neighbour pairs |
| 1 | `−sNaN` | commit / handoff: publish packets, verify all 256 heads, flip the manifest |

The cycle:

```text
epoch E, phase 0:
  slot 0 preloads its 43 heads
  slot 1 preloads its 43 heads
  ...
  slot 5 preloads its 42 heads

epoch E, phase 1:
  each prepared slot processes its heads and writes HeadPackets
  the round becomes ready when all six packet sets are present
  the round becomes complete when all six slots commit
  verify 256 unique heads, same epoch
  write one handoff ledger event
  publish the next manifest generation
  clock tick -> E+1, phase -> 1-phase
```

`HandoffRound` is the barrier:

- `prepare(runner, packets)` validates epoch, ownership, duplicates;
- `commit(runner)` confirms the runner's share;
- `ready()` requires all six prepares;
- `complete()` requires all six commits;
- `verify()` checks 256 unique heads and correct owners;
- `digest()` is the round hash;
- `record_handoff()` appends one ledger event.

A runner never starts the next epoch before the previous round is complete.
The ring is **sequential by default**: one slot writes its packet set, releases
its per-slot lease, and the next slot is dispatched. Six concurrent writers
would corrupt the single NaNLMind journal; `--parallel` is an experiment, not
the default.

---

## 4. Preload and map back

### Preload

Each slot loads:

- the current chart page / manifest generation;
- its 42–43 head records and head cells;
- the head scratchpads (`local` + `work`);
- the pair cells needed for its heads' row/column walks;
- the address-register capabilities and the page base hash.

It verifies the base hash before touching state. If the hash does not match, the
slot refuses and the coordinator retries with the committed generation.

### Map back

When all six packet sets exist:

1. collect all `HeadPacket`s;
2. verify 256 unique `head` values and `epoch == E`;
3. verify `owner(head) == runner`;
4. compute `HandoffRound::digest()`;
5. append one `HANDOFF` ledger event with epoch `E`;
6. publish manifest generation `G+1` with the new root;
7. advance the clock tick and toggle the phase;
8. release the lease.

No packet, no commit. A duplicate packet is rejected. A stale epoch is
rejected. The global digest is the identity.

---

## 5. Temporal directions

The pair cell has two rails:

```text
s+ : forward  (past -> future)
s- : reverse  (future -> past)
```

The epoch uses both directions:

- **forward** (`s+`, phase 0) is the normal preload/prepare path;
- **reverse** (`s-`, phase 1) is the commit/rollback path.

If a slot fails after phase 0 but before the round commits, the next slot reads
the last committed page and replays the reverse direction to the previous
manifest. Nothing partial is applied. This is the R17 rule applied to the ring:
stale workspace rejected, abort leaves no state, commit is one history entry.

The logical clock supplies the epoch and the phase. It is not wall time; the
lease has a wall-clock expiry for transport safety, but the semantic order is
`(tick, phase, ledger seq)`.

---

## 6. Handoff packet

```text
HeadPacket {
    head              u8
    epoch             u64
    phase             u32 Q16.16
    transform_phase   u8  I/B/BR/R
    self_error        u16
    scratch_used      u16
    state_hash        u64
    output            32 bytes
}
```

The packet is the minimum needed to reconstruct the head's local contribution:
identity, logical time, phase, transform image, error, scratch watermark, state
hash, and output. The authoritative state remains the page; the packet is the
handoff summary.

---

## 7. Workflows

| repo / workflow | role |
|---|---|
| `NaNLMind/.github/workflows/ring.yml` | dispatch six slots for one epoch, verify gate/rate limit, self-redispatch |
| `NaNLMind/.github/workflows/keeper.yml` | cron every 20 min; restart only when no ring run is active |
| `NaNLMind/.github/workflows/nanlm-bootstrap.yml` | create `nanlm-ram`/`nanlm-vram` releases and bin-0 superblocks |
| `nanlm-cpu-N/.github/workflows/runner.yml` | checkout core + deeprepo engine, build, run one head shift |
| `NaNLMind/runner/nanlm_worker.py` | selftest, prewarm, headshift, handoff, status |
| `NaNLMind/runner/ring_dispatch.py` | interleaved dispatch and await |

One CI secret: `DEEPREPO_PAT`. It is never shipped in an APK and never given to
Android/community nodes; those use a scoped, revocable intake credential.

Required permissions:

| repo | permission |
|---|---|
| `NaNLMind` | Contents R, Actions RW, Variables RW |
| `deeprepo` | Contents R |
| `nanlm-ram`, `nanlm-vram` | Contents RW |
| `nanlm-cpu-1..6` | Actions RW, Contents R |

### Rate limits

- one slot at a time, six dispatches per epoch;
- `ring.yml` checks `/rate_limit` and fails if core remaining < 200;
- `ring_dispatch.py` waits for each run before dispatching the next;
- `deepcore.Budget`/`ApiMeter` is used when the tier connection is available;
- `keeper.yml` never overlaps an active ring run;
- `concurrency` groups prevent duplicate ring/keeper runs.

This keeps the ring within GitHub Actions and API limits while leaving the
ring on its own six slots.

---

## 8. Training on the ring

Each slot trains only its heads:

```text
for each head h in slot:
    read head cell / scratch
    observe (a,b,target) or sequence transition
    update Boolean scores in scratch
    update temporal link counts
    emit packet + ScratchJournal delta
```

The round commits the deltas through the same `HandoffRound` barrier. A
community volunteer can train a shard and submit a `ScratchJournal` with a base
hash; consolidation replays it into a COW page.

---

## 9. Failure modes

| failure | response |
|---|---|
| slot times out | round incomplete; no manifest flip; retry the slot |
| stale epoch | reject packet; reload committed page |
| duplicate packet | reject / idempotent no-op |
| lease held | wait or fail closed; never write concurrently |
| page hash mismatch | refetch from `nanlm-vram`; do not apply |
| runner disappears | its packet set is missing; the round cannot validate |
| clock drift | logical epoch wins; wall clock is only for lease expiry |
| retired Qwen ring | removed; no separate tier or journal |
| rate limit low | preflight fails; keeper waits for the next window |

---

## 10. Current status

First live epoch completed on 2026-11-05:

- `nanlm-ram`/`nanlm-vram` bootstrapped;
- six slots ran sequentially;
- all six packet sets present;
- `nanlm/manifest.generation = 2`, `epoch = 1`;
- round digest recorded;
- ring self-redispatch enabled (`loop=true`).

Wall time for one epoch is ~6m25s in the six-workflow path. The persistent loop
processes many epochs in one 350-minute job (300-minute loop budget, 200 epochs
target). The six-hour limit is per job, not per day.

Implemented and tested:

- `HeadMap` and `HandoffRound` (prepare/commit/verify/digest);
- one ledger event per round;
- six runner repos and workflow template;
- `ring.yml`, `keeper.yml`, `nanlm-bootstrap.yml`;
- worker selftest/prewarm/headshift/status with local fallback;
- `nanlm-ram`/`nanlm-vram` repos;
- `DEEPREPO_PAT` set on all nine repos.

Next:

1. replace the deterministic packet worker with live `HeadView` state and a
   chart snapshot from `nanlm-vram`;
2. add a drift/dropped-slot test with the real workflow;
3. add the legacy R18T sequence and logic suites to the ring acceptance gate;
4. add a persistent slot loop to reduce the six-job overhead;
5. keep only the NaNLMind ring and its tiers.

---

## 11. What this is not

- It is not six independent minds. The head map is a placement of one object.
- It is not a wall-clock ring. The epoch is logical; the lease is transport.
- It is not a claim that the 256-head topology beats a plain RNN. The R18T
  control is explicit that it does not.
- It is not a claim that GitHub Actions is a 24/7 supercomputer. It is a
  bounded, rate-limited ring of disposable runners.
