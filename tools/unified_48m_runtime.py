#!/usr/bin/env python3
"""One runtime path: native NaN16 candidate feedback -> frozen 48M decoder.

This is the language-model entry point of the unified system.  The original
R25/R27 checkpoint is an external optional word model.  The NaN16 guest
supplies finite candidate log weights through ``build/nanlm48m-native-batch``;
this adapter asks the frozen decoder for P0 and returns the exact normalized
finite-candidate distribution.

Scope is deliberately finite: this is a candidate-shortlist top-k readout, not
a full-vocabulary argmax and not tensor promotion.  Without the original
archive it fails closed instead of producing a surrogate decoder metric.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Mapping, Sequence

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

from decoder48m_candidate import (  # noqa: E402
    FiniteCandidateDistribution,
    frozen_r25_emitter,
)


def normalize_candidate_scores(
    emitter,
    context: str,
    native_log_weights: Mapping[str, float],
    candidate_words: Sequence[str],
) -> dict:
    """Return the exact normalized candidate scores and a ranked top-k.

    ``emitter`` is the frozen 48M interface: score(context, word) ->
    {"probability": p0}.  No candidate probability is invented here; the
    FiniteCandidateDistribution class owns the exact finite-support normalizer.
    """
    if not isinstance(context, str) or not context.strip():
        raise ValueError("nonempty context required")
    candidates = list(candidate_words)
    if not candidates or len(candidates) > 4096:
        raise ValueError("1..4096 candidate words required")
    if len(set(candidates)) != len(candidates):
        raise ValueError("duplicate candidate word")
    if any(not isinstance(w, str) or not w or w != w.lower() or
           not w.isalpha() for w in candidates):
        raise ValueError("candidates must be canonical lowercase alphabetic")
    if set(native_log_weights) != set(candidates):
        raise ValueError("native weights must cover exactly the shortlist")
    weights = {w: float(native_log_weights[w]) for w in candidates}
    for value in weights.values():
        if not math.isfinite(value) or abs(value) > 8.0:
            raise ValueError("native candidate log weight outside [-8,8]")
    distribution = FiniteCandidateDistribution(emitter, context, weights)
    rows = []
    for word in candidates:
        baseline = distribution.emitter.score(context, word)
        candidate = distribution.score(word)
        p0 = float(baseline["probability"])
        p1 = float(candidate["probability"])
        if not (math.isfinite(p0) and 0.0 <= p0 <= 1.0 and
                math.isfinite(p1) and 0.0 <= p1 <= 1.0):
            raise ValueError("frozen decoder returned an invalid probability")
        rows.append({
            "word": word,
            "baseline_probability": p0,
            "candidate_probability": p1,
            "native_log_weight": weights[word],
            "native_applied": True,
        })
    ranked = sorted(rows, key=lambda row: (-row["candidate_probability"],
                                           row["word"]))
    if len(ranked) > 5:
        top = ranked[:5]
    else:
        top = ranked
    return {
        "normalizer": distribution.Z,
        "rows": rows,
        "top_k": top,
        "candidate_only": True,
        "full_vocabulary_argmax": False,
        "tensor_promotion": False,
        "frozen_model_modified": False,
    }


def run_native_emit(
    emit_binary: Path,
    context: str,
    candidate_words: Sequence[str],
    timeout: int = 300,
) -> dict:
    """Run the full Native48MFeedbackBridge path once per candidate.

    This is the full native measurement path: phase, field/triheads, Hodge,
    committed MC0, and candidate tensor staging. The host only supplies text
    windows and parses the typed candidate receipt.
    """
    import tempfile
    emit_binary = emit_binary.resolve()
    if not emit_binary.is_file():
        raise FileNotFoundError(f"native emit binary missing: {emit_binary}")
    words = context.split()
    if not words:
        raise ValueError("native emit requires a nonempty context")
    current = words[-1]
    previous = words[-2] if len(words) >= 2 else current
    if len(previous.encode()) > 64 or len(current.encode()) > 64:
        raise ValueError("native emit windows must be 1..64 bytes")
    candidates = list(candidate_words)
    if not candidates or len(set(candidates)) != len(candidates):
        raise ValueError("unique nonempty candidates required")
    if any(not w or w != w.lower() or not w.isalpha() for w in candidates):
        raise ValueError("candidates must be canonical lowercase alphabetic")
    weights = {}
    evidence = {}
    with tempfile.TemporaryDirectory(prefix="nanlm-unified-48m-emit-") as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "previous.txt").write_text(previous, encoding="utf-8")
        (tmp_path / "current.txt").write_text(current, encoding="utf-8")
        for word in candidates:
            out = tmp_path / f"{word}.json"
            completed = subprocess.run(
                [str(emit_binary), str(tmp_path / "previous.txt"),
                 str(tmp_path / "current.txt"), context, word, str(out)],
                cwd=str(ROOT), text=True, capture_output=True, timeout=timeout)
            if completed.returncode != 0:
                raise RuntimeError(
                    "native candidate emit failed: " +
                    (completed.stderr.strip() or completed.stdout.strip()))
            receipt = json.loads(out.read_text())
            native = receipt.get("native_log_weights")
            if not isinstance(native, dict) or set(native) != {word}:
                raise RuntimeError("native emit shortlist mismatch")
            value = float(native[word])
            if not math.isfinite(value) or abs(value) > 8.0:
                raise RuntimeError("native emit weight outside [-8,8]")
            native_evidence = receipt.get("native_evidence", {})
            if (not isinstance(native_evidence, dict) or
                    native_evidence.get("meta_available") is not True or
                    native_evidence.get("candidate_staged") is not True or
                    native_evidence.get("automatic_promotion") is not False):
                raise RuntimeError("native emit did not provide candidate-only evidence")
            weights[word] = value
            evidence[word] = native_evidence
    return {
        "native_log_weights": weights,
        "native_accepted": len(weights),
        "candidate_count": len(candidates),
        "native_evidence": evidence,
    }


def run_native_batch(
    batch_binary: Path,
    context: str,
    candidate_words: Sequence[str],
    timeout: int = 300,
) -> dict:
    """Ask the NaN16 guest for finite candidate log weights.

    The host only transports the shortlist and parses the typed receipt.
    """
    batch_binary = batch_binary.resolve()
    if not batch_binary.is_file():
        raise FileNotFoundError(f"native batch binary missing: {batch_binary}")
    words = context.split()
    if not words:
        raise ValueError("native batch requires a nonempty context")
    current = words[-1]
    previous = words[-2] if len(words) >= 2 else current
    if len(previous.encode()) > 64 or len(current.encode()) > 64:
        raise ValueError("native batch windows must be 1..64 bytes")
    candidates = list(candidate_words)
    if not candidates or len(set(candidates)) != len(candidates):
        raise ValueError("unique nonempty candidates required")
    if any(not w or w != w.lower() or not w.isalpha() for w in candidates):
        raise ValueError("candidates must be canonical lowercase alphabetic")
    import tempfile
    with tempfile.TemporaryDirectory(prefix="nanlm-unified-48m-") as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "previous.txt").write_text(previous, encoding="utf-8")
        (tmp_path / "current.txt").write_text(current, encoding="utf-8")
        (tmp_path / "words.txt").write_text(
            "\n".join(candidates) + "\n", encoding="utf-8")
        out = tmp_path / "native.json"
        completed = subprocess.run(
            [str(batch_binary), str(tmp_path / "previous.txt"),
             str(tmp_path / "current.txt"), context,
             str(tmp_path / "words.txt"), str(out)],
            cwd=str(ROOT), text=True, capture_output=True, timeout=timeout)
        if completed.returncode != 0:
            raise RuntimeError(
                "native candidate batch failed: " +
                (completed.stderr.strip() or completed.stdout.strip()))
        receipt = json.loads(out.read_text())
        if receipt.get("context") != context:
            raise RuntimeError("native batch context mismatch")
        weights = receipt.get("native_log_weights")
        if not isinstance(weights, dict) or set(weights) != set(candidates):
            raise RuntimeError("native batch shortlist mismatch")
        clean = {}
        for word in candidates:
            value = float(weights[word])
            if not math.isfinite(value) or abs(value) > 8.0:
                raise RuntimeError("native batch weight outside [-8,8]")
            clean[word] = value
        return {
            "native_log_weights": clean,
            "native_accepted": int(receipt.get("accepted", 0)),
            "candidate_count": int(receipt.get("candidate_count", 0)),
        }


def unified_48m_readout(
    emitter,
    context: str,
    candidate_words: Sequence[str],
    native_weights: Mapping[str, float],
) -> dict:
    result = normalize_candidate_scores(
        emitter, context, native_weights, candidate_words)
    return {
        "schema": "nanlm.unified-48m-runtime/1",
        "runtime": (
            "frozen 48M R25 emitter + native NaN16 candidate shortlist + "
            "exact finite-support normalization"),
        "context": context,
        "candidate_count": len(candidate_words),
        "native_candidate_weights": dict(native_weights),
        **result,
        "notes": [
            "The external 48M checkpoint is optional; the native "
            "guest supplies finite candidate log weights.",
            "Top-k is over the supplied finite shortlist. Full-vocabulary "
            "argmax over the 48M trie is not claimed.",
            "Tensor promotion is false; this is not a trained-weight update.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root", type=Path, required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--candidate-file", type=Path, required=True)
    parser.add_argument("--native-mode", choices=("bridge", "batch"),
                        default="bridge")
    parser.add_argument("--native-batch", type=Path,
                        default=ROOT / "build" / "nanlm48m-native-batch")
    parser.add_argument("--native-emit", type=Path,
                        default=ROOT / "build" / "nanlm48m-native-emit")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.archive_root.is_dir():
        print("unified_48m_error: original frozen 48M archive is required; "
              "no surrogate decoder is substituted", file=sys.stderr)
        return 2
    candidates = [line.strip() for line in
                  args.candidate_file.read_text(encoding="utf-8").splitlines()
                  if line.strip()]
    try:
        if args.native_mode == "bridge":
            native = run_native_emit(args.native_emit, args.context, candidates)
            native_binary = args.native_emit
        else:
            native = run_native_batch(args.native_batch, args.context, candidates)
            native_binary = args.native_batch
        emitter = frozen_r25_emitter(args.archive_root)
        result = unified_48m_readout(
            emitter, args.context, candidates,
            native["native_log_weights"])
        result["native_source"] = {
            "mode": args.native_mode,
            "accepted": native["native_accepted"],
            "candidate_count": native["candidate_count"],
            "binary": str(native_binary),
        }
        if args.native_mode == "bridge":
            result["native_evidence"] = native.get("native_evidence", {})
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"unified_48m_error: {exc}", file=sys.stderr)
        return 1
    encoded = json.dumps(result, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
