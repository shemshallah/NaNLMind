# Cross-repository integration selection — 2026-11-09

Status: **selection record**, not a quality claim. The canonical runtime is the
raw NaN16 guest; C++/Python are allowed only as host marshals, references and
tests.

## Sources reviewed

- NaNLMind `main` (`9b59a21` at review time).
- NaNLMind `feature/mth-seven-credit-nanlm-train-20261109`.
- NaNLMind `feat/v2-geometric-trail-field-credit`.
- nanlm-test `pr44` / `pr45` (native semantic ground truth and context ablation).
- nanlm-test `pr50` / `pr52` (contextual roles and senses).
- nanlm-test HW4 geometric/TRAIL branches and HW5 Gutenberg/context branches.

## Picks

### 1. Context-indexed memory is the language base

Pick the native `context-train` path and the HW5 context ablation result:
exact/compact context memory beats context-collapsed byte geometry on
Gutenberg. The measured full-corpus transfer was:

| route/job | before | after 10 epochs |
|---|---:|---:|
| HW4 WordNet held-out | 0% | 61.1681% |
| HW5 Gutenberg from HW4 | 22.1986% | 39.1602% |
| HW4 after HW5 | 61.1681% | 52.999% |

This is a real learning gain and a real retention loss. Keep context memory as
the base; do not replace it with a trunk-only predictor.

### 2. Q16 gate conversion

Pick the branch fix:

```text
credit gate output (Q16.16)
  -> CVTIF -> float32 -> /65536
  -> trunk/QKV update ABI
```

Without this, a gate may accept but the trunk arithmetic receives Q16 bits as
float bits. Adopted in `field_driver.nas`.

### 3. Seven raw credit ABIs

Pick the raw seven-kernel ABI (HOLO/RING/LEAF/TCA/FLUX command methods) and the
`mth_credit_rate_float` conversion. The methods are host-staged, guest-executed.

Reject the branch's **positive MTH7 trainer artifact** until fixed: in this
integration its accepted step produced `-nan` trunk weights. The rejected
control stayed byte-identical, so the gate/rollback side is sound; the
accepted update path is not.

### 4. Transactional TRAIL field

Pick the design from `feat/v2-geometric-trail-field-credit`:
255 local TRAIL updates staged, 2/3 triad sign vote, 43/85 field commit,
generation check, and no canonical write unless accepted. This is exactly the
non-BPTT commit model. Do not take that branch's wholesale deletion of context
memory and context checkpoints.

### 5. Exact semantics as oracle, not runtime

Pick PR44/PR45 semantic **results and fixtures** as an oracle:

- exact synset IDs and typed edges;
- 3-hop inheritance, exceptions, contradiction, abstention;
- 600-query full-WordNet audit and held-out wrong-context ablation.

The PR44 implementation is C++ on a separate `Universe` API. It is not raw
NaN16 and cannot be claimed as the native implementation. Use its expected
answers as raw fixture vectors and port only the bounded ledger/proof core.

### 6. Role and sense experiments as references

PR50 (contextual roles, held-out 100%, shuffled control 54.17%) and PR52
(sense held-out 87.5%, shuffled control 50%) are valuable **controlled
references**, but they are C++ double-precision learners. They are not raw
guest kernels and are not merged as production.

### 7. NANNET C(256,2) corpus objects

The routes are actual `RawRoute` definitions with typed object references:

- `HW4` → `hyperedge` object over the WordNet corpus;
- `HW5` → `memory` object over the Gutenberg corpus;
- both objects contain a **C(256,2) = 32,640-entry unordered byte-pair
  matrix** derived from the corpus bytes;
- object IDs and matrix SHA-256 values are stable and recorded;
- route definitions are committed to the NANNET rawroute registry.

`spec/nannet_corpus_objects.v1.json` lists the canonical route text, route ID,
object ID, matrix digest and object files. `tools/nannet_corpus_objects.py`
builds the matrices and commits the routes. `tools/nannet_route_train.py`
resolves the object back to the corpus/checkpoint and emits a receipt containing
the typed object and matrix digest.

The canonical universe remains `HW0::BS0`; the route target is the HW4/HW5
control-plane object, not a second universe. The runner ring remains `HW5:0`.

## Rejects

- Global BPTT as the primary learning path.
- Wholesale branch merges that delete context memory/checkpoints while adding
  a narrower geometric path.
- Host C++/Python semantic or role learners counted as native.
- Fabricated HW4/HW5 nodes or labels without actual C(256,2) route objects.
- Byte-only improvements that do not preserve context or held-out performance.

## Next raw implementation order

1. Fix the accepted MTH7 trainer path and prove finite weights after one
   accepted step.
2. Integrate transactional TRAIL field with the current 2/3 + 43/85 commit.
3. Add a raw context-residual gate: context memory is the default; QKV/MLP
   contributes only when held-out context confidence is low.
4. Port the bounded semantic ledger/query core to raw and feed it as a
   verification/abstention gate, not as a byte predictor.
5. Run HW4 then HW5 through the NANNET route manifest, tracking both target
   held-out accuracy and retention.
