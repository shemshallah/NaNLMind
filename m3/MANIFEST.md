# M3 R4 cumulative manifest

The archive contains exactly one current M3 R4 source implementation, its
tests, full DEV and previously exposed TEST results, per-book bootstrap,
benchmark stdout and this research report; it also includes recovered R0,
R1, and R2 source, research notes and raw NaNROUTER split books intact.

| Directory | Contents |
| --- | --- |
| `nan16_resonance_r0/` | Original R0 volumetric experiment and numeric outputs |
| `nan16_resonance_r1/` | Original crossed-wave R1 and controls |
| `nan16_resonance_r2/` | Original book-disjoint R2 wave probe and outputs |
| `nan16_resonance_corpus/books/` | Original disjoint train/dev/test books and corpus SHA-256 provenance |
| `m3/r4.py` | New standalone M3 R4 byte/BPE/word/sentence-class causal memory experiment |
| `m3/test_r4.py` | Geometry, directionality, BPE and causal/OOV tests |
| `m3/analyze.py` | Book-disjoint paired bootstrap analysis |
| `m3/results.json` | Full current per-book R4 measurements |
| `m3/book_bootstrap.json` | Descriptive paired whole-book uncertainty |
| `m3/REPORT.md` | Current benchmark report and failure boundaries |
| `m3/CLAIM_LEDGER.md` | Provenance and promotion-status ledger |
| `m3/RESEARCH_LOG.md` | Cumulative R0–R4 research log |
| `SHA256SUMS` | Checksums of all included files except itself |

The prior R2 ZIP is **not nested** inside this archive. No trained neural
checkpoint was available or altered. Temporary Python caches are excluded.

Verify with `sha256sum -c SHA256SUMS` at archive root. For replay commands,
see `m3/README.md`.
