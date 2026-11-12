#!/usr/bin/env python3
"""Page-checkpoint validation and held-out NLL gate smoke test."""
from __future__ import annotations
import hashlib
import json
import math
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAGIC = 0x48315233


def put_bf16(page: bytearray, offset: int, value: float) -> None:
    bits = struct.unpack("<I", struct.pack("<f", value))[0]
    page[offset:offset + 2] = struct.pack("<H", bits >> 16)


def empty_page() -> bytearray:
    page = bytearray(1024 * 1024)
    page[0xFCC00:0xFCC04] = MAGIC.to_bytes(4, "little")
    return page


def identity_page() -> bytearray:
    page = empty_page()
    for layer in range(3):
        base = layer * 0x50000
        for matrix, rows, cols in (
            (0x00000, 128, 128), (0x08000, 128, 128),
            (0x10000, 128, 128), (0x18000, 128, 128),
            (0x20000, 384, 128), (0x38000, 128, 384),
        ):
            for i in range(min(rows, cols)):
                put_bf16(page, base + matrix + (i * cols + i) * 2, 1.0)
    return page


def checkpoint(directory: Path, page: bytes, generation: int) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "head-001.page"
    path.write_bytes(page)
    digest = hashlib.sha256(page).hexdigest()
    (directory / "manifest.txt").write_text(f"1 {generation} {digest}\n")


def main() -> int:
    gate = ROOT / "build" / "nanlm-head-page-gate"
    worker = ROOT / "build" / "head_worker.nan"
    batch = ROOT / "build" / "nanlm-head-worker-batch"
    if not all(p.is_file() for p in (gate, worker, batch)):
        print("SKIP page gate binary/image missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-page-gate-"))
    try:
        baseline = tmp / "baseline"
        candidate = tmp / "candidate"
        checkpoint(baseline, bytes(empty_page()), 0)
        checkpoint(candidate, bytes(identity_page()), 1)
        context = [0.0] * 128
        context[0] = 1.0
        (tmp / "context.txt").write_text(" ".join(map(str, context)) + "\n")

        # Obtain the candidate worker state, then construct a small two-candidate
        # readout from its direction (target 0) and a zero competitor.
        state_json = tmp / "state.json"
        run = subprocess.run(
            [str(batch), str(candidate), str(tmp / "context.txt"), "1",
             str(state_json)], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        state = json.loads(state_json.read_text())["selected"][0]["last_state"]
        scale = 0.001
        candidates = [x * scale for x in state] + [0.0] * 128
        (tmp / "candidates.txt").write_text(
            " ".join(map(str, candidates)) + "\n")
        receipt = tmp / "gate.json"
        run = subprocess.run(
            [str(gate), str(baseline), str(candidate),
             str(tmp / "context.txt"), "1", str(tmp / "candidates.txt"),
             "0", str(receipt)], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        result = json.loads(receipt.read_text())
        assert result["schema"] == "nanlm.head-page-gate/1"
        assert result["host_math"] is False
        assert result["tensor_promotion"] is False
        assert result["page_training"] is False
        assert result["accepted"] is True
        assert math.isfinite(result["baseline_nll"])
        assert math.isfinite(result["candidate_nll"])
        assert result["candidate_nll"] < result["baseline_nll"]
        assert len(result["baseline_state_sha256"]) == 64
        assert len(result["candidate_state_sha256"]) == 64
        assert len(result["baseline_root"]) == 64
        assert len(result["candidate_root"]) == 64

        # Identical checkpoints cannot pass the strict improvement gate.
        same_receipt = tmp / "same.json"
        run = subprocess.run(
            [str(gate), str(baseline), str(baseline),
             str(tmp / "context.txt"), "1", str(tmp / "candidates.txt"),
             "0", str(same_receipt)], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        same = json.loads(same_receipt.read_text())
        assert same["accepted"] is False
        print("PASS native head-page checkpoint gate")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
