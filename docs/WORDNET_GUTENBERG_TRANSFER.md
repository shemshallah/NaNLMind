# WordNet → Gutenberg transfer run

Status: **native context-memory transfer experiment**, not a language-quality
claim. The current best native next-byte learner is the context-indexed 16x16
class memory (`context-train`), not a trained transformer trunk.

## Setup

- WordNet corpus: `state/wordnet_corpus.txt` (8,991,484 bytes; 117,454 usable
  samples).
- Gutenberg corpus: `state/gutenberg_corpus.txt` (25,338 lines; 21,194 usable
  samples).
- 11,456 buckets, 4-byte context, LR 0.1, 10 epochs per corpus.
- Checkpoints use the new `load=PATH save=PATH` options on `context-train`.
- Full-corpus run: train fraction 1.0.
- Held-out control: random 80/20 split with the same seed.

## Full-corpus run

WordNet 10 epochs:

| epoch | train loss | train accuracy |
|---:|---:|---:|
| 1 | 3.49897 | 62.2737% |
| 2 | 2.47074 | 67.1259% |
| 3 | 2.10142 | 66.9343% |
| 4 | 1.88985 | 66.9053% |
| 5 | 1.74874 | 66.8662% |
| 6 | 1.64614 | 66.8968% |
| 7 | 1.56763 | 66.7819% |
| 8 | 1.50521 | 66.8798% |
| 9 | 1.45415 | 66.8875% |
| 10 | 1.41131 | 66.8662% |

Final same-corpus evaluation: **66.3707%**, loss `1.36737`.
Training time: 127.1 s.

Gutenberg after loading the WordNet table:

| checkpoint | loss | full accuracy |
|---|---:|---:|
| WordNet table, before Gutenberg | 3.87796 | 23.7237% |
| after 10 Gutenberg epochs | **2.07317** | **54.3928%** |

Improvement: **+30.6691 points**, loss **−1.80479**.
Gutenberg training time: 23.2 s.

WordNet after the Gutenberg transfer:

| checkpoint | loss | full accuracy |
|---|---:|---:|
| after WordNet 10 | 1.36737 | 66.3707% |
| after Gutenberg 10 | 1.60578 | 55.7563% |

Retention loss: **−10.6144 points**. The transfer learns Gutenberg while
forgetting part of WordNet. This is a real measured trade-off, not hidden.

## Held-out control

Random 80/20 split, same bucket/context/LR:

| corpus/checkpoint | held-out accuracy | loss |
|---|---:|---:|
| WordNet, zero table | 0% | 5.54518 |
| WordNet after 10 | **61.1681%** | 1.74156 |
| Gutenberg, WordNet table before training | 22.1986% | 3.98129 |
| Gutenberg after 10 | **39.1602%** | 2.95091 |
| WordNet after Gutenberg transfer | **52.999%** | 1.88138 |

Gutenberg held-out improvement: **+16.9616 points**.
WordNet held-out retention loss: **−8.1691 points**.

## Interpretation

- The native context memory does learn: WordNet held-out accuracy rises from
  0% to 61.17%, and Gutenberg held-out accuracy rises from 22.20% to 39.16%.
- Sequential transfer is strongly non-stationary: Gutenberg training improves
  Gutenberg but degrades WordNet.
- This run does not train the QKV/MLP trunk. It trains the context-indexed
  class memory, the current best native learner.
- Next steps: replay/mix a small WordNet sample during Gutenberg training,
  lower/decay the transfer LR, and checkpoint-select by the combined held-out
  score. Those are needed before claiming retention.

## Reproduce

```sh
# Full WordNet (10 epochs, checkpoint)
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 10 100000 11456 4 0.1 1 1.0 none 8192 \
  save=state/transfer/wn_full10.ctx

# Full Gutenberg after WordNet
./build/nanlm-universal context-train state/gutenberg_corpus.txt \
  0 10 100000 11456 4 0.1 1 1.0 none 8192 \
  load=state/transfer/wn_full10.ctx \
  save=state/transfer/wn_full_gut10.ctx

# Evaluate retention without resetting
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 0 100000 11456 4 0.1 1 1.0 none 8192 \
  load=state/transfer/wn_full_gut10.ctx
```

Held-out control uses train fraction `0.8` and separate checkpoints
`wn10.ctx` / `wn_gut10.ctx`.
