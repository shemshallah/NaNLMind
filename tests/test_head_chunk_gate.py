#!/usr/bin/env python3
"""Smoke-test the 64-slot long-chunk checkpoint gate."""
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
    binary = ROOT / "build" / "nanlm-head-chunk-gate"
    worker = ROOT / "build" / "head_worker.nan"
    if not binary.is_file() or not worker.is_file():
        print("SKIP chunk gate binary/image missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-chunk-gate-"))
    try:
        baseline = tmp / "baseline"
        candidate = tmp / "candidate"
        checkpoint(baseline, page())
        checkpoint(candidate, page())
        tokens = []
        for t in range(8):
            row = [0.0] * 128
            row[0] = 0.01 * (t + 1)
            tokens.extend(row)
        candidates = [0.0] * (2 * 128)
        (tmp / "tokens.txt").write_text(" ".join(map(str, tokens)) + "\n")
        (tmp / "candidates.txt").write_text(
            " ".join(map(str, candidates)) + "\n")
        receipt = tmp / "out.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(candidate),
             str(tmp / "tokens.txt"), "1", str(tmp / "candidates.txt"),
             "0", str(receipt)], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        report = json.loads(receipt.read_text())
        assert report["schema"] == "nanlm.head-chunk-gate/1"
        assert report["tokens"] == 8
        assert report["accepted"] is False
        assert report["host_math"] is False
        assert report["tensor_promotion"] is False
        assert len(report["baseline_state_sha256"]) == 64
        assert len(report["candidate_state_sha256"]) == 64
        assert len(report["baseline_root"]) == 64
        assert report["baseline_chunks"] == 1

        long_tokens = []
        for t in range(256):
            row = [0.0] * 128
            row[0] = 0.001 * (t + 1)
            long_tokens.extend(row)
        (tmp / "long_tokens.txt").write_text(
            " ".join(map(str, long_tokens)) + "\n")
        long_receipt = tmp / "long.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(candidate),
             str(tmp / "long_tokens.txt"), "1", str(tmp / "candidates.txt"),
             "0", str(long_receipt)], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        long_report = json.loads(long_receipt.read_text())
        assert long_report["tokens"] == 256
        assert long_report["baseline_chunks"] >= 4
        assert long_report["accepted"] is False
        print("PASS native 64-slot long-chunk gate (256-token chunk)")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
