#!/usr/bin/env python3
"""Matched word-level top-k benchmark: system association memory vs n-grams.

Only orchestration lives here. Both binaries use the same corpus and 80/20
token split. The system has no normalized score, so BPB remains a baseline-only
metric and is marked unsupported for the system row.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    if proc.returncode != 0:
        raise SystemExit(
            f"command failed ({proc.returncode}): {' '.join(cmd)}\n"
            f"{proc.stdout[-1000:]}\n{proc.stderr[-2000:]}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path,
                    default=Path("data/alice_full.txt"))
    ap.add_argument("--out", type=Path,
                    default=Path("state/benchmarks/system_word_bench.json"))
    args = ap.parse_args()
    corpus = (ROOT / args.corpus).resolve() if not args.corpus.is_absolute() \
        else args.corpus
    if not corpus.is_file():
        raise SystemExit(f"missing corpus: {corpus}")
    out = ROOT / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    baseline_path = out.with_name("word_baselines_matched.json")
    system_path = out.with_name("word_system_matched.json")
    run([str(BUILD / "word-baselines"), str(corpus), str(baseline_path)])
    run([str(BUILD / "word-system"), str(corpus), str(system_path)])
    baseline = json.loads(baseline_path.read_text())
    system = json.loads(system_path.read_text())
    if baseline.get("test_tokens") != system.get("test_tokens"):
        raise SystemExit("word benchmark split mismatch")
    result = {
        "schema": "nanlm.system-word-bench/1",
        "corpus": str(args.corpus),
        "split": {
            "train_tokens": system["train_tokens"],
            "test_tokens": system["test_tokens"],
            "oov_rate": system.get("oov_rate"),
        },
        "scope": (
            "matched word top-k on the same held-out tokens; system is the "
            "integer associative layer ranking its full learned vocabulary by "
            "association score. System BPB is unsupported (scores are not "
            "normalized). Baselines are full-vocabulary smoothed n-grams."),
        "system": {
            "runtime": system.get("runtime"),
            "vocab": system.get("vocab"),
            "associations": system.get("associations"),
            "top1": system.get("top1"),
            "top5": system.get("top5"),
            "in_vocab_top1": system.get("in_vocab_top1"),
            "in_vocab_top5": system.get("in_vocab_top5"),
            "bpb": None,
        },
        "baselines": {
            "unigram": baseline.get("unigram"),
            "bigram": baseline.get("bigram"),
        },
        "delta_system_minus_bigram": {
            "top1": system["top1"] - baseline["bigram"]["top1"],
            "top5": system["top5"] - baseline["bigram"]["top5"],
            "in_vocab_top1": (system["in_vocab_top1"] -
                              baseline["bigram"]["in_vocab_top1"]),
            "in_vocab_top5": (system["in_vocab_top5"] -
                              baseline["bigram"]["in_vocab_top5"]),
        },
        "notes": [
            "The associative layer ranks only learned training words; the "
            "baseline vocabulary also contains <unk>. In-vocab top-k is the "
            "closer apples-to-apples row. System scores are not normalized, so "
            "no model BPB is claimed.",
            "This is an integer associative-memory system component, not the "
            "native 48M decoder, and must not be presented as a frontier metric.",
        ],
    }
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "system_top1": result["system"]["top1"],
        "system_top5": result["system"]["top5"],
        "unigram_top5": result["baselines"]["unigram"]["top5"],
        "bigram_top5": result["baselines"]["bigram"]["top5"],
        "bigram_in_vocab_top5": result["baselines"]["bigram"]["in_vocab_top5"],
        "out": str(out),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
