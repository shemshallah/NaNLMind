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


def _full_step(weights, x, target, lr):
    scores = (weights @ x).astype(np.float32)
    target_score = float(scores[target])
    masked = scores.copy()
    masked[target] = -np.inf
    best_idx = int(np.argmax(masked))
    best_wrong = float(masked[best_idx])
    loss = max(0.0, best_wrong - target_score + 1.0)
    ok = target_score > best_wrong
    if loss > 0.0:
        weights[target] = (weights[target] + lr * x).astype(np.float32)
        weights[best_idx] = (weights[best_idx] - lr * x).astype(np.float32)
    return ok, loss


def _sampled_step(weights, x, target, lr, salt):
    target_score = float(weights[target] @ x)
    best_idx = target
    best_wrong = -np.inf
    for k in range(1, 9):
        idx = (target + salt + k * 37) % 255
        score = float(weights[idx] @ x)
        if score > best_wrong:
            best_wrong = score
            best_idx = idx
    loss = max(0.0, best_wrong - target_score + 1.0)
    ok = target_score > best_wrong
    if loss > 0.0:
        weights[target] = (weights[target] + lr * x).astype(np.float32)
        weights[best_idx] = (weights[best_idx] - lr * x).astype(np.float32)
    return ok, loss


def train(corpus: Path, max_lines: int = 0, epochs: int = 3,
          report_every: int = 10000, mode: str = "sampled") -> dict:
    lines = corpus.read_bytes().splitlines()
    if max_lines:
        lines = lines[:max_lines]
    usable = [line for line in lines if len(line) >= 9 and line[8] < 255]
    weights = np.zeros((255, 8), dtype=np.float32)
    global_step = 0
    steps = []
    epochs_out = []
    for epoch in range(1, epochs + 1):
        total = correct = 0
        loss_sum = 0.0
        report_total = report_correct = 0
        report_loss = 0.0
        for sample, line in enumerate(usable):
            target = int(line[8])
            tokens = np.zeros((8, 8), dtype=np.float32)
            for j in range(8):
                tokens[j, line[j] & 7] = 1.0
            x = feature(tokens)
            if mode == "full" or (sample + epoch * 7) % 16 == 0:
                ok, loss = _full_step(weights, x, target, np.float32(0.05))
            else:
                ok, loss = _sampled_step(weights, x, target, np.float32(0.05),
                                         global_step)
            global_step += 1
            total += 1
            report_total += 1
            correct += int(ok)
            report_correct += int(ok)
            loss_sum += loss
            report_loss += loss
            if report_every and report_total >= report_every:
                steps.append({
                    "epoch": epoch, "step": global_step,
                    "train_loss": report_loss / report_total,
                    "train_accuracy": 100.0 * report_correct / report_total,
                })
                report_total = report_correct = 0
                report_loss = 0.0
        if report_total:
            steps.append({
                "epoch": epoch, "step": global_step,
                "train_loss": report_loss / report_total,
                "train_accuracy": 100.0 * report_correct / report_total,
            })
        epochs_out.append({
            "epoch": epoch, "samples": total,
            "train_loss": loss_sum / max(1, total),
            "train_accuracy": 100.0 * correct / max(1, total),
        })
    # Full 255-class evaluation after training.
    eval_total = eval_correct = 0
    eval_loss = 0.0
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
        best_wrong = float(np.max(masked))
        loss = max(0.0, best_wrong - target_score + 1.0)
        eval_total += 1
        eval_correct += int(target_score > best_wrong)
        eval_loss += loss
    return {
        "schema": "nanlm.trunk-reference/1",
        "samples": len(usable),
        "epochs": epochs,
        "steps": steps,
        "epoch_metrics": epochs_out,
        "full_eval": {
            "samples": eval_total,
            "loss": eval_loss / max(1, eval_total),
            "accuracy": 100.0 * eval_correct / max(1, eval_total),
        },
    }

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path, nargs="?", default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--max-lines", type=int, default=0)
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--report-every", type=int, default=10000)
    ap.add_argument("--mode", choices=("sampled", "full"), default="sampled")
    args = ap.parse_args()
    print(json.dumps(train(args.corpus, args.max_lines, args.epochs,
                           args.report_every, args.mode), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
