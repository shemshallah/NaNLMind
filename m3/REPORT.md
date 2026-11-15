# M3 R4 — Multiscale Mirror Memory, Causal Diagnostic

**Author:** Justin Howard-Stanley — Independent Researcher, Santa Cruz, California, USA.  
**Status:** Reproduced numerical experiment; not a trained neural LM, not native NaN VM, not a checkpoint promotion.

## Experimental setup

Source and checksum-verified corpus are carried forward intact from the
NaN16 Volumetric Resonance R2 archive. Train/development/previously exposed
test splits contain 12/12/14 disjoint NaNROUTER Gutenberg books. The only
learned parameters are deterministic 32 train-only byte-pair merges and a
train-only 1,024-word frequency vocabulary. Class priors use TRAIN only.
No pretrained weights, optimizer states or R3 wave checkpoint are loaded.

Every evaluated book uses a bounded region around its midpoint. Readout
memory gets at most 128 most recent transitions plus 2,048 older transitions.
Every prediction is computed before recording its target. Train and
evaluation books remain disjoint. Fixed memory smoothing and readout weights
are identical for all arms and were not fitted on TEST. Hash collisions in
256-head routing are disambiguated by TRAIN-prior class frequency.

## DEV baseline — 12 books

| Level and target | Events | Train prior top-1 / top-5 | M3 triangle top-1 / top-5 | Prior bits/unit | Triangle bits/unit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Byte (+1) | 3,072 | 18.20% / 44.95% | **29.17% / 64.84%** | 4.5840 | **3.8624 bits/byte** |
| 288-class BPE token (+1) | 3,072 | 6.12% / 20.93% | **18.98% / 44.92%** | 5.9144 | **5.0469 bits/token** |
| Word, 1,024 lexemes + UNK (+1) | 1,536 | 0.00% / 14.84% | **0.46% / 18.68%** | 6.2496 | **5.9981 bits/class** |
| Next-sentence STRUCTURE class (16 bins) | 192 | 27.60% / 86.98% | 33.33% / 87.50% | 2.7881 | 2.6240 bits/class |

Sentence-class *same-direction* memory has the better DEV loss: 2.6136
bits/class. A sentence class describes only length bin and punctuation,
not the identity, words or probability of an entire sentence.

BPE spans a mean of 1.35156 bytes/token in the evaluated windows. The
triangle readout's token-code length is 3.7341 bits per source byte in those
windows, but that is not a matched same-boundary next-byte prediction score.

The word OOV rate is **31.58%**. Its exact top-1 excludes UNK hits;
accuracy conditioned on a known word is **0.666%**. Closed-class word
perplexity is not genuine open-vocabulary word perplexity.

## Structural controls — DEV

| Comparison | Mean bit saving per event | Positive books / 12 | Descriptive book-bootstrap 95% interval |
| --- | ---: | ---: | ---: |
| Byte triangle vs ordinary forward pair memory | +0.15956 | 12 | [+0.13535, +0.18395] |
| Byte triangle vs train prior | +0.72168 | 12 | [+0.66086, +0.78349] |
| Byte correct-book forward history vs wrong-book history | +0.22629 | 12 | [+0.14391, +0.32304] |
| Byte crossed-old reverse lookup vs same-direction lookup | **−0.43762** | 0 | [−0.47901, −0.39666] |
| BPE triangle vs forward pair memory | +0.16695 | 12 | [+0.12779, +0.20334] |
| BPE correct-book forward history vs wrong-book history | +0.36718 | 12 | [+0.26567, +0.49166] |

These are descriptive whole-book bootstraps, not preregistered significance
tests or a newly sealed independent TEST result.

**Critical interpretation:** sparse C(256,3) triangle readout is currently
an oriented three-event count mapped to an unordered triangle address.
The matched `plain_trigram` arm is exactly the same predictor by construction.
Therefore the improvement supports **higher-order causal memory**, not a
unique physical or mathematical advantage of triangle topology.

Likewise, this R4 `crossed` arm reverses the lookup orientation of the older
observed-history bank. It does **not** run R3's cross-coupled 3D standing
waves, so negative R4 reverse-lookup results do not refute R3 wave physics.

## Additional 14-book split (previously exposed in R2)

| Level | Triangle top-1 | Top-5 | Bits/unit | Events |
| --- | ---: | ---: | ---: | ---: |
| Byte | 30.86% | 67.63% | 3.68760 bits/byte | 3,584 |
| BPE token | 21.15% | 48.91% | 4.90312 bits/token | 3,584 |
| Word (exact; UNK wrong) | 0.11% | 17.02% | 6.55121 bits/class | 1,792 |
| Sentence structure | 30.80% | 88.39% | 2.46173 bits/class | 224 |

Triangle vs forward-only pair memory saved 0.18354 bits/byte on all 14
previously exposed TEST books. Correct-book forward memory beat wrong-book
history by 0.24266 bits/byte on 13 of 14 books. **These are exploratory
checks, not newly sealed test-set confirmation.** No configuration is selected
based on this split.

## R3 historical comparison and boundary

The prior conversational R3 wave-plus-memory result was 3.8438 bits/byte,
27.44% byte top-1 and 64.32% top-5 on DEV. Its source was not found in the
R2 archive. R4's 3.8624 bits/byte cannot be treated as a same-architecture
improvement over R3 despite R4's higher top-1; evaluation state and readout
differ. A controlled combined experiment is the next decisive test.

## Promotion gate

**No promotion.** R4 has not demonstrated learned cross-level feedback,
open-vocabulary word generation, exact sentence prediction, geometry-specific
improvement, a freshly sealed TEST result, or native NaN16 execution.

The strongest supported finding is that correct-book addressable 128+2,048
causal history and sparse three-event retrieval contain useful predictive
information beyond train-only priors; a conventional trigram has the same
effect as the current triangle implementation.

