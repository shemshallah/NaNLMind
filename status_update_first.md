# status_update_first.md

**Repository:** https://github.com/shemshallah/NaNLMind  
**Status date:** 2026-11-05  
**CI:** green — core tests, R18T sequence, legacy logic, atomic-clock self-test  
**Ring:** six head runners live, sequential epochs, self-redispatching 24/7

---

## 1. The next layer is more spaces

The local chart is unchanged:

```text
256 x 256 addresses
256 palindromic heads
32,640 mirror pairs
32,896 canonical cells
2 rails per pair
```

A higher layer is more charts, multiplied by 256:

| level | universes | canonical cells | dense |
|---:|---:|---:|---:|
| 0 | 1 | 32,896 | 8 MiB |
| 1 | 256 | 8,421,376 | 2 GiB |
| 2 | 65,536 | 2,155,872,256 | 512 GiB |
| 3 | 16,777,216 | 551,903,297,536 | 128 TiB |
| 4 | 4,294,967,296 | 141,287,244,169,216 | 32 PiB |

The 256 diagonal points of a **router chart** are child universes; the 32,640
pair cells are routes between them.

---

## 2. Portal protocol

| NaN | direction | meaning |
|---|---|---|
| `+qNaN` | BE / FUTURE | quiet read |
| `−qNaN` | LE / PAST | quiet read, reverse |
| `+sNaN` | BE / FUTURE | signaling write / open |
| `−sNaN` | LE / PAST | signaling write / close / rollback |

A `PortalWord` carries `op`, `flags`, and 32 bits of `data`. The address pairing
is `addr(src,dst) = (src << 8) | reverse8(dst)`; one canonical cell holds both
rails. The two directions are independent.

The root router chart is a **field of the one topology**, not a separate mind.
Its resonance/attention selects routes; the one ledger and one digest still
apply.

---

## 3. Frame sync

Forward rail `s+` and rollback rail `s-` are frame directions.

```text
runner 0: frame 0, +4  -> target 4
runner 1: frame 7, -3  -> target 4
meet at frame 4
next runner (2) has precedence
```

`FrameSync::meet()` rejects same-rail requests and disjoint targets.
`FrameSync::meet_window()` chooses the earliest overlapping frame. The meeting
is a logical event, not a wall-clock sleep.

---

## 4. Inverse computation and contemplation

A `HeadFrame` stores the exact before/after cell, head record, and 1 KiB
scratchpad. `compute_reverse_frame()` restores the before-state;
`compute_forward_frame()` re-applies the after-state.

`contemplate(view, mutation, commit)`:

1. capture before;
2. apply candidate forward mutation;
3. capture after;
4. compute the exact inverse;
5. compare the restored before-state;
6. commit the after-frame or leave the exact before-frame.

This works for irreversible Boolean heads because the frame keeps the missing
information. Reversible rules can reconstruct from the reverse rail alone.

---

## 5. Atomic/wall time

The logical clock orders state. The wall anchor gives real time for snapshots
and leases.

`runner/atomic_clock.py` samples:

- GitHub `Date` header;
- `worldtimeapi.org`;
- `timeapi.io`.

It takes the median offset, rejects outliers, and reports uncertainty. The
anchor is written to `nanlm/atomic`; a universe requests it through the router:

```text
RouterChart::request_time(src, dst, epoch)
  data  = "TIME"
  flags = kTimeRequestFlag
```

`SnapshotStamp` carries `wall_ns`, `uncertainty_ns`, `logical_tick`, `phase`, and
`anchor_id`. The ring round record and manifest include the atomic record.
Wall time never enters the state-ordering digest.

---

## 5.1 NaN Translation Fabric

The new tier between the Universe Network Map and the physical mesh:

```text
nan://U-07/R-03/H-0x0180/T-108/model/a
```

- physical locator: `tcp://node-a.example:7401/nan`
- universe address: `U / region / head / generation`
- semantic resource: `model/a`

`MappingRecord` carries `topology_root`, providers, locators, generation,
mapping version, capabilities, expiry, crypto suite, and signature.
`TranslationFabric` publishes/resolves/routes/revokes; stale version,
generation, expiry, and unsigned mappings are rejected.
`TemporalHandoff` validates destination generation, expiry, epoch, and phase.
`MeshRegistry` advertises peers and expires them.

Crypto is a hook: Ed25519 / ML-KEM / SHA3 / NSP8 belong in NaN/0S or a native
verifier. A valid universe address does not grant access; identity, address,
and authorization are separate.

## 5.2 NCR and two cluster layers

The NaN Cluster Runtime maps physical systems to Heads:

- `SystemProfile` — arch, cores, RAM, GPU, storage, bandwidth;
- `ClusterProfile` — up to 256 systems;
- `ClusterRuntime` — placement, two-phase handoff ownership, failover,
  migration planning;
- `SuperclusterProfile` — 256 clusters;
- `SuperclusterRuntime` — 256 regions × 256 Heads = 65,536 Head placements.

A failed system reassigns its Heads inside the cluster. A whole region can
migrate to another compatible cluster. A universe can be hosted by a cluster
of phones, a cluster of servers, or a mixed cluster.

The global meta (256 meta-universes × 256 superclusters × 256 clusters × 256
systems) is design-only. The arithmetic envelope is 4.29B systems, 1.1T Head
instances, 32 PiB dense at the extreme; the regional reading is one universe per
supercluster = 65,536 universes, 16.7M Heads, 512 GiB dense.

Earth-scale check (`experiments/earth_scale.py`): assuming 23.5B devices and
100% participation, the hierarchy needs ~1,401 IoT spaces, ~5.5 global meshes,
and ~0.02 superclusters. All GPUs fit in ~0.23 of one global mesh. A supercluster
is ~46× Earth's assumed device count; the supercluster layer is beyond current
need.

## 6. Live ring

- `nanlm-cpu-1..6` — disposable head runners
- `nanlm-ram`, `nanlm-vram` — separate tiers
- `deeprepo-cpu-1..5` — Qwen demo, untouched
- one secret: `DEEPREPO_PAT`

First live epoch:

```text
epoch = 1
manifest generation = 2
all six slots present
round digest = 0cc600649c35b0f91f0ed9693ac0916f14a03fa4587a2d292b33b7b091d7d61c
```

Epoch 2 succeeded and self-redispatched. The ring is sequential by default:
six concurrent writers corrupt the single reporam journal. One-epoch dispatch is
~6m25s because it starts six workflow jobs.

The persistent loop (`op=loop`) is now live: one job processes multiple epochs
in one workspace and rotates across the six runner repos per shift. Three
epochs were processed in one job in ~94 seconds. The six-workflow protocol is
still available as the explicit handoff proof.

---

## 6.1 Single-universe training

`UniverseTrainer` trains Boolean heads and temporal sequences on one 8 MiB
chart. `tests/test_universe_task.cpp` learns XOR, AND, and OR on separate heads
at 4/4, and replays a four-head sequence forward and backward.

First byte-level result on `data/alice_excerpt.txt` (30 KB, 80/20):

| model | top-1 | bits/byte |
|---|---:|---:|
| topology bigram | 29.97% | 3.895 |
| host bigram | 29.97% | 3.895 |
| order-0 | 16.18% | 4.681 |
| slot-1 / host bigram | 29.97% | 3.895 |
| slot-2 (context 2 + backoff) | 41.06% | 4.023 |

The topology matches the host bigram exactly. That is storage fidelity, not a
shared-array trick: snapshot/restore preserves it, a different training corpus
changes predictions, and a direct pair-cell count mutation changes the
prediction. Bigram beats order-0 by 0.786 bits/byte. Context-2 improves top-1 to 41.06% but is still worse in BPC (4.023)
because 30 KB is too sparse for a 65,536-context table even with backoff. The
next baseline is a stronger smoothing method or more data, then a plain RNN.

`make universe-check` runs the single-universe gate:

- Boolean learning;
- byte-level bigram equivalence;
- 256-head structure;
- sequence order;
- handoff;
- growth;
- inverse frames;
- contemplation;
- dropped-slot recovery using the reverse frame.

The global meta waits until these pass on a real byte-level task.

## 7. CLOCK_SYNC result

From `NaN16_PTC_merged_R15-R23clock.zip`:

| mode | order before drop | during drop | late | rejoin recovered | median recovery | epoch spread |
|---|---:|---:|---:|---:|---:|---:|
| free-running | 0.282 | 0.290 | 0.286 | 0/10 | — | 121.3 |
| local plurality | 0.704 | 0.932 | 0.975 | 9/10 | 1 tick | 317.7 |
| global scratch | 0.964 | 0.963 | 0.963 | 10/10 | 10.5 ticks | 0.4 |

Local phase agreement is not a clock; the epoch spread is too large. The global
scratch is the sync bus.

Orbit-count note: the archive states 64,800 / 720 / 16; an exhaustive check of
the stated transforms gives **65,040 / 480 / 16**. The 720 figure
double-counts a 240-address family. The 240 half-rate + 16 static head split is
correct.

---

## 8. Training

Integer score learning in the scratchpad:

```text
score[op] += match ? +1 : -1
rule = argmax score
mask = 1 << rule
```

The R18T control is explicit: a plain RNN (126K params) matches the 256-head
full-W model (197K params) at 2.18–2.25 vs 2.19–2.20 bits/byte. The topology is
storage/addressing and bidirectional memory, not a measured learning advantage.

---

## 9. Legacy tests

- `tests/test_r18t_sequence.cpp` — asymmetric sequence order, symmetric control
- `tests/test_legacy_logic.cpp` — cognitive 9/9, hard 8/8, extreme 8/8,
  formal 9/9, puzzles 7/7, modal 8/8
- `make legacy` in CI

---

## 9.1 Runner time limit

Six hours is the maximum duration of **one job**, not a daily quota. The ring
uses a 350-minute job timeout, a 300-minute loop budget, and 200 epochs per
shift, then dispatches a fresh job. Concurrency, API limits, and fair use still
apply.

## 9.2 Rate-limit guard

A 403 during development polling was contained: `/rate_limit` preflight (<200),
keeper resume (<100), 30s polling, 60s backoff on 403, persistent 10-epoch jobs,
and separate concurrency groups. No state was corrupted. See
`docs/26_RATE_LIMITS.md`.

## 10. Next

1. Load real chart/head/scratch state from `nanlm-vram` in the ring worker.
2. Add order-0, slot-memory, and plain-RNN controls to the byte task.
3. Connect the NTF mapping record to the signed registry and peer discovery.
4. Two-universe communication demo with the NTF and temporal handoff.
5. Dropped-slot recovery using reverse rails and contemplation frames.
