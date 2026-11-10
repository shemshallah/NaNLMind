#!/usr/bin/env python3
"""Validate the chunked raw phase-train metric stream and best checkpoint."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    prefix = Path(sys.argv[1] if len(sys.argv) > 1 else "state/phase_train")
    metrics_path = Path(str(prefix) + ".metrics.jsonl")
    summary_path = Path(str(prefix) + ".metrics.json")
    if not metrics_path.exists() or not summary_path.exists():
        print(f"missing {metrics_path} or {summary_path}", file=sys.stderr)
        return 1
    rows = []
    for line in metrics_path.read_text().splitlines():
        if line.strip():
            rows.append(json.loads(line))
    if len(rows) < 2:
        print("phase-train needs at least two metric steps", file=sys.stderr)
        return 1
    for row in rows:
        if int(row.get("eval_windows", 0)) <= 0:
            print("phase-train has no held-out windows", file=sys.stderr)
            return 1
        if float(row.get("eval_mean_l1_q16", -1)) < 0:
            print("phase-train eval L1 is negative", file=sys.stderr)
            return 1
        hit = float(row.get("probe_hit_rate", -1))
        if not 0.0 <= hit <= 1.0:
            print("phase-train probe hit rate out of range", file=sys.stderr)
            return 1
        if int(row.get("matrix_nonzero", 0)) <= 0:
            print("phase-train matrix is empty", file=sys.stderr)
            return 1
    summary = json.loads(summary_path.read_text())
    if summary.get("schema") != "nanlm.phase-train-metrics/1":
        print("unexpected phase-train summary schema", file=sys.stderr)
        return 1
    best = min(float(row["eval_mean_l1_q16"]) for row in rows)
    if abs(float(summary["best_eval_mean_l1_q16"]) - best) > 1e-6:
        print("phase-train best held-out metric mismatch", file=sys.stderr)
        return 1
    print(
        "PHASE_TRAIN PASS "
        f"steps={len(rows)} train_windows={summary.get('train_windows')} "
        f"eval_windows={summary.get('eval_windows')} "
        f"codewords={summary.get('codewords')} "
        f"best_step={summary.get('best_step')} "
        f"best_eval_l1={summary.get('best_eval_mean_l1_q16')} "
        f"best_hot_triads={summary.get('best_hot_triads')} "
        f"best_field_hot={summary.get('best_field_hot')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
