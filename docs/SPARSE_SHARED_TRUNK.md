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

## Hopfield memory inside the trunk (optional, default off)

The old `HopfieldRouter` is still used as a sparse associative **expert and
router** in v2. It is not the deep sequence model. The mapped hypermatrix is
the larger compositional associative store. Both can coexist with the shared
transformer trunk.

The default sparse-trunk path is **without Hopfield**. The probes below did not
show a reliable enough gain to justify the cost, so `memory_slots=0` is the
default; the memory layer remains an explicit optional experiment only.

Modern Hopfield retrieval is one step of softmax attention over stored
patterns:

```text
p       = softmax(beta * X q)
xi'     = X^T p
```

With `X` as both keys and values, this is exactly cross-attention to a
persistent pattern bank. It therefore does not conflict with the transformer;
it is a memory sublayer:

- tokens query the pattern bank and retrieve an associative state;
- a learned gate mixes that state into the residual stream;
- only the top-k patterns are read, so cost is `O(k*d)`, not `O(N*N)`;
- inactive patterns receive no gradient in the reference;
- the native path should write patterns with local CFT/LEAF credit, not a
  global BPTT tape.

`HopfieldMemory` is retained in `experiments/sparse_shared/model.py` for
ablation only. It is deliberately **not** a replacement for attention:
attention handles ordered local syntax, the Hopfield bank handles sparse
associative recall and long-range stored associations, the hypermatrix holds
compositional triples and leaves, and the wave/field keep temporal state and
consensus.

On the reference CPU harness, adding the 256-pattern Hopfield bank changed
d=64/4-layer throughput from 8.79 to 7.79 tokens/s (about 11% overhead) at
top-k=8. Quick probes were mixed: on a 256-key fixed association table a tiny
d=8 model improved from 74.2% to 82.8% (31% slower), but at d=16/128 keys both
models reached 100% and the memory was 47% slower. On the Alice excerpt probe
the memory gave a small held-out loss improvement, but it was not reliable
enough to make it a default. It is therefore excluded from the production
sparse-trunk path until a larger, source-disjoint ablation shows a clear win.

## Measured reference

PyTorch CPU, batch 1, sequence 8. The first table is without the optional
Hopfield memory bank:

| configuration | active heads | tokens/s | note |
|---|---:|---:|---|
| d=32, 2 layers, sparse | 8/255 | 38.0 | small model |
| d=32, 2 layers, random top-k | 8/255 | 29.7 | routing control |
| d=32, 2 layers, dense | 255/255 | 7.36 | 5.2x slower than sparse |
| d=64, 4 layers, sparse | 8/255 | 12.9 | reference default |
| d=64, 4 layers, dense | 255/255 | 1.93 | 6.7x slower than sparse |
| d=64, 4 layers, sparse + Hopfield 256/top-8 | 8/255 | 7.79 | about 11% overhead |
| d=64, 4 layers, sparse without Hopfield | 8/255 | 8.79 | matched control |

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

- `experiments/sparse_shared/model.py` — trunk, Hopfield memory, 255 adapters,
  router, hotspot.
- `experiments/sparse_shared/train.py` — dense/sparse/random benchmarks.
- `tests/test_sparse_shared.py` — budget, top-k, inactive-gradient isolation,
  hotspot promotion, Hopfield retrieval and fixed-batch loss decrease.

Run:

```sh
python3 -m unittest tests.test_sparse_shared -v
python3 -m experiments.sparse_shared.train --mode sparse --active 8 --steps 2
python3 -m experiments.sparse_shared.train --mode dense --steps 1
python3 -m experiments.sparse_shared.assoc_probe --memory-slots 64
python3 -m experiments.sparse_shared.lm_probe --memory-slots 128 --steps 80
```

## V2 state mapping

The reference is deliberately shaped to map onto the existing v2 fields:

| reference state | v2 target |
|---|---|
| trunk weights + 8-bit moments | quantized sidecar (d=512, 12 layers; 72 MiB + 72 MiB) |
| 255 adapters | extension records: 2·d·rank Q16.16 values + router score + credit |
| router logits | per-head routing scores in scratch; top-k in the field |
| hotspot | per-head/triad credit derived from adapter gradient norms |
| Hopfield pattern bank | sparse persistent memory rows; top-k retrieval; local CFT/LEAF writes |
| Hopfield gate | per-token residual gate in chart scratch, voted before commit |
| triad gate | existing 85 triads, 2/3 vote |
| field gate | existing 43/85 field vote |
| hypermatrix | 32,640 pair rows × 256 candidate bits |
| leaf state | exact address/word/bit leaves and leaf masks |
| CFT credit | triangle flux base in the native CFT bank |

A rejected sparse proposal must restore the adapter/trunk scratch and leave
`s+`/`s-`, digest and generation unchanged. The native port must run through
the one canonical nan0s VM; the Python reference is a control, not the result.

## Native step 1: sparse head/field bank

The first native piece is now in the chart, without Hopfield:

- `include/nanlm/sparse_field.hpp` / `src/sparse_field.cpp`;
- 255 low-rank adapters, d=8, rank=2, Q1.15 weights;
- top-8 routing, integer normalised weights, 255-bit active mask;
- per-head hotspot and usage state;
- local non-BPTT credit update for a selected adapter;
- state stored in `Universe::sparse_field()` and serialized/digested with the
  chart (older snapshots restore with a zeroed bank);
- `tests/test_sparse_field.cpp` checks top-k uniqueness, inactive-adapter
  isolation, triad hotspot promotion, persistence and old-snapshot restore.

This is the native **head/field** half of the sparse trunk. The shared P1
QKV/MLP trunk kernel and its feature feed are still the next native step; the
current Python reference supplies that feature vector and is not counted as the
native result.

## Integration into NaNLMind

1. Keep the 8 MiB root as canonical field.
2. Put the shared trunk weights in the quantized sidecar (16-bit weights,
   8-bit moments), demand-paged.
3. Store 255 adapters and router/hotspot state in the extension; hot triads
   set the mapped hypermatrix rows.
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
