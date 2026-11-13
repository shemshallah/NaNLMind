#!/usr/bin/env python3
"""Smoke-test the single system orchestration entry point."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools" / "nanlm_unified_system.py"


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CLI)] + args,
                          cwd=ROOT, text=True, capture_output=True)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="nanlm-system-cli-") as tmp:
        tmp_path = Path(tmp)
        status = run(["status", "--out", str(tmp_path / "status.json")])
        if status.returncode != 0:
            raise SystemExit(status.stderr)
        report = json.loads((tmp_path / "status.json").read_text())
        if report.get("schema") != "nanlm.unified-system-status/1":
            raise SystemExit("bad status schema")
        if "byte_readout" not in report.get("components", {}):
            raise SystemExit("missing byte component")
        if "token_projection" not in report.get("components", {}):
            raise SystemExit("missing token component")
        if report.get("artifacts", {}).get("byte_direct256", {}).get(
                "status") != "present":
            raise SystemExit("byte artifact missing")

        direct = run(["byte", "data/alice_excerpt.txt",
                      str(tmp_path / "byte.json"), "1000", "512", "12000"])
        if direct.returncode != 0:
            raise SystemExit(direct.stderr)
        payload = json.loads((tmp_path / "byte.json").read_text())
        if payload.get("schema") != "nanlm.system-byte-bench/1":
            raise SystemExit("delegated byte benchmark failed")
        print("PASS unified system CLI")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
