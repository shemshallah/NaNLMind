#!/usr/bin/env python3
"""Validate the unified NaNLMind/NaNROUTER system link map.

The spec at ``spec/unified_system.v1.json`` is the link layer. This checker
does not invent kernel results: it verifies that every linked artifact exists,
that the declared provider counts still match the live trees, that the
cross-repo kernel audit runs, and that the retired Hopfield legacy surface is
gone.

With ``--run`` it also executes both fixture suites through the audit tool.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPEC = ROOT / "spec" / "unified_system.v1.json"
DEFAULT_NANROUTER = Path.home() / "NaNROUTER"


def _load(path: Path) -> dict:
    if not path.is_file():
        raise SystemExit(f"missing spec: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _count_glob(root: Path, pattern: str) -> int:
    return len(list(root.glob(pattern)))


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _run_audit(nanlmind: Path, nanrouter: Path, run: bool) -> tuple[dict, str]:
    tmp = Path(tempfile.mkdtemp(prefix="unified-system-"))
    out = tmp / "audit.json"
    markdown = tmp / "audit.md"
    command = [
        sys.executable,
        str(nanlmind / "tools" / "unified_kernel_audit.py"),
        "--nanlmind",
        str(nanlmind),
        "--nanrouter",
        str(nanrouter),
        "--out",
        str(out),
        "--markdown",
        str(markdown),
    ]
    if run:
        command.append("--run")
    proc = subprocess.run(command, cwd=nanlmind, text=True, capture_output=True)
    if proc.returncode != 0:
        return {}, f"audit failed: {proc.stderr.strip() or proc.stdout.strip()}"
    return _read_json(out), ""


def _run_core_tests(nanlmind: Path) -> dict:
    results: dict[str, dict] = {}
    for name in ("test_raw_field", "test_dual_head"):
        path = nanlmind / "build" / name
        if not path.is_file():
            results[name] = {"status": "missing"}
            continue
        started = time.monotonic()
        proc = subprocess.run([str(path)], cwd=nanlmind, text=True, capture_output=True)
        text = (proc.stdout + "\n" + proc.stderr).strip()
        results[name] = {
            "status": "pass" if proc.returncode == 0 else "fail",
            "returncode": proc.returncode,
            "seconds": round(time.monotonic() - started, 3),
            "tail": "\n".join(text.splitlines()[-4:]),
        }
    return results


def _check_legacy(spec: dict, nanlmind: Path) -> list[str]:
    errors: list[str] = []
    for item in spec.get("legacy_removed", []):
        for rel in item.get("paths", []):
            if (nanlmind / rel).exists():
                errors.append(f"legacy path still exists: {rel}")
        for surface in item.get("surfaces", []):
            if surface in (nanlmind / "Makefile").read_text(encoding="utf-8"):
                errors.append(f"legacy Makefile surface still exists: {surface}")
    return errors


def _check_evidence(nanlmind: Path) -> tuple[list[str], list[str], dict]:
    errors: list[str] = []
    warnings: list[str] = []
    evidence: dict[str, object] = {}

    ingest_path = nanlmind / "spec" / "nannet_ingest_result.v1.json"
    if ingest_path.is_file():
        ingest = _read_json(ingest_path)
        evidence["nannet_ingest_schema"] = ingest.get("schema")
        if ingest.get("schema") != "nanlm.nannet-ingest-result/1":
            errors.append("NANNET ingest result has the wrong schema")
        for split in ("stream_train", "stream_heldout"):
            block = ingest.get(split, {})
            word = block.get("word_geometry", {})
            evidence[f"{split}_meta_attention_ok"] = word.get("meta_attention_ok")
            evidence[f"{split}_shape_field_hot"] = word.get("shape_field_hot")
            evidence[f"{split}_hodge_ok"] = word.get("hodge_ok")
            evidence[f"{split}_global_field_hot"] = word.get("global_field_hot")
            if word.get("meta_attention_ok") is not True:
                errors.append(f"{split}: meta_attention_ok is not true")
            if word.get("shape_field_hot") is not True:
                errors.append(f"{split}: shape_field_hot is not true")
            if word.get("hodge_ok") is not True:
                errors.append(f"{split}: hodge_ok is not true")
            if word.get("global_field_hot") is not True:
                errors.append(f"{split}: global_field_hot is not true")
    else:
        warnings.append("NANNET ingest result is missing")

    baseline_path = nanlmind / "spec" / "relation_triangle_matched_baseline.v1.json"
    if baseline_path.is_file():
        baseline = _read_json(baseline_path)
        evidence["matched_baseline_schema"] = baseline.get("schema")
        if baseline.get("schema") != "nanlm.relation-triangle-matched-baseline/1":
            errors.append("matched baseline has the wrong schema")
        rows = baseline.get("rows", {})
        expected = {"train": 115184, "valid": 14333, "test": 14229}
        if rows != expected:
            errors.append(f"matched baseline rows changed: {rows} != {expected}")
        metrics = baseline.get("test_metrics", {})
        for name in (
            "constant_majority",
            "source_prior",
            "deterministic_random",
            "shape_only",
            "raw_global_model",
        ):
            if name not in metrics:
                errors.append(f"matched baseline missing metric: {name}")
    else:
        warnings.append("matched baseline is missing")
    return errors, warnings, evidence


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--nanlmind", type=Path, default=ROOT)
    parser.add_argument("--nanrouter", type=Path, default=DEFAULT_NANROUTER)
    parser.add_argument("--run", action="store_true", help="run both fixture suites")
    parser.add_argument("--json", action="store_true", help="emit JSON only")
    args = parser.parse_args(argv)

    nanlmind = args.nanlmind.resolve()
    nanrouter = args.nanrouter.resolve()
    spec = _load(args.spec)
    errors: list[str] = []
    warnings: list[str] = []
    checks: dict[str, object] = {}

    if spec.get("schema") != "nanlm.unified-system/1":
        errors.append("unified system spec has the wrong schema")
    if not (nanrouter / "tools" / "mth_unified.py").is_file():
        errors.append(f"NaNROUTER catalog tool missing: {nanrouter}")

    for name, rel in spec.get("links", {}).items():
        path = nanlmind / rel
        if not path.exists():
            errors.append(f"link {name} missing: {rel}")
    checks["links"] = len(spec.get("links", {}))

    lm = spec.get("providers", {}).get("nanlmind", {})
    rt = spec.get("providers", {}).get("nanrouter", {})
    lm_sources = _count_glob(nanlmind, lm.get("source_glob", ""))
    lm_fixtures = _count_glob(nanlmind, lm.get("fixture_glob", ""))
    checks["nanlmind_sources"] = lm_sources
    checks["nanlmind_fixtures"] = lm_fixtures
    if lm_sources != lm.get("counts", {}).get("sources"):
        errors.append(
            f"NaNLMind source count changed: {lm_sources} != "
            f"{lm.get('counts', {}).get('sources')}"
        )
    if lm_fixtures != lm.get("counts", {}).get("fixtures"):
        errors.append(
            f"NaNLMind fixture count changed: {lm_fixtures} != "
            f"{lm.get('counts', {}).get('fixtures')}"
        )

    audit, audit_error = _run_audit(nanlmind, nanrouter, args.run)
    if audit_error:
        errors.append(audit_error)
    else:
        lm_audit = audit.get("providers", {}).get("nanlmind", {})
        rt_audit = audit.get("providers", {}).get("nanrouter", {})
        checks["audit"] = {
            "nanlmind": {
                "direct_fixture_sources": lm_audit.get("direct_fixture_sources"),
                "driver_included_sources": lm_audit.get("driver_included_sources"),
                "uncovered_sources": len(lm_audit.get("uncovered_sources", [])),
            },
            "nanrouter": {
                "kernels": rt_audit.get("kernel_count"),
                "fixtures": rt_audit.get("runner_fixture_count"),
                "missing": len(rt_audit.get("kernels_without_runner_fixture", [])),
            },
        }
        expected_lm = lm.get("counts", {})
        if lm_audit.get("direct_fixture_sources") != expected_lm.get("direct_fixture_sources"):
            errors.append("NaNLMind direct fixture reach changed")
        if lm_audit.get("driver_included_sources") != expected_lm.get("driver_included_sources"):
            errors.append("NaNLMind driver reach changed")
        if lm_audit.get("uncovered_sources"):
            errors.append("NaNLMind has uncovered sources")
        expected_rt = rt.get("counts", {})
        if rt_audit.get("kernel_count") != expected_rt.get("kernels"):
            errors.append("NaNROUTER kernel count changed")
        if rt_audit.get("runner_fixture_count") != expected_rt.get("fixtures"):
            errors.append("NaNROUTER fixture count changed")
        if rt_audit.get("kernels_without_runner_fixture"):
            errors.append("NaNROUTER has kernels without runner fixtures")
        checks["catalog_status"] = rt_audit.get("catalog_status")
        if rt_audit.get("catalog_status") != "green":
            errors.append("NaNROUTER catalog status is not green")

    if args.run:
        core = _run_core_tests(nanlmind)
        checks["core_tests"] = core
        for name, result in core.items():
            if result.get("status") == "fail":
                errors.append(f"core test failed: {name}")
            elif result.get("status") == "missing":
                warnings.append(f"core test binary missing: {name}")

    legacy_errors = _check_legacy(spec, nanlmind)
    errors.extend(legacy_errors)
    checks["legacy_removed"] = not legacy_errors

    evidence_errors, evidence_warnings, evidence = _check_evidence(nanlmind)
    errors.extend(evidence_errors)
    warnings.extend(evidence_warnings)
    checks["evidence"] = evidence

    report = {
        "schema": "nanlm.unified-system-check/1",
        "status": "green" if not errors else "red",
        "spec": str(args.spec),
        "nanlmind": str(nanlmind),
        "nanrouter": str(nanrouter),
        "ran_fixtures": bool(args.run),
        "checks": checks,
        "errors": errors,
        "warnings": warnings,
    }
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
