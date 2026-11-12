#!/usr/bin/env python3
"""Smoke-test the unified context CLI."""
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


def checkpoint(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    lines = []
    for head in (1, 3):
        data = page()
        (directory / f"head-{head:03d}.page").write_bytes(data)
        lines.append(f"{head} 0 {hashlib.sha256(data).hexdigest()}\n")
    (directory / "manifest.txt").write_text("".join(lines))


def main() -> int:
    binary = ROOT / "build" / "nanlm-unified-context"
    worker = ROOT / "build" / "head_worker.nan"
    if not binary.is_file() or not worker.is_file():
        print("SKIP unified context CLI binary missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-unified-context-"))
    try:
        checkpoint(tmp / "cp")
        credits = [0.0] * 255
        credits[1], credits[3] = 5.0, 9.0
        tokens = []
        for t in range(7):
            row = [0.0] * 128
            row[0] = 0.01 * (t + 1)
            tokens.extend(row)
        (tmp / "credits.txt").write_text(" ".join(map(str, credits)) + "\n")
        (tmp / "tokens.txt").write_text(" ".join(map(str, tokens)) + "\n")
        bank = []
        for head in (1, 3):
            row = [0.0] * 128
            row[head - 1] = 0.5
            bank.append("7 256 " + str(head) + " " +
                        " ".join(map(str, row)))
        (tmp / "bank.tsv").write_text("\n".join(bank) + "\n")
        out = tmp / "out.json"
        run = subprocess.run(
            [str(binary), str(tmp / "cp"), "3,1", str(tmp / "credits.txt"),
             str(tmp / "tokens.txt"), str(out), "--bank", str(tmp / "bank.tsv"),
             "--top-k", "2", "--summary-k", "2", "--retrieve-head", "3"],
            cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        report = json.loads(out.read_text())
        assert report["schema"] == "nanlm.unified-context/1"
        assert report["accepted"] is True
        assert report["host_math"] is False
        assert report["advance"]["hierarchical"] is True
        assert report["advance"]["heads"] == [3, 1]
        assert len(report["advance"]["final_states"]) == 2
        assert all(len(s) == 128 for s in report["advance"]["final_states"])
        assert report["checkpoint"]["resident"] == 2
        assert report["bank"]["size"] == 1
        assert report["retrieve"]["head"] == 3
        assert len(report["retrieve"]["hits"]) == 1
        assert report["retrieve"]["hits"][0]["chunk_id"] == 7
        assert len(report["memory"]["state"]) == 128
        print("PASS unified context CLI")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
