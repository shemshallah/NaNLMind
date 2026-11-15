# M3 — NaN16 causal multiscale memory

Author: Justin Howard-Stanley (Independent Researcher, Santa Cruz, California, USA).

**Status: research diagnostic, not an inherited-checkpoint training run.** No pretrained
language model is loaded. The native NaN16 VM is neither changed nor replaced.

The single logical 256-head address topology has 256 diagonal Head coordinates,
32,640 unordered mirror pairs, and 2,763,520 unordered distinct-head triangles.
`addr(a,b)=(a<<8)|reverse8(b)`; 16-bit reversal transposes the ordered pair.

Every level (byte, train-only BPE, train-only word vocabulary, 16-class sentence
structure) uses **tagged channels in the same mathematical address topology**.
Each channel stores a recent 128-event directed transition window and the
preceding 2,048 transitions. Observed transitions age between windows. Their
S+ symmetric and S− antisymmetric rails reconstruct both directions exactly.
Sparse orientation-aware ordered triples supply an optional triangle readout;
the unordered 3-head identity is its C(256,3) address. A matched ordinary
trigram arm is **mathematically equivalent**: the experiment does not show
any topology-specific predictive gain beyond a sparse 3-event count.

Predicting a target always precedes the state update that records that target.
No suffix from another book or future position is used. The `wrong_book` arm
keeps a different book's historical state but still uses the correct last byte
as the query. All parameters are fixed in source; the code does not train a
neural checkpoint or optimize its settings on DEV/TEST.

## Reproduction

From this cumulative archive's root, using Python 3 + NumPy:

```bash
python3 -m unittest m3.test_r4 -v
OPENBLAS_NUM_THREADS=1 python3 -m m3.r4 \
  --corpus nan16_resonance_corpus/books --output m3/results.json \
  --test-exploratory
python3 -m m3.analyze --input m3/results.json \
  --output m3/book_bootstrap.json
sha256sum -c SHA256SUMS
```

The source archive R0–R2 corpus was extracted intact, without enclosing a
second ZIP. Train/dev/test IDs are disjoint (12/12/14). Both DEV and the
previously exposed R2 TEST corpus are descriptive; this is not a newly sealed
independent-test promotion gate.

## Metric boundaries

- Bytes: genuine next-byte 256-way probability, top-1/top-5 and bits/byte.
- BPE: next-token 288-way probability (32 train-only merges), bits/token,
  bytes/token and token-sequence code length normalized by bytes consumed.
- Words: 1,024 train-word labels plus an UNK class. Exact-word top-1/top-5
  count UNK predictions as **wrong**, and report OOV rate separately. The
  closed-class perplexity includes UNK, so it is not open-vocabulary word PPL.
- Sentences: **16 next-sentence structural classes** from byte-length bin and
  terminal punctuation, not exact complete sentence prediction. Their
  class-code bits/byte are not language-model text BPB.

R3's reported wave-plus-history result (3.8438 BPB, 27.44% top-1, 64.32%
top-5) is retained as external prior-round provenance, **not reproduced here**.
This R4 test isolates addressable memory and triangle readouts without running
R3's volumetric standing wave. Therefore the two numbers must not be treated
as controlled architectural alternatives.

## Remaining requirements

1. Integrate original R3 wave source and verify a matched wave-only control.
2. Align all four levels on one causal event clock; add actual cross-level
   upward and downward feedback with zero-effect ablation on migration.
3. Use a fresh never-inspected book-disjoint TEST set, and separately report
   correct-history vs wrong-history and signed vs symmetric ablations.
4. Add genuine next-sentence candidate ranking and open-vocabulary word
   character fallback; sentence-class prediction alone is insufficient.
5. Verify NaN payload packing, Android/Runner parity and bounded memory/time.

