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
