# Symbiotic field architecture — memory, thinking circuits and geometric credit

Status: **architecture plan and point-by-point TODO**. NaNLMind v2 is the
target; NaNLM v1 is a reference only. The canonical VM is NaN0S; N16I is its
raw-NaN guest interpreter, not a second VM.

## 1. The memory constraint is real

The exact 8 MiB root is fully allocated:

| mapping | bytes |
|---|---:|
| 256 head registers × 128 B | 32,768 |
| 32,640 mirror cells × 256 B | 8,355,840 |
| total | 8,388,608 |

We will **not** pretend that 85 fully parameterized transformers (let alone
255) fit inside that root. The root remains the identity and working field.
Anything larger is a sparse, mapped extension/child page with an explicit
budget, never a second universe.

NaNLMind v2's chart has a register-file layout plus a mapped hypermatrix and
free extension. The design below uses:

- the 8 MiB chart for the 256 heads, 32,640 mirror cells, hypermatrix,
  triad/field state, address records and small leaf counters;
- **85 shared triad transformer banks**, not 255 private full models;
- per-head low-rank adapters (the 255 head interfaces);
- optional sparse sidecar/child pages for inactive banks, long context and
  larger d_model; only the active top-k window is resident.

The system is one topology and one ledger even when weights are paged.

### 1.1 The 1 MiB-per-head independence option

Yes: **256 independent 1 MiB parameter banks are possible** if the weights live
in a mapped sidecar, not in the 8 MiB root. That is 256 MiB of weights, plus the
8 MiB root and a few MiB of activations/scratch. It is a deliberate memory tier,
not a claim that the root contains them.

A one-layer, per-head bank that fits 1 MiB at 4 bytes per parameter:

| component | parameters |
|---|---:|
| QKV projections, d=128 | 49,152 |
| output projection, d=128 | 16,384 |
| MLP 128 -> 480 -> 128 | 122,880 |
| token embedding, vocab=256 | 32,768 |
| output head, vocab=256 | 32,768 |
| biases + two layer norms | ~1,600 |
| **total** | **~255,552 parameters = 1,022,208 bytes** |

That leaves about 26 KiB for per-head metadata. At 16-bit weights the same
1 MiB holds twice the parameter budget; at 8-bit, four times.

This makes each head **parameter-independent**: separate QKV, MLP, embedding,
readout, optimizer/credit and persistence. It does not make it independent of
the shared vocabulary/context protocol or of the field vote. If those are also
private, the heads become independent modules inside one topology; if the field
backpropagates through all heads, they are coupled again.

Memory cost and training mode:

| mode | weights | optimizer | practical note |
|---|---:|---:|---|
| 256 x 1 MiB, SGD/local credit | 256 MiB | ~0 | fits with root and activations under 1 GiB |
| 256 x 1 MiB, Adam | 256 MiB | ~512 MiB | near the 1 GiB ceiling; train per-head or use 8-bit/offload |
| 85 x 1 MiB triad banks | 85 MiB | ~0-170 MiB | not fully independent; 3 heads share a bank |
| sparse top-k active set | paged | paged | only active banks resident; throughput/memory measured |

The independent mode does **not** require 256 full models to be resident at
once. The sidecar is demand-paged; routing activates a top-k set. The 8 MiB
root remains the canonical identity, heads and hypermatrix.

Recommendation: support both budgets explicitly. Use 85 triad banks for the
cheap symbiotic mode; use 256 independent 1 MiB per-head banks for the
independent-head research mode. Never blur which one produced a result.

## 2. Four mechanisms, four jobs

| mechanism | job |
|---|---|
| **micro-transformer triads** | fast thinking circuits: QKV, MLP, sparse top-k routing, selective full triad attention |
| **standing-wave fabric** | temporal substrate: cheap 255-head forward/inverse wave, eligibility and phase |
| **hypermatrix + leaves** | compositional associative memory: pair rows, candidate bits, exact address/sub-definition leaves |
| **global field** | shared working state: 85 triads, 43/85 field vote, gain and commit control |

The 255 heads are **persistent specialized interfaces** between these
mechanisms, not 255 minds and not 255 output neurons.

## 3. Memory and layout targets

| region | bytes | role |
|---|---:|---|
| 8 MiB root | 8,388,608 | canonical identity, 256 heads, 32,640 pairs |
| hypermatrix | 1,044,480 | 32,640 rows × 256 candidate bits |
| triad vote/field state | ~2 KiB | 85 masks, credits, field counter |
| leaf counters | 65,536 | 256 heads × 256 leaf bits (8-bit signed) |
| rail frames | ~32,640 | T=8 × 85 × 48 B staged frames |
| 85 triad banks | 217,600 | 2,560 B each, shared QKV/MLP/gains |
| head adapters | 65,280 | 255 × 256 B low-rank head interface |
| **subtotal in extension** | ~1.37 MB | fits the available chart extension |
| optional sidecar | operator budget | inactive banks, long context, larger d_model |

A 255-private-bank design is rejected: it leaves no room for leaves, frames,
context or sidecar coordination, and it contradicts the single-field model.
Triad banks are shared by their three heads; heads differentiate through
low-rank adapters, routing and credit.

## 4. Sparse top-k routing and multiscale context

Routing is hierarchical and sparse:

1. **Head-local gate**: each of 255 heads scores a small context window and
   proposes its triad.
2. **Triad top-k**: each triad selects `k_t` of its members/adapters; only
   those run the full QKV/MLP block.
3. **Field top-k**: the field activates at most `k_f` triads per token; the
   rest keep the cheap wave update.
4. **Selective triad attention**: full triad attention runs only when the
   routing margin and wave coherence exceed thresholds; otherwise the cheap
   255-head wave state is the temporal substrate.

Context is multiscale:

| scale | state | use |
|---|---|---|
| 8/16 bytes | head scratch ring | immediate token/wave state |
| 48 bytes | current window | baseline comparison |
| 256 bytes | per-triad ring | short motif/relation context |
| 4 KiB | chart scratch | paragraph/segment context |
| 64 KiB | extension/child page | document/working-set context |
| 65,536 addresses | hypermatrix rows/hashed postings | long-range associative recall |

Long context is read through sparse top-k postings, not a dense 65,536×65,536
attention matrix. Every context expansion is measured for throughput, resident
memory and held-out loss.

## 5. Learning: CFT base plus geometric credit hybrid

No single local rule is assumed to equal BPTT. The native system uses a
**base CFT (cycle-flux) credit** and hybrid geometric credits; a host
differentiable reference provides gradient checks and a joint-training upper
bound.

### 5.1 Base CFT

For triangle `(a,b,c)` with edge energies `E`:

```text
F = E(0,a,c) + E(a,b,c) - E(0,b,c)
p = sum_d x_d F_d
e = target - p
Δ_d = η g e x_d
E(0,a,c) += Δ/3; E(a,b,c) += Δ/3; E(0,b,c) -= Δ/3
```

The three updates change the circulation by exactly `Δ`; mirror antisymmetry
is preserved. CFT is the base because it is already native and gauge-aware.

### 5.2 Hybrid credit layers

| layer | rule | role |
|---|---|---|
| TRAIL | two-rail TD eligibility in `s+`/`s-` | temporal credit without a tape |
| CFT | triangle circulation residual | base geometric credit |
| HOLO | cycle holonomy/gauge defect | order-sensitive phase credit |
| RING | forward/inverse angular correlation over 255 lanes | rotation/triad mapping |
| LEAF | hypermatrix row + exact leaf mask/counter | address/sub-definition credit |
| TCA | leave-one-out triad advantage | specializes/penalizes heads |
| FLUX | temporal-link divergence | working-state flow/relaxation |

A bounded combination is:

```text
credit = α CFT + β TRAIL + γ HOLO + δ RING + ε LEAF + ζ TCA + η FLUX
```

Coefficients are validated on development data and frozen before test. No
weight is chosen by training loss alone.

### 5.3 Joint training with a differentiable reference

The native path is integer NaN16. For joint training, a host reference mirrors
the *same* shared projections, soft top-k routing, triad attention, field gate
and wave recurrence. It uses straight-through/Gumbel routing for the discrete
choices and backpropagates through the shared differentiable parts. The native
path receives the resulting candidates and commits only through the triad
(2/3) and field (43/85) votes.

This gives three separate claims:

1. **native forward** — exact NaN16 state and persistence;
2. **host joint training** — gradient-checked differentiable reference, not the
   native runtime;
3. **native local credit** — CFT/TRAIL/hybrid updates that commit only after
   votes and rollback checks.

No claim is made that a local rule is equivalent to BPTT. The matched reference
is used to falsify or validate it.

### 5.4 Field commit

A proposal is staged in scratch, voted by its triad (2/3), aggregated by the
field (43/85), checked for stale generation, NaN/overflow and budget, then
committed with a ledger event and rollback record. Rejection leaves `s+`/`s-`,
checksums and generation unchanged.

## 6. 255 heads as persistent interfaces

Each head stores:

- address identity, phase/energy, self-error, load and credits;
- a 256-bit leaf mask and 256 signed leaf counters;
- a low-rank adapter (the head's interface to its triad bank);
- routing score, triad slot, vote and write budget;
- provenance of the last accepted/rejected proposal.

Heads do not own private full models. They specialize the shared triad
circuits and the field state.

## 7. Point-by-point TODO

### S0 — constraints, VM and dependency

- [ ] S0.1 Freeze the 8 MiB root map and the extension/sidecar budget in one
  document; reject any plan that silently exceeds it.
- [ ] S0.2 Keep one canonical NaN0S VM; N16I is a guest interpreter. Sync
  `nanlmind_hermes/nan0s` byte-for-byte to canonical `shemshallah/NaN0S`.
- [ ] S0.3 Add `QMUL/QADD` only if profiling proves the two-op Q16 multiply is
  the bottleneck; no VM fork.
- [ ] S0.4 Add a versioned layout/schema bump for new extension fields.

### S1 — memory layout

- [ ] S1.1 Place 85 triad banks (2,560 B) and per-head adapters (256 B) in the
  extension; keep the 8 MiB root identity intact.
- [ ] S1.2 Add 64 KiB leaf counters, 32-byte head leaf masks and 48-byte rail
  frames with exact offsets.
- [ ] S1.3 Add optional sidecar paging for inactive banks/long context; one
  digest for the active set and a manifest for paged pages.
- [ ] S1.4 Add a budget auditor that fails before overwriting a child page or
  extension boundary.
- [ ] S1.5 Add the independent mode: 256 x 1 MiB per-head sidecar banks, demand-paged.
- [ ] S1.6 Add per-head optimizer/credit state and a digest/manifest for paged banks.
- [ ] S1.7 Keep 85 x 1 MiB triad mode as the cheap symbiotic control; label results by mode.

### S2 — micro-transformer P1

- [ ] S2.1 d=8 block: QKV, 2 heads of d=4, residual, layer norm.
- [ ] S2.2 MLP 8→16→8 with `FTANH`; raw NaN16 kernel plus C++ state adapter.
- [x] S2.3 Shared projections for 85 triad banks; 255 low-rank head adapters in the NaNLMind reference.
- [x] S2.4 Sparse top-k head→triad→field routing with margins and budgets in the reference; native port open.
- [ ] S2.5 Selective full triad attention only above routing/coherence gates.
- [ ] S2.6 Context scales 48/256/4KiB/64KiB and 65,536-address postings;
  measure throughput, resident memory and held-out loss for each.
- [ ] S2.7 Native/N16I parity on fixed vectors and generated tokens.
- [ ] S2.8 Fit and test the d=128, MLP=480, vocab=256 one-layer 1 MiB per-head bank.
- [ ] S2.9 Per-head embeddings/readout in independent mode; shared vocab only by explicit contract.
- [ ] S2.10 Compare 85 triad banks vs 256 independent banks at equal active compute.

### S3 — temporal substrate

- [ ] S3.1 Keep the cheap 255-head forward/inverse wave update on every token.
- [ ] S3.2 Add TRAIL eligibility in `s+`/`s-` without a full tape.
- [ ] S3.3 Add HOLO phase/holonomy credit using the existing CORDIC.
- [ ] S3.4 Add RING angular correlation and triad/field rotation votes.
- [ ] S3.5 Add FLUX temporal-link divergence and bounded relaxation.
- [ ] S3.6 Persist eligibility/frames; verify byte-identical replay.

### S4 — hypermatrix and leaves

- [ ] S4.1 Keep 32,640 pair rows × 256 candidate bits; no dense 255³ tensor.
- [ ] S4.2 Implement exact leaf IDs `(cell, word, bit/byte)` and 256-bit head
  leaf masks.
- [ ] S4.3 Implement `LEAF` counter updates from local error.
- [ ] S4.4 Link `R_ab[c]` and `L_c[l]`; add leaf-level ablation.
- [ ] S4.5 Add `Descriptor.aux` support/credit/generation fields and a
  versioned checksum.
- [ ] S4.6 Add `TCA` leave-one-out advantage and triad/field promotion.
- [ ] S4.7 Add CFT cycle banks; use them as the base control.

### S5 — joint training and commit

- [ ] S5.1 Host differentiable reference for shared projections, soft top-k,
  triad attention, field gate and wave recurrence.
- [ ] S5.2 Gradient checks against finite differences on a reversible block.
- [ ] S5.3 Straight-through routing and field gate; no fabricated exact
  gradient for discrete votes.
- [ ] S5.4 Native CFT/TRAIL/HOLO/RING/LEAF/TCA/FLUX credit updates (reference CFT/vote path exists).
- [ ] S5.5 Triad 2/3 and field 43/85 commit with rollback and ledger.
- [ ] S5.6 Reject updates that only improve training loss.
- [ ] S5.7 Independent local training vs joint field backprop; measure gradient coupling.
- [ ] S5.8 Native AdamW Q16.16 kernel with 8-bit/16-bit moment quantization.
- [ ] S5.9 Block-scale quantization, deterministic error feedback and float32 Adam control.

### S6 — evaluation

- [ ] S6.1 Multi-author, source-disjoint held-out corpora; train/dev/test
  frozen before test.
- [ ] S6.2 Actual free generation, not stored answers; repetition/novelty/
  validity metrics.
- [ ] S6.3 Feature ablations: no hypermatrix, no leaf, no triad attention, no
  wave, no field; matched dense controls.
- [ ] S6.4 Throughput, RSS/cache/energy and context scaling on Android ARM.
- [ ] S6.5 Persistence, crash/replay and generation-CAS tests.
- [ ] S6.6 Report ties/failures prominently; no open-domain fluency claim.
- [ ] S6.7 Measure 256 MiB paged resident set, cache pressure and active-bank throughput.
- [ ] S6.8 Compare 16-bit weights + 8-bit Adam (512 MiB) against 8-bit + 8-bit (768 MiB) and Lion.

## 8. Acceptance gates

1. **Layout gate**: exact byte accounting; no silent overflow.
2. **P1 gate**: QKV/MLP parity native ↔ N16I; loss decreases on a tiny task.
3. **Routing gate**: top-k sparsity improves throughput at equal or better
   held-out loss; dense and random-routing controls.
4. **Credit gate**: CFT/TRAIL/hybrid sign parity with finite differences on a
   reversible block; ablations beat matched controls.
5. **Field gate**: 2/3 and 43/85 thresholds exact; rejected proposals leave
   digest unchanged; accepted updates replay byte-for-byte.
6. **Evaluation gate**: source-disjoint held-out and free-generation results,
   with all controls and failures reported.

## 8.5 Native Adam and 8-bit weights

Yes, Adam can run natively on the NaNVM1 op set. The current ISA already has
`FMUL/FADD/FDIV/FSQRT`, `CVTIF/CVTFI`, byte access and Q16.16 integer ops.
No new opcode is required.

The memory cost is the issue, not the arithmetic:

| representation | weights/head | Adam m+v/head | total/head | 256 heads |
|---|---:|---:|---:|---:|
| 8-bit w + 8-bit m/v, block scales | 1 MiB | 2 MiB | 3 MiB | 768 MiB |
| 16-bit w + 8-bit m/v, block scales | 1 MiB | 1 MiB | 2 MiB | 512 MiB |
| 16-bit w + 16-bit m/v | 1 MiB | 2 MiB | 3 MiB | 768 MiB |
| 8-bit w + 16-bit m/v | 1 MiB | 4 MiB | 5 MiB | 1.25 GiB |
| Lion/one-state, 8-bit | 1 MiB | 1 MiB | 2 MiB | 512 MiB |

The 768 MiB cases fit the 1 GiB resident ceiling only with paged/top-k active
banks and a lean activation budget. The 1.25 GiB case does not fit all-resident.
The 512 MiB cases are the practical all-resident independent targets.

Native Adam step:

```text
m  = b1*m + (1-b1)*g
v  = b2*v + (1-b2)*g*g
mh = m * inv(1-b1^t)
vh = v * inv(1-b2^t)
w  = clamp(w - lr*mh/(sqrt(vh)+eps))
```

Bias-correction powers can be maintained iteratively; no `FEXP` needed. For
8-bit weights/states, use per-block Q16.16 scales, saturating integer updates
and deterministic error feedback. Quantization must be tested against a
float32 Adam reference; held-out loss, not training loss, decides acceptance.

A native Adam kernel is therefore feasible. The decision is a memory tier:
512 MiB (16-bit weights + 8-bit moments) or 768 MiB (8-bit weights + 8-bit
moments) for 256 independent heads, with sparse paging. Full 16-bit moments
for all 256 heads is 1.25 GiB and is rejected for the 1 GiB resident target.

## 8.6 Depth and context expense

Parameters per transformer layer at width d and MLP m:

```text
P_layer ≈ 4d² + 2dm + 4d
```

Persistent costs per head with 16-bit weights and 8-bit m/v are `4 P_layer`
bytes (2 B weights + 2 B moments). 256 heads multiply that by 256.

### 256 independent heads, d=128, MLP=512

| depth | params/head | weights | + 8-bit moments | 256 heads | KV @256 | KV @512 | KV @1024 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.20M | 385 KiB | 770 KiB | 192.5 MiB | 32 MiB | 64 MiB | 128 MiB |
| 2 | 0.39M | 770 KiB | 1.50 MiB | 385 MiB | 64 MiB | 128 MiB | 256 MiB |
| 4 | 0.79M | 1.50 MiB | 3.01 MiB | 770 MiB | 128 MiB | 256 MiB | 512 MiB |
| 8 | 1.58M | 3.01 MiB | 6.02 MiB | 1.50 GiB | 256 MiB | 512 MiB | 1.00 GiB |
| 12 | 2.37M | 4.51 MiB | 9.02 MiB | 2.26 GiB | 384 MiB | 768 MiB | 1.50 GiB |

**Consequence:** the 512 MiB persistent budget only supports roughly
**one layer at 256/512/1024 context**, or two layers with a short/partial
context and active top-k. Four independent layers at 1024 context are about
770 MiB weights/moments + 512 MiB KV = **1.28 GiB**, even before activations.

### 256 independent heads, d=256, MLP=1024

| depth | 256-head weights+moments | KV @1024 |
|---:|---:|---:|
| 1 | 769 MiB | 256 MiB |
| 2 | 1.50 GiB | 512 MiB |
| 4 | 3.00 GiB | 1.00 GiB |
| 8 | 6.01 GiB | 2.00 GiB |
| 12 | 9.01 GiB | 3.00 GiB |

This is outside the 512 MiB and 1 GiB resident targets.

### Shared deep trunk plus 255 adapters

One shared d=512, 12-layer, MLP=2048 trunk:

- 37.77M parameters;
- 16-bit weights 72 MiB;
- 8-bit moments 72 MiB;
- total 144 MiB;
- KV @1024 = 24 MiB;
- 255 rank-4 head adapters add only a few MiB.

This is the practical way to get deep thinking circuits without 256 deep
models. The heads remain persistent interfaces; the trunk is shared fast
thinking; the wave/hypermatrix/field keep their roles.

### Context and compute scaling

- KV cache is linear in context: `2 * T * d * bytes * layers * active_heads`.
- Causal attention compute is quadratic in context: about `4 T d` FLOPs per
  token per layer per head; MLP is about `4 d m`.
- Flash/streaming attention avoids materializing `T²` scores, but the
  `T²` arithmetic remains unless routing sparsifies it.
- With 256 heads all active, depth 4 at d=128 is about 0.8 GFLOP/token; depth
  12 is about 2.4 GFLOP/token. Sparse top-k active heads reduce that
  proportionally.

Recommended ladder:

1. **Independent mode**: 256 x depth-1, d=128, context 256/512/1024; fits 512
   MiB persistent plus KV with top-k.
2. **Hybrid mode**: shared deep d=512 trunk + 255 shallow head adapters.
3. **Deep independent mode**: only if the operator accepts multi-GiB weights,
   KV and optimizer state; not a 512 MiB claim.

## 9. Non-claims

- This is not a claim that 255 full transformers fit in 8 MiB.
- This is not a claim that local geometric credit equals BPTT.
- Host differentiable training is not the native runtime.
- CFT/LEAF/hypermatrix gains must beat matched controls; ties are valid results.
- No production NANNET route, canonical merge or fluency claim is implied.
