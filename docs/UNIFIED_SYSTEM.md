# Unified system link layer

Status: **provider-scoped unification with one checker**. NaNLMind and
NaNROUTER are linked into one auditable surface without pretending that their
kernel namespaces are semantically identical.

## Entry points

```sh
make unified-system-check
```

This builds the focused C++ gates, runs the cross-repo kernel audit, executes
both fixture suites, and validates the link map. The direct forms are:

```sh
python3 tools/unified_kernel_audit.py --run
python3 tools/unified_system_check.py --run
```

Artifacts:

| path | role |
|---|---|
| `spec/unified_system.v1.json` | canonical link map: providers, counts, links, legacy removals, commands |
| `tools/unified_kernel_audit.py` | discovers both kernel/fixture surfaces and runs both suites |
| `tools/unified_system_check.py` | validates links, counts, evidence, retired surfaces and core tests |
| `spec/nannet_ingest_result.v1.json` | NANNET corpus ingest evidence |
| `spec/relation_triangle_matched_baseline.v1.json` | matched relation-triangle baselines |
| `spec/nanrouter_integration.v1.json` | NaNLMind ↔ NaNROUTER stage map |
| `spec/nannet_corpus_routes.v1.json` | NaNROUTER corpus route manifest |

## Current surface

| provider | kernel/source surface | fixtures | coverage |
|---|---:|---:|---|
| NaNLMind | 74 `mth/nan16` sources | 33 | 43 direct fixture reach, 73 driver-included, 0 unreached |
| NaNROUTER | 160 catalog kernels | 156 | 0 kernels without a runner fixture |

The checker validates 11 linked artifacts, the committed NANNET ingest result,
the matched-baseline schema and row counts, and the core C++ gates
(`test_raw_field`, `test_dual_head`).

## Kernel identity policy

Kernel IDs are provider-scoped:

```text
nanlmind.mth.nan16.<source-stem>
nanrouter.<catalog-kernel-id>
```

This is deliberate. The two trees currently share **zero source basenames and
zero fixture basenames**; assigning cross-provider equivalence would invent a
semantic map that has not been approved. The link layer makes the surfaces
visible in one place and gives the next refactor a stable place to add a
canonical map.

## Retired Hopfield surface

The legacy Hopfield byte-router benchmark, byte-expert router test, Hopfield
learning test, three legacy docs and their Makefile targets are removed. The
bounded `HopfieldRouter` class remains only because `BootstrapMesh` and
`HeadStore` still use it as an internal key store; it is not part of the
unified production surface. Retiring that internal primitive requires a
bootstrap key-store replacement and is a separate refactor.

## Non-claims

- This is a link/check layer, not a claim that the two kernel trees are
  semantically identical.
- The audit runs real fixtures; it does not fabricate kernel results.
- The NANNET ingest result is evidence for the ingest wiring, not a
  language-quality or held-out-accuracy claim.
- The matched baseline remains a negative result: the raw global model does not
  beat the source-prior or shape-only controls on the current sample.

## Canonical execution path

The link map is not the execution contract. The canonical runtime path is:

```text
bytes
  -> tokenizer (word/subword + 3 preceding / 3 anticipatory spans)
  -> 256-component phase vectors
  -> temporal S+ / current-255 / S- slots
  -> heads 0..254 -> 85 triads (2/3) -> 43/85 field
  -> hyperbolic path + shape triangle (tightness/area/stretch)
  -> hyperedges / pair-flow -> Hodge consistency
  -> sparse tensor candidate/active bank
  -> local attention -> trihead attention -> meta-global attention
  -> credit bundle (CFT/TRAIL/HOLO/RING/LEAF/TCA/FLUX)
  -> field/vote commit
```

Point `255` is the current-context register. It is **not** an active math
head, triad member, incidence endpoint, or simplicial face vertex.

### Attention levels

`stream-train` now reports three attention levels:

1. `local_attention_*` — raw masked attention over the local context window.
2. `meta_field_hot_*` / trihead field — 85 triads and 43/85 field voting.
3. `meta_attention_*` — MC0-compatible attention over committed line summaries.

### Context model

The measured 70%+ context route is canonical:

```text
mth_context_hier.nas   16x16 high-nibble / conditional-low-nibble memory
mth_context_backoff.nas guest-owned exact 4-byte / FNV 3-byte fallback
mth_context_class.nas   class -> head/triad/43-85 bridge (command 30)
```

`context-train` now defaults to the 4-byte guest-backoff route when no route is
given. The measured WordNet run is 73.7821% same-corpus byte accuracy at 3
epochs. Evidence: `spec/context_model.v1.json`.

The context-class command was moved from colliding command `30` to `31`.
Without that fix the context-to-triad bridge was unreachable.

### Triangle stretch

The raw triangle kernel now returns `stretch_q15 = (max_side-min_side) /
(max_side+1)`. `stream-train` reports `triangle_stretch_sum` and
`triangle_stretched`; strongly stretched triangles are excluded from the
hyperbolic field/Hodge vote. A high stretch value means the three points are
not a compact triangle.

### Credit bundle

`stream-train` executes the raw seven-credit bundle and reports
`credit_bundle_ok` and `credit_bundle`:

```text
[CFT, TRAIL, HOLO, RING, LEAF, TCA, FLUX]
```

This is the local-credit replacement path for BPTT. The values are currently
measured, not yet used to mutate a trainable tensor.

### Six-neighbor trigonometric attention

`mth_six_context_poincare_attention.nas` consumes six neighbor word IDs plus
the observed anchor at NOW=255:

```text
[-3, -2, -1, +1, +2, +3] + NOW(255)
```

It uses the existing native CORDIC and `mth_meta_attention16_f32` kernels,
rejects future slots in causal mode, validates generations, and projects the
native attention result into a 2D Poincare disk. `stream-train` reports:

```text
six_context_ok
six_context_observations
six_context_radius
six_context_distance
six_context_now_head=255
```

### Branch policy

No long-lived architecture branches. Merged branches are deletion candidates;
unmerged branches must be tagged, audited, and only their stage code
cherry-picked. `docs/BRANCH_TRIAGE.md` is the decision list.

## Guest driver budget and restored context routes

The raw field driver is capped at **0x100000 words** (1,048,576 emitted words) by the code/data boundary; the phase table moved to `[0x395000,0x395200)`, and the VM default is now 16M words (128 MiB). 255 resident 1 MiB pages require a paged external arena; attempting a flat 512 MiB/1 GiB VM has repeatedly OOM-restarted this device.
Adding code past that boundary silently corrupts dispatch/state; the Makefile
now rejects an over-budget image. To make room for the canonical routes, the
unused `mth_context_hash` and `mth_context_batch` includes were removed from
the driver; their source files remain available for standalone experiments.

Restored raw commands:

| command | kernel | purpose |
|---:|---|---|
| 30 | `mth_context_class` | 16x16 class -> head/triad/43-85 field bridge |
| 43 | `mth_context_hier_joint` | joint high/low head-pair readout |
| 44 | `mth_context_copy` | copy/induction context route |
| 45 | `mth_triad_score` | 2-of-3 triad objective with majority bonus |
| 107 | `mth_context6_window_stream` selected window | six-slot target-safe trig attention |
| 108 | `mth_hyperedge_poincare128_curl` | 128D Poincare hyperedge depth + signed curl |
| 109 | `mth_context6_window_stream` fused | source stream -> six-slot attention -> Poincare NOW |
| 118 | `mth_shortlist_batch_proposal` | one native call for an entire candidate shortlist |
| 120 | `mth_mirror_rail_gradient` | native oriented gradient from both physical mirror rails |
| 122 | `mth_head_block` | 128D three-layer bf16 QKV/MLP block from a paged head slot |

These are the kernel-level paths removed by the earlier ABI-conflict merge.
They are now reachable and covered by focused tests. CLI exposure for the
`backoffjoint` and `induction` routes is the next integration step; the raw
commands and bridges are already present.


## Unified test base

`make unified-test-base` runs one report covering native fixtures, context
backoff/route, six-context Poincare, hyperedge128, 48M native feedback,
128MiB dual tensor, seven-credit ablation, native batch shortlist and build
verification:

```text
state/benchmarks/unified_test_base.json
```

Metric scopes are explicit:

- `train_accuracy_percent`: online training window for one epoch;
- `eval_accuracy_percent`: post-epoch evaluation on the selected split;
- `same_corpus`: diagnostic only, never generalization;
- `heldout`: held-out rows in the selected line window;
- `canonical_full_corpus_reference`: 73.7821 same-corpus / 66.8894 held-out.

Deterministic regression metrics are expected to repeat. A changed value means
that path changed or regressed. Closed-loop learning metrics come from
`baseline_nll`, `candidate_nll`, `nll_delta` and per-horizon probabilities in
`tools/decoder48m_future3.py`.

## Closed generation loop

The intended single path is now expressed as one feedback loop:

```text
generated prefix
  -> native stream6 (opcode 109)
  -> trig attention + Poincare NOW(255)
  -> hothead -> hottrihead -> field
  -> Hodge divergence/curl
  -> MC0 committed meta
  -> 128D hyperedge Poincare/curl (opcode 108)
  -> native shortlist batch (opcode 118)
  -> frozen 48M exact normalization
  -> choose next word
  -> append and remeasure
```

`tools/decoder48m_future3.py --native-batch build/nanlm48m-native-batch`
implements the sequencing adapter. It never passes gold future words and
remeasures the native guest at every generated prefix. The frozen decoder
remains the whole-word probability model; candidate tensor promotion remains
blocked until a disjoint precommitted NLL gate passes.


## Head page loader

`include/nanlm/head_page_arena.hpp` owns 255 × 1 MiB pages as a demand-paged
anonymous mapping. `include/nanlm/head_page_loader.hpp` loads a page into one
of **16 guest slots** at `0x00800000 + slot*0x00040000`.

Sixteen is the chosen optimum: it is a power of two, matches the 16-slot meta
batch, fits the remaining 128 MiB guest window, and avoids a flat 255 MiB/1 GiB
VM that OOMs this device. Each 1 MiB page expands to 2 MiB of guest storage
because a NaN word is 8 bytes. LRU eviction replaces the least recently used
slot.

The main field driver keeps a single-token compatibility route through
`mth/nan16/mth_head_block.nas`. The six-token path is the dedicated
`mth/drivers/head_worker.nas` image: it starts at word 0, has its own
`0x4000` command block, and includes `mth/nan16/mth_head_block6.nas`. The
worker performs three 128D bf16 layers with Q/K/V, sqrt(128)-scaled
six-token softmax attention, LayerNorm, tanh MLP, residual updates and page
header validation. It is 598 emitted words and does not compete with the main
driver's low code window.

The base command surface is `mth/drivers/field_driver_base.nas`; fixtures that
append test code include it directly. The full `field_driver.nas` adds the
single-token compatibility block through a low `CALLF 0x3E60` trampoline. The
1 MiB page layout is frozen in `spec/head_page_memory.v1.json`; the worker ABI is frozen in
`spec/head_worker.v1.json`.

`NANLM_STEP_BUDGET` sets the 64-bit native command budget; default
`4,000,000,000`.


## NLHE2 typed hyperedge store

`include/nanlm/nlhe2.hpp` defines the canonical NLHE2 structural hyperedge
record and codec. It is stored as `TensorLeafKind::HyperedgeRecordV2` (12) at
`include/nanlm/tensor_point.hpp` point coordinates. Every point is
`(h,a,b)` with each axis in `0..254`; the encoded reference is

```text
0x4E000000 | (h << 16) | (tp_reverse8(a) << 8) | b
```

The record carries a logical edge id, label, Q16 weight, epoch, home point,
and 2–255 ordered members with role and leaf-kind declarations. It does not
carry floats, votes, gradients, or active state. Provenance is the enclosing
typed leaf's `source_generation` and authenticated 64-hex `source_sha256`.

`include/nanlm/nlhe2_arena.hpp` attaches the canonical bytes at the declared
home coordinate through the existing candidate-leaf gate. Exact replay is a
no-op, same-generation conflicts are rejected, and per-point quota is enforced
by the arena. `newest_nlhe2` resolves the highest live revision; an
equal-generation payload conflict returns no value.


## Paged head-worker scheduler

`include/nanlm/head_worker_scheduler.hpp` selects up to 16 active heads from
external credits, asks the 16-slot LRU page loader for each resident page, and
invokes the six-token worker once per head. It keeps the last-token 128D state
for all 255 heads as a host transport bank; no head arithmetic runs on the
host.

`stage_head_worker_batch` transports accepted guest states into the canonical
candidate tensor at `T[h,h,h]`: a `HeadVector128` leaf carrying the last-token
vector, one guest output lane as the candidate scalar, the candidate generation,
and the authenticated source SHA-256. `stage_head_worker_tokens` additionally
writes one `HeadVector128` leaf for every worker token (up to six per head),
giving the explicit per-token candidate path without touching ACTIVE. Any late staging failure aborts the
candidate, leaving ACTIVE untouched. The scheduler ABI is frozen in
`spec/head_worker_scheduler.v1.json`.


## Head-worker batch CLI

`tools/nanlm_head_worker_batch.cpp` is the first external adapter for the
paged head worker:

```text
nanlm-head-worker-batch <pages-dir> <context.f32> <heads> <out.json>
```

It loads each selected `head-NNN.page` (1 MiB), verifies the SHA-256, selects
the requested active heads, runs the native six-token worker, and serializes
the last-token 128D states with slot and page provenance. An optional
`candidates.f32` file supplies 1..64 transported 128D vectors; opcode **123**
then computes guest-side dot scores for each selected head. These are linear
readout values, not trained logits. The adapter performs no host attention or
model scoring. The readout ABI is frozen in `spec/head_state_readout.v1.json`. `spec/head_worker_cli.v1.json` freezes the ABI.
