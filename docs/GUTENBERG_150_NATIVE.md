# Gutenberg ingestion and 150-book native run

Status: **ingestion-corrected native experiment**, not a language-quality
claim.

## Ingestion pipeline

`tools/gutenberg_books.py` downloads 150 deterministic English Gutenberg books
from Gutendex and records per-book SHA-256 provenance.

`tools/gutenberg_ingest.py` then:

1. strips the Gutenberg START/END boilerplate from every book;
2. normalizes CRLF/NULs and trailing whitespace;
3. writes cleaned per-book files;
4. makes a deterministic **book-disjoint** 120/30 train/held-out split;
5. writes separate train and held-out corpora and a manifest.

| corpus | books | bytes | lines |
|---|---:|---:|---:|
| raw 150-book download | 150 | 105,730,856 | 2,151,709 |
| cleaned full corpus | 150 | 100,648,974 | 2,093,889 |
| cleaned train corpus | 120 | 84,131,127 | 1,778,476 |
| cleaned held-out corpus | 30 | 16,517,846 | 315,412 |

Corpus hashes:

```text
train   87eaecc8cb57f5b29f31b66595f0c4f26880feada1d9145d89705b1270ab7d75
heldout 0c2e331ee21e10f5115655b7e8028693487d4b2d8532dfcfe7ea455cf7b9cc0a
```

The old raw 150-book file is preserved as `state/gutenberg_corpus_raw_150.txt`.
`state/gutenberg_corpus.txt` is now the cleaned full corpus.

## C(256,2) absorption

The cleaned corpus was re-absorbed into the NANNET route objects:

```text
HW4 WordNet   hyperedge  object 4119657226
HW5 Gutenberg memory    object 1632653404
pair cells    32640
HW5 nonzero   4970
HW5 matrix    6150505c066646cf02d1296598862200ee448300fac458df784c38f172f91392
```

The old raw-corpus object `3122105839` is preserved as provenance. Routes
remain control-plane objects under `HW0::BS0`; no extra HW node is created.

## Corrected 150-book result

The old `53.1653%` number used a **random line split**, so the same books
appeared on both sides. It is retained only as a control, not as generalization.

Book-disjoint native context memory, 11,456 buckets, 4-byte context,
exact/backoff route, LR `0.1`:

| run | training-window | held-out |
|---|---:|---:|
| 150 books, 1 epoch | `46.7182%` | **44.1444%** |
| 150 books, 5 epochs | `46.887%` | **43.9514%** |

5-epoch held-out loss: `2.15699`.

The corrected split removes most of the apparent 53% score. Five epochs are
flat/slightly worse than one epoch on held-out books. This is the honest
ingestion result.

## 21-book result

The 21-book result (`54.6394%`) used the earlier random line split and is not
directly comparable to the book-disjoint 150-book result. It remains a
same-line-distribution control.

## Commands

```sh
# Download once.
python3 tools/gutenberg_books.py --count 150 \
  --catalog-files /tmp/gutendex.json /tmp/g2.json /tmp/g3.json \
  /tmp/g4.json /tmp/g5.json \
  --corpus state/gutenberg_150_corpus.txt \
  --manifest state/gutenberg_150_books.json

# Clean + book-disjoint split.
python3 tools/gutenberg_ingest.py

# Five book-disjoint epochs.
./build/nanlm-universal context-train state/gutenberg_150_train.txt \
  0 5 100000 11456 4 0.1 1 1 backoff 10500 \
  eval=state/gutenberg_150_heldout.txt \
  save=state/transfer/hw5_gutenberg150_bookdisjoint_5.ctx
```

The route manifest now points HW5 at the train/held-out files, the clean
object, and the 5-epoch checkpoint.

## Non-claims

- 44% is held-out next-byte accuracy on 30 unseen books, not language quality.
- The random-line 53% result is not a generalization result.
- The Gutenberg corpus is public-domain source text, not an instruction set.
- HW4/HW5 are route objects under `HW0::BS0`, not extra hardware universes.
