#!/usr/bin/env python3
"""Smoke-test the native head-worker CLI adapter.

Pages are synthetic zero-weight pages with the required header; this verifies
transport, selection, worker execution and JSON shape, not trained quality.
"""
from __future__ import annotations
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def page() -> bytes:
    data = bytearray(1024 * 1024)
    magic = 0x48315233
    data[0xFCC00:0xFCC04] = magic.to_bytes(4, "little")
    return bytes(data)


def main() -> int:
    binary = ROOT / "build" / "nanlm-head-worker-batch"
    worker = ROOT / "build" / "head_worker.nan"
    if not binary.is_file() or not worker.is_file():
        print("SKIP head worker CLI binary/image missing")
        return 0

    tmp = Path(tempfile.mkdtemp(prefix="nanlm-head-worker-cli-"))
    try:
        for head in (1, 3):
            (tmp / f"head-{head:03d}.page").write_bytes(page())
        context = [0.01 * (i - 128) for i in range(2 * 128)]
        (tmp / "context.txt").write_text(" ".join(map(str, context)) + "\n")
        candidates = [0.0] * (2 * 128)
        candidates[0] = 1.0
        candidates[128 + 1] = 1.0
        (tmp / "candidates.txt").write_text(
            " ".join(map(str, candidates)) + "\n")
        out = tmp / "out.json"
        run = subprocess.run(
            [str(binary), str(tmp), str(tmp / "context.txt"), "1,3", str(out),
             str(tmp / "candidates.txt")],
            cwd=ROOT, text=True, capture_output=True,
        )
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        result = json.loads(out.read_text())
        assert result["schema"] == "nanlm.head-worker-batch/1"
        assert result["accepted"] is True
        assert result["host_math"] is False
        assert result["token_count"] == 2
        assert result["resident"] == 2
        assert [row["head"] for row in result["selected"]] == [1, 3]
        for row in result["selected"]:
            assert len(row["page_sha256"]) == 64
            assert len(row["last_state"]) == 128
            assert all(isinstance(v, (int, float)) for v in row["last_state"])
            assert len(row["candidate_scores"]) == 2
            assert all(isinstance(v, (int, float))
                       for v in row["candidate_scores"])
        print("PASS native head-worker CLI adapter")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
