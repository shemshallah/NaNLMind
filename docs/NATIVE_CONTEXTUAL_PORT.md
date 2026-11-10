# Contextual role/sense port and compact head catalog

Status: **raw-NaN production path**. The role and sense learners now train
inside the NaN0S VM at D=24. The C++ double-precision PR50/PR52 ports remain
as convergence and scrambled-label controls; they are no longer the production
contextual training loop.

The host only tokenizes text and stages token ids, positions, oracle relation /
sense targets, and the initial parameter blocks. Every forward pass, sigmoid or
softmax, shared-encoder local gradient, relation/sense head update, and bias
update runs in `mth/drivers/field_driver.nas`.

## Ported

- `include/nanlm/wordnet.hpp` — exact synset graph loader/saver and lookup.
- `include/nanlm/contextual_roles.hpp` — shared contextual encoder and binary
  role learner.
- `include/nanlm/contextual_senses.hpp` — exact-WordNet-sense softmax sharing
  the role learner's token/position state.
- `tests/test_contextual_roles.cpp`
- `tests/test_contextual_senses.cpp`

The Universe-root dependency is replaced by a checkpoint prefix, so the
learners persist without a second universe.

The shared contextual encoder is now native raw:

- `mth/nan16/mth_context_encode.nas` — command 40
- word embeddings, position gates, bias/order, orientation and context slots
  are staged by the host; the dot products, `1/sqrt(T)` normalization and
  `FTANH` happen in the NaN16 guest.

Two raw training heads now use it:

- `mth/nan16/mth_role_step.nas` — command 41, sigmoid role CE and relation
  gradient update;
- `mth/nan16/mth_sense_step.nas` — command 42, softmax exact-synset head CE
  and sense-head/bias update.

Both have C++ bridges (`role_step`, `sense_step`) and guest tests. The raw
kernels now backpropagate through the shared encoder as well:

- role: relation logit → `dh` → token embeddings, position gates, bias, order,
  relation and relation bias;
- sense: softmax CE → `dh` → token embeddings, position gates, bias, order,
  sense heads and sense biases.

The D=8 path is exercised by `test_raw_field`; the production corpus path uses
D=24:

- `mth_context_encode24.nas` — shared contextual encoder;
- `mth_role_step24.nas` — single-relation raw role kernel;
- `mth_role_step24k.nas` — multi-relation raw role heads (command 57);
- `mth_sense_step24.nas` — exact-sense softmax head (command 56);
- fixture `mth/tests/mth_context24_test.nas`;
- corpus test `tests/test_raw_contextual.cpp`.

The corpus test uses the same PR50/PR52 synthetic splits as the C++ controls
(288/144/144 role rows and 120 train / 8 held-out sense rows), but the host
does not call `ContextualRoleLearner` or `ContextualSenseLearner`. Measured raw
result:

```text
RAW_CONTEXTUAL PASS
role_train=288 role_dev=144 role_test=144
role_dev_accuracy=1 role_test_accuracy=1
role_inversion=yes role_restored_accuracy=1 role_shuffled_accuracy=0.5
role_updates=25920
sense_train=120 sense_test=8
sense_accuracy=0.875 sense_restored_accuracy=0.875
sense_shuffled_accuracy=0.375 sense_updates=14400
```

Role features follow PR50: subject/object tokens are removed, the remaining
lexical tokens use four relative position slots, and orientation is +1/-1 from
subject/object order. Sense features follow PR52: the target surface form is
removed and the remaining context uses pre/post-target slots. Unknown test
words are skipped exactly as in the C++ reference.

The raw context, multi-relation head bank, sense heads, and biases are read
back from guest memory and reloaded into fresh VMs. Both restored models keep
their held-out accuracy exactly, so the checkpoint state is not trapped in one
host process.

## Measured reference results

Role learner:

```text
train=288 dev=144 test=144
test CE=0.000633987 accuracy=100%
shuffled-label accuracy=41.6667%
native updates=25,920
```

Sense learner:

```text
train=120 test=8
test CE=0.162007 accuracy=87.5%
shuffled-label accuracy=62.5%
synsets=2 updates=14,400
shared tokens=40
```

Both tests pass as compiled executables. These are controlled synthetic
benchmarks, not Gutenberg or unrestricted semantic-acquisition results.

## Raw bounded semantic query

`mth/nan16/mth_semantic_query.nas` (command 53) is the first raw semantic
graph kernel:

- BFS over up to 32 concepts and 64 ISA edges;
- direct negative ISA claims (support/refutation coexistence);
- ability claims with nearest-ancestor specificity;
- explicit `support | refute` state and depth;
- PR44 five-synset fixture:
  - artifact→entity ISA support+refutation at depth 3;
  - fiction→entity unknown (contradiction is not ISA);
  - artifact ability support+refutation at nearest specificity;
  - object negative at distance 0;
  - physical inherits entity's positive ability at distance 1.

## Compact head representation

`include/nanlm/head_catalog.hpp` fixes cognitive heads to the canonical
identity range:

```text
0..254 = cognitive heads
255    = field/network head
```

The full set requires **no 32-byte leaf mask and no separate leaf table**
(`kFullSetLeafBytes = 0`). Lookup is the hardcoded identity list; head 255 is
excluded from leaf lookup. Non-full subsets can still use explicit leaf masks.

Test: `build/test_head_catalog` → PASS.

## Remaining

- Feed the shared contextual raw state from the UnifiedWave/context memory.
- Promote the in-memory D=24 checkpoint round-trip into the persistent
  role/sense checkpoint container.
- Keep exact WordNet IDs in the sparse semantic ledger, not in 256 head buckets.
- Evaluate on source-disjoint prose after the raw port.
