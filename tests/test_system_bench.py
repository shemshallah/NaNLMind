#!/usr/bin/env python3
"""Smoke tests for the matched byte and word system benchmarks."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    if proc.returncode != 0:
        raise SystemExit(
            f"command failed ({proc.returncode}): {' '.join(cmd)}\n"
            f"{proc.stdout[-1000:]}\n{proc.stderr[-2000:]}")


def check_metrics(row: dict, name: str) -> None:
    for key in ("bpb", "top1", "top5", "samples"):
        if key not in row:
            raise SystemExit(f"{name}: missing {key}")
    if not (0.0 <= row["top1"] <= row["top5"] <= 1.0):
        raise SystemExit(f"{name}: invalid top-k ordering: {row}")
    if not (row["bpb"] > 0.0):
        raise SystemExit(f"{name}: invalid BPB: {row}")
    if row["samples"] <= 0:
        raise SystemExit(f"{name}: empty sample set")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="nanlm-system-bench-") as tmp:
        tmp_path = Path(tmp)
        byte_out = tmp_path / "byte.json"
        run([str(BUILD / "system-byte-bench"),
             "data/alice_excerpt.txt", str(byte_out),
             "256", "200", "1", "0.1", "12000"])
        byte = json.loads(byte_out.read_text())
        if byte.get("schema") != "nanlm.system-byte-bench/1":
            raise SystemExit("bad byte benchmark schema")
        if byte.get("eval_positions", 0) <= 0:
            raise SystemExit("empty byte evaluation")
        check_metrics(byte["system"], "byte/system")
        check_metrics(byte["order0_matched"], "byte/order0")
        check_metrics(byte["bigram_matched"], "byte/bigram")
        check_metrics(byte["context2_matched"], "byte/context2")
        if not (byte["system"]["top1"] <= byte["system"]["top5"]):
            raise SystemExit("byte system top-k ordering")
        if "native opcode" not in byte.get("metric_scope", ""):
            raise SystemExit("byte scope does not identify the native system")

        word_out = tmp_path / "word.json"
        run([sys.executable, "tools/system_word_bench.py", "--out",
             str(word_out)])
        word = json.loads(word_out.read_text())
        if word.get("schema") != "nanlm.system-word-bench/1":
            raise SystemExit("bad word benchmark schema")
        system = word["system"]
        if system.get("bpb") is not None:
            raise SystemExit("word system must not claim a normalized BPB")
        if not (0.0 <= system["top1"] <= system["top5"] <= 1.0):
            raise SystemExit("word system top-k ordering")
        bigram = word["baselines"]["bigram"]
        if not (0.0 <= bigram["top5"] <= 1.0):
            raise SystemExit("word bigram top5 bounds")
        if word["split"]["test_tokens"] <= 0:
            raise SystemExit("word benchmark empty split")
        if "delta_system_minus_bigram" not in word:
            raise SystemExit("word benchmark missing delta")

        print("byte_system",
              byte["system"]["bpb"], byte["system"]["top1"],
              byte["system"]["top5"])
        print("word_system",
              system["top1"], system["top5"], system["in_vocab_top5"])
        print("word_bigram_top5", bigram["top5"])
    print("PASS matched system byte/word top-k benchmarks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
