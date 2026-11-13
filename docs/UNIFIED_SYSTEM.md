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
  -> native direct-256 context readout / candidate gates
```

The optional external 48M adapter is not part of this native execution path.

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
They are now reachable and covered by focused tests. `context-train` exposes
both remaining routes:

- `backoffjoint` trains through the same guest k=4 exact / k=3 fallback route
  as `guestbackoff`, then evaluates with `mth_context_hier_joint` on that same
  routed bucket. The host only transports the returned bucket.
- `induction` feeds the guest-selected exact keys into `mth_context_copy` and
  trains the 2-byte suffix continuation table together with the shared memory
  table. `aux=N` sets the suffix bucket count and `weight=F` the soft gate.
  It is train/eval only: `load=`/`save=` are rejected because the suffix table
  has no checkpoint format yet.


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

## External 48M adapter (optional; not part of NaNLMind)

The R27/48M archive is **not** part of NaNLMind and is not a dependency of the
native frontier path below. The adapter remains available for compatibility
with an externally supplied archive; it is not the canonical model here. Its
entrypoint is:

```sh
python3 tools/unified_48m_runtime.py \
  --archive-root /path/to/R27/experiment_archive \
  --context 'the bright river' \
  --candidate-file words.txt
```

The path is:

```text
text context + finite candidate shortlist
  -> native NaN16 candidate measurement
       bridge: phase/triheads/Hodge/committed MC0 (nanlm48m-native-emit)
       batch:  opcode118 finite shortlist (nanlm48m-native-batch)
  -> frozen 48M P0(w|context)
  -> Z=1+sum P0*(exp(delta)-1)
  -> exact normalized finite-candidate distribution and top-k
```

Both modes are in one runtime contract:
`spec/unified_48m_runtime.v1.json`. The default `--native-mode bridge` runs the full
phase/trihead/Hodge/MC0 path once per candidate; `--native-mode batch`
selects the faster native opcode118 shortlist.

With a missing archive the adapter exits **2** before emitting scores; it never
substitutes an n-gram, the associative word layer, or another decoder. The
native byte/context metrics below do not use R27 and are the current NaNLMind
system results.

Top-k from this optional adapter is over the supplied finite candidate
shortlist and is normalized by the external 48M `P0`. Full-vocabulary top-5
over the archived trie is not claimed. Tensor promotion remains false.

For a matched finite-candidate language panel:

```sh
python3 tools/unified_48m_eval.py \
  --archive-root /path/to/R27/experiment_archive \
  --panel panel.json
```

The panel row format is `{"context": "...", "candidates": [...],
"target": "..."}`. The evaluator reports exact-word BPB for `P0` and the
candidate-normalized `P*`, plus finite-shortlist top-1/top-5. It refuses a
target outside the declared candidate set and never labels the result
full-vocabulary. Without the archive it exits 2 and writes no metric. This is
not part of the NaNLMind scorecard.


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


## Native head-state candidate training

Worker opcode **124** performs one guest-side softmax SGD step over the
transported candidate vectors. It computes the candidate dot scores, softmax,
cross-entropy loss, predicted index, and updates each candidate vector in
place. The host reads back the updated vectors and writes the receipt; it does
not compute gradients or loss.

`build/nanlm-head-readout-train` exposes one step:

```text
nanlm-head-readout-train <state.f32> <candidates.f32> <target> <lr>   <out-candidates.f32> <out.json>
```

This is an error-corrective readout step, not BPTT, page-weight training, or
promotion evidence. The ABI is frozen in `spec/head_state_train.v1.json`.


## Head-readout checkpoint loop

`tools/nanlm_head_readout_loop.cpp` runs repeated opcode124 training steps over
a state/target dataset, evaluates the unchanged candidate vectors on held-out
examples with `lr=0`, and applies a strict improvement gate:

```text
candidate_heldout_nll < baseline_heldout_nll
```

The updated candidate vectors and both NLLs are written for audit, alongside
initial/final SHA-256 values. The receipt explicitly sets
`tensor_promotion: false`; this gate accepts or rejects a **readout checkpoint**,
not a tensor bank, decoder, or page-weight update. The ABI is frozen in
`spec/head_readout_loop.v1.json`.


## Head-page checkpoint store

`include/nanlm/head_page_checkpoint.hpp` persists the 255 × 1 MiB page bank as
a directory of `head-NNN.page` files plus a canonical `manifest.txt` carrying
each generation and SHA-256. Writes use page-temp/rename followed by
manifest-temp/rename. Reads verify size, digest, and the canonical page-header
magic. `root_digest()` hashes the sorted present-head records.

The store permits partial checkpoints and does not claim power-loss ordering
on every filesystem. It is host storage/provenance only; no page arithmetic or
training runs here. The format is frozen in `spec/head_page_checkpoint.v1.json`.


## Page-checkpoint validation gate

`build/nanlm-head-page-gate` verifies a baseline and candidate page checkpoint,
loads selected pages through the 16-slot worker, and scores the resulting
last-token states with the native readout at `lr=0`:

```text
nanlm-head-page-gate <baseline-dir> <candidate-dir> <context.f32>   <heads> <candidates.f32> <target> <out.json>
```

Acceptance is a strict finite improvement:

```text
candidate_average_nll < baseline_average_nll
```

The receipt includes per-bank state SHA-256 and checkpoint root digests. It
sets `tensor_promotion:false` and `page_training:false`; the gate validates a
page checkpoint, it does not train or promote one. The ABI is frozen in
`spec/head_page_gate.v1.json`.


## Final-projection page training

Worker opcode **125** performs one local final-layer W2 update after the
six-token forward pass:

```text
e[j] = target[j] - state[j]
W2[j,k] += lr * e[j] * hidden[k]
```

The target is a transported 128D state; the hidden vector is the last-token
tanh MLP activation produced by the guest. Weights are read/written as bf16;
arithmetic is f32. This is deliberately a **local final-projection update**,
not full three-layer backpropagation.

`build/nanlm-head-page-train` loads one checkpoint page, runs one or more
epochs, exports the modified slot, and writes a candidate checkpoint with a
new generation and source/candidate SHA-256. The optional trailing mode
`w2` (default), `wo`, `w1`, or `wv` selects the final MLP W2 projection, the
final attention output Wo projection, the hidden W1 projection, or the final
value projection. W1 uses the final W2 gradient to form `g_h`, applies the
tanh derivative, and updates `W1[k,d] += lr*g_h[k]*(1-h[k]^2)*xn2[d]`. Wv
uses `g_ctx = Wo^T e` and the last-query softmax probabilities to update
`Wv[k,d] += lr*sum_j p[j]*g_ctx[k]*xn[j][d]`. The `qk` mode computes
`d_s[j] = p[j]*(g_v[j]-mean)` and updates final Wq/Wk through
`d_q=sum_j d_s[j]*K[j]/sqrt(128)` and
`d_k[j]=d_s[j]*Q[last]/sqrt(128)`. The `l1w2` mode updates layer-1 W2 using the final output error and the
retained layer-1 hidden vector. The `l1w1` mode uses layer-1 W2^T error and
the retained layer-1 pre-MLP LN vector. The `l1wo` mode updates layer-1 Wo
from the retained layer-1 attention context, `l1wv` uses layer-1 Wo^T error with retained layer-1 probabilities/XN to
update Wv, and `l1qk` uses retained layer-1 Q/K/V/probabilities to update
Wq/Wk through the softmax score derivative. These are explicit local
approximations, not full layer-2 backpropagation. All are local updates. The page gate can then compare
the source and candidate checkpoints. The ABI is frozen in
`spec/head_page_train.v1.json`.


## Page training-gate transaction

`tools/head_page_train_gate.py` composes the native final-W2 trainer with the
page-checkpoint NLL gate in one orchestration transaction:

```text
train candidate page
  -> write candidate checkpoint
  -> validate both checkpoints
  -> native held-out readout NLL gate
  -> publish accepted_dir only on improvement
```

Rejected candidates remain under `workdir/candidate` for audit; the accepted
directory is not created. The receipt embeds the training and gate reports and
sets `tensor_promotion:false`. The contract is frozen in
`spec/head_page_train_gate.v1.json`.


## Long-context trajectory

`include/nanlm/long_context_scheduler.hpp` implements the first long-context
layer: a persistent 128D memory per head plus up to five new token vectors per
worker call. `include/nanlm/long_context64_scheduler.hpp` raises the same
pattern to the native 64-slot worker: `[memory, token0..token62]`, with the
last-token state becoming the next memory. The stream length is unbounded, but
this is a **recurrent window**, not full-context attention.

The native block64 test exercises all 64 local slots, causal future-token isolation, and exact last-token parity with opcode136. Both the six-token and 64-token bf16 matvecs decode packed pairs, two MACs per word load. The 64-token matvec now processes two rows per pass, hoists matrix/vector/output cursors, and advances attention-context cursors; opcode136 starts the final layer directly at the last token. Measured on the same harness: opcode135 T=64 improved from 5.165s/435M steps to 2.323s/171M steps (2.22x, -60.6% steps), and opcode136 T=64 from 3.919s/331M steps to 1.766s/130M steps. Outputs remain byte-identical; `test_long_context64` fell from 5.73s to 2.74s and `test_chunk_summary` from 6.87s to 3.25s. The six-token kernel preserves caller r9/r12/r13 across matvec calls. Opcode136 skips the final layer’s unused earlier queries and MLP rows; the long-context scheduler uses it by default. The long-context64 test uses 63 new tokens per chunk and arbitrary stream length. `chunk_summary.hpp`
adds a chunk-summary scheduler and paged summary bank: a chunk is reset and
processed through the 64-slot worker, and the final per-head memory becomes its
summary. The default target is 256 tokens per summary and 512 summary slots, covering 131,072 tokens before eviction. `tests/test_summary_bank_128k.cpp` validates the complete tier shape: 512 records, 131,072 covered tokens, native retrieval over all 512 candidates in 64-candidate batches, and oldest-record eviction on the 513th chunk. This is storage/retrieval tier validation; a full 131,072-token forward replay is still too expensive to run in the standard test base.

The frontier trajectory needs hierarchical paged memory:

```text
64-token native local attention
  -> 256-token chunk summaries
  -> 256-slot global summary bank
  -> top-k summary retrieval
  -> target 8k / 32k / 128k effective context
```

A 128 MiB guest VM cannot hold full frontier-scale KV. The current recurrent
path is the correctness/storage stepping stone; the next native step is the
64-token local block and chunk summarizer. The contract is frozen in
`spec/long_context.v1.json`.


## Byte baselines

`build/byte-baselines` records BPB, top-1 and top-5 on the held-out 20% of
`data/alice_full.txt` for order-0, byte-bigram and context-2 models:

```text
state/benchmarks/byte_baselines.json
```

The top-5 metric is over the 256 byte classes, not words, and is explicitly a
reference baseline. The byte-bigram reports `3.50947` BPB and the context-2
baseline reports `3.28056` BPB on this corpus. These values are included in the
unified report and are not native head-worker word probabilities.


## Native summary retrieval

`include/nanlm/summary_retriever.hpp` groups summary-bank records by head and
scores the current 128D state against up to 64 summary vectors per native
readout call (opcode123). The guest performs every dot product; the host only
batches candidates and sorts the returned scores. The selected summaries can
then be fed into the 64-slot worker. The contract is frozen in
`spec/summary_retrieval.v1.json`.

The readout training loop now also reports held-out candidate-panel top-1 and
top-5 accuracy alongside NLL. It still does not claim full-vocabulary BPB.


## Hierarchical context assembler

`LongContext64Scheduler::run_hierarchical` packs:

```text
[ persistent memory | top-k summary states | local token vectors ]
```

into the native 64-slot worker, with:

```text
summary_k + local_tokens + 1 <= 64
```

Summaries are selected by native opcode123 dot scores; the host only orders
the returned scores. The last local-token output becomes the next memory.
Summary states never become the recurrent memory. The assembler is host
transport/orchestration over the unchanged native block64 kernel.


## Long-chunk checkpoint gate

`build/nanlm-head-chunk-gate` evaluates baseline and candidate page
checkpoints over an arbitrary token-vector chunk through the 64-slot causal
recurrent worker. Final per-head memory is scored by the native readout at
`lr=0`; acceptance requires a strict finite NLL improvement.

The default target is a 256-token chunk; the gate test exercises the full
256-token path and reports recurrent chunk counts. This is a candidate-panel readout gate, not
full-vocabulary BPB or tensor promotion. The contract is frozen in
`spec/head_chunk_gate.v1.json`.


## Word baselines

`build/word-baselines` records held-out word BPB and full-vocabulary top-1/top-5
for training-vocabulary unigram and interpolated bigram models. The BPB
denominator is the target word bytes plus one separator byte per held-out word.
Top-5 ranks the full training vocabulary plus `<unk>`, not a shortlist. Current
Alice-full held-out results are unigram BPB 1.87039 / top-1 8.216% / top-5
16.834%, and interpolated bigram BPB 1.61632 / top-1 14.247% / top-5 30.698%;
in-vocabulary bigram top-5 is 33.333%, with OOV rate 7.907%.

This is a word-level reference baseline, not the 48M frontier decoder and not
native head-worker logits. The contract is frozen in
`spec/word_baselines.v1.json`.


## Matched system benchmarks

Two benchmark surfaces now compare system output with the reference floors on
the same held-out rows. These are **diagnostic floors**, not replacements for
the unified 48M language entrypoint above. The contracts and measured values
are frozen in `spec/system_benchmarks.v1.json`.

### Byte system: native direct 256-bin context

`mth_context_direct256.nas` is the current byte readout. The guest selects
6000 exact 4-byte contexts with the existing count-threshold route, keeps a
256-bin count row for each exact context, and uses 10384 hashed last-two-byte
fallback rows for everything else. Exact rows blend the matching fallback row
with weight 0.05; fallback rows are used directly. Training increments one
count; evaluation applies fixed add-alpha smoothing `alpha=0.01`:

```text
score(c) = exact[c] + 0.05*fallback[c]   (exact contexts)
score(c) = fallback[c]                   (fallback contexts)
P(c | row) = (score[c] + 0.01) / (sum(score) + 0.01*256)
```

The guest returns top-1..top-5 and the target natural-log loss. The driver
route is context command **40 mode 8**; no host probability or ranking math is
used.

`build/direct256-bench` evaluates the same byte positions as matched order-0,
byte-bigram and context-2 references:

| model | BPB | top-1 | top-5 |
|---|---:|---:|---:|
| native direct-256 context | **2.39338** | **57.330%** | **84.652%** |
| order-0 matched | 4.71318 | 15.652% | 42.260% |
| byte bigram matched | 3.50949 | 32.058% | 69.592% |
| context-2 matched | 3.28052 | 42.915% | 79.358% |
| class-memory ablation | 2.60280 | 55.825% | 78.706% |

The direct-256 readout beats every external reference floor and the class-memory
ablation on all three metrics. The 6000-exact/10384-fallback blended
configuration was selected for frontier top-5 while keeping BPB and top-1
strong; the class-memory route remains for context-class/triad compatibility.
The result is still a byte-level context memory, not a word model and not the
R27/48M decoder.

Reproduce both full rows with:

```sh
make system-benchmarks
```

The byte row alone is:

```sh
./build/direct256-bench data/alice_full.txt \
  state/benchmarks/system_byte_direct256.json 6000 10384
```

Artifact:

```text
state/benchmarks/system_byte_direct256.json
```

### Word system: associative top-5

`build/word-system` ranks the full learned vocabulary of the existing integer
associative word layer by its own dot-product recall scores. It does not emit a
normalized distribution, so its BPB is explicitly unsupported.

On `data/alice_full.txt`, matched 80/20 held-out results are:

| model | top-1 | top-5 | in-vocab top-5 |
|---|---:|---:|---:|
| associative diagnostic layer (host) | 13.190% | 28.074% | 30.485% |
| unigram baseline | 8.216% | 16.834% | 18.279% |
| interpolated bigram | **14.247%** | **30.698%** | **33.333%** |

The diagnostic associative layer ranks its full learned 2291-word training vocabulary by its own
association scores (12107 associations). It beats the unigram baseline, but
still trails the interpolated bigram by 1.06 points top-1 and 2.62 points top-5.
The baseline vocabulary also contains `<unk>` while the system does not, so the
in-vocabulary row is the closer comparison; the system is still 2.85 points
behind there. This is an honest system-vs-baseline result, not a promotion
claim.

Full-Alice word baseline BPB remains: unigram 1.87039, interpolated bigram
1.61632. System BPB is `null`: association scores are not a normalized
distribution and no BPB is fabricated. The system is a host associative-memory
component, not the native 48M decoder.

Reproduce:

```sh
python3 tools/system_word_bench.py --corpus data/alice_full.txt
```

Contract and artifacts:

```text
spec/system_benchmarks.v1.json
state/benchmarks/system_word_bench.json
state/benchmarks/word_baselines.json
```


## Unified context runtime

`include/nanlm/unified_context_runtime.hpp` is the canonical composition point
for the long-context stack. It owns one shared VM/page arena and exposes only:

```text
load_checkpoint(...)
advance(credits, tokens, top_k, bank, summary_k, local_limit)
summarize(chunk_id, credits, tokens, top_k)
retrieve(bank, head, query, top_k)
memory(head)
```

The runtime composes head checkpoint paging, the 64-token causal worker,
persistent memory, chunk summaries, the 512-slot bank, native summary
retrieval, and hierarchical assembly. No alternate model path is introduced.
`main` is canonical; older branches are audit-only. The contract is frozen in
`spec/unified_architecture.v1.json`.


## Summary-bank checkpoint

`include/nanlm/summary_bank_checkpoint.hpp` persists the 512-slot summary bank
as `summary-NNN.bin` records plus a SHA-256 manifest. It validates record
shape, head range/uniqueness, finite states, file size, digest, and manifest
ordering; `root_digest()` covers sorted present records. `write_bank` supports
the full 512-slot bank, including slot 511. The format is frozen in
`spec/summary_bank_checkpoint.v1.json`.


## Unified context CLI

`build/nanlm-unified-context` exposes the canonical runtime as one command:

```text
nanlm-unified-context <checkpoint-dir> <heads.csv> <credits.f32>   <tokens.f32> <out.json> [--bank bank.tsv] [--top-k N] [--summary-k N]   [--local-limit N] [--retrieve-head H] [--retrieve-k N] [--query query.f32]
```

It loads head pages, runs the unified 64-slot causal context path, optionally
retrieves from a summary-bank TSV, and emits final states plus retrieval hits.
The host performs transport, input validation, and JSON only. The contract is
frozen in `spec/unified_context_cli.v1.json`.


## Layer-2 dX2 reverse

Worker opcode **137** computes exact layer-2 input gradients for T=1 and T=2.
The loss is `0.5*||Y_last-target||^2`, so `dY` is nonzero only for the last
token. The T=1 path reduces to:

```text
dY  = output - target
dH  = W2^T dY
dZ  = dH * (1 - H^2)
dXN2 = W1^T dZ
dX1 = dY + LNbwd(A2, dXN2, inv2)
dC  = Wo^T dX1
dXN1 = Wv^T dC
dX2 = dX1 + LNbwd(A1, dXN1, inv1)
```

The T=2 path reverses the attention form that `mth_head_block6` actually
implements: an **unmasked** per-query softmax over all T keys. There is no
causal mask in that forward, so dK/dV include every key column:

```text
dH[t]   = W2^T dY[t]
dZ[t]   = dH[t] * (1 - H[t]^2)
dXN2[t] = W1^T dZ[t]
dR1[t]  = dY[t] + LNbwd(A2[t], dXN2[t], inv2[t])
dctx[t] = Wo^T dR1[t]
dP[i][j] = dctx[i] . V[j]
ds[i][j] = p[i][j] * (dP[i][j] - sum_k p[i][k]*dP[i][k])
dQ[i]   = sum_j ds[i][j] * K[j] / sqrt(128)
dK[j]   = sum_i ds[i][j] * Q[i] / sqrt(128)
dV[j]   = sum_i p[i][j] * dctx[i]
dA1[t]  = Wq^T dQ[t] + Wk^T dK[t] + Wv^T dV[t]
dX2[t]  = dR1[t] + LNbwd(A1[t], dA1[t], inv1[t])
```

The forward pass retains A1/inv1, A2/inv2, hidden H, Q/K/V and normalized
attention probabilities for every token and layer. Opcode 137 does not mutate
the page. T>2 is rejected; layers 0/1 reverse remain outside opcode 137.
The test uses passthrough layers 0/1, an identity layer 2 and a nonzero second
token, then checks central finite differences on sampled coordinates
(measured max relative error: T=1 1.3e-3, T=2 5.0e-3 at eps=1e-2). The
contract is frozen in `spec/head_page_train_dx2.v1.json`.

## Full dX0 reverse

Worker opcode **138** computes the exact gradient of the same last-token loss
with respect to the original context input. It runs the same forward captures
as opcode 137, then applies the layer reverse above three times, feeding each
result into the next stage:

```text
dX2 = layer_rev(layer 2, dY)
dX1 = layer_rev(layer 1, dX2)
dX0 = layer_rev(layer 0, dX1)
```

Each `layer_rev` uses that layer's own page weights and its own captured
A1/inv1, A2/inv2, H, Q/K/V and normalized probabilities. The attention reverse
is the exact reverse of the unmasked per-query softmax in `mth_head_block6`.
Opcode 138 does not mutate the page. T=1 and T=2 only; T>2 is rejected. Weight
gradients through all layers and arbitrary-length BPTT remain blocked.

The test uses an all-identity page for all three layers (not passthrough
layers 0/1), plus a page whose layers are scaled differently so a stage cannot
silently reuse another layer's weights. Central finite differences on sampled
context coordinates give a max relative error of 2.3e-3 (T=1) and 7.3e-3
(T=2) for the all-identity page, and 1.6e-3 / 8.8e-3 for the scaled page, at
eps=1e-2. The contract is frozen in `spec/head_page_train_dx0.v1.json`.
