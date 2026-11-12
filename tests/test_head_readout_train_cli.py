#!/usr/bin/env python3
"""Smoke-test the native head-readout training CLI adapter."""
from __future__ import annotations
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    binary = ROOT / "build" / "nanlm-head-readout-train"
    worker = ROOT / "build" / "head_worker.nan"
    if not binary.is_file() or not worker.is_file():
        print("SKIP head readout trainer binary/image missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-head-readout-train-"))
    try:
        state = [0.0] * 128
        state[0] = 1.0
        candidates = [0.0] * (2 * 128)
        candidates[0] = 1.0
        candidates[128] = -1.0
        (tmp / "state.txt").write_text(" ".join(map(str, state)) + "\n")
        (tmp / "candidates.txt").write_text(
            " ".join(map(str, candidates)) + "\n")
        out_candidates = tmp / "updated.txt"
        out_json = tmp / "out.json"
        run = subprocess.run(
            [str(binary), str(tmp / "state.txt"), str(tmp / "candidates.txt"),
             "0", "0.1", str(out_candidates), str(out_json)],
            cwd=ROOT, text=True, capture_output=True,
        )
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        result = json.loads(out_json.read_text())
        assert result["schema"] == "nanlm.head-readout-train/1"
        assert result["target"] == 0
        assert result["predicted"] == 0
        assert result["host_math"] is False
        assert math.isfinite(result["loss"]) and result["loss"] >= 0.0
        assert abs(sum(result["probabilities"]) - 1.0) < 1e-4
        updated = [float(v) for v in out_candidates.read_text().split()]
        assert len(updated) == 2 * 128
        assert updated[0] > candidates[0]
        assert updated[128] < candidates[128]
        print("PASS native head-readout training CLI")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
