#!/usr/bin/env python3
"""Smoke-test the page-train + page-gate transaction."""
from __future__ import annotations
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAGIC = 0x48315233


def page() -> bytes:
    data = bytearray(1024 * 1024)
    data[0xFCC00:0xFCC04] = MAGIC.to_bytes(4, "little")
    return bytes(data)


def checkpoint(directory: Path, data: bytes) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "head-001.page").write_bytes(data)
    (directory / "manifest.txt").write_text(
        f"1 0 {hashlib.sha256(data).hexdigest()}\n")


def main() -> int:
    required = [ROOT / "build/nanlm-head-page-train",
                ROOT / "build/nanlm-head-page-gate",
                ROOT / "build/head_worker.nan"]
    if not all(p.is_file() for p in required):
        print("SKIP page train/gate binary missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-page-train-gate-"))
    try:
        baseline = tmp / "baseline"
        checkpoint(baseline, page())
        context = [0.0] * 128
        context[0] = 1.0
        target = [0.0] * 128
        candidates = [0.0] * (2 * 128)
        (tmp / "context.txt").write_text(" ".join(map(str, context)) + "\n")
        (tmp / "target.txt").write_text(" ".join(map(str, target)) + "\n")
        (tmp / "candidates.txt").write_text(
            " ".join(map(str, candidates)) + "\n")
        receipt = tmp / "receipt.json"
        run = subprocess.run(
            [str(ROOT / "tools/head_page_train_gate.py"),
             str(baseline), str(tmp / "context.txt"), str(tmp / "target.txt"),
             "1", "0.0", "1", str(tmp / "context.txt"),
             str(tmp / "candidates.txt"), "0", str(tmp / "work"),
             str(tmp / "accepted"), str(receipt)],
            cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        report = json.loads(receipt.read_text())
        assert report["schema"] == "nanlm.head-page-train-gate/1"
        assert report["accepted"] is False
        assert report["host_math"] is False
        assert report["tensor_promotion"] is False
        assert Path(report["candidate_checkpoint"]).is_dir()
        assert report["accepted_checkpoint"] is None
        assert report["training"]["page_training"] is True
        assert report["gate"]["accepted"] is False
        assert not (tmp / "accepted").exists()
        print("PASS page training + held-out gate transaction")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
