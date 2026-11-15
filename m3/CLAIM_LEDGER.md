# M3 R4 — claim and provenance ledger

| Claim | Evidence | Status |
| --- | --- | --- |
| 256 fixed heads, 32,640 mirror pairs, 2,763,520 unordered triangles | `m3/test_r4.py` exhaustive 65,536 address checks, pair ranks, endpoints | Verified mathematical identities |
| Symmetric and antisymmetric rails invert to directed transition counts | `Memory.rails` and unit tests | Verified for probed states |
| Correct causal update ordering | Prediction loop in `m3/r4.py`; prefix-independence unit test | Verified in bounded harness |
| Train-only 32-merge byte-pair vocabulary | `train_bpe`; train split only; byte reconstruction unit test | Verified in harness |
| Numeric byte/BPE/word/sentence-class DEV metrics | `m3/results.json` | Measured; preliminary |
| Triangle address geometry uniquely improves prediction over ordinary n-grams | Exact `plain_trigram` matched control | **Not established; equal predictions by construction** |
| Different-book control and paired whole-book bootstrap | `m3/book_bootstrap.json` | Descriptive, not confirmatory |
| Fresh sealed TEST improvement | Existing TEST corpus already exposed in R2 | **Not established** |
| Actual R3 volumetric waves integrated into M3 hierarchy | R3 source unavailable in recovered R2 archive | **Not implemented** |
| Exact open-vocabulary next-word and next-sentence prediction | UNK word class and 16 sentence structural bins only | **Not implemented** |
| One learned neural model, unified optimizer continuation | No neural checkpoint or optimizer in this experiment | **Not claimed** |
| NaN-native execution / Android timing | Python/NumPy diagnostics only | **Not established** |

