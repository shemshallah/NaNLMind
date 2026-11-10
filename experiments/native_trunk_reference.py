"""Matched Python reference for the raw NaN16 trunk/readout trainer.

Identity QKV/MLP, one-hot 8-lane byte tokens, 255-class readout, local
error-corrective update, and the same one-margin hinge loss as the guest.
This is a control reference only; it is not the native runtime.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def feature(tokens: np.ndarray) -> np.ndarray:
    # tokens: [8, 8] one-hot; identity QKV, causal softmax over 8 tokens.
    q = tokens[-1]
    scores = tokens @ q
    scores = np.exp(scores - scores.max()).astype(np.float32)
    alpha = (scores / scores.sum()).astype(np.float32)
    context = alpha @ tokens
    h = (tokens[-1] + context).astype(np.float32)
    return (h + np.tanh(h)).astype(np.float32)


def train(corpus: Path, max_lines: int = 0, epochs: int = 3,
          report_every: int = 10000) -> dict:
    lines = corpus.read_bytes().splitlines()
    if max_lines:
        lines = lines[:max_lines]
    usable = [line for line in lines if len(line) >= 9 and line[8] < 255]
    weights = np.zeros((255, 8), dtype=np.float32)
    global_step = 0
    starts = []
    epochs_out = []
    for epoch in range(1, epochs + 1):
        total = correct = 0
        loss_sum = 0.0
        report_total = report_correct = 0
        report_loss = 0.0
        for line in usable:
            target = int(line[8])
            tokens = np.zeros((8, 8), dtype=np.float32)
            for j in range(8):
                tokens[j, line[j] & 7] = 1.0
            x = feature(tokens)
            scores = (weights @ x).astype(np.float32)
            target_score = float(scores[target])
            masked = scores.copy()
            masked[target] = -np.inf
            best_idx = int(np.argmax(masked))
            best_wrong = float(masked[best_idx])
            ok = target_score > best_wrong
            loss = max(0.0, best_wrong - target_score + 1.0)
            if not ok:
                lr = np.float32(0.05)
                weights[target] = (weights[target] + lr * x).astype(np.float32)
                weights[best_idx] = (weights[best_idx] - lr * x).astype(np.float32)
            global_step += 1
            total += 1
            report_total += 1
            correct += int(ok)
            report_correct += int(ok)
            loss_sum += loss
            report_loss += loss
            if report_every and report_total >= report_every:
                starts.append({
                    "epoch": epoch, "step": global_step,
                    "train_loss": report_loss / report_total,
                    "train_accuracy": 100.0 * report_correct / report_total,
                })
                report_total = report_correct = 0
                report_loss = 0.0
        if report_total:
            starts.append({
                "epoch": epoch, "step": global_step,
                "train_loss": report_loss / report_total,
                "train_accuracy": 100.0 * report_correct / report_total,
            })
        epochs_out.append({
            "epoch": epoch, "samples": total,
            "train_loss": loss_sum / max(1, total),
            "train_accuracy": 100.0 * correct / max(1, total),
        })
    return {
        "schema": "nanlm.trunk-reference/1",
        "samples": len(usable),
        "epochs": epochs,
        "steps": starts,
        "epoch_metrics": epochs_out,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path, nargs="?", default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--max-lines", type=int, default=0)
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--report-every", type=int, default=10000)
    args = ap.parse_args()
    print(json.dumps(train(args.corpus, args.max_lines, args.epochs,
                           args.report_every), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
