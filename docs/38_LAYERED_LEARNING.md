# Layered learning: bootstrap to global mesh

**Status:** architecture record. The scalar/topology rules stay fixed; every
learning layer has its own math, storage, and trace contract.

## 1. The stack

```text
L0  bootstrap reflex       8 MiB, 256 heads
    sparse Hopfield slots, byte/word tokens, fast local learning

L1  overbootstrap mind     2 GiB map on the runner
    head evidence, route reliability, layer policy, merge manifests

L2  vector/concept         bins + macro associations
    token/paragraph vectors, nearest-neighbor recall, corpus memory

L3  syntax/logic           temporal rails + hyperedges + rules
    sequence order, relation triples, exceptions, contradiction

L4  code/tests             exact rules and rewrite/test records
    no gradient; exactness is the learner

L5  corpus/expertise       supercluster corpus bins
    retrieval, indexing, provenance, region vocabulary

L6  global mesh            route namespaces only
    research / industrial / personal / public regions
```

Lower layers learn **fast, local, concrete** state. Higher layers learn
**slow, compressed, relational** state. None is a copy of the one below.

## 2. Upward: traces, never raw state

Each layer emits a small `TraceEnvelope`:

```text
TraceEnvelope {
  layer, step, nanclock_tick
  input_hash / output_hash
  active_heads[] or route_ids[]
  confidence, correctness
  delta_digest
  optional prototype vector
}
```

Rules:

- lower layers send **summaries/deltas**, not raw input text;
- a trace is replayable and idempotent;
- a trace is mergeable through the Koyeb merge service;
- the higher layer never needs the lower layer's full chart;
- the lower layer never lets a higher layer overwrite its local keys.

Examples:

| lower layer | upward trace | higher layer learns |
|---|---|---|
| bootstrap | active heads, correct/wrong, strength delta | head reliability, bias, top-k |
| overbootstrap | route success, layer confidence, merged policy | vector prototypes, layer budget |
| vector | token/paragraph centroid, recall score | syntax/topic clusters |
| syntax/logic | rule/exception outcomes, parse traces | code/test curriculum |
| code | test pass/fail, rewrite trace | corpus/expertise retrieval |

## 3. Downward: priors and policy, never state replacement

Higher layers send bounded controls:

```text
LayerPolicy {
  top_k
  bias_limit
  eviction_threshold
  learning_stride
  memory_budget
  route_prior
  curriculum_weight
}
```

The bootstrap receives only **bounded head bias and top-k/stride policy**. It
keeps its own keys, slots, and strengths. This is what lets overbootstrap be the
mind without becoming a second copy of the bootstrap.

## 4. Overbootstrap is the initial mind

Overbootstrap owns:

- head reliability evidence;
- route/portal selection;
- per-layer `LayerPolicy`;
- merge manifests and Koyeb generations;
- memory placement in the 2 GiB map;
- promotion/demotion of a layer.

It does **not** own the bootstrap's local byte/word slots. It steers them.

## 5. Hyperparameters are a learned layer, not a config file

Do not hand-tune one global set. Use an **integer bandit / evidence policy** at
L1:

- candidate `top_k` values: 1, 2, 4, 8, 16;
- candidate `bias_limit`: 0, 1, 2, 4, 8;
- eviction policy: weakest, oldest, lowest-use;
- learning stride / merge interval;
- memory budget per layer.

Track `(candidate, success, cost)` and choose the best confidence. This is
different math from Hopfield: regret/evidence, not key vectors. It is still
deterministic and integer-friendly.

## 6. Vector layer: what learns from what

Vectors do not replace Hopfield slots. They sit above them:

```text
bootstrap correct traces
  -> active-head centroid / token co-occurrence
  -> vector bin
  -> nearest-neighbor concept recall
  -> route prior to overbootstrap
```

Storage:

- `BinStore` int16 vectors (co-occurrence-augmented);
- `AssocMemory` macro key sets;
- `WordRef [U,M,C,P]` for word/concept routes;
- paragraph hash -> bin, with collision bucket.

The vector layer learns **similarity and prototypes**. It does not learn byte
transitions; that stays in L0.

## 7. Macrocluster: choose one job, not all jobs

A macrocluster should not be another dense Hopfield learner. It should learn
one of these:

### Option A: routing/bandit (recommended)

Learns which cluster/head/layer is reliable for a task. State is small:
success counters, route scores, cost, region. This is the natural home for
`LayerPolicy` at scale.

### Option B: corpus/index (recommended for superclusters)

Stores immutable corpus bins, hashes, indexes, provenance. Learns taxonomy and
retrieval paths, not weights. A research region can have a corpus macrocluster
with a huge store without touching the bootstrap.

### Option C: merge/consensus

Learns version/generation reconciliation, conflicts, provenance. It is a
systems learner, not a cognitive one.

**Reject:** macrocluster as a larger copy of bootstrap, one global optimizer, or
one central mind.

## 8. Global mesh regions

Global regions are **namespaces and policies**, not new geometry:

```text
global mesh
  research region  -> superclusters with corpus/expertise stores
  industrial region -> superclusters with telemetry/control corpora
  personal region  -> edge universes and private bins
  public region    -> shared corpus/retrieval
```

Cross-region paths use NTF routes and nanclock generation. A region can have a
different learner mix (retrieval-heavy, rule-heavy, vector-heavy) while keeping
the same address algebra.

Superclusters can hold the **massive corpus stores**; macroclusters route and
merge; bootstrap/overbootstrap handle the small fast mind.

## 9. What else can we use?

| mechanism | where | keep/reject |
|---|---|---|
| sparse Hopfield | L0 | keep |
| count/Kneser-Ney/context-2 | L0–L1 | keep as fast baseline |
| co-occurrence/vector bins | L2 | keep |
| hyperedges | L2–L3 | keep |
| temporal rails | L3 | keep |
| resonance energy | L1/L3 routing | keep bounded |
| rule/exception memory | L3 | keep |
| exact rewrite/tests | L4 | keep |
| retrieval/BM25/ANN | L5 | keep |
| bandit/regret | L1 hyperparameters | keep |
| CRDT/consensus | macrocluster merge | keep |
| gradient/Adam in object | all | reject |
| transformer/MoE claim | all | reject |
| full state replication | all | reject |
| one dense learner per layer | all | reject |

## 10. Evaluation gates

A layer is promoted only if:

- lower-layer gate stays green;
- its own metric improves against a shuffled/null baseline;
- upward trace size is bounded;
- downward policy does not corrupt bootstrap keys;
- merge is idempotent and stale-safe;
- memory stays within the 8 MiB or 2 GiB budget;
- Android remains 8 MiB only.

Each layer has a different metric:

```text
L0 BPC/top-1        L1 route accuracy/calibration
L2 recall@k         L3 parse/exception accuracy
L4 test pass rate   L5 retrieval/coverage
L6 route latency/cost
```

## 11. Build order

1. L0/L1 mesh: done in the two-rate test.
2. Hyperparameter learner with bandit evidence: implemented in
   `HyperparameterLearner` (`tests/test_hyperparameter.cpp`). It learns a
   candidate `top_k` and a bounded bias limit from success counts; k=1 wins over
   noisy k=8, then k=4 wins after more evidence.
3. Vector-layer trace from correct bootstrap heads.
4. Koyeb merge of L1 policy + L2 prototypes.
5. L3 rules/exceptions over vectors.
6. Supercluster corpus store and retrieval.
7. Global region namespaces; routing only.
8. No gradient/global optimizer inside the object.

## 12. Thesis

Bootstrap is the fast hand; overbootstrap is the mind that learns which hand to
use; vectors are its concepts; rules are its logic; corpus superclusters are its
memory; global mesh regions are its institutional boundaries. Every layer learns
from a compressed trace of the layer below and replies with a bounded policy,
never a copy of the lower state.
