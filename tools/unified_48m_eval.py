#!/usr/bin/env python3
"""Finite-candidate language metrics on the unified 48M runtime.

This is the language-model evaluation surface: each panel row has a context,
a bounded candidate list, and a target word.  The frozen 48M P0 and the native
candidate-normalized P* are scored on the same rows.  It is not a
full-vocabulary 48M argmax and refuses rows whose target is outside the
declared candidate set.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

from decoder48m_candidate import frozen_r25_emitter  # noqa: E402
from unified_48m_runtime import (  # noqa: E402
    normalize_candidate_scores,
    run_native_batch,
    run_native_emit,
)


def score_panel(emitter, records, native_weights_by_index) -> dict:
    """Score a finite candidate panel without changing the frozen model."""
    if not isinstance(records, list) or not records:
        raise ValueError("nonempty panel records required")
    if len(records) != len(native_weights_by_index):
        raise ValueError("one native weight map per panel row required")
    baseline_bits = 0.0
    candidate_bits = 0.0
    top1 = top5 = 0
    candidate_mass = 0.0
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            raise ValueError("panel row must be an object")
        context = record.get("context")
        candidates = record.get("candidates")
        target = record.get("target")
        if not isinstance(context, str) or not context.strip():
            raise ValueError("panel row context required")
        if not isinstance(candidates, list) or not candidates:
            raise ValueError("panel row candidates required")
        if not isinstance(target, str) or target not in candidates:
            raise ValueError("panel target must be in the candidate list")
        weights = native_weights_by_index[index]
        result = normalize_candidate_scores(
            emitter, context, weights, candidates)
        rows = {row["word"]: row for row in result["rows"]}
        target_row = rows[target]
        p0 = target_row["baseline_probability"]
        p1 = target_row["candidate_probability"]
        if not (0.0 < p0 <= 1.0 and 0.0 < p1 <= 1.0):
            raise ValueError("panel probability outside (0,1]")
        baseline_bits += -math.log2(p0)
        candidate_bits += -math.log2(p1)
        ranked = [row["word"] for row in result["top_k"]]
        if ranked and ranked[0] == target:
            top1 += 1
        if target in ranked[:5]:
            top5 += 1
        candidate_mass += sum(row["candidate_probability"]
                              for row in result["rows"])
    n = len(records)
    return {
        "positions": n,
        "baseline_exact_word_bpb": baseline_bits / n,
        "candidate_exact_word_bpb": candidate_bits / n,
        "bpb_improvement": (baseline_bits - candidate_bits) / n,
        "candidate_top1": top1 / n,
        "candidate_top5": top5 / n,
        "mean_candidate_mass": candidate_mass / n,
        "finite_candidate_scope": True,
        "full_vocabulary_scope": False,
        "frozen_model_modified": False,
        "tensor_promotion": False,
    }


def load_panel(path: Path) -> list:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or not isinstance(
            payload.get("records"), list):
        raise ValueError("panel must contain a records array")
    return payload["records"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root", type=Path, required=True)
    parser.add_argument("--panel", type=Path, required=True)
    parser.add_argument("--native-mode", choices=("batch", "bridge"),
                        default="batch")
    parser.add_argument("--native-batch", type=Path,
                        default=ROOT / "build" / "nanlm48m-native-batch")
    parser.add_argument("--native-emit", type=Path,
                        default=ROOT / "build" / "nanlm48m-native-emit")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.archive_root.is_dir():
        print("unified_48m_eval_error: original frozen 48M archive is required; "
              "no surrogate metric is produced", file=sys.stderr)
        return 2
    try:
        records = load_panel(args.panel)
        emitter = frozen_r25_emitter(args.archive_root)
        weights = []
        for record in records:
            context = record["context"]
            candidates = record["candidates"]
            if args.native_mode == "bridge":
                receipt = run_native_emit(
                    args.native_emit, context, candidates)
            else:
                receipt = run_native_batch(
                    args.native_batch, context, candidates)
            weights.append(receipt["native_log_weights"])
        metrics = score_panel(emitter, records, weights)
    except (KeyError, OSError, ValueError, RuntimeError) as exc:
        print(f"unified_48m_eval_error: {exc}", file=sys.stderr)
        return 1
    result = {
        "schema": "nanlm.unified-48m-eval/1",
        "archive_root": str(args.archive_root),
        "native_mode": args.native_mode,
        **metrics,
        "notes": [
            "All probabilities are exact frozen-48M values over the declared "
            "finite candidate set; full-vocabulary top-k is not claimed.",
            "No checkpoint or active tensor is modified.",
        ],
    }
    encoded = json.dumps(result, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
