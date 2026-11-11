#!/usr/bin/env python3
"""Matched baselines for the NaN16 triangle-shape model.

The raw model scores and all corpus labels come from the same N16TRI/1 audit
stream. This evaluates four controls on the exact same split:

* constant-majority
* source-prior confidence
* deterministic random
* shape-only score (no relation/global bank)

The raw model remains the guest output; this script only reads persisted scores.
"""
from __future__ import annotations
import argparse, csv, hashlib, json, math
from pathlib import Path
from typing import Iterable

POS = {"positive", "inverse"}


def auc(scores: list[float], labels: list[int]) -> float:
    pairs = sorted(zip(scores, labels), key=lambda x: x[0])
    pos = sum(labels)
    neg = len(labels) - pos
    if not pos or not neg:
        return 0.5
    rank = 0.0
    i = 0
    while i < len(pairs):
        j = i
        while j + 1 < len(pairs) and pairs[j + 1][0] == pairs[i][0]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            if pairs[k][1]:
                rank += avg
        i = j + 1
    return (rank - pos * (pos + 1) / 2.0) / (pos * neg)


def best_threshold(scores: list[float], labels: list[int]) -> float:
    values = sorted(set(scores))
    best = (0.5, 0.0)
    for t in values:
        tp = sum(1 for s, y in zip(scores, labels) if s >= t and y)
        fn = sum(1 for s, y in zip(scores, labels) if s < t and y)
        tn = sum(1 for s, y in zip(scores, labels) if s < t and not y)
        fp = sum(1 for s, y in zip(scores, labels) if s >= t and not y)
        ba = 0.5 * (tp / max(1, tp + fn) + tn / max(1, tn + fp))
        if ba > best[0] + 1e-12:
            best = (ba, float(t))
    return best[1]


def metrics(scores: list[float], labels: list[int], threshold: float) -> dict:
    tp = sum(1 for s, y in zip(scores, labels) if s >= threshold and y)
    fn = sum(1 for s, y in zip(scores, labels) if s < threshold and y)
    tn = sum(1 for s, y in zip(scores, labels) if s < threshold and not y)
    fp = sum(1 for s, y in zip(scores, labels) if s >= threshold and not y)
    precision = tp / max(1, tp + fp)
    recall = tp / max(1, tp + fn)
    return {"n": len(labels), "positives": sum(labels),
            "threshold": threshold, "auc": auc(scores, labels),
            "balanced_accuracy": 0.5 * (tp / max(1, tp + fn) + tn / max(1, tn + fp)),
            "precision": precision,
            "recall": recall,
            "f1": 2 * precision * recall / max(1e-12, precision + recall),
            "tp": tp, "fp": fp, "tn": tn, "fn": fn}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scores", type=Path)
    ap.add_argument("--out", type=Path, default=Path("state/relation_triangle/matched_baseline.json"))
    args = ap.parse_args()
    rows = []
    with args.scores.open(newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row.get("split") not in {"train", "valid", "test"}:
                continue
            label = 1 if row.get("label") in POS else 0
            rows.append((row["split"], row["relation"], label,
                         float(row.get("score", "0")) / 65536.0,
                         float(row.get("confidence", "0")) / 65535.0,
                         float(row.get("global_score", "0")) / 65536.0,
                         float(row.get("shape_score", "0")) / 65536.0,
                         row.get("provenance", "")))
    if not rows:
        raise SystemExit("no scored rows")
    train = [r for r in rows if r[0] == "train"]
    valid = [r for r in rows if r[0] == "valid"]
    test = [r for r in rows if r[0] == "test"]
    if not train or not valid or not test:
        raise SystemExit("scores must contain train/valid/test")
    # Deterministic random score from provenance digest.
    def random_score(prov: str) -> float:
        h = hashlib.sha256(prov.encode()).digest()
        return int.from_bytes(h[:4], "little") / 2**32
    # Majority by train label.
    majority = 1 if sum(r[2] for r in train) * 2 >= len(train) else 0
    baselines = {
        "constant_majority": [float(majority)] * len(test),
        "source_prior": [r[4] for r in test],
        "deterministic_random": [random_score(r[7]) for r in test],
        "shape_only": [r[6] for r in test],
        "raw_global_model": [r[5] for r in test],
    }
    test_labels = [r[2] for r in test]
    out = {"schema": "nanlm.matched-baseline/1", "scores": str(args.scores),
           "rows": {"train": len(train), "valid": len(valid), "test": len(test)},
           "positive_rate": {"train": sum(r[2] for r in train)/len(train),
                              "valid": sum(r[2] for r in valid)/len(valid),
                              "test": sum(r[2] for r in test)/len(test)},
           "baselines": {}}
    valid_scores = {
        "constant_majority": [float(majority)] * len(valid),
        "source_prior": [r[4] for r in valid],
        "deterministic_random": [random_score(r[7]) for r in valid],
        "shape_only": [r[6] for r in valid],
        "raw_global_model": [r[5] for r in valid],
    }
    valid_labels = [r[2] for r in valid]
    for name, scores in baselines.items():
        t = best_threshold(valid_scores[name], valid_labels)
        out["baselines"][name] = metrics(scores, test_labels, t)
    args.out.write_text(json.dumps(out, indent=2) + "\n")
    print(json.dumps(out, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
