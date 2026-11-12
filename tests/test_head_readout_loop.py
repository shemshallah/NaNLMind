#!/usr/bin/env python3
"""Smoke-test the native head-readout training/checkpoint loop."""
from __future__ import annotations
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def write_candidates(path: Path) -> None:
    rows = []
    first = [0.0] * 128
    first[0] = 1.0
    second = [0.0] * 128
    second[0] = -1.0
    rows = [first, second]
    path.write_text("\n".join(" ".join(map(str, row)) for row in rows) + "\n")


def write_dataset(path: Path, count: int) -> None:
    lines = []
    for _ in range(count):
        state = [0.0] * 128
        state[0] = 1.0
        lines.append(" ".join(map(str, state + [0])))
    path.write_text("\n".join(lines) + "\n")


def run(binary: Path, candidates: Path, train: Path, heldout: Path,
        lr: str, out_candidates: Path, out_json: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(binary), str(candidates), str(train), str(heldout), "8", lr,
         str(out_candidates), str(out_json)],
        cwd=ROOT, text=True, capture_output=True,
    )


def main() -> int:
    binary = ROOT / "build" / "nanlm-head-readout-loop"
    worker = ROOT / "build" / "head_worker.nan"
    if not binary.is_file() or not worker.is_file():
        print("SKIP head readout loop binary/image missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-head-readout-loop-"))
    try:
        candidates = tmp / "candidates.txt"
        train = tmp / "train.dat"
        heldout = tmp / "heldout.dat"
        write_candidates(candidates)
        write_dataset(train, 4)
        write_dataset(heldout, 2)
        updated = tmp / "updated.txt"
        receipt = tmp / "out.json"
        result = run(binary, candidates, train, heldout, "0.2",
                     updated, receipt)
        if result.returncode != 0:
            print(result.stdout)
            print(result.stderr)
            return 1
        report = json.loads(receipt.read_text())
        assert report["schema"] == "nanlm.head-readout-loop/1"
        assert report["candidate_count"] == 2
        assert report["train_samples"] == 4
        assert report["heldout_samples"] == 2
        assert report["host_math"] is False
        assert report["tensor_promotion"] is False
        assert report["accepted"] is True
        assert math.isfinite(report["baseline_heldout_nll"])
        assert math.isfinite(report["candidate_heldout_nll"])
        assert report["candidate_heldout_nll"] < report["baseline_heldout_nll"]
        assert len(report["initial_candidate_sha256"]) == 64
        assert len(report["candidate_sha256"]) == 64
        assert 0.0 <= report["candidate_top1"] <= 1.0
        assert 0.0 <= report["candidate_top5"] <= 1.0
        assert report["candidate_top1"] <= report["candidate_top5"] + 1e-12
        assert updated.is_file()

        # Zero learning rate must not pass the improvement gate.
        zero_updated = tmp / "zero-updated.txt"
        zero_receipt = tmp / "zero.json"
        result = run(binary, candidates, train, heldout, "0.0",
                     zero_updated, zero_receipt)
        if result.returncode != 0:
            print(result.stdout)
            print(result.stderr)
            return 1
        zero = json.loads(zero_receipt.read_text())
        assert zero["accepted"] is False
        print("PASS native head-readout training/checkpoint loop")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
