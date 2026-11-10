# Learning architecture: from byte context to a class hierarchy

Status: **measurement-driven architecture note**, not a quality claim. The
current native readout is a local error-corrective learner over a frozen
identity trunk. The first probes show that the main limit is the feature and
class factorization, not the VM arithmetic.

## Diagnosis

The current feature is an eight-lane one-hot vector produced from
`byte & 7`, followed by an identity QKV/MLP trunk and a 255 x 8 readout.
That discards five bits of every byte and most position information. The
observed full 255-class accuracy is about **20%** after a full softmax epoch.
The exact one-epoch hinge control is **8.18%**; the 100-epoch eight-negative
sampled hinge control is **12.88%**. The sampled trainer was optimizing a
different objective and is not a quality path.

A linear softmax probe on the same task gives:

| feature | dim | full-class accuracy, 2 epochs |
|---|---:|---:|
| current trunk feature | 8 | about `20.9%` |
| last-byte nibbles | 32 | `24.2%` |
| last 2 bytes, nibble pairs | 64 | `30.1%` |
| last 8 bytes, 8-lane hashes | 64 | `31.6%` |
| last 4 bytes, nibble pairs | 128 | `34.5%` |
| last byte one-hot | 256 | `28.9%` |

Positional byte features are the largest immediate win. A conditional
16x16 factorization

```text
P(byte | context) = P(high_nibble | context)
                  * P(low_nibble | high_nibble, context)
```

reaches **34.15%** in the host probe while evaluating only two 16-class heads
per sample. It is the basis of the native `hier-train` path.

## Architectural linkages, ranked

### 0. Context-indexed class memory

The strongest immediate result is a sparse n-gram class memory, not a wider
dense readout. Hash the last 3 bytes to one of 8,192 buckets, then store a
16-class high-nibble head and 16x16 conditional low-nibble heads per bucket.
Only one table column is read or updated per sample.

- Native `context-train` / `mth_context_hier.nas` / `mth_softmax16_table.nas`.
- Full-corpus, 3 epochs: **57.8644% same-corpus** accuracy, about 35 s of
  training and 6.8 s of evaluation.
- Native random 80/20: **55.9874% held-out** (`61.3539%` training-window)
  after 3 epochs.
- Python random 80/20 probe: **55.43% held-out** at the same bucket count.
- This maps directly to the existing topology: high nibbles are field groups,
  low classes are head rows; the context bucket is sparse memory.

### 1. Positional feature bank + conditional hierarchy

- Give the readout the last 2-8 bytes as separate nibble or byte blocks.
- Predict the high nibble with 16 classes; select one of 16 low-nibble heads.
- Cost is `2 * 16 * D` per sample instead of `255 * D`; storage remains the
  full 16 x 16 class table.
- Native pieces: `mth_readout_hier.nas`, `mth_softmax16.nas`,
  `RawFieldVM::readout_hier`, `hier-train`.
- Next: add a raw feature builder so the host only tokenizes, and concatenate
  the positional bank with the trunk feature rather than replacing it.

### 2. Map the hierarchy onto the 255 physical heads

The 255 triad-member heads plus field head naturally form a 16 x 16 class
table:

```text
head = high_nibble * 16 + low_nibble      (0..255; 255 is the field head)
triad group = high_nibble                 (16 groups)
field gate = 43/85 vote over the selected groups
```

Use the existing triads/field commit to select the high-nibble group and the
low-nibble head rows as class experts. CFT triangle credit and TRAIL
eligibility can update the selected group instead of a dense 255-row update.
This links class factorization directly to the existing topology instead of
building a second readout bank.

### 3. Train the trunk, not just the readout

The trunk is frozen identity today. Existing native pieces already exist:

- `mth_trunk_credit.nas` / wide Wout/W1/W2 local credit;
- `mth_qkv_credit.nas` / wide QKV local credit;
- CFT and TRAIL credit;
- sparse head/field bank with d=512/rank=4 adapters.

The next gate is to run one local credit step per token after the readout
error, with a checkpointed feature cache invalidated when trunk weights
change. This should learn byte embeddings and causal position mixing, which
the hand-built nibble bank cannot express.

### 4. Optimizer and schedule

The fixed-rate softmax probe peaked at epoch 2 and drifted by epoch 3. The
full hinge run also peaked and then forgot. Required:

- LR warmup and decay;
- per-row Adam/RMSProp moments (raw Q16 or float guest state);
- gradient clipping;
- best checkpoint selected by full-class evaluation, not window loss;
- shuffle every epoch (already in the native loops);
- optional class-balanced sampling.

### 5. Better objective

Full softmax is the first stable objective. The next objective should be
hierarchical softmax with label smoothing, and a held-out split by synset or
gloss domain. Report:

- full 255-class accuracy;
- observed-class macro accuracy;
- high-nibble and conditional low-nibble accuracy;
- top-k accuracy;
- calibration and loss.

Do not report sampled-window accuracy as model quality.

### 6. Copy and induction heads

Next-byte prediction benefits from copying recent bytes. Add residual
features for the last byte and short n-grams, and let the sparse field select
a copy expert when the context repeats. This is a cheap inductive bias and a
natural use for the 255-head field overlay.

### 7. Batching and parallel runners

Per-sample guest invocation is still the main cost. Batch several samples
inside one guest command, reuse the readout matrix, and shard independent
evaluation across runner slots. Keep the raw arithmetic unchanged.

## Current native evidence

- `context-train ... 8192 3 0.5 1`: **57.8644% same-corpus** full accuracy
  after 3 epochs; native random 80/20 **55.9874% held-out**.
- `trunk-train ... softmax shuffle 0.1`: one epoch `19.8341%`; three fixed-rate
  epochs `19.8341 / 21.2151 / 18.4719%` (best at epoch 2).
- `hier-train ... 0.5`: first full-corpus run `28.2102%`, one epoch.
- `hier-train ... 0.1`: **`33.2641%`** full-class accuracy after one epoch
  (`40.4346%` training-window accuracy, loss `2.34407`).
- The Python conditional hierarchical probe reaches `34.15%`, so the native
  hierarchy is within one point of the reference at one epoch.

The next implementation target is a native held-out split and a
best-checkpointed context-memory run, then a trunk-credit run that uses the
context bucket as a residual feature.
