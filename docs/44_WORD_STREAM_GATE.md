# Word-stream gate

## 1. Setup

Alice excerpt tokenized into lowercase words (letters/digits/apostrophe).

```text
words:       5,607
vocabulary:    960
train:        80%
test:         20%
```

Two baselines:

- unigram: most frequent word (`the`);
- bigram: most frequent next word after the previous word, with unigram
  fallback.

## 2. Result

```text
unigram top-1: 6.42%
bigram top-1:  8.12%
```

The word bigram beats unigram by **1.70 percentage points**. That is a real
word-level signal but still weak; a 960-word vocabulary with 1.1k test words is
sparse.

## 3. What this means

- Word-level learning starts from a very low base.
- Bigram context helps, but not enough for a strong word model.
- The next word layer needs vectors/associations, not only counts.
- The byte layer's count expert is still much stronger in its own unit
  (29.22% top-1).

## 4. Test

```sh
make build/test_word_stream_learning
./build/test_word_stream_learning
```

The test requires bigram >= unigram, not an arbitrary high threshold.

## 5. Next

1. Add word vectors/co-occurrence bins.
2. Use punctuation/sentence boundaries.
3. Compare word-bigram with the vector prototype layer.
4. Feed word traces into overbootstrap.
5. Keep the threshold fixed as the vector layer improves.
