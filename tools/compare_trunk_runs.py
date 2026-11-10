#!/usr/bin/env python3
"""Compare native trunk-train step logs with the Python reference JSON."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

STEP = re.compile(
    r"trunk_step epoch=(\d+) step=(\d+) train_loss=([0-9.eE+-]+) "
    r"train_accuracy=([0-9.eE+-]+)")
FULL = re.compile(
    r"trunk_full_eval samples=(\d+) loss=([0-9.eE+-]+) "
    r"accuracy=([0-9.eE+-]+) seconds=([0-9.eE+-]+)")


def parse_native(path: Path) -> tuple[list[dict], dict | None]:
    rows = []
    full = None
    for line in path.read_text(encoding="utf-8").splitlines():
        match = STEP.search(line)
        if match:
            rows.append({
                "epoch": int(match.group(1)),
                "step": int(match.group(2)),
                "train_loss": float(match.group(3)),
                "train_accuracy": float(match.group(4)),
            })
            continue
        match = FULL.search(line)
        if match:
            full = {
                "samples": int(match.group(1)),
                "loss": float(match.group(2)),
                "accuracy": float(match.group(3)),
                "seconds": float(match.group(4)),
            }
    return rows, full


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("native_log", type=Path)
    ap.add_argument("reference_json", type=Path)
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()
    native, native_full = parse_native(args.native_log)
    reference = json.loads(args.reference_json.read_text(encoding="utf-8"))
    ref = {(r["epoch"], r["step"]): r for r in reference["steps"]}
    rows = []
    for row in native:
        ref_row = ref.get((row["epoch"], row["step"]))
        if ref_row is None:
            continue
        rows.append({
            "epoch": row["epoch"],
            "step": row["step"],
            "native_loss": row["train_loss"],
            "reference_loss": ref_row["train_loss"],
            "loss_abs_diff": abs(row["train_loss"] - ref_row["train_loss"]),
            "native_accuracy": row["train_accuracy"],
            "reference_accuracy": ref_row["train_accuracy"],
            "accuracy_abs_diff": abs(row["train_accuracy"] - ref_row["train_accuracy"]),
        })
    max_loss = max((r["loss_abs_diff"] for r in rows), default=0.0)
    max_acc = max((r["accuracy_abs_diff"] for r in rows), default=0.0)
    reference_full = reference.get("full_eval")
    full_diff = None
    if native_full is not None and reference_full is not None:
        full_diff = {
            "loss_abs_diff": abs(native_full["loss"] - reference_full["loss"]),
            "accuracy_abs_diff": abs(
                native_full["accuracy"] - reference_full["accuracy"]),
        }
    result = {
        "schema": "nanlm.trunk-compare/1",
        "rows": len(rows),
        "max_loss_abs_diff": max_loss,
        "max_accuracy_abs_diff": max_acc,
        "native_full_eval": native_full,
        "reference_full_eval": reference_full,
        "full_eval_abs_diff": full_diff,
        "steps": rows,
    }
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.write_text(text, encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
