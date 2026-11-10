#!/usr/bin/env python3
"""Run the native WordNet context-memory held-out benchmark and write JSON.

Only orchestration lives here: the native binary owns all table arithmetic.
The script runs the greedy baseline, then reloads the same checkpoint in
joint head-pair routing mode so the comparison isolates the readout kernel.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path

EVAL_RE = re.compile(
    r"^(ctx_eval|ctx_full_eval) samples=(\d+) loss=(\S+) accuracy=(\S+)"
    r"(?: seconds=(\S+))?(?: epoch=(\d+))?$")
TABLES_RE = re.compile(
    r"^context_tables buckets=(\d+) train_samples=(\d+) eval_samples=(\d+)"
    r" joint_readout=(\d+)")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def parse(stdout: str) -> dict:
    evals = []
    tables = {}
    for line in stdout.splitlines():
        m = EVAL_RE.match(line.strip())
        if m:
            evals.append({
                "tag": m.group(1),
                "samples": int(m.group(2)),
                "loss": float(m.group(3)),
                "accuracy_percent": float(m.group(4)),
                "seconds": float(m.group(5)) if m.group(5) else None,
                "epoch": int(m.group(6)) if m.group(6) else None,
            })
        t = TABLES_RE.match(line.strip())
        if t:
            tables = {"buckets": int(t.group(1)),
                      "train_samples": int(t.group(2)),
                      "eval_samples": int(t.group(3)),
                      "joint_readout": int(t.group(4))}
    final = next((e for e in reversed(evals) if e["tag"] == "ctx_full_eval"), None)
    return {"tables": tables, "evals": evals, "final": final}


def run(cmd: list[str], cwd: Path) -> dict:
    proc = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if proc.returncode != 0:
        raise SystemExit(
            f"command failed ({proc.returncode}): {' '.join(cmd)}\n"
            f"{proc.stderr[-2000:]}")
    return parse(proc.stdout)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path, default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--binary", type=Path, default=Path("build/nanlm-universal"))
    ap.add_argument("--out", type=Path,
                    default=Path("artifacts/wordnet_context_score.json"))
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--buckets", type=int, default=11456)
    ap.add_argument("--exact", type=int, default=10500)
    ap.add_argument("--lr", type=float, default=0.1)
    ap.add_argument("--fraction", type=float, default=0.8)
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[1]
    corpus = (root / args.corpus).resolve()
    binary = (root / args.binary).resolve()
    if not corpus.is_file():
        raise SystemExit(f"missing corpus: {corpus}")
    if not binary.is_file():
        raise SystemExit(f"missing native binary: {binary} (run make)")

    base_cmd = [
        str(binary), "context-train", str(corpus), "0", str(args.epochs),
        "100000", str(args.buckets), "4", str(args.lr), "1",
        str(args.fraction),
    ]
    with tempfile.TemporaryDirectory(prefix="nanlm-context-score-") as tmp:
        checkpoint = Path(tmp) / "wordnet.ctx"
        baseline = run(base_cmd + ["backoff", str(args.exact),
                                   f"save={checkpoint}"], root)
        if not checkpoint.is_file():
            raise SystemExit("baseline run did not save a checkpoint")
        checkpoint_hash = sha256(checkpoint)
        checkpoint_bytes = checkpoint.stat().st_size
        # Zero training epochs: this only re-scores the identical table with
        # the joint head-pair selection rule.
        joint = run(base_cmd[:4] + ["0"] + base_cmd[5:] +
                    ["backoffjoint", str(args.exact),
                     f"load={checkpoint}"], root)

    if baseline["final"] is None or joint["final"] is None:
        raise SystemExit("missing final evaluation in benchmark output")
    result = {
        "schema": "nanlm.context-memory-score/1",
        "runtime": "raw NaN16 table math; host orchestrates files and SHA-256",
        "corpus": {
            "path": str(args.corpus),
            "sha256": sha256(corpus),
            "bytes": corpus.stat().st_size,
        },
        "split": {"seed": 99, "train_fraction": args.fraction,
                  "train_samples": baseline["tables"].get("train_samples")},
        "config": {"buckets": args.buckets, "exact_contexts": args.exact,
                   "context_bytes": 4, "lr": args.lr, "epochs": args.epochs,
                   "route": "backoff (exact 4-byte + 3-byte FNV fallback)"},
        "baseline_greedy": baseline["final"],
        "joint_head_pair": joint["final"],
        "baseline_history": baseline["evals"],
        "joint_eval_history": joint["evals"],
        "checkpoint": {"bytes": checkpoint_bytes,
                       "sha256": checkpoint_hash},
        "delta_accuracy_points":
            joint["final"]["accuracy_percent"] -
            baseline["final"]["accuracy_percent"],
        "delta_loss": joint["final"]["loss"] - baseline["final"]["loss"],
        "note": ("joint_head_pair re-scores the identical greedy checkpoint; "
                 "it changes only the inference selection rule, not training."),
    }
    out = (root / args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "baseline": baseline["final"],
        "joint": joint["final"],
        "delta_accuracy_points": result["delta_accuracy_points"],
        "delta_loss": result["delta_loss"],
        "checkpoint_sha256": checkpoint_hash,
        "out": str(out),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
