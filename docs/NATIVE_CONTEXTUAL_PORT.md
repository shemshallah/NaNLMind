# Contextual role/sense port and compact head catalog

Status: **reference port**, not a raw-NaN production claim. The role and sense
learners are C++ double-precision references ported from nanlm-test PR50/PR52
into NaNLMind. Their arithmetic must still be moved to 0xNaN before being
counted as native runtime.

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

Both have C++ bridges (`role_step`, `sense_step`) and guest tests. The
**shared encoder parameters are frozen in this first raw slice**; PR50/PR52
also backpropagate through the shared token/position encoder, which remains
the next raw gradient extension. This is a genuine raw role/sense training
path for the heads, not a claim of full shared-encoder parity.

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

- Port role/sense forward and gradient updates to raw `mth/*.nas`.
- Feed the shared contextual state from the UnifiedWave/context memory.
- Keep exact WordNet IDs in the sparse semantic ledger, not in 256 head buckets.
- Evaluate on source-disjoint prose after the raw port.
