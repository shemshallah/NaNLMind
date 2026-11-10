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
dense readout. Map the top exact 4-byte contexts to compact bucket IDs and
use a 3-byte hash fallback for rare/unseen contexts; each bucket stores a
16-class high-nibble head and 16x16 conditional low-nibble heads. Only one
table column is read or updated per sample.

- Native `context-train` / `mth_context_hier.nas` / `mth_softmax16_table.nas`.
- Full-corpus, 3 epochs: **73.7795% same-corpus** accuracy, about 31 s of
  training and 6.1 s of evaluation.
- Native random 80/20: **66.8894% held-out** (`67.3435%` training-window)
  after 5 epochs.
- Pure hash control: `57.8644%` same-corpus and `55.9874%` held-out.
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

The mapping tool `tools/context_head_map.py` writes
`state/context_head_map.json`:

```text
class head = high_nibble * 16 + low_nibble   (0..254)
field head = 255
class triad = class // 3, member = class % 3
high group g = triads 5g..5g+4
field threshold = 43/85
```

This is the canonical class/head map for connecting the context memory to the
existing triad/field bank. The raw NaN16 kernel
`mth/nan16/mth_context_class.nas` (driver command 30) now implements it in the
guest: it reads the high and conditional-low scores, computes
`head = high*16 + low` and `triad = head/3`, optionally applies a native CFT or
TRAIL credit to the selected head, and votes the 255 head credits through
2-of-3 triad support to the 43/85 field gate. `RawFieldVM::context_class_map`,
`context_class_credit` and `context_class_apply` are the C++ bridge. The next
gate is to make the memory rows physically live in the sparse head adapters
rather than only the context bucket table.

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

The `backoffcopy` route allocates a small unigram/copy table for contexts that
have no seen 3-byte history. It was tested against the 3-byte backoff:
WordNet held-out `66.7788%` versus `66.8894%`, so the 3-byte backoff remains
the default. The route and table partition are implemented, but the copy
expert is not yet a win. A learned gate rather than a hard route is the next
step.

### 7. Batching and parallel runners

`tools/parallel_context_train.sh` runs WordNet and Gutenberg context-memory
training concurrently and saves both tables:

- WordNet: held-out `66.8894%`, 12.46 MB saved context table.
- Gutenberg (Alice + Moby): held-out `40.7879%`, 12.46 MB saved table.

`HW4`/`HW5` in the logs are local job labels, not instantiated HW nodes; the
canonical topology remains `HW0::BS0`.

## Current native evidence

- `context-train ... backoff`: **73.7795% same-corpus** full accuracy after 3
  epochs; native random 80/20 **66.8894% held-out** after 5 epochs.
- `context-train ... 11456 4 0.1 1`: earlier hash-only `66.4822%`
  same-corpus and `61.3639%` held-out.
- `context-train ... 8192 3 0.5 1`: earlier `57.8644%` same-corpus and
  `55.9874%` held-out.
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
