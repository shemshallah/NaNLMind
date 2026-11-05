# Android bootstrap

## 1. Target

The long-run target is the same bootstrap universe running on the Android device
that is used for development, not only on a hosted x86 runner. The 7 GiB runner
is then a ceiling, not a dependency.

This Termux device reports 3.4 GiB RAM. The C++ core already builds and runs
there:

```sh
make -j2
./build/nanlm-universal bootstrap data/alice_full.txt 1 8
```

No Python, PyTorch, GPU, or network is needed for the bootstrap loop. A PyTorch
transformer control was attempted on the same device and hung; it is not part of
the on-device path.

## 2. Current memory profile

| object | memory |
|---|---:|
| one 8 MiB chart | 8 MiB |
| compact context-2, Alice (79 slabs) | ~20 MiB |
| compact context-2, Moby (109 slabs) | ~28 MiB |
| dense context-2 child universes, Alice | 632 MiB |
| dense context-2 child universes, Moby | 872 MiB |

The compact slab is the first on-device target. The dense child-universe layout
is the topology proof, not the phone allocation yet. Sparse child pages are the
next step before the full child layout can run comfortably on a small device.

## 3. Data scale

Project Gutenberg is not one uniform size:

- The 2024 English plaintext archive is **7.8 GB**, with **57,049 files**
  (Internet Archive, `pg_eng_txt_2024`).
- Project Gutenberg itself had nearly **78,000 items** in March 2026, including
  non-English and non-text items.
- The all-format archive is much larger; the English plaintext slice is the
  useful part for byte-level training.

Do not put 7.8 GB into GitHub. Use a 100-500 MB subset for the first Android
curriculum, then stream the rest from local storage or an external release tier.
The full English plaintext corpus is small by transformer pretraining standards;
it is enough to test the substrate, not to claim a language model.

## 4. Byte bootstrap results

The streaming loop counts one trigram per training byte in order and evaluates
on a fixed 20% test split after each chunk.

Alice full (151 KB, 80/20):

| bytes seen | BPC | top-1 | alphabetic top-1 | word-start top-1 |
|---:|---:|---:|---:|---:|
| 15,117 | 4.288 | 41.33% | 33.87% | 18.40% |
| 60,474 | 3.611 | 43.41% | 35.48% | 19.81% |
| 120,950 | 3.281 | 45.12% | 37.26% | 20.35% |

Moby Dick (1.2 MB, 80/20):

| bytes seen | BPC | top-1 | alphabetic top-1 | word-start top-1 |
|---:|---:|---:|---:|---:|
| 123,463 | 3.570 | 37.92% | 30.68% | 16.52% |
| 493,858 | 3.180 | 38.94% | 31.70% | 17.69% |
| 987,714 | 3.067 | 38.98% | 31.78% | 17.91% |

The BPC drop is real sequential improvement as new bytes arrive. Top-1 and
word-start top-1 rise, then flatten. Repeating the same corpus after saturation
lowers BPC further only through count scaling; it does **not** change the argmax
or the word-start result. That is not new learning.

## 5. Curriculum

1. **Bytes** — current gate. Streaming context-2, BPC and word-start metrics.
2. **Words** — next gate. Add a word-boundary model and report whole-word or
   next-word accuracy, not only first-letter accuracy.
3. **Logic puzzles** — the archived R14 bird/eagle/penguin suite and the later
   R19-R23 logic regressions. These are currently host-symbolic tests, not
   evidence that the topology learned logic from bytes. Keep the distinction.

The older material is in `NaNLM_statespace/archive/`; `make legacy` exercises the
R19-R23 behavior gate. The penguin exception test is a specification target, not
a claim about byte-level learning.

## 6. Command

```sh
# 1 pass, 8 sequential evaluation points
./build/nanlm-universal bootstrap data/alice_full.txt 1 8

# same loop on the larger corpus
./build/nanlm-universal bootstrap data/moby.txt 1 8
```

Each line is one chunk: `bytes_seen`, `bpc`, `top1`, `alpha_top1`,
`word_start_top1`. The loop is deterministic and uses the same 80/20 split as
the other byte gates.
