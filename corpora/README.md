# NaNLMind corpora

This directory is the in-repository, small-corpus intake area for native
training smoke tests and schema examples. Large external bundles stay under
`NaNROUTER/corpora/` or release storage.

## wordlists/google-10000-english

Normalized one-word-per-line corpus derived from the
`wordlist-google-10000-english` release.

```text
google-10000-english.txt          10,000 words
google-10000-english.train.txt     9,000 words
google-10000-english.heldout.txt   1,000 words
```

```sh
./build/nanlm-universal phase-train \
  corpora/wordlists/google-10000-english.train.txt 2000 8 32 2000 \
  state/corpora_phase corpora/wordlists/google-10000-english.heldout.txt
```
