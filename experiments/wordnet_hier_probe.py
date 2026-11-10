#!/usr/bin/env python3
"""Probe factorized/hierarchical readout ideas on the same WordNet task."""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from experiments.wordnet_feature_probe import build_features


def softmax_head(x, y, classes, epochs, lr, batch, seed):
    rng = np.random.default_rng(seed)
    n, d = x.shape
    w = np.zeros((classes, d), dtype=np.float32)
    idx = np.arange(n)
    for _ in range(epochs):
        rng.shuffle(idx)
        for start in range(0, n, batch):
            take = idx[start:start + batch]
            logits = x[take] @ w.T
            logits -= logits.max(axis=1, keepdims=True)
            p = np.exp(logits)
            p /= p.sum(axis=1, keepdims=True)
            grad = p
            grad[np.arange(len(take)), y[take]] -= 1.0
            grad /= len(take)
            w -= (lr * (grad.T @ x[take])).astype(np.float32)
    return w


def metrics(x, y, w_hi, w_lo):
    hi = y >> 4
    lo = y & 15
    score_hi = x @ w_hi.T
    score_lo = x @ w_lo.T
    pred_hi = score_hi.argmax(axis=1)
    pred_lo = score_lo.argmax(axis=1)
    return {
        "hi": 100.0 * (pred_hi == hi).mean(),
        "lo": 100.0 * (pred_lo == lo).mean(),
        "exact": 100.0 * ((pred_hi == hi) & (pred_lo == lo)).mean(),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path)
    ap.add_argument("--variant", default="nibble4")
    ap.add_argument("--epochs", type=int, default=2)
    ap.add_argument("--lr", type=float, default=0.5)
    ap.add_argument("--batch", type=int, default=1024)
    args = ap.parse_args()
    x, y = build_features(args.corpus, args.variant)
    hi = y >> 4
    lo = y & 15
    w_hi = softmax_head(x, hi, 16, args.epochs, args.lr, args.batch, 1)
    w_lo = softmax_head(x, lo, 16, args.epochs, args.lr, args.batch, 2)
    print(args.variant, metrics(x, y, w_hi, w_lo))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
