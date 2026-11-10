# Wordlist corpus intake

The phase/PQ/matrix stack consumes one lexical item per line. NaNROUTER's
canonical wordlist landing page is:

```text
../NaNROUTER/corpora/wordlists/
```

The payload is intentionally not committed to git; its sources and release
bundle are described in `NaNROUTER/corpora/wordlists/README.md`.

## Normalize the bundle

```sh
make wordlist-corpus
# The target returns a clear failure when the bundle is absent or yields no
# lexical items. Download the release bundle first; use --allow-empty only for
# a manifest-only check.
# or:
python3 tools/prepare_wordlist_corpus.py \
  --root ../NaNROUTER/corpora/wordlists \
  --out state/wordlists.corpus.txt \
  --lower --dedupe
```

The converter recursively reads the bundle and skips README/SOURCES/MANIFEST,
checksum files, hidden paths and binary payloads. It handles:

- plain wordlists
- CSV/TSV with rank/frequency columns
- JSON arrays/objects
- JSONL records
- gzip-compressed files
- nested source directories

It writes:

- `state/wordlists.corpus.txt` — one normalized word per line
- `state/wordlists.corpus.txt.json` — source file counts, word count, SHA-256

The converter only normalizes text and provenance. It performs no vector,
trig, PQ, matrix, checkpoint or field arithmetic.

## Verify normalization without the bundle

```sh
make wordlist-intake-check
# WORDLIST_INTAKE PASS
```

This creates a temporary nested bundle containing plain text, ranked CSV,
JSON, JSONL and gzip sources, normalizes it, and runs short-word phase ingest.

## Train against the normalized corpus

```sh
./build/nanlm-universal phase-train \
  state/wordlists.corpus.txt 0 8 32 0 \
  state/phase_wordlists
```

The phase readers pad short wordlist lines with spaces to the configured
window (normally 8 bytes), so words shorter than the window are accepted rather
than skipped. Long prose still uses the trailing window, preserving the
existing Gutenberg behavior.

For held-out evaluation use a separate corpus as the last argument:

```sh
./build/nanlm-universal phase-train \
  state/wordlists.corpus.txt 100000 8 32 100000 \
  state/phase_wordlists state/gutenberg_150_heldout.txt
```

## Metrics and checkpoints

`phase-train` writes:

- `PREFIX.metrics.jsonl` — per-chunk train/eval L1, probe hit rate, leaf
  verification, matrix coverage, hot heads/triads and 43/85 field state
- `PREFIX.metrics.json` — selected best checkpoint and resume flag
- `PREFIX.ckpt` — codebook/matrix payload with raw FNV-1a digests
- `PREFIX.codebook.bin`, `PREFIX.matrix.bin`, `PREFIX.triads.bin`

A subsequent run with the same prefix resumes only when both raw checkpoint
digests match. The codebook and matrix are selected by held-out L1, with the
43/85 field state as a tie-break.

## Notes

- Password-style wordlists contain secrets and should be handled as sensitive
  corpus material.
- `--max-words`, `--min-length`, `--dedupe` and `--lower` control the
  normalized corpus size and normalization.
- The converter is deterministic for a given tree and options.
