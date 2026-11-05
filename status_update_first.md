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

## 10. Next

1. Load real chart/head/scratch state from `nanlm-vram` in the ring worker.
2. Route selection by resonance attention with congestion/backpressure.
3. Connect the NTF mapping record to the signed registry and peer discovery.
4. Two-universe communication demo with the NTF and temporal handoff.
5. Dropped-slot recovery using reverse rails and contemplation frames.
