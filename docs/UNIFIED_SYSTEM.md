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

The raw field driver is capped at **0x3E00 words** (15,872 emitted words).
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
| 46 | `mth_six_context_poincare_attention` | 3 back + 3 forward + NOW=255 trig attention and Poincare projection |

These are the kernel-level paths removed by the earlier ABI-conflict merge.
They are now reachable and covered by focused tests. CLI exposure for the
`backoffjoint` and `induction` routes is the next integration step; the raw
commands and bridges are already present.
