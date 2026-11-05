# One universe: training and testing

This is the current focus. The global meta is design-only until this universe
passes its gates.

---

## 1. Scope

```text
one 8 MiB chart
256 palindromic heads
32,640 pair cells
4 NaN words per cell
1 KiB scratch per head
logical clock + wall anchor
```

No cluster training, no 256-meta orchestration, no mesh dependency. Those are
later layers.

---

## 2. Training signals

| signal | API | state |
|---|---|---|
| Boolean function | `HeadView::train_boolean` | 16 int16 scores in `scratch.work()[16..47]` |
| sequence order | `BidirectionalMemory::link` | pair rails / temporal links |
| resonance | `ResonanceLattice::step` | integer Q16.16 energy/phase |
| self-modification | `self_modify_boolean` | 16-bit `ops` mask |
| growth | `GrowthPolicy` | self-error streak or scratch watermark |
| consolidation | `ScratchJournal` | R17 base-hash replay |

Training is integer and replayable. No gradient is required in the core.

---

## 3. UniverseTrainer

`include/nanlm/training.hpp`:

```cpp
UniverseTrainer trainer(heads);

trainer.train_boolean(head, samples, epochs);
auto report = trainer.evaluate_boolean(head, samples);

trainer.train_sequence({3, 7, 11, 19}, epoch);
auto fwd = trainer.recall_forward(3, 3);   // 7, 11, 19
auto rev = trainer.recall_reverse(19, 3);  // 11, 7, 3
```

`tests/test_universe_task.cpp` trains XOR, AND, and OR on separate heads,
evaluates all three at 4/4, and replays a four-head sequence both ways.

---

## 4. Test ladder

| gate | test | pass condition |
|---|---|---|
| address algebra | `test_address` | exhaustive |
| NaN16 Boolean | `test_nan16` | all 16 functions |
| chart structure | `test_universe` | 32,896 cells, 256 heads |
| pager / bit addressing | `test_pager` | COW, dirty, snapshots |
| heads | `test_heads` | 256 unique portals, handoff |
| Boolean learning | `test_training`, `test_universe_task` | learned rule + accuracy |
| sequence | `test_r18t_sequence` | forward/reverse order; symmetric fails |
| frame sync | `test_frame_sync` | +4 / -3 meet at 4; next runner wins |
| inverse | `test_inverse`, `test_contemplation` | exact before/after restore |
| growth | `test_growth` | error/scratch trigger, child chart |
| consolidation | `test_consolidation` | stale/abort/commit |
| handoff | `test_handoff` | 256 heads across 6 slots |
| router | `test_router` | q/s + BE/LE route |
| NTF | `test_ntf` | address/mapping/route/handoff |
| NCR | `test_ncr` | 256 systems, failover, migration plan |
| supercluster | `test_supercluster` | 256 clusters × 256 heads |

`make universe-check` runs the single-universe subset.

---

## 5. First byte-level result (2026-11-05)

Corpus: `data/alice_excerpt.txt`, 30,000 bytes, 80/20 split.

| model | top-1 | bits/byte |
|---|---:|---:|
| topology bigram | 29.97% | 3.895 |
| host bigram reference | 29.97% | 3.895 |
| order-0 | 16.18% | 4.681 |
| slot1 / host bigram | 29.97% | 3.895 |
| slot2 (context 2 + backoff) | **41.06%** | 4.023 |

The topology **matches** the independent host bigram exactly. That is not
suspicious; it is the storage-fidelity gate. The test now proves it three ways:
snapshot/restore preserves the result; training on a different corpus changes
predictions; writing a count directly into a pair cell changes the prediction.
Bigram beats order-0 by 0.786 bits/byte on the 30 KB excerpt.

### Larger corpora and Kneser-Ney

Same 80/20 split, byte level:

| corpus | order-0 | topology bigram | KN-1 | KN-2 | context-2 layout |
|---|---:|---:|---:|---:|---:|
| Alice excerpt (30 KB) | 4.681 | **3.895** | 3.377* | 2.676* | — |
| Alice full (151 KB) | 4.713 | 3.509 | 3.377 | **2.676** | 3.281 |
| Moby Dick (1.2 MB) | 4.563 | 3.539 | — | **2.895** | 3.067 |

`*` measured on `alice_full.txt` for the KN rows; the excerpt topology number is
shown separately. The topology bigram cannot represent a two-byte context. The
Kneser-Ney trigram beats it by **0.83 BPC** on Alice full and **0.64 BPC** on
Moby Dick.

The context-2 layout is the child-universe mapping, measured with compact slabs:
79 slabs on Alice full and 109 on Moby Dick. Its top-1 is 45.12% / 38.98%. It
beats the topology bigram but not KN-2, which is the honest target.

### Context-2 child universes

`Context2Topology` materializes the layout: the router chart's 256 heads are
first context bytes, and each observed first byte opens one child universe. The
child's pair cells hold a directed 256x256 count matrix:

```text
child(a).pair_cell(b,c).s_plus()  = count(a,b,c)  when b <= c
child(a).pair_cell(b,c).s_minus() = count(a,b,c)  when b >  c
```

The two rails are required: a pair cell is canonical, so using only the address
would alias `(b,c)` with `(c,b)`. `tests/test_context2_topology.cpp` proves the
counts, prediction, child count, checksums, and missing-context empty result.

Dense child-universe cost is 8 MiB each: 79 charts = 632 MiB on Alice full,
109 = 872 MiB on Moby Dick. That fits a runner with paging, but it is why the
next step is sparse child pages or a compact count slab behind the pager, not
256 dense universes. The topology mapping is real; the dense allocation is the
remaining engineering cost. For the on-device byte loop and Gutenberg data
scale, see [27_ANDROID_BOOTSTRAP.md](27_ANDROID_BOOTSTRAP.md).

Run:

```sh
./build/nanlm-universal byte data/alice_excerpt.txt
```

## 6. Baselines and honest results

- Boolean score learning is exact for the 16-function space; it is not a
  gradient method.
- R18T sequence memory is real: asymmetric order replays; symmetric storage
  fails.
- The R18T RNN control shows a plain RNN matches the 256-head full-W model at
  bits/byte. The topology is not a measured learning advantage.
- Resonance is an integer field; its capability claim is still open.
- Hyperedge completion is still open.

The first external task should be byte-level next-byte prediction with:

- the order-0 and bigram baselines;
- Kneser-Ney 1/2/3;
- a plain RNN control;
- a held-out stream and confidence interval.

Do not scale the meta until one universe beats a baseline on a task that is not
a tautology.

---

## 7. Commands

```sh
make universe-check
./build/nanlm-universal verify
./build/nanlm-universal heads
./build/nanlm-universal phase
./build/nanlm-universal router
./build/nanlm-universal ntf
./build/nanlm-universal snapshot --out state/chart.nmc
./build/nanlm-universal headshift --slot 1 --epoch 0 --runners 6 \
  --snapshot state/chart.nmc --out state/chart.nmc --json state/packets.json
```

The ring can run the same universe through `nanlm-cpu-1..6`, but the training
gate is local first. `headshift` now emits real `HeadView` packets from the
serialized chart and evolves a local snapshot. Cross-job persistence needs the
`nanlm-vram` snapshot adapter, which is next.

---

## 8. Exit criteria for the single universe

1. All `make universe-check` tests pass.
2. A held-out byte task beats the bigram baseline.
3. Sequence forward/backward recall beats symmetric storage.
4. A hyperedge completion task beats a pairwise baseline.
5. A dropped-slot handoff preserves the exact head state.
6. The global digest replays from genesis.
7. No step requires a 256-cluster mesh.

Only then does the next layer matter.
