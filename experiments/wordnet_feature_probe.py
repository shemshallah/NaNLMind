#!/usr/bin/env python3
"""Probe how much the readout feature architecture limits next-byte learning.

Host-side experiment only. It compares the current 8-lane trunk feature with
positional byte/nibble features, training a linear softmax readout with the
same 255 classes and a 20% held-out split.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


def build_features(corpus: Path, variant: str, max_lines: int = 0):
    lines = corpus.read_bytes().splitlines()
    if max_lines:
        lines = lines[:max_lines]
    usable = [line for line in lines if len(line) >= 9 and line[8] < 255]
    n = len(usable)
    if variant == "nibble1":
        dim = 32
        x = np.zeros((n, dim), dtype=np.float32)
        for i, line in enumerate(usable):
            b = line[7]
            x[i, b & 15] = 1.0
            x[i, 16 + (b >> 4)] = 1.0
    elif variant == "nibble2":
        dim = 64
        x = np.zeros((n, dim), dtype=np.float32)
        for i, line in enumerate(usable):
            for k in range(2):
                b = line[7 - k]
                x[i, k * 32 + (b & 15)] = 1.0
                x[i, k * 32 + 16 + (b >> 4)] = 1.0
    elif variant == "nibble4":
        dim = 128
        x = np.zeros((n, dim), dtype=np.float32)
        for i, line in enumerate(usable):
            for k in range(4):
                b = line[7 - k]
                x[i, k * 32 + (b & 15)] = 1.0
                x[i, k * 32 + 16 + (b >> 4)] = 1.0
    elif variant == "byte1":
        dim = 256
        x = np.zeros((n, dim), dtype=np.float32)
        for i, line in enumerate(usable):
            x[i, line[7]] = 1.0
    elif variant == "hash8":
        dim = 64
        x = np.zeros((n, dim), dtype=np.float32)
        for i, line in enumerate(usable):
            for k in range(8):
                x[i, k * 8 + (line[7 - k] & 7)] = 1.0
    else:
        raise SystemExit(f"unknown variant {variant}")
    y = np.array([line[8] for line in usable], dtype=np.int64)
    return x, y


def softmax_train(x, y, epochs, lr, batch, seed):
    rng = np.random.default_rng(seed)
    n, d = x.shape
    w = np.zeros((255, d), dtype=np.float32)
    idx = np.arange(n)
    for epoch in range(1, epochs + 1):
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
        # held-out 20% and train metrics
        scores = x @ w.T
        target = scores[np.arange(n), y]
        mask = scores.copy()
        mask[np.arange(n), y] = -np.inf
        correct = target > mask.max(axis=1)
        print(variant, "epoch", epoch,
              "train_all_acc", 100.0 * correct.mean(),
              flush=True)
    return w


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path, nargs="?", default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--variant", default="nibble1")
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--lr", type=float, default=0.5)
    ap.add_argument("--batch", type=int, default=512)
    ap.add_argument("--max-lines", type=int, default=0)
    args = ap.parse_args()
    global variant
    variant = args.variant
    x, y = build_features(args.corpus, args.variant, args.max_lines)
    print("samples", len(y), "dim", x.shape[1], "variant", args.variant, flush=True)
    softmax_train(x, y, args.epochs, args.lr, args.batch, 1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
