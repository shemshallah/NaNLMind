# Word-vector gate

## 1. Model

`WordVectorLayer` builds:

- a 1024-dimension word bin with a unique anchor per vocabulary item and a small
  co-occurrence tail;
- a one-hot value bin for next-word targets;
- an `AssocMemory` entry from context word to next-word value, weighted by
  training count;
- most-frequent-word fallback for unseen context.

## 2. Result

Alice excerpt, same 80/20 split:

```text
words          5,607
vocabulary       960
associations   3,240
unigram         6.42%
word bigram     8.12%
word vector     7.85%
```

The vector expert beats unigram and is close to bigram, but does not beat it.
That is the honest result.

## 3. What it proves

- The vector bins can carry word identity/context.
- Association recall can approximate a bigram.
- Exact identity anchors matter: a 64-dimension code for 960 words was too
  colliding and scored ~3.4%.
- A missing-word fallback is required for held-out vocabulary.

## 4. Test

```sh
./build/test_word_vector_learning
```

## 5. Next

1. Add word co-occurrence vectors with a larger tail and no anchor dominance.
2. Add phrase/word-pair tokens.
3. Route between word-vector and word-bigram experts.
4. Feed word traces into overbootstrap.
5. Keep the byte challenge separate.
