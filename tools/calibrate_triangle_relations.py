#!/usr/bin/env python3
"""Calibrate raw NaN16 triangle-contrast scores on a held-out valid split.

The C++ trainer emits ``PREFIX.scores.tsv`` with raw contrastive scores.  Those
scores are shape-bank similarities, not probabilities.  This tool fits two
monotone calibrators on the ``valid`` split and reports the untouched ``test``
split:

* Platt scaling: ``p = sigmoid(a * score_norm + b)``, fitted by Newton steps on
  log loss.
* Isotonic regression: pool-adjacent-violators (PAV), applied with linear
  interpolation between the fitted knots.

The calibrator is chosen by valid log loss.  Isotonic is only chosen when it
improves valid log loss by at least ``--isotonic-margin`` (default 0.01); the
preference for Platt keeps small valid splits from producing a jagged step
function.  Test metrics include AUC, balanced accuracy, precision/recall/F1,
confusion matrix, Brier score, log loss and expected calibration error (ECE).

The output calibrated labels are **research labels**: they are calibrated
against WordNet-derived valid rows, not a claim that the triangle score is
semantic truth.  See docs/RELATION_TRIANGLE_CORPUS.md for the full caveat.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Iterable, Sequence

try:
    import numpy as np
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit("numpy is required for calibration") from exc

POSITIVE_LABELS = {"positive", "inverse"}
RELATIONS = (
    "ISA",
    "HAS_SUBTYPE",
    "PART_OF",
    "HAS_PART",
    "CONTRADICTS",
    "ASSOCIATED",
)
SCHEMA = "nanlm.triangle-calibration/1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def sigmoid(z: np.ndarray | float) -> np.ndarray | float:
    z = np.clip(z, -60.0, 60.0)
    return 1.0 / (1.0 + np.exp(-z))


def logit(p: float) -> float:
    p = min(max(p, 1e-6), 1.0 - 1e-6)
    return math.log(p / (1.0 - p))


def fit_platt(scores: np.ndarray, labels: np.ndarray) -> tuple[float, float]:
    """Fit a 1-D logistic calibrator with Newton's method."""
    n = len(scores)
    if n == 0:
        return 0.0, 0.0
    positives = float(labels.sum())
    if positives == 0.0 or positives == n:
        prior = (positives + 0.5) / (n + 1.0)
        return 0.0, logit(prior)
    a = 1.0
    b = 0.0
    for _ in range(100):
        z = a * scores + b
        p = sigmoid(z)
        w = p * (1.0 - p)
        g0 = float(np.sum((p - labels) * scores))
        g1 = float(np.sum(p - labels))
        h00 = float(np.sum(w * scores * scores)) + 1e-9
        h01 = float(np.sum(w * scores))
        h11 = float(np.sum(w)) + 1e-9
        det = h00 * h11 - h01 * h01
        if abs(det) < 1e-18:
            break
        da = (h11 * g0 - h01 * g1) / det
        db = (-h01 * g0 + h00 * g1) / det
        # Damped update: Newton can overshoot on small or separable samples.
        step = 1.0
        for _ in range(20):
            na, nb = a - step * da, b - step * db
            np_ = sigmoid(na * scores + nb)
            new_loss = -np.mean(
                labels * np.log(np.clip(np_, 1e-12, 1.0))
                + (1.0 - labels) * np.log(np.clip(1.0 - np_, 1e-12, 1.0))
            )
            old_loss = -np.mean(
                labels * np.log(np.clip(p, 1e-12, 1.0))
                + (1.0 - labels) * np.log(np.clip(1.0 - p, 1e-12, 1.0))
            )
            if new_loss <= old_loss + 1e-12 or step < 1e-4:
                break
            step *= 0.5
        a, b = a - step * da, b - step * db
        if max(abs(step * da), abs(step * db)) < 1e-10:
            break
    return float(a), float(b)


def fit_isotonic(
    scores: np.ndarray, labels: np.ndarray
) -> tuple[np.ndarray, np.ndarray]:
    """Fit PAV isotonic regression and return increasing knots (x, p)."""
    if len(scores) == 0:
        return np.array([0.0, 1.0]), np.array([0.5, 0.5])
    order = np.argsort(scores, kind="mergesort")
    sorted_scores = scores[order]
    sorted_labels = labels[order].astype(np.float64)
    # Group exact score ties before PAV.
    unique_scores: list[float] = []
    means: list[float] = []
    weights: list[int] = []
    i = 0
    while i < len(sorted_scores):
        j = i
        while j < len(sorted_scores) and sorted_scores[j] == sorted_scores[i]:
            j += 1
        unique_scores.append(float(sorted_scores[i]))
        means.append(float(sorted_labels[i:j].mean()))
        weights.append(j - i)
        i = j
    # Each block: [sum_y, weight, first_index, last_index]
    blocks: list[list[float]] = []
    for index, (mean, weight) in enumerate(zip(means, weights)):
        blocks.append([mean * weight, float(weight), index, index])
        while len(blocks) >= 2:
            left = blocks[-2]
            right = blocks[-1]
            if left[0] / left[1] <= right[0] / right[1]:
                break
            blocks.pop()
            blocks.pop()
            blocks.append(
                [left[0] + right[0], left[1] + right[1], left[2], right[3]]
            )
    xs: list[float] = []
    ps: list[float] = []
    for total, weight, first, last in blocks:
        p = total / weight
        for index in range(int(first), int(last) + 1):
            xs.append(unique_scores[index])
            ps.append(p)
    x = np.asarray(xs, dtype=np.float64)
    p = np.asarray(ps, dtype=np.float64)
    # np.interp requires strictly increasing x.  unique_scores is strictly
    # increasing by construction, so this is already true.
    return x, p


def apply_platt(scores: np.ndarray, a: float, b: float) -> np.ndarray:
    return np.asarray(sigmoid(a * scores + b), dtype=np.float64)


def apply_isotonic(scores: np.ndarray, x: np.ndarray, p: np.ndarray) -> np.ndarray:
    return np.asarray(
        np.interp(scores, x, p, left=float(p[0]), right=float(p[-1])),
        dtype=np.float64,
    )


def auc(labels: np.ndarray, scores: np.ndarray) -> float:
    n = len(labels)
    positives = int(labels.sum())
    negatives = n - positives
    if positives == 0 or negatives == 0:
        return 0.5
    order = np.argsort(scores, kind="mergesort")
    sorted_scores = scores[order]
    ranks = np.empty(n, dtype=np.float64)
    i = 0
    while i < n:
        j = i
        while j < n and sorted_scores[j] == sorted_scores[i]:
            j += 1
        average_rank = (i + 1 + j) / 2.0
        ranks[order[i:j]] = average_rank
        i = j
    rank_sum = float(ranks[labels == 1].sum())
    return (rank_sum - positives * (positives + 1) / 2.0) / (
        positives * negatives
    )


def binary_metrics(
    labels: np.ndarray, probabilities: np.ndarray, threshold: float = 0.5
) -> dict:
    predictions = probabilities >= threshold
    tp = int(np.sum((labels == 1) & predictions))
    fp = int(np.sum((labels == 0) & predictions))
    tn = int(np.sum((labels == 0) & ~predictions))
    fn = int(np.sum((labels == 1) & ~predictions))
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    specificity = tn / (tn + fp) if (tn + fp) else 0.0
    f1 = (
        2.0 * precision * recall / (precision + recall)
        if (precision + recall)
        else 0.0
    )
    return {
        "threshold": float(threshold),
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
        "precision": precision,
        "recall": recall,
        "specificity": specificity,
        "f1": f1,
        "balanced_accuracy": 0.5 * (recall + specificity),
    }


def select_threshold(labels: np.ndarray, probabilities: np.ndarray) -> float:
    """Choose the probability threshold with the best valid balanced accuracy."""
    positives = int(labels.sum())
    negatives = int(len(labels) - positives)
    if positives == 0 or negatives == 0:
        return 0.5
    order = np.argsort(probabilities, kind="mergesort")[::-1]
    sorted_p = probabilities[order]
    sorted_y = labels[order]
    best_ba = 0.5
    best_f1 = 0.0
    best_threshold = 1.0000001  # predict all negative
    tp = 0
    fp = 0
    i = 0
    while i < len(sorted_p):
        j = i
        while j < len(sorted_p) and sorted_p[j] == sorted_p[i]:
            if sorted_y[j] == 1:
                tp += 1
            else:
                fp += 1
            j += 1
        fn = positives - tp
        tn = negatives - fp
        recall = tp / positives
        specificity = tn / negatives if negatives else 0.0
        precision = tp / (tp + fp) if (tp + fp) else 0.0
        f1 = (
            2.0 * precision * recall / (precision + recall)
            if (precision + recall)
            else 0.0
        )
        ba = 0.5 * (recall + specificity)
        threshold = float(sorted_p[i])
        better = (
            ba > best_ba + 1e-12
            or (
                abs(ba - best_ba) <= 1e-12
                and f1 > best_f1 + 1e-12
            )
            or (
                abs(ba - best_ba) <= 1e-12
                and abs(f1 - best_f1) <= 1e-12
                and abs(threshold - 0.5) < abs(best_threshold - 0.5)
            )
        )
        if better:
            best_ba = ba
            best_f1 = f1
            best_threshold = threshold
        i = j
    return float(best_threshold)


def expected_calibration_error(
    labels: np.ndarray, probabilities: np.ndarray, bins: int = 10
) -> float:
    if len(labels) == 0:
        return 0.0
    edges = np.linspace(0.0, 1.0, bins + 1)
    # Include the right edge in the final bin.
    indices = np.clip(np.digitize(probabilities, edges[1:-1]), 0, bins - 1)
    total = 0.0
    for index in range(bins):
        mask = indices == index
        count = int(mask.sum())
        if count == 0:
            continue
        confidence = float(probabilities[mask].mean())
        accuracy = float(labels[mask].mean())
        total += (count / len(labels)) * abs(accuracy - confidence)
    return float(total)


def probability_metrics(
    labels: np.ndarray,
    probabilities: np.ndarray,
    bins: int = 10,
    threshold: float = 0.5,
) -> dict:
    probabilities = np.clip(probabilities, 1e-12, 1.0 - 1e-12)
    brier = float(np.mean((probabilities - labels) ** 2)) if len(labels) else 0.0
    log_loss = (
        float(
            -np.mean(
                labels * np.log(probabilities)
                + (1.0 - labels) * np.log(1.0 - probabilities)
            )
        )
        if len(labels)
        else 0.0
    )
    result = binary_metrics(labels, probabilities, threshold)
    result.update(
        {
            "n": int(len(labels)),
            "positives": int(labels.sum()),
            "negatives": int(len(labels) - labels.sum()),
            "auc": auc(labels, probabilities),
            "brier": brier,
            "log_loss": log_loss,
            "ece": expected_calibration_error(labels, probabilities, bins),
        }
    )
    return result


def constant_prior(labels: np.ndarray) -> float:
    if len(labels) == 0:
        return 0.5
    positives = float(labels.sum())
    return (positives + 0.5) / (len(labels) + 1.0)


def calibrate_model(
    valid_scores: np.ndarray,
    valid_labels: np.ndarray,
    test_scores: np.ndarray,
    test_labels: np.ndarray,
    *,
    bins: int,
    isotonic_margin: float,
) -> dict:
    if len(valid_scores) == 0:
        prior = 0.5
        valid_p = np.full(len(valid_scores), prior)
        test_p = np.full(len(test_scores), prior)
        empty_valid = probability_metrics(valid_labels, valid_p, bins, 0.5)
        empty_test = probability_metrics(test_labels, test_p, bins, 0.5)
        empty_valid["raw_auc"] = 0.5
        empty_test["raw_auc"] = 0.5
        return {
            "chosen": "prior",
            "prior": prior,
            "threshold": 0.5,
            "platt": {"a": 0.0, "b": logit(prior)},
            "isotonic": {"knots": [[0.0, prior], [1.0, prior]]},
            "valid": empty_valid,
            "test": empty_test,
            "test_at_0.5": empty_test,
        }
    platt_a, platt_b = fit_platt(valid_scores, valid_labels)
    platt_valid = apply_platt(valid_scores, platt_a, platt_b)
    platt_test = apply_platt(test_scores, platt_a, platt_b)
    iso_x, iso_p = fit_isotonic(valid_scores, valid_labels)
    iso_valid = apply_isotonic(valid_scores, iso_x, iso_p)
    iso_test = apply_isotonic(test_scores, iso_x, iso_p)
    platt_valid_metrics = probability_metrics(valid_labels, platt_valid, bins)
    iso_valid_metrics = probability_metrics(valid_labels, iso_valid, bins)
    if iso_valid_metrics["log_loss"] < (
        platt_valid_metrics["log_loss"] - isotonic_margin
    ):
        chosen = "isotonic"
        valid_p, test_p = iso_valid, iso_test
    else:
        chosen = "platt"
        valid_p, test_p = platt_valid, platt_test
    threshold = select_threshold(valid_labels, valid_p)
    valid_metrics = probability_metrics(valid_labels, valid_p, bins, threshold)
    test_metrics = probability_metrics(test_labels, test_p, bins, threshold)
    test_half = probability_metrics(test_labels, test_p, bins, 0.5)
    raw_valid_auc = auc(valid_labels, valid_scores)
    raw_test_auc = auc(test_labels, test_scores)
    valid_metrics["raw_auc"] = raw_valid_auc
    test_metrics["raw_auc"] = raw_test_auc
    test_half["raw_auc"] = raw_test_auc
    return {
        "chosen": chosen,
        "threshold": threshold,
        "platt": {"a": platt_a, "b": platt_b},
        "isotonic": {
            "knots": [
                [float(x), float(p)] for x, p in zip(iso_x.tolist(), iso_p.tolist())
            ]
        },
        "valid": valid_metrics,
        "test": test_metrics,
        "test_at_0.5": test_half,
        "candidates": {
            "platt_valid": platt_valid_metrics,
            "isotonic_valid": iso_valid_metrics,
        },
    }


def apply_calibrator(model: dict, scores: np.ndarray) -> np.ndarray:
    chosen = model.get("chosen", "prior")
    if chosen == "platt":
        return apply_platt(scores, model["platt"]["a"], model["platt"]["b"])
    if chosen == "isotonic":
        knots = model["isotonic"]["knots"]
        x = np.asarray([k[0] for k in knots], dtype=np.float64)
        p = np.asarray([k[1] for k in knots], dtype=np.float64)
        return apply_isotonic(scores, x, p)
    return np.full(len(scores), float(model.get("prior", 0.5)))


def read_scores(path: Path) -> tuple[list[dict], list[str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        try:
            header = next(reader)
        except StopIteration as exc:
            raise SystemExit(f"empty scores file: {path}") from exc
        required = {
            "split",
            "relation",
            "label",
            "confidence",
            "relation_trained",
            "score",
            "global_score",
            "provenance",
        }
        missing = required - set(header)
        if missing:
            raise SystemExit(f"scores file missing columns: {sorted(missing)}")
        rows: list[dict] = []
        for line_no, values in enumerate(reader, 2):
            if not values:
                continue
            if len(values) != len(header):
                raise SystemExit(
                    f"{path}:{line_no}: expected {len(header)} fields, got {len(values)}"
                )
            row = dict(zip(header, values))
            row["label_binary"] = 1 if row["label"] in POSITIVE_LABELS else 0
            row["score_norm"] = float(row["score"]) / 65536.0
            row["global_score_norm"] = float(row["global_score"]) / 65536.0
            rows.append(row)
        return rows, header


def select_rows(
    rows: Sequence[dict], split: str, relation: str | None
) -> list[dict]:
    selected = []
    for row in rows:
        if row["split"] != split:
            continue
        if relation is not None and row["relation"] != relation:
            continue
        selected.append(row)
    return selected


def arrays(rows: Sequence[dict], score_key: str) -> tuple[np.ndarray, np.ndarray]:
    labels = np.asarray([row["label_binary"] for row in rows], dtype=np.float64)
    scores = np.asarray([row[score_key] for row in rows], dtype=np.float64)
    return scores, labels


def calibrate_all(
    rows: Sequence[dict], *, bins: int, isotonic_margin: float
) -> tuple[dict, dict]:
    per_relation: dict[str, dict] = {}
    for relation in RELATIONS:
        all_valid = select_rows(rows, "valid", relation)
        all_test = select_rows(rows, "test", relation)
        trained = any(
            row["relation"] == relation and row["relation_trained"] == "1"
            for row in rows
        )
        valid = [row for row in all_valid if row["relation_trained"] == "1"]
        test = [row for row in all_test if row["relation_trained"] == "1"]
        if not trained:
            prior = 0.5
            per_relation[relation] = {
                "trained": False,
                "valid_rows": len(all_valid),
                "test_rows": len(all_test),
                "chosen": "untrained",
                "prior": prior,
                "platt": {"a": 0.0, "b": logit(prior)},
                "isotonic": {"knots": [[0.0, prior], [1.0, prior]]},
                "valid": probability_metrics(
                    np.asarray([], dtype=np.float64),
                    np.asarray([], dtype=np.float64),
                    bins,
                ),
                "test": probability_metrics(
                    np.asarray([], dtype=np.float64),
                    np.asarray([], dtype=np.float64),
                    bins,
                ),
            }
            continue
        valid_scores, valid_labels = arrays(valid, "score_norm")
        test_scores, test_labels = arrays(test, "score_norm")
        per_relation[relation] = {
            "trained": True,
            "valid_rows": len(valid),
            "test_rows": len(test),
            "valid_rows_total": len(all_valid),
            "test_rows_total": len(all_test),
            **calibrate_model(
                valid_scores,
                valid_labels,
                test_scores,
                test_labels,
                bins=bins,
                isotonic_margin=isotonic_margin,
            ),
        }
    global_valid = select_rows(rows, "valid", None)
    global_test = select_rows(rows, "test", None)
    global_scores, global_labels = arrays(global_valid, "global_score_norm")
    global_test_scores, global_test_labels = arrays(
        global_test, "global_score_norm"
    )
    global_model = {
        "valid_rows": len(global_valid),
        "test_rows": len(global_test),
        **calibrate_model(
            global_scores,
            global_labels,
            global_test_scores,
            global_test_labels,
            bins=bins,
            isotonic_margin=isotonic_margin,
        ),
    }
    return per_relation, global_model


def write_calibrated_tsv(
    rows: Sequence[dict],
    per_relation: dict,
    global_model: dict,
    path: Path,
) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
                "split",
                "relation",
                "label",
                "confidence",
                "score",
                "global_score",
                "relation_model",
                "platt_p",
                "isotonic_p",
                "calibrated_p",
                "calibrated_threshold",
                "calibrated_label",
                "global_p",
                "global_threshold",
                "global_label",
                "provenance",
            ]
        )
        for row in rows:
            if row["split"] == "train":
                continue
            relation_model = per_relation.get(row["relation"])
            if relation_model is None:
                relation_model = {
                    "chosen": "prior",
                    "prior": 0.5,
                    "threshold": 0.5,
                }
            relation_threshold = float(relation_model.get("threshold", 0.5))
            global_threshold = float(global_model.get("threshold", 0.5))
            score = np.asarray([row["score_norm"]], dtype=np.float64)
            global_score = np.asarray(
                [row["global_score_norm"]], dtype=np.float64
            )
            platt_p = float(
                apply_platt(
                    score,
                    relation_model.get("platt", {}).get("a", 0.0),
                    relation_model.get("platt", {}).get("b", 0.0),
                )[0]
            )
            knots = relation_model.get("isotonic", {}).get("knots", [[0.0, 0.5], [1.0, 0.5]])
            iso_x = np.asarray([k[0] for k in knots], dtype=np.float64)
            iso_p = np.asarray([k[1] for k in knots], dtype=np.float64)
            isotonic_p = float(apply_isotonic(score, iso_x, iso_p)[0])
            calibrated_p = float(apply_calibrator(relation_model, score)[0])
            global_p = float(apply_calibrator(global_model, global_score)[0])
            writer.writerow(
                [
                    row["split"],
                    row["relation"],
                    row["label"],
                    row["confidence"],
                    row["score"],
                    row["global_score"],
                    relation_model.get("chosen", "prior"),
                    f"{platt_p:.9f}",
                    f"{isotonic_p:.9f}",
                    f"{calibrated_p:.9f}",
                    f"{relation_threshold:.9f}",
                    1 if calibrated_p >= relation_threshold else 0,
                    f"{global_p:.9f}",
                    f"{global_threshold:.9f}",
                    1 if global_p >= global_threshold else 0,
                    row["provenance"],
                ]
            )


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "scores", type=Path, nargs="?", help="PREFIX.scores.tsv from the trainer"
    )
    parser.add_argument(
        "prefix",
        type=Path,
        nargs="?",
        default=Path("state/triangle_contrast"),
        help="output prefix (default: state/triangle_contrast)",
    )
    parser.add_argument("--bins", type=int, default=10, help="ECE bins")
    parser.add_argument(
        "--isotonic-margin",
        type=float,
        default=0.01,
        help="valid log-loss improvement required to choose isotonic over Platt",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run a synthetic calibration smoke test and exit",
    )
    return parser.parse_args(argv)


def self_test() -> int:
    rng = np.random.default_rng(20261110)
    n = 2000
    labels = rng.integers(0, 2, size=n).astype(np.float64)
    scores = np.where(
        labels == 1,
        rng.normal(0.72, 0.12, size=n),
        rng.normal(0.38, 0.14, size=n),
    )
    scores = np.clip(scores, 0.0, 1.0)
    # Use a monotone but distorted score so calibration has work to do.
    distorted = scores**2
    valid = slice(0, 1000)
    test = slice(1000, n)
    model = calibrate_model(
        distorted[valid],
        labels[valid],
        distorted[test],
        labels[test],
        bins=10,
        isotonic_margin=0.01,
    )
    assert model["chosen"] in ("platt", "isotonic"), model["chosen"]
    assert model["test"]["n"] == 1000
    assert 0.0 <= model["test"]["auc"] <= 1.0
    assert model["test"]["ece"] >= 0.0
    assert model["test"]["brier"] >= 0.0
    # Calibration should improve Brier/log loss over the raw distorted score.
    raw = probability_metrics(labels[test], distorted[test], 10)
    assert model["test"]["brier"] <= raw["brier"] + 1e-9, (model, raw)
    print(
        "self-test PASS chosen=%s test_auc=%.4f raw_brier=%.4f calibrated_brier=%.4f "
        "raw_ece=%.4f calibrated_ece=%.4f"
        % (
            model["chosen"],
            model["test"]["auc"],
            raw["brier"],
            model["test"]["brier"],
            raw["ece"],
            model["test"]["ece"],
        )
    )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.self_test:
        return self_test()
    if args.scores is None:
        print("scores path is required", file=sys.stderr)
        return 2
    scores_path = args.scores
    if not scores_path.is_file():
        print(f"scores file not found: {scores_path}", file=sys.stderr)
        return 2
    rows, header = read_scores(scores_path)
    if not rows:
        print("scores file has no rows", file=sys.stderr)
        return 3
    per_relation, global_model = calibrate_all(
        rows, bins=args.bins, isotonic_margin=args.isotonic_margin
    )
    prefix = args.prefix
    if prefix.parent and not prefix.parent.exists():
        prefix.parent.mkdir(parents=True, exist_ok=True)
    calibrated_path = Path(str(prefix) + ".calibrated.tsv")
    report_path = Path(str(prefix) + ".calibration.json")
    write_calibrated_tsv(rows, per_relation, global_model, calibrated_path)
    report = {
        "schema": SCHEMA,
        "scores": str(scores_path),
        "scores_sha256": sha256_file(scores_path),
        "score_columns": header,
        "rows": len(rows),
        "splits": dict(Counter(row["split"] for row in rows)),
        "labels": dict(Counter(row["label"] for row in rows)),
        "relations": dict(Counter(row["relation"] for row in rows)),
        "bins": args.bins,
        "isotonic_margin": args.isotonic_margin,
        "method_selection": (
            "choose isotonic only when valid log loss improves by at least "
            "the isotonic margin; otherwise choose Platt"
        ),
        "per_relation": per_relation,
        "global": global_model,
        "calibrated_labels": str(calibrated_path),
        "notes": [
            "calibrators are fitted on valid only; test metrics are held out",
            "the raw score is a shape-bank similarity, not semantic truth",
            "calibrated labels are research labels bound to the WordNet-derived corpus",
            "train rows are intentionally omitted from the calibrated TSV",
        ],
    }
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        "triangle_calibration rows=%d calibrated=%s report=%s global_test_auc=%.4f "
        "global_test_ece=%.4f global_test_brier=%.4f"
        % (
            len(rows),
            calibrated_path,
            report_path,
            global_model["test"]["auc"],
            global_model["test"]["ece"],
            global_model["test"]["brier"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
