# WordNet 3.1 native trunk/readout training

Status: **native training run and matched Python reference**, not a language
quality claim. The native model is the raw NaN16 causal trunk forward
(`mth_trunk_causal.nas`) plus the raw readout trainer
(`mth_readout_train.nas`). The trunk weights are initialized identity and are
not updated in this run; the 255-way readout is trained by a local
error-corrective rule. The 100-epoch result supersedes the earlier 3-epoch
instrumentation.

## Corpus

`tools/wordnet_corpus.py` extracts every gloss from all four WordNet 3.1
`data.*` files:

| field | value |
|---|---:|
| archive | `/storage/emulated/0/Download/NaNLMind/wn3.1.dict.zip` |
| archive SHA-256 | `1820414c1056652b56717df5794609ef0c91aae033d3fc54ddc9846249294285` |
| synset glosses | 117,791 |
| corpus bytes | 8,991,484 |
| corpus SHA-256 | `18e6dff10f4af298eab92748999decd893b89c1d7453b398ff17b485f1464716` |

Each usable line contributes an 8-byte context and the next byte target. The
trainer skips targets 255 and lines shorter than nine bytes. The native run
reports 117,454 usable samples per epoch.

## Commands

```sh
python3 tools/wordnet_corpus.py \
  --archive /storage/emulated/0/Download/NaNLMind/wn3.1.dict.zip \
  --out state/wordnet_corpus.txt \
  --manifest state/wordnet_corpus.json

# 100 epochs over the whole corpus, reporting every 10,000 steps.
# Default "sampled" mode is the fast training path: 8 rotated negatives per
# step plus a full 255-class step every 16th sample.
./build/nanlm-universal trunk-train state/wordnet_corpus.txt 0 100 10000 sampled

# Exact 255-class local update at every sample (slower, matches the original
# one-epoch reference arithmetic).
./build/nanlm-universal trunk-train state/wordnet_corpus.txt 0 100 10000 full

# Matched Python reference over the same samples and mode.
python3 experiments/native_trunk_reference.py state/wordnet_corpus.txt \
  --epochs 100 --report-every 10000 --mode sampled

# Compare the two step logs.
python3 tools/compare_trunk_runs.py \
  state/wordnet_native_100epoch.txt state/wordnet_python_100epoch.json \
  --out state/wordnet_trunk_compare.json
```

## Model and update

```text
tokens x_0..x_7  = 8-lane one-hot byte vectors
trunk            = identity QKV/MLP causal block (raw NaN16), frozen
feature h        = mth_trunk_causal(x_0..x_7)
readout          = 255 x 8 float32 rows, one class per non-255 byte
score[b]         = dot(readout[b], h)
loss             = max(0, best_wrong - target + 1.0)  (one-margin hinge)
update           = target row += lr*h; best-wrong row -= lr*h
```

The readout update is a local error-corrective step, not a BPTT tape. The
raw guest computes the trunk, scores, target/best selection, hinge loss and
update. The C++/Python host only tokenizes bytes, invokes the guest and
accumulates metrics.

## Speed path

The first native run took 88.1 s per epoch because every sample re-ran the
frozen trunk, rewrote all 512 trunk weights, and re-ran a 255 x 8 readout in a
separate guest command. The optimized path keeps the same raw guest arithmetic
but changes the intake and training schedule:

- The frozen trunk feature is computed once per corpus sample and cached on
  the host (`trunk_features`); the guest still computes that feature.
- `mth_readout_only.nas` performs the exact 255-class local update from the
  cached feature, with no trunk recomputation.
- `mth_readout_sample.nas` performs 8 deterministic negative scores per step
  (`idx = (target + salt + k*37) mod 255`). The salt is rotated per step.
- Every 16th sample, rotated by epoch, takes the exact 255-class step instead
  of the sampled step. The final metric is a separate full 255-class
  evaluation over the whole corpus.

Measured on the full 117,454-sample corpus on this device:

| path | epoch | 100 epochs |
|---|---:|---:|
| original per-sample trunk/readout | 88.1 s | about 2 h 27 min |
| cached feature + sampled 8 | about 4.5 s | about 8-9 min |

The sampled loss is a training diagnostic, not the exact full-corpus hinge
loss. Only the `trunk_full_eval` line (and the Python `full_eval` object) is
the full 255-class evaluation. Sampled training is an optimization tradeoff;
the exact `full` mode remains available for arithmetic/reference checks.

## Pipeline status

- Native CFT triangle credit: `mth_cft_credit.nas`
- Native two-rail TRAIL credit: `mth_trail_credit.nas`
- Native signed Q16 multiply: `mth_q16_mul.nas`
- Native CFT-credit -> 85 triad votes -> 43/85 field commit:
  `mth_field_commit.nas`
- Composed CFT -> TRAIL -> field-commit fixture:
  `mth_credit_pipeline_test.nas`
- Native sparse head/field bank and hot-trihead auto-mapping: present.
- Native causal trunk forward: present.
- Native readout training over the raw trunk feature: present.

The QKV/MLP trunk weights are **not** trained in this run. The trunk is a
frozen identity feature extractor; only the readout is trained. A full trunk
gradient/CFT update through QKV/MLP remains open and must not be claimed.

## Non-claims

- This is not a full Transformer trained end-to-end in NaN16.
- It is not evidence of WordNet reasoning, retrieval quality or language
  fluency.
- Training loss on the same corpus is not held-out generalization.
- The Python reference is a control, not the native runtime.
