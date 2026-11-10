#!/usr/bin/env python3
"""Quick host-side probe: can a linear readout learn the WordNet next-byte task?

This is an algorithm experiment, not the native runtime. It uses the same
frozen identity-trunk feature as experiments/native_trunk_reference.py.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


def feature(tokens: np.ndarray) -> np.ndarray:
    q = tokens[-1]
    scores = tokens @ q
    scores = np.exp(scores - scores.max()).astype(np.float32)
    alpha = (scores / scores.sum()).astype(np.float32)
    context = alpha @ tokens
    h = (tokens[-1] + context).astype(np.float32)
    return (h + np.tanh(h)).astype(np.float32)


def load(corpus: Path, max_lines: int = 0):
    lines = corpus.read_bytes().splitlines()
    if max_lines:
        lines = lines[:max_lines]
    usable = [line for line in lines if len(line) >= 9 and line[8] < 255]
    x = np.zeros((len(usable), 8), dtype=np.float32)
    y = np.zeros(len(usable), dtype=np.int64)
    for i, line in enumerate(usable):
        tokens = np.zeros((8, 8), dtype=np.float32)
        for j in range(8):
            tokens[j, line[j] & 7] = 1.0
        x[i] = feature(tokens)
        y[i] = line[8]
    return x, y


def evaluate(weights, x, y, observed):
    scores = x @ weights.T
    target_scores = scores[np.arange(len(y)), y]
    mask = scores.copy()
    mask[np.arange(len(y)), y] = -np.inf
    best = mask.max(axis=1)
    correct = target_scores > best
    loss = np.maximum(0.0, best - target_scores + 1.0)
    out = {
        "acc255": 100.0 * correct.mean(),
        "loss255": float(loss.mean()),
    }
    obs = scores[:, observed]
    obs_target = np.searchsorted(observed, y)
    target_obs = obs[np.arange(len(y)), obs_target]
    obs_mask = obs.copy()
    obs_mask[np.arange(len(y)), obs_target] = -np.inf
    best_obs = obs_mask.max(axis=1)
    correct_obs = target_obs > best_obs
    out["acc_observed"] = 100.0 * correct_obs.mean()
    out["classes_observed"] = int(len(observed))
    return out


def train_softmax(x, y, epochs, lr, batch, seed, observed):
    rng = np.random.default_rng(seed)
    n, d = x.shape
    w = np.zeros((255, d), dtype=np.float32)
    b = np.zeros(255, dtype=np.float32)
    for epoch in range(1, epochs + 1):
        order = rng.permutation(n)
        for start in range(0, n, batch):
            idx = order[start:start + batch]
            logits = x[idx] @ w.T + b
            logits -= logits.max(axis=1, keepdims=True)
            p = np.exp(logits)
            p /= p.sum(axis=1, keepdims=True)
            grad = p
            grad[np.arange(len(idx)), y[idx]] -= 1.0
            grad /= len(idx)
            w -= (lr * (grad.T @ x[idx])).astype(np.float32)
            b -= (lr * grad.sum(axis=0)).astype(np.float32)
        print("softmax", epoch, evaluate(w, x, y, observed), flush=True)
    return w, b


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path, nargs="?", default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--max-lines", type=int, default=0)
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--lr", type=float, default=0.5)
    ap.add_argument("--batch", type=int, default=512)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    x, y = load(args.corpus, args.max_lines)
    observed = np.array(sorted(set(y.tolist())))
    print("samples", len(y), "observed classes", len(observed), flush=True)
    print("initial", evaluate(np.zeros((255, 8), np.float32), x, y, observed), flush=True)
    train_softmax(x, y, args.epochs, args.lr, args.batch, args.seed, observed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
