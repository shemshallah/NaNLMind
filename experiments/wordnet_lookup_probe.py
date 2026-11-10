#!/usr/bin/env python3
"""Probe context-indexed class memory: a native-friendly n-gram readout.

Instead of a dense feature dot product, each context hashes to one bucket and
the 255 class scores live in a table indexed by that bucket. This is the same
kind of sparse memory the 255-head/field topology can hold, and it is much
cheaper than a wide dense readout.

Host experiment only; it measures held-out and same-corpus accuracy.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


def hash_context(line: bytes, k: int, buckets: int) -> int:
    h = 2166136261
    for b in line[8 - k:8]:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h % buckets


def load(corpus: Path, k: int, buckets: int, max_lines: int = 0):
    lines = corpus.read_bytes().splitlines()
    if max_lines:
        lines = lines[:max_lines]
    usable = [line for line in lines if len(line) >= 9 and line[8] < 255]
    x = np.array([hash_context(line, k, buckets) for line in usable], dtype=np.int64)
    y = np.array([line[8] for line in usable], dtype=np.int64)
    return x, y


def train_hier(x, y, buckets, epochs, lr, seed, n_train):
    rng = np.random.default_rng(seed)
    hi = y >> 4
    lo = y & 15
    w_hi = np.zeros((16, buckets), dtype=np.float32)
    w_lo = np.zeros((16, 16, buckets), dtype=np.float32)
    order = np.arange(n_train)
    for epoch in range(1, epochs + 1):
        rng.shuffle(order)
        for i in order:
            b = x[i]
            g = hi[i]
            # high head update, all 16 classes at this bucket
            z = w_hi[:, b]
            z -= z.max()
            p = np.exp(z)
            p /= p.sum()
            p[g] -= 1.0
            w_hi[:, b] -= lr * p
            # low head conditioned on true high, 16 classes at this bucket
            z = w_lo[g, :, b]
            z -= z.max()
            p = np.exp(z)
            p /= p.sum()
            p[lo[i]] -= 1.0
            w_lo[g, :, b] -= lr * p
    return w_hi, w_lo


def evaluate(x, y, w_hi, w_lo):
    hi = y >> 4
    lo = y & 15
    n = len(y)
    ph = np.zeros(n, dtype=np.int64)
    pl = np.zeros(n, dtype=np.int64)
    for i in range(n):
        b = x[i]
        ph[i] = int(np.argmax(w_hi[:, b]))
        pl[i] = int(np.argmax(w_lo[ph[i], :, b]))
    exact = (ph == hi) & (pl == lo)
    return {
        "hi": 100.0 * (ph == hi).mean(),
        "low_given_pred_high": 100.0 * (pl == lo).mean(),
        "exact": 100.0 * exact.mean(),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path, nargs="?", default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--buckets", type=int, default=4096)
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--lr", type=float, default=0.5)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--train-fraction", type=float, default=0.8)
    ap.add_argument("--max-lines", type=int, default=0)
    args = ap.parse_args()
    x, y = load(args.corpus, args.k, args.buckets, args.max_lines)
    n_train = int(len(y) * args.train_fraction)
    # Random split by line, not by contiguous gloss block.
    rng = np.random.default_rng(99)
    order = rng.permutation(len(y))
    x, y = x[order], y[order]
    w_hi, w_lo = train_hier(x, y, args.buckets, args.epochs, args.lr,
                            args.seed, n_train)
    print("k", args.k, "buckets", args.buckets,
          "train", evaluate(x[:n_train], y[:n_train], w_hi, w_lo),
          "heldout", evaluate(x[n_train:], y[n_train:], w_hi, w_lo))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
