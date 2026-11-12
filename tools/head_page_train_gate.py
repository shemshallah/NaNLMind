#!/usr/bin/env python3
"""Single-transaction page trainer + held-out NLL gate.

1. train a candidate page checkpoint with the native final-W2 update;
2. evaluate source vs candidate through the native page gate;
3. publish the candidate checkpoint only when the gate accepts.

The trainer and gate are separate guest-native executables. This script is
orchestration only; it does not compute gradients, NLL, or tensor values.
"""
from __future__ import annotations
import argparse
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("baseline")
    ap.add_argument("train_context")
    ap.add_argument("train_target")
    ap.add_argument("head")
    ap.add_argument("lr")
    ap.add_argument("epochs")
    ap.add_argument("validation_context")
    ap.add_argument("validation_candidates")
    ap.add_argument("validation_target")
    ap.add_argument("workdir")
    ap.add_argument("accepted_dir")
    ap.add_argument("out_json")
    args = ap.parse_args(argv)

    work = Path(args.workdir)
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    candidate = work / "candidate"
    train_json = work / "train.json"
    gate_json = work / "gate.json"

    train = run([str(ROOT / "build/nanlm-head-page-train"),
                 args.baseline, args.train_context, args.train_target,
                 args.head, args.lr, args.epochs, str(candidate),
                 str(train_json)])
    if train.returncode != 0:
        print(train.stdout)
        print(train.stderr)
        return 1
    gate = run([str(ROOT / "build/nanlm-head-page-gate"),
                args.baseline, str(candidate), args.validation_context,
                args.head, args.validation_candidates,
                args.validation_target, str(gate_json)])
    if gate.returncode != 0:
        print(gate.stdout)
        print(gate.stderr)
        return 1
    gate_report = json.loads(gate_json.read_text())
    train_report = json.loads(train_json.read_text())
    accepted = bool(gate_report.get("accepted"))
    accepted_path = Path(args.accepted_dir)
    if accepted:
        if accepted_path.exists():
            shutil.rmtree(accepted_path)
        shutil.copytree(candidate, accepted_path)
    receipt = {
        "schema": "nanlm.head-page-train-gate/1",
        "accepted": accepted,
        "head": int(args.head),
        "epochs": int(args.epochs),
        "learning_rate": float(args.lr),
        "candidate_checkpoint": str(accepted_path if accepted else candidate),
        "accepted_checkpoint": str(accepted_path) if accepted else None,
        "training": train_report,
        "gate": gate_report,
        "host_math": False,
        "tensor_promotion": False,
        "transaction": "candidate is published only when the held-out NLL gate accepts",
    }
    out = Path(args.out_json)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"head_page_train_gate accepted={str(accepted).lower()} "
          f"candidate={receipt['candidate_checkpoint']} output={out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
