# Gutenberg 21 -> 150 book native run

Status: **active native context-memory experiment**, not a language-quality
claim.

## Corpus expansion

`tools/gutenberg_books.py` downloads a deterministic top-150 English Gutenberg
list from Gutendex and stores per-book SHA-256 records.

| corpus | books | bytes | lines |
|---|---:|---:|---:|
| 21-book slice | 21 | 23,806,708 | 563,436 |
| 150-book slice | 150 | 105,730,856 | 2,151,709 |

`state/gutenberg_corpus.txt` was replaced with the 150-book corpus; the old
2-book corpus is preserved as `state/gutenberg_corpus_2books.txt`.

## C(256,2) absorption

`tools/nannet_corpus_objects.py` rebuilt the actual NANNET route objects:

```text
HW4 WordNet   hyperedge  object 4119657226
HW5 Gutenberg memory    object 3122105839
pair cells    32640
HW5 nonzero   5073
HW5 matrix    ba178def3afab5f965ac5ed286bdd260c6afe4a5acf1c673b131550adec13d28
```

The routes remain control-plane objects under the canonical `HW0::BS0`; they
do not instantiate extra hardware nodes. `spec/nannet_training_routes.v1.json`
now points HW5 at the 150-book corpus and its new route object.

## 21-book result

Native context memory, 11,456 buckets, 4-byte context, exact/backoff route,
5 epochs, random 80/20 split:

| metric | value |
|---|---:|
| training-window accuracy | `57.8506%` |
| held-out accuracy | **`54.6394%`** |
| held-out loss | `1.91564` |
| checkpoint | `state/hw5_gutenberg21.ctx` |

## 150-book run

The current universe is trained from scratch (the table is reset, not loaded
from the 2-book or 21-book checkpoint) with the raw guest backoff route:

```sh
# executed in the isolated raw-backoff worktree
context-train state/gutenberg_150_corpus.txt \
  0 1 100000 11456 4 0.1 1 0.8 guestbackoff 10500 \
  save=state/transfer/hw5_gutenberg150_guest.ctx
```

The final held-out score will be recorded here when the run completes. The
150-book corpus and its C(256,2) object are already built and registered; the
checkpoint path is in the HW5 training route.

## Non-claims

- Random line split, not a book-disjoint or author-disjoint split.
- 21/150 books are public-domain source text, not a language model evaluation.
- The 150-book result must be compared to the 21-book result; a larger table
  is not automatically better.
- HW4/HW5 are control-plane route objects, not extra hardware universes.
