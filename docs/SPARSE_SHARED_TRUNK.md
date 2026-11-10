# Sparse shared deep trunk — NaNLMind reference integration

Status: **reference integrated into NaNLMind experiments; native NaN16 port is
staged**. The executable reference is Python/PyTorch under
`experiments/sparse_shared/`; it is not the native runtime and makes no
NaN16-performance claim.

## Why shared trunk

Making all 255 heads deep is prohibitive: 256 independent d=128, 12-layer
heads need ~2.26 GiB of 16-bit weights + 8-bit moments, plus up to 1.5 GiB of
KV at 1024 context. A shared deep trunk plus 255 low-rank adapters costs:

```text
d=512, 12 layers, MLP=2048 trunk: 37.77M params
16-bit weights: 72 MiB
8-bit moments:   72 MiB
KV @1024:        24 MiB
255 rank-4 adapters: a few MiB
```

The heads remain persistent routing/specialization interfaces; the trunk does
the deep computation.

## Sparse activation

Per token:

```text
score_h = router_h(x) + hotspot_h
indices = top_k(score)
active triad  iff >=2 of its 3 heads are selected
field cap     limits total active triads
```

`hotspot_h` is a persistent bias derived from the triad's recent adapter
gradient norm. It decays each step, so hot triads stay active briefly without
permanent hard routing. Inactive adapters are not evaluated and receive no
gradient.

## Hopfield decision

Hopfield was tested as an optional memory sublayer and then removed from the
production path. The quick probes were mixed: small gains only on a tiny
low-capacity association table, with 30-50% extra cost, and no reliable
held-out advantage at normal width. `experiments/sparse_shared` is now the
Hopfield-free shared-trunk reference. The v2 path does not use Hopfield.

## Measured reference

PyTorch CPU, batch 1, sequence 8:

| configuration | active heads | tokens/s | note |
|---|---:|---:|---|
| d=32, 2 layers, sparse | 8/255 | 38.0 | small model |
| d=32, 2 layers, random top-k | 8/255 | 29.7 | routing control |
| d=32, 2 layers, dense | 255/255 | 7.36 | 5.2x slower than sparse |
| d=64, 4 layers, sparse | 8/255 | 12.9 | reference default |
| d=64, 4 layers, dense | 255/255 | 1.93 | 6.7x slower than sparse |

Sparse is not a free 32x: the shared trunk, attention, router and Python/PyTorch
overhead are fixed costs. Measured speedup is 5–7x on this CPU harness.

## Throughput math for 1000 tokens/s

`4 tok/s` does **not** multiply by 255 heads. Token rate is set by FLOPs,
memory bandwidth, batch and hardware, not by head count alone.

At an effective 10 GFLOP/s:

- a 75 MFLOP/token shared 12-layer trunk tops out around 130 tok/s;
- 1000 tok/s needs <=10 MFLOP/token at 10 GFLOP/s;
- 8 active heads at d=128, 12 layers are ~75 MFLOP/token, so ~130 tok/s;
- 1 active head at that depth is ~9.4 MFLOP/token, close to 1000 tok/s but
  loses the ensemble/specialization;
- batching increases aggregate throughput but not single-stream latency;
- a 100 GFLOP/s target (GPU or a much smaller/quantized trunk) makes 1000
  tok/s plausible at ~100 MFLOP/token.

The realistic first target is **100–200 tok/s** on CPU with a small shared
trunk and top-k=8–16; 1000 tok/s requires a smaller trunk, batching, or
accelerator.

## Files

- `experiments/sparse_shared/model.py` — trunk, 255 adapters, router, hotspot.
- `experiments/sparse_shared/train.py` — dense/sparse/random benchmarks.
- `tests/test_sparse_shared.py` — budget, top-k, inactive-gradient isolation,
  hotspot promotion and fixed-batch loss decrease.

Run:

```sh
python3 -m unittest tests.test_sparse_shared -v
python3 -m experiments.sparse_shared.train --mode sparse --active 8 --steps 2
python3 -m experiments.sparse_shared.train --mode dense --steps 1
```

## V2 state mapping

The reference is deliberately shaped to map onto the existing v2 fields:

| reference state | v2 target |
|---|---|
| trunk weights + 8-bit moments | quantized sidecar (d=512, 12 layers; 72 MiB + 72 MiB) |
| 255 adapters | extension records: 2·d·rank Q16.16 values + router score + credit |
| router logits | per-head routing scores in scratch; top-k in the field |
| hotspot | per-head/triad credit derived from adapter gradient norms |
| triad gate | existing 85 triads, 2/3 vote |
| field gate | existing 43/85 field vote |
| hypermatrix | 32,640 pair rows × 256 candidate bits |
| leaf state | exact address/word/bit leaves and leaf masks |
| CFT credit | triangle flux base in the native CFT bank |

A rejected sparse proposal must restore the adapter/trunk scratch and leave
`s+`/`s-`, digest and generation unchanged. The native port must run through
the one canonical nan0s VM; the Python reference is a control, not the result.

## Native step 1: sparse head/field bank

The first native piece is now integrated, without Hopfield:

- `include/nanlm/sparse_field.hpp` / `src/sparse_field.cpp`;
- 255 low-rank adapters, runtime-configurable up to **d=512, rank=4**,
  Q1.15 weights (default d=32/rank=4; d=512 is a 2.35 MB sidecar allocation);
- top-8 routing, integer-normalised weights, 255-bit active mask;
- per-head hotspot and usage state;
- local non-BPTT credit update for a selected adapter;
- state stored in a heap-backed `Universe::sparse_field()` sidecar and
  serialized/digested with the chart; it is not counted against the fixed
  8 MiB root budget, and older snapshots restore with a zeroed bank;
- `tests/test_sparse_field.cpp` checks top-k uniqueness, inactive-adapter
  isolation, d=512 operation, adaptive-triad hotspots, 43/85 field
  identification, persistence and old-snapshot restore.

### Hot heads and hot triangles

`SparseField::update_hotspots` scans the whole field, not fixed head/3 groups:

1. every one of the 255 heads with credit above the head threshold is a hot
   head;
2. every one of the 85 triads is scored from its **adaptive** members;
3. a triad is hot when at least two members are hot, or its mean credit is
   above the triad threshold;
4. a hot triad promotes all three members;
5. the field flag is set only at the 43/85 threshold.

The result is available as `Hotspots.heads`, `Hotspots.triads`,
`Hotspots.hot_heads`, `Hotspots.hot_triads` and `Hotspots.field_hot`.

The raw NaN16 path is authoritative for auto-mapping: `mth_hot_trihead.nas`
scans the 255 head credits, groups hot individuals in threes, writes a unique
85x3 mapping at `0x8000`, and reports the 43/85 field flag. A group of three hot
heads becomes a hot triad; cold heads fill the remaining slots. The C++ bridge
`RawFieldVM::hot_triheads` validates the mapping and commits it to the chart.
The raw fixture covers three non-contiguous hot heads and 129 hot heads
(43 hot triads).

A raw two-token QKV/softmax/tanh feature feed, `mth_micro_feature.nas`, now
crosses the native boundary into `SparseField`: `RawFieldVM::micro_feature`
writes two 8-lane vectors, runs the guest, and converts the eight output lanes
to Q16.16 for the native sparse head/field bank.

The learned QKV/MLP causal block is now in `mth_trunk_causal.nas` and
`RawFieldVM::causal_trunk`. It accepts host-loaded Wq/Wk/Wv/Wout/W1/W2
matrices, supports 1..256-token causal context, and produces the eight-lane
feature that feeds `SparseField`. Tests cover T=1 exact learned-matrix math,
non-identity weights, T=8, T=48 and T=256. It is still a forward block; weight
training and credit updates are the next gate.

The wide path `mth_trunk_wide.nas` supports runtime D up to 128, hidden H up
to 512, and 1024 tokens. `RawFieldVM::causal_trunk_wide` writes host-loaded
matrices and returns D features; the test exercises D=16 with T=1 exact math
and T=1024.

The raw local credit commands (14, 15, 18, 20) are **diagnostic local
error-corrective updates**, not BPTT and not the production credit policy.
They use the last forward's activations and a readout error, with no saved
sequence tape. The production path is CFT/TRAIL/geometric credit:

- `mth_cft_credit.nas` — cycle-flux credit;
- `mth_trail_credit.nas` — two-rail TD eligibility;
- `mth_field_commit.nas` — credit → 2/3 triad → 43/85 field.

Exact local-credit parity is exercised at D=4/H=8/T=4, and the 1024-token path
exercises QKV and output/MLP local credit. CFT/TRAIL gating now exists through `mth_credit_gate.nas`, and
`mth_credit_field.nas` performs raw 2/3 triad and 43/85 field votes over 255
signed head credits. The next step is to stage candidate trunk deltas, vote
them, and commit only on acceptance with rollback. Adding a global BPTT tape is
explicitly not the plan.

This is the native **head/field** half of the sparse trunk. The shared P1
QKV/MLP trunk kernel and its feature feed are still the next native step; the
current Python reference supplies that feature vector and is not counted as the
native result. The d=512 adapter bank is a 2.35 MB heap-backed sidecar, not
part of the fixed root.

## Native status

The sparse shared trunk and adapter bank are native in the head/field half:
d=512/rank=4 is exercised in the sidecar. The shared
QKV/MLP trunk kernel, native top-k feature feed, adapter training and
AdamW/Gumbel path are still open. Hopfield is not on this path.

## Integration into NaNLMind

1. Keep the 8 MiB root as canonical field.
2. Put the shared trunk weights in the quantized sidecar (16-bit weights,
   8-bit moments), demand-paged.
3. Store 255 adapters and router/hotspot state in the sidecar; hot triads set
   the mapped hypermatrix rows.
4. Port the local CFT/triad/field vote path: 2/3 triad, 43/85 field.
5. Native NaN16 kernel for the trunk/adapters; host reference only as control.
6. Measure throughput, RSS/cache/energy and held-out loss on source-disjoint
   corpora before claiming a win.

The reference is now executable in NaNLMind:

```sh
python3 -m unittest tests.test_sparse_shared -v
python3 -m experiments.sparse_shared.train --mode sparse --active 8 --steps 2
make sparse-shared-test
```

## Limits

- The reference is a shallow synthetic next-byte model, not language quality.
- The trunk is shared, so heads are not fully independent models; they are
  persistent specialized interfaces and voters.
- Hotspot routing is not yet end-to-end differentiable; router gradients and
  local credit need separate validation.
- 1000 tok/s is not demonstrated.
