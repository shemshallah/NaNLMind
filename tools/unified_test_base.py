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
import tempfile
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
    out: dict[str, object] = {}
    for line in result["output"].splitlines():
        if line.startswith("ctx_epoch "):
            for key, name in (("samples", "train_samples"),
                              ("train_loss", "train_loss"),
                              ("train_accuracy", "train_accuracy_percent"),
                              ("seconds", "train_seconds")):
                m = re.search(rf"\b{key}=([0-9.]+)", line)
                if m:
                    out[name] = float(m.group(1))
        elif line.startswith("ctx_full_eval "):
            for key, name in (("samples", "eval_samples"),
                              ("loss", "eval_loss"),
                              ("accuracy", "eval_accuracy_percent"),
                              ("seconds", "eval_seconds")):
                m = re.search(rf"\b{key}=([0-9.]+)", line)
                if m:
                    out[name] = float(m.group(1))
        elif line.startswith("context_guest_backoff "):
            for key in ("exact", "fallback", "threshold", "unique"):
                m = re.search(rf"\b{key}=(\d+)", line)
                if m:
                    out[key] = int(m.group(1))
    return out

def run_context_model(name: str, fraction: float, lines: int,
                      label: str) -> tuple[dict, dict]:
    result = run(name, [
        str(BUILD / "nanlm-universal"), "context-train",
        "state/wordnet_corpus.txt", str(lines), "1", "100000", "11456",
        "4", "0.1", "1", str(fraction),
    ])
    metrics = parse_context(result)
    metrics.update({
        "label": label,
        "line_window": lines,
        "train_fraction": fraction,
        "same_corpus": fraction >= 1.0,
        "note": "line-window-only diagnostic; full-corpus values are in spec/context_model.v1.json",
    })
    return result, metrics

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
              "six_context_now_head", "hyperedge128_ok",
              "hyperedge128_radius", "hyperedge128_distance",
              "hyperedge128_curl_feedback", "current_slot_head",
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
                 "test_dual_tensor_arena", "test_head_page_arena",
                 "test_head_page_loader", "test_head_block", "test_head_worker", "test_head_worker_scheduler", "test_head_readout", "test_head_readout_train", "test_head_page_train", "test_head_page_checkpoint", "test_nlhe2"):
        path = BUILD / name
        if path.is_file():
            results.append(run(name, [str(path)]))
        else:
            results.append({"name": name, "status": "missing"})
    if (ROOT / "tests/test_head_worker_cli.py").is_file():
        results.append(run("head_worker_cli",
                           ["python3", "tests/test_head_worker_cli.py"]))
    if (ROOT / "tests/test_head_readout_train_cli.py").is_file():
        results.append(run("head_readout_train_cli",
                           ["python3", "tests/test_head_readout_train_cli.py"]))
    if (ROOT / "tests/test_head_readout_loop.py").is_file():
        results.append(run("head_readout_loop",
                           ["python3", "tests/test_head_readout_loop.py"]))
    if (ROOT / "tests/test_head_page_gate.py").is_file():
        results.append(run("head_page_gate",
                           ["python3", "tests/test_head_page_gate.py"]))
    if (ROOT / "tests/test_head_page_train.py").is_file():
        results.append(run("head_page_train",
                           ["python3", "tests/test_head_page_train.py"]))
    if (ROOT / "tests/test_head_page_train_gate.py").is_file():
        results.append(run("head_page_train_gate",
                           ["python3", "tests/test_head_page_train_gate.py"]))
    if (ROOT / "tests/test_decoder48m_candidate.py").is_file():
        results.append(run("decoder48m_candidate",
                           ["python3", "tests/test_decoder48m_candidate.py"]))
    if (ROOT / "tests/test_decoder48m_future3.py").is_file():
        results.append(run("decoder48m_future3",
                           ["python3", "tests/test_decoder48m_future3.py"]))
    if (BUILD / "credit-ablation").is_file():
        credit = run("credit_ablation", [str(BUILD / "credit-ablation")])
        for line in credit["output"].splitlines():
            if line.startswith("{"):
                credit["metrics"] = json.loads(line)
        results.append(credit)
    if (BUILD / "nanlm48m-native-batch").is_file():
        with tempfile.TemporaryDirectory(prefix="unified-batch-") as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "previous.txt").write_text("a quiet morning")
            (tmp_path / "current.txt").write_text("the bright river reflects light")
            (tmp_path / "words.txt").write_text("bird\nsky\nriver\n")
            out = tmp_path / "batch.json"
            batch = run("native_batch_abi", [
                str(BUILD / "nanlm48m-native-batch"),
                str(tmp_path / "previous.txt"), str(tmp_path / "current.txt"),
                "the bright river", str(tmp_path / "words.txt"), str(out),
            ])
            if out.is_file():
                receipt = json.loads(out.read_text())
                batch["metrics"] = {
                    "candidate_count": receipt.get("candidate_count"),
                    "accepted": receipt.get("accepted"),
                    "native_log_weights": receipt.get("native_log_weights"),
                }
            results.append(batch)
    results.append(run("verify", [str(BUILD / "nanlm-universal"), "verify"],
                       timeout=300))

    context_models: dict[str, dict] = {}
    context_results: dict[str, dict] = {}
    if not args.skip_context and (ROOT / "state/wordnet_corpus.txt").is_file():
        for key, fraction, label in (
                ("same_corpus_2000", 1.0, "same-corpus line window"),
                ("heldout_2000", 0.8, "random 80/20 held-out line window")):
            result, metrics = run_context_model(
                f"context_{key}", fraction, 2000, label)
            context_results[key] = result
            context_models[key] = metrics
            results.append(result)

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
        "accuracy_definitions": {
            "train_accuracy_percent": "online accuracy over the shuffled training window during that epoch",
            "eval_accuracy_percent": "post-epoch accuracy on the evaluation indices",
            "same_corpus": "train and eval use the same rows; this is not generalization",
            "heldout": "random 80/20 within the same line window; still window-limited",
            "canonical_full_corpus_reference": "spec/context_model.v1.json; 73.7821 same-corpus / 66.8894 held-out"
        },
        "metric_semantics": {
            "regression_metrics_are_deterministic": True,
            "why_values_repeat": "fixed corpus slice, fixed seed, no model candidate promotion",
            "learning_metrics_that_must_change": [
                "baseline vs candidate NLL on generated prefixes",
                "per-horizon probability delta",
                "trihead acceptance",
                "tensor candidate promotion"
            ],
            "closed_loop_requires": "frozen 48M exact decoder plus native emit callback"
        },
        "canonical_full_corpus_reference": {
            "source": "spec/context_model.v1.json",
            "same_corpus_accuracy_percent": 73.7821,
            "heldout_80_20_accuracy_percent": 66.8894,
            "same_corpus_epochs": 3,
            "heldout_epochs": 5,
            "note": "not run in this quick invocation"
        },
        "context_models": context_models,
        "stream_metrics": stream_metrics,
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"unified_test_base status={report['summary']['status']} "
          f"passed={passed}/{len(results)} out={args.out}")
    for key, metrics in context_models.items():
        if metrics.get("same_corpus"):
            print(f"{key} train_accuracy={metrics.get('train_accuracy_percent')} "
                  f"eval_accuracy={metrics.get('eval_accuracy_percent')} "
                  "DIAGNOSTIC_ONLY same rows, NOT generalization")
        else:
            print(f"{key} train_accuracy={metrics.get('train_accuracy_percent')} "
                  f"heldout_accuracy={metrics.get('eval_accuracy_percent')} "
                  f"split={metrics.get('label')}")
    print(f"stream_curl={stream_metrics.get('hodge_curl_l1')} "
          f"six_radius={stream_metrics.get('six_context_radius')}")
    for name in failed:
        print(f"FAILED {name}")
    for name in missing:
        print(f"MISSING {name}")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
