#!/usr/bin/env python3
"""Conditional hierarchical readout probe: P(high nibble) * P(low | high)."""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from experiments.wordnet_feature_probe import build_features
from experiments.wordnet_hier_probe import softmax_head


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path, nargs="?", default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--variant", default="nibble4")
    ap.add_argument("--epochs", type=int, default=5)
    ap.add_argument("--lr", type=float, default=0.5)
    ap.add_argument("--batch", type=int, default=1024)
    args = ap.parse_args()
    x, y = build_features(args.corpus, args.variant)
    hi = y >> 4
    lo = y & 15
    w_hi = softmax_head(x, hi, 16, args.epochs, args.lr, args.batch, 1)
    low_heads = []
    for group in range(16):
        mask = hi == group
        if mask.sum() < 16:
            low_heads.append(None)
            continue
        low_heads.append(softmax_head(
            x[mask], lo[mask], 16, args.epochs, args.lr,
            min(args.batch, int(mask.sum())), 100 + group))
    score_hi = x @ w_hi.T
    pred_hi = score_hi.argmax(axis=1)
    pred_lo = np.zeros(len(y), dtype=np.int64)
    for group in range(16):
        mask = pred_hi == group
        if mask.any():
            if low_heads[group] is None:
                pred_lo[mask] = 0
            else:
                pred_lo[mask] = (x[mask] @ low_heads[group].T).argmax(axis=1)
    exact = (pred_hi == hi) & (pred_lo == lo)
    true_lo = np.zeros(len(y), dtype=np.int64)
    for group in range(16):
        mask = hi == group
        if mask.any():
            if low_heads[group] is None:
                true_lo[mask] = 0
            else:
                true_lo[mask] = (x[mask] @ low_heads[group].T).argmax(axis=1)
    print(args.variant, {
        "hi": 100.0 * (pred_hi == hi).mean(),
        "low_conditional_pred_high": 100.0 * (pred_lo[hi == pred_hi] == lo[hi == pred_hi]).mean(),
        "low_conditional_true_high": 100.0 * (true_lo == lo).mean(),
        "exact": 100.0 * exact.mean(),
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
