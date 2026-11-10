#!/usr/bin/env bash
# Local parallel context-memory training jobs.
#
# HW4/HW5 are job labels only. They do not instantiate HW nodes or runner
# slots; the canonical topology still has one HW0::BS0 universe.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p state logs
wordnet_log="logs/hw4_wordnet.log"
gutenberg_log="logs/hw5_gutenberg.log"
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 3 100000 11456 4 0.1 1 0.8 backoff 10500 \
  save=state/hw4_wordnet.ctx >"$wordnet_log" 2>&1 &
wn=$!
./build/nanlm-universal context-train state/gutenberg_corpus.txt \
  0 5 100000 11456 4 0.1 1 0.8 backoff 10500 \
  save=state/hw5_gutenberg.ctx >"$gutenberg_log" 2>&1 &
gb=$!
wait "$wn" "$gb"
echo "wordnet: $wordnet_log"
echo "gutenberg: $gutenberg_log"
