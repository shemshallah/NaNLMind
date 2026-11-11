#!/usr/bin/env python3
"""Audit the NaNLMind and NaNROUTER native-kernel surface in one pass.

This is a read-only coverage audit. It does not modify either repository and
does not invent kernel results. It answers three questions:

1. How many kernels does each provider declare?
2. Which declared kernels are reachable from a registered fixture?
3. Which sources/fixtures are shared, and which are exclusive to one tree?

With ``--run`` it also executes both fixture suites and records their exit
status and wall time. The output is a provenance-bound JSON report and an
optional Markdown summary.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_NANROUTER = Path(os.environ.get("NANROUTER_ROOT", str(Path.home() / "NaNROUTER")))
LABEL_RE = re.compile(r"^(mth_[A-Za-z0-9_]+):", re.MULTILINE)
CALL_RE = re.compile(r"CALL\s+@(mth_[A-Za-z0-9_]+)")
INCLUDE_RE = re.compile(r'\.include\s+"([^"]+)"')


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(name, None)
        raise
    return module


def _fixture_dicts(fixtures: Iterable) -> list[dict]:
    out = []
    for fixture in fixtures:
        out.append(
            {
                "name": fixture.name,
                "path": fixture.path,
                "steps": int(fixture.steps),
                "marker": fixture.marker,
            }
        )
    return out


def _source_labels(source_dir: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for path in sorted(source_dir.glob("*.nas")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        labels = sorted(set(LABEL_RE.findall(text)))
        out[path.name] = {
            "path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
            "labels": labels,
            "label_count": len(labels),
        }
    return out


def _fixture_reachability(fixture_paths: Iterable[Path]) -> dict:
    calls: set[str] = set()
    includes: set[str] = set()
    per_fixture: dict[str, dict] = {}
    for path in fixture_paths:
        text = path.read_text(encoding="utf-8", errors="ignore")
        fixture_calls = set(CALL_RE.findall(text))
        fixture_includes = {Path(x).name for x in INCLUDE_RE.findall(text)}
        calls |= fixture_calls
        includes |= fixture_includes
        per_fixture[path.name] = {
            "calls": sorted(fixture_calls),
            "includes": sorted(fixture_includes),
        }
    return {"calls": calls, "includes": includes, "per_fixture": per_fixture}


def _include_closure(
    included: set[str], source_dir: Path
) -> set[str]:
    graph: dict[str, set[str]] = {}
    for path in source_dir.glob("*.nas"):
        graph[path.name] = {
            Path(x).name for x in INCLUDE_RE.findall(
                path.read_text(encoding="utf-8", errors="ignore")
            )
        }
    out: set[str] = set()
    stack = list(included)
    while stack:
        name = stack.pop()
        if name in out:
            continue
        out.add(name)
        stack.extend(graph.get(name, ()))
    return out


def _nanlmind_report(nanlmind: Path) -> dict:
    source_dir = nanlmind / "mth" / "nan16"
    test_dir = nanlmind / "mth" / "tests"
    fixture_module = _load_module(
        nanlmind / "tools" / "run_nan16_fixtures.py", "nanlmind_fixtures"
    )
    fixtures = _fixture_dicts(fixture_module.FIXTURES)
    fixture_paths = [nanlmind / f["path"] for f in fixtures]
    reach = _fixture_reachability(fixture_paths)
    closure = _include_closure(reach["includes"], source_dir)
    driver = nanlmind / "mth" / "drivers" / "field_driver.nas"
    driver_includes = {
        Path(x).name for x in INCLUDE_RE.findall(
            driver.read_text(encoding="utf-8", errors="ignore")
        )
    }
    sources = _source_labels(source_dir)
    source_rows = {}
    directly_covered = set()
    driver_covered = set()
    for name, info in sources.items():
        labels = set(info["labels"])
        direct = bool(labels & reach["calls"]) or name in closure
        driver_hit = name in driver_includes
        if direct:
            directly_covered.add(name)
        if driver_hit:
            driver_covered.add(name)
        source_rows[name] = {
            **info,
            "direct_fixture": direct,
            "driver_include": driver_hit,
            "covered_by": (
                "fixture" if direct else ("driver" if driver_hit else "none")
            ),
        }
    uncovered = sorted(
        name for name, row in source_rows.items() if row["covered_by"] == "none"
    )
    return {
        "provider": "NaNLMind",
        "root": str(nanlmind),
        "fixture_count": len(fixtures),
        "fixtures": fixtures,
        "source_count": len(sources),
        "sources": source_rows,
        "direct_fixture_sources": len(directly_covered),
        "driver_included_sources": len(driver_covered),
        "uncovered_sources": uncovered,
        "fixture_calls": sorted(reach["calls"]),
        "fixture_includes": sorted(reach["includes"]),
        "driver_includes": sorted(driver_includes),
    }


def _nanrouter_catalog(nanrouter: Path) -> dict:
    proc = subprocess.run(
        [sys.executable, "tools/mth_unified.py", "--json"],
        cwd=nanrouter,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        raise SystemExit(
            "NaNROUTER unified catalog failed: "
            + (proc.stderr.strip() or proc.stdout.strip())
        )
    return json.loads(proc.stdout)


def _nanrouter_report(nanrouter: Path, catalog: dict) -> dict:
    fixture_module = _load_module(
        nanrouter / "tools" / "run_mth_fixtures.py", "nanrouter_fixtures"
    )
    fixtures = _fixture_dicts(fixture_module.FIXTURES)
    runner_paths = {f["path"] for f in fixtures}
    kernels = catalog.get("kernels", [])
    fixture_to_kernels: dict[str, list[str]] = defaultdict(list)
    missing_fixture: list[dict] = []
    for kernel in kernels:
        fixture = kernel.get("fixture", "")
        fixture_to_kernels[fixture].append(kernel.get("kernel_id", ""))
        if fixture not in runner_paths:
            missing_fixture.append(
                {
                    "kernel_id": kernel.get("kernel_id"),
                    "fixture": fixture,
                }
            )
    source_dir = nanrouter / "mth" / "nan16"
    test_dir = nanrouter / "mth" / "tests"
    return {
        "provider": "NaNROUTER",
        "root": str(nanrouter),
        "catalog_schema": catalog.get("schema"),
        "catalog_status": catalog.get("status"),
        "kernel_count": len(kernels),
        "runner_fixture_count": len(fixtures),
        "unique_runner_fixtures": len(runner_paths),
        "unique_kernel_fixtures": len(fixture_to_kernels),
        "fixtures": fixtures,
        "kernels": kernels,
        "fixture_to_kernels": {
            fixture: sorted(ids) for fixture, ids in sorted(fixture_to_kernels.items())
        },
        "kernels_without_runner_fixture": missing_fixture,
        "source_count": len(list(source_dir.glob("*.nas"))),
        "test_count": len(list(test_dir.glob("*.nas"))),
    }


def _overlap(nanlmind: dict, nanrouter: dict) -> dict:
    lm_sources = set(nanlmind["sources"])
    rt_sources = {
        Path(k.get("source", "")).name for k in nanrouter.get("kernels", [])
    }
    lm_fixtures = {Path(f["path"]).name for f in nanlmind["fixtures"]}
    rt_fixtures = {Path(f["path"]).name for f in nanrouter["fixtures"]}
    return {
        "source_names": {
            "nanlmind": len(lm_sources),
            "nanrouter_catalog": len(rt_sources),
            "shared": sorted(lm_sources & rt_sources),
            "nanlmind_only": sorted(lm_sources - rt_sources),
            "nanrouter_only": sorted(rt_sources - lm_sources),
        },
        "fixture_names": {
            "nanlmind": len(lm_fixtures),
            "nanrouter": len(rt_fixtures),
            "shared": sorted(lm_fixtures & rt_fixtures),
            "nanlmind_only": sorted(lm_fixtures - rt_fixtures),
            "nanrouter_only": sorted(rt_fixtures - lm_fixtures),
        },
    }


def _run(label: str, command: list[str], cwd: Path) -> dict:
    started = time.monotonic()
    proc = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    elapsed = time.monotonic() - started
    text = (proc.stdout + "\n" + proc.stderr).strip()
    tail = "\n".join(text.splitlines()[-8:])
    return {
        "label": label,
        "command": command,
        "cwd": str(cwd),
        "returncode": proc.returncode,
        "seconds": round(elapsed, 3),
        "tail": tail,
    }


def _markdown(report: dict) -> str:
    lm = report["providers"]["nanlmind"]
    rt = report["providers"]["nanrouter"]
    ov = report["overlap"]
    lines = [
        "# Unified kernel coverage audit",
        "",
        f"Generated: `{report['generated']}`",
        "",
        "## Provider summary",
        "",
        "| provider | fixture files | declared kernels | source files | coverage gap |",
        "|---|---:|---:|---:|---|",
        f"| NaNLMind | {lm['fixture_count']} | {lm['source_count']} source files | {lm['source_count']} | {len(lm['uncovered_sources'])} sources not directly reached |",
        f"| NaNROUTER | {rt['runner_fixture_count']} | {rt['kernel_count']} | {rt['source_count']} | {len(rt['kernels_without_runner_fixture'])} kernels without a runner fixture |",
        "",
        "## NaNLMind",
        "",
        f"- fixtures: **{lm['fixture_count']}**",
        f"- source files: **{lm['source_count']}**",
        f"- sources directly reached by a fixture call/include: **{lm['direct_fixture_sources']}**",
        f"- sources included by `field_driver.nas`: **{lm['driver_included_sources']}**",
        f"- sources with neither direct nor driver reach: **{len(lm['uncovered_sources'])}**",
    ]
    if lm["uncovered_sources"]:
        lines.append("- uncovered: " + ", ".join(f"`{x}`" for x in lm["uncovered_sources"]))
    lines += [
        "",
        "## NaNROUTER",
        "",
        f"- catalog status: **{rt['catalog_status']}**",
        f"- declared kernels: **{rt['kernel_count']}**",
        f"- runner fixtures: **{rt['runner_fixture_count']}** ({rt['unique_runner_fixtures']} unique)",
        f"- unique kernel fixtures: **{rt['unique_kernel_fixtures']}**",
        f"- kernels without a runner fixture: **{len(rt['kernels_without_runner_fixture'])}**",
    ]
    lines += [
        "",
        "## Shared surface",
        "",
        f"- source basenames shared: **{len(ov['source_names']['shared'])}**",
        f"- NaNLMind-only source basenames: **{len(ov['source_names']['nanlmind_only'])}**",
        f"- NaNROUTER-only catalog source basenames: **{len(ov['source_names']['nanrouter_only'])}**",
        f"- fixture basenames shared: **{len(ov['fixture_names']['shared'])}**",
        f"- NaNLMind-only fixtures: **{len(ov['fixture_names']['nanlmind_only'])}**",
        f"- NaNROUTER-only fixtures: **{len(ov['fixture_names']['nanrouter_only'])}**",
    ]
    runs = report.get("runs", [])
    if runs:
        lines += ["", "## Executed suites", "", "| suite | return code | seconds |", "|---|---:|---:|"]
        for run in runs:
            lines.append(
                f"| {run['label']} | {run['returncode']} | {run['seconds']} |"
            )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nanlmind", type=Path, default=ROOT)
    parser.add_argument("--nanrouter", type=Path, default=DEFAULT_NANROUTER)
    parser.add_argument(
        "--out",
        type=Path,
        default=ROOT / "state" / "benchmarks" / "unified_kernel_audit.json",
    )
    parser.add_argument("--markdown", type=Path, default=None)
    parser.add_argument("--run", action="store_true", help="execute both fixture suites")
    args = parser.parse_args(argv)

    nanlmind = args.nanlmind.resolve()
    nanrouter = args.nanrouter.resolve()
    if not (nanlmind / "mth" / "nan16").is_dir():
        raise SystemExit(f"not a NaNLMind tree: {nanlmind}")
    if not (nanrouter / "tools" / "mth_unified.py").is_file():
        raise SystemExit(f"not a NaNROUTER tree: {nanrouter}")

    catalog = _nanrouter_catalog(nanrouter)
    lm = _nanlmind_report(nanlmind)
    rt = _nanrouter_report(nanrouter, catalog)
    report = {
        "schema": "nanlm.unified-kernel-audit/1",
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "providers": {"nanlmind": lm, "nanrouter": rt},
        "overlap": _overlap(lm, rt),
        "runs": [],
    }
    if args.run:
        report["runs"].append(
            _run(
                "NaNLMind fixtures",
                [sys.executable, "tools/run_nan16_fixtures.py"],
                nanlmind,
            )
        )
        report["runs"].append(
            _run(
                "NaNROUTER fixtures",
                [sys.executable, "tools/run_mth_fixtures.py"],
                nanrouter,
            )
        )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.markdown is not None:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(_markdown(report), encoding="utf-8")
    print(
        json.dumps(
            {
                "nanlmind": {
                    "fixtures": lm["fixture_count"],
                    "source_files": lm["source_count"],
                    "direct_sources": lm["direct_fixture_sources"],
                    "driver_sources": lm["driver_included_sources"],
                    "uncovered_sources": len(lm["uncovered_sources"]),
                },
                "nanrouter": {
                    "kernels": rt["kernel_count"],
                    "fixtures": rt["runner_fixture_count"],
                    "unique_fixtures": rt["unique_runner_fixtures"],
                    "missing": len(rt["kernels_without_runner_fixture"]),
                },
                "runs": report["runs"],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
