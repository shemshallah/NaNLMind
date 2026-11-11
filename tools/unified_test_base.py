#!/usr/bin/env python3
"""Unified native test and metric base for NaNLMind.

Host code only schedules existing binaries and parses their output.  All
mathematical work is performed by the raw NaN16 guest / native tests.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
STATE = ROOT / "state" / "benchmarks"


def run(name: str, cmd: list[str], timeout: int = 900) -> dict:
    started = time.monotonic()
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True,
                          timeout=timeout)
    text = (proc.stdout + "\n" + proc.stderr).strip()
    return {
        "name": name,
        "command": cmd,
        "returncode": proc.returncode,
        "status": "pass" if proc.returncode == 0 else "fail",
        "seconds": round(time.monotonic() - started, 3),
        "tail": "\n".join(text.splitlines()[-8:]),
        "output": text,
    }


def parse_context(result: dict) -> dict:
    metrics: dict[str, float] = {}
    for line in result["output"].splitlines():
        if line.startswith("ctx_full_eval "):
            for key in ("samples", "loss", "accuracy", "seconds"):
                m = re.search(rf"\b{key}=([0-9.]+)", line)
                if m:
                    metrics[key] = float(m.group(1))
        if line.startswith("context_guest_backoff "):
            for key in ("exact", "fallback", "threshold", "unique"):
                m = re.search(rf"\b{key}=(\d+)", line)
                if m:
                    metrics[key] = int(m.group(1))
    return metrics


def parse_stream(result: dict, prefix: Path) -> dict:
    path = prefix.with_suffix(".json")
    if not path.is_file():
        return {}
    data = json.loads(path.read_text())
    word = data.get("word_geometry", {})
    keys = (
        "shape_field_hot", "hodge_ok", "hodge_divergence_l1",
        "hodge_curl_l1", "global_field_hot", "triangle_stretched",
        "triangle_stretch_sum", "local_attention_ok",
        "local_attention_energy", "meta_attention_ok",
        "meta_context_energy", "credit_bundle_ok", "credit_bundle",
        "attention_levels",
    )
    out = {k: word.get(k) for k in keys if k in word}
    for k in ("six_context_ok", "six_context_observations",
              "six_context_radius", "six_context_distance",
              "six_context_now_head", "current_slot_head",
              "current_slot", "words", "temporal_contexts"):
        if k in data:
            out[k] = data[k]
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path,
                    default=STATE / "unified_test_base.json")
    ap.add_argument("--skip-context", action="store_true")
    ap.add_argument("--skip-stream", action="store_true")
    args = ap.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)

    results = []
    results.append(run("nan16_fixtures",
                       ["python3", "tools/run_nan16_fixtures.py"]))
    for name in ("test_raw_field", "test_context_backoff",
                 "test_context_route", "test_native48m_feedback",
                 "test_dual_tensor_arena"):
        path = BUILD / name
        if path.is_file():
            results.append(run(name, [str(path)]))
        else:
            results.append({"name": name, "status": "missing"})
    if (ROOT / "tests/test_decoder48m_candidate.py").is_file():
        results.append(run("decoder48m_candidate",
                           ["python3", "tests/test_decoder48m_candidate.py"]))
    if (BUILD / "credit-ablation").is_file():
        credit = run("credit_ablation", [str(BUILD / "credit-ablation")])
        for line in credit["output"].splitlines():
            if line.startswith("{"):
                credit["metrics"] = json.loads(line)
        results.append(credit)
    results.append(run("verify", [str(BUILD / "nanlm-universal"), "verify"],
                       timeout=300))

    context_metrics = {}
    if not args.skip_context and (ROOT / "state/wordnet_corpus.txt").is_file():
        context = run("context_model_canonical", [
            str(BUILD / "nanlm-universal"), "context-train",
            "state/wordnet_corpus.txt", "2000", "1", "100000", "11456",
            "4", "0.1", "1", "1",
        ])
        context_metrics = parse_context(context)
        context["metrics"] = context_metrics
        results.append(context)

    stream_metrics = {}
    if not args.skip_stream and (ROOT / "data/alice_excerpt.txt").is_file():
        prefix = Path("/data/data/com.termux/files/usr/tmp/unified_test_stream")
        stream = run("stream_smoke", [
            str(BUILD / "nanlm-universal"), "stream-train",
            "data/alice_excerpt.txt", "50", "0", str(prefix),
        ])
        stream_metrics = parse_stream(stream, prefix)
        stream["metrics"] = stream_metrics
        results.append(stream)

    passed = sum(1 for r in results if r.get("status") == "pass")
    failed = [r["name"] for r in results if r.get("status") == "fail"]
    missing = [r["name"] for r in results if r.get("status") == "missing"]
    report = {
        "schema": "nanlm.unified-test-base/1",
        "generated_unix": int(time.time()),
        "tests": results,
        "summary": {
            "passed": passed,
            "total": len(results),
            "failed": failed,
            "missing": missing,
            "status": "green" if not failed else "red",
        },
        "context_model": context_metrics,
        "stream_metrics": stream_metrics,
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"unified_test_base status={report['summary']['status']} "
          f"passed={passed}/{len(results)} out={args.out}")
    print(f"context_accuracy={context_metrics.get('accuracy')} "
          f"stream_curl={stream_metrics.get('hodge_curl_l1')} "
          f"six_radius={stream_metrics.get('six_context_radius')}")
    for name in failed:
        print(f"FAILED {name}")
    for name in missing:
        print(f"MISSING {name}")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
