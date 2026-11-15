# M3 cumulative research log

## R0–R2 preserved

The R0 volumetric concept, R1 two-field crossing and R2 book-disjoint wave
readout sources, reports, manifests, results and corpus were recovered from
`NaN16_Volumetric_Resonance_R2_cumulative.zip` without editing source files.

R2 reported an actual uncrossed TEST next-byte result of 4.42474 BPB; its
counter-direction crossing did not beat it on TEST loss (4.42731 BPB).
This remained a frozen diagnostic, not a model promotion.

## R3 retrospective (reported, not locally reproduced)

On 12 DEV books and 3,072 predictions, the prior R3 conversation reported:

| Arm | Bits/byte | Top-1 | Top-5 |
| --- | ---: | ---: | ---: |
| Wave only | 4.5647 | 20.35% | 49.51% |
| Wave + correct 128/2,048 causal history | 3.8438 | 27.44% | 64.32% |

The code/checkpoint for that R3 experiment was not in the recovered R2 ZIP.
The memory-vs-wave gain is **not** proof of crossing-specific improvement.

## M3 R4 — multiscale diagnostic

Built one tagged NaN16 memory readout for four label scales: raw bytes,
train-only BPE, train-only word labels, and sentence structural classes.
Added reverse-direction, same-direction, symmetric-only, wrong-book and sparse
triangle controls. Every target is predicted before recording its event.
No pretrained model, model weights or optimizer moments were touched.

First repeatable local round completed on 12 DEV and 14 previously exposed
TEST books; results and descriptive bootstrap are retained alongside scripts.
An initial M3 scratch environment reset during development; the R2 archive
was recovered again and the code was reconstructed and revalidated before
publication. Unit checks cover the entire 16-bit mirror map, exact directed
rail reconstruction, BPE reversibility, causal prefixes and OOV accuracy.

