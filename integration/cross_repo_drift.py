#!/usr/bin/env python3
"""Reproducible SHA-256 audit for the 24 NaN ecosystem repositories.

Run against a directory containing shallow checkout folders named exactly
as REPOSITORIES (except EXPECTED_EMPTY, which deliberately has no git tree).
No writes are made to the checked-out repositories. This is a source/drift
audit, not evidence of running jobs, native execution or trained weights.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

OWNER = "shemshallah"
REPOSITORIES = (
    "nan0", "nan0s-android", "NaN0S", "NaNLM", "NaNLMind",
    "nanlm-ram", "nanlm-vram",
    *(f"nanlm-cpu-{i}" for i in range(1, 7)),
    "NaNLMind_android", "NaNLMind_HERMES", "NaNROUTER",
    "NaNLMind_CLOCKED", "nanrunner-hermes",
    *(f"nanrouter-runner-{i}" for i in range(6)),
)
EXPECTED_EMPTY = frozenset(("nan0s-android",))
ROUTER_BASE = "nanrouter-runner-0"
CPU_BASE = "nanlm-cpu-1"

# Contract parity is stricter than coincidental matching filenames.
# These are deliberately synchronized bytes, not rewritten approximations.
EXACT_CONTRACTS = (
    ("NaN0S", "aarch64/android/core/nan16.c",
     "NaNLMind_android", "aarch64/android/core/nan16.c"),
    ("NaN0S", "aarch64/android/core/nan16.h",
     "NaNLMind_android", "aarch64/android/core/nan16.h"),
    ("NaN0S", "aarch64/android/core/nan16_int.h",
     "NaNLMind_android", "aarch64/android/core/nan16_int.h"),
    ("NaN0S", "src/nannet/n16t_android_guest.nas",
     "NaNLMind_android", "src/nannet/n16t_android_guest.nas"),
    ("NaNLMind", "nanlmind_nannet/nan16de.py",
     "NaNLMind_HERMES", "nanlmind_hermes/nan16de.py"),
)
# Same relative path does not imply same ownership or synchronized code.
GENERIC_FILES = frozenset((
    "README.md", "LICENSE", ".gitignore", ".env.example",
    "Makefile", "Dockerfile", "compose.yaml", "pyproject.toml",
    "CONTRIBUTING.md", "SECURITY.md",
))
SOURCE_SUFFIXES = (".py", ".c", ".h", ".nas", ".kt", ".sh", ".awk", ".yml", ".yaml")


class DriftError(RuntimeError):
    pass


def _run(path: Path, *args: str) -> bytes:
    try:
        return subprocess.check_output(
            ["git", "-C", str(path), *args], stderr=subprocess.PIPE)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise DriftError(f"git inspection failed for {path.name}: {args}") from exc


def _hash_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    if path.is_symlink():
        # Never read through untrusted repository symlinks.
        target = os.readlink(path).encode("utf-8", errors="surrogateescape")
        digest.update(b"symlink\0" + target)
        return digest.hexdigest(), len(target)
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return digest.hexdigest(), size


def scan_repository(path: Path) -> dict:
    head = _run(path, "rev-parse", "HEAD").decode().strip()
    if re.fullmatch(r"[0-9a-f]{40}", head) is None:
        raise DriftError(f"invalid Git source identity: {path.name}")
    names = _run(path, "ls-files", "-z").split(b"\0")
    manifest = {}
    for encoded in names:
        if not encoded:
            continue
        name = encoded.decode("utf-8", errors="surrogateescape")
        item = path / name
        if not item.is_file() and not item.is_symlink():
            raise DriftError(f"tracked source missing: {path.name}/{name}")
        sha, size = _hash_file(item)
        manifest[name] = {"sha256": sha, "bytes": size}
    return {"head_sha": head, "tracked_file_count": len(manifest),
            "tracked_files": dict(sorted(manifest.items()))}


def _text(root: Path, repo: str, filename: str) -> str:
    path = root / repo / filename
    if path.is_symlink() or not path.is_file():
        raise DriftError(f"missing regular source file: {repo}/{filename}")
    return path.read_text(encoding="utf-8")


def verify_router_runner_family(root: Path, scan: dict) -> dict:
    baseline = scan[ROUTER_BASE]["tracked_files"]
    excluded = {"README.md", "slot"}
    checked = {p for p in baseline if p not in excluded}
    if not {"ring_runner.py", "ring_authority_client.py",
            "slot_fabric.py", "tests/test_ring_runner.py"}.issubset(checked):
        raise DriftError("canonical router-runner source files are missing")
    errors = []
    for i in range(6):
        repo = f"nanrouter-runner-{i}"
        files = scan[repo]["tracked_files"]
        slot = _text(root, repo, "slot")
        if slot != f"{i}\n":
            errors.append(f"{repo}: slot file is not the exact assigned ID")
        if not _text(root, repo, "README.md").startswith(f"# {repo}\n"):
            errors.append(f"{repo}: README identifies wrong runner")
        actual = set(files) - excluded
        if actual != checked:
            errors.append(f"{repo}: source inventory differs: "
                          f"missing={sorted(checked - actual)} extra={sorted(actual - checked)}")
        for path in checked & actual:
            if files[path]["sha256"] != baseline[path]["sha256"]:
                errors.append(f"{repo}/{path}: differs from runner-0 source")
    return {"status": "PASS" if not errors else "FAIL", "slots": 6,
            "identical_source_files": len(checked), "errors": sorted(errors)}


def normalize_cpu_workflow(text: str, number: int) -> str:
    slot_value = f'        default: "{number}"'
    bootstrap_value = f'  NANNET_BOOTSTRAP_SLOT: "{number - 1}"'
    endpoint_var = f"BSR{number - 1}_PORTAL_API"
    endpoint_lines = (
        f"  {endpoint_var}: ${{{{ vars.{endpoint_var} }}}}",
        f"  NANNET_PORTAL_API: ${{{{ vars.{endpoint_var} }}}}",
    )
    # Only the designated input slot and bootstrap slot may vary. Requiring
    # exact anchors avoids accidentally masking unrelated workflow changes.
    marker = "        description: runner slot 1..6\n        type: string\n"
    if text.count(marker + slot_value) != 1:
        raise DriftError(f"CPU-{number} workflow slot input mismatch")
    if text.count(bootstrap_value) != 1:
        raise DriftError(f"CPU-{number} bootstrap slot mismatch")
    if any(text.count(line) != 1 for line in endpoint_lines):
        raise DriftError(f"CPU-{number} assigned portal endpoint mismatch")
    return (text.replace(marker + slot_value, marker + '        default: "<slot>"', 1)
            .replace(bootstrap_value, '  NANNET_BOOTSTRAP_SLOT: "<bootstrap>"', 1)
            .replace(endpoint_lines[0], '  <slot>_PORTAL_API: <portal>', 1)
            .replace(endpoint_lines[1], '  NANNET_PORTAL_API: <portal>', 1))


def verify_cpu_worker_family(root: Path, scan: dict) -> dict:
    errors = []
    canonical = normalize_cpu_workflow(
        _text(root, CPU_BASE, ".github/workflows/runner.yml"), 1)
    expected = scan[CPU_BASE]["tracked_files"].keys()
    for number in range(1, 7):
        repo = f"nanlm-cpu-{number}"
        if set(scan[repo]["tracked_files"]) != set(expected):
            errors.append(f"{repo}: tracked-file inventory differs")
        try:
            normalized = normalize_cpu_workflow(
                _text(root, repo, ".github/workflows/runner.yml"), number)
            if normalized != canonical:
                errors.append(f"{repo}: workflow code drift beyond slot constants")
            if not _text(root, repo, "README.md").startswith(f"# {repo}\n"):
                errors.append(f"{repo}: README identifies wrong CPU worker")
        except (DriftError, UnicodeError) as exc:
            errors.append(str(exc))
    return {"status": "PASS" if not errors else "FAIL", "workers": 6,
            "permitted_workflow_differences": (
                "workflow_dispatch.inputs.slot.default",
                "env.NANNET_BOOTSTRAP_SLOT",
                "env.BSRn_PORTAL_API",
                "env.NANNET_PORTAL_API"), "errors": sorted(errors)}


def verify_exact_contracts(scan: dict) -> dict:
    out = []
    for repo_a, path_a, repo_b, path_b in EXACT_CONTRACTS:
        a = scan[repo_a]["tracked_files"].get(path_a)
        b = scan[repo_b]["tracked_files"].get(path_b)
        same = a is not None and b is not None and a["sha256"] == b["sha256"]
        out.append({"left": f"{repo_a}/{path_a}",
                    "right": f"{repo_b}/{path_b}",
                    "status": "PASS" if same else "FAIL",
                    "left_sha256": a["sha256"] if a else None,
                    "right_sha256": b["sha256"] if b else None})
    return {"status": "PASS" if all(v["status"] == "PASS" for v in out)
            else "FAIL", "contracts": out}


def observed_source_collisions(scan: dict) -> list[dict]:
    """Report all shared relative *source* paths, but never presume ownership.

    Same pathname collisions across distinct projects can be intentional;
    only EXACT_CONTRACTS and the two runner family checks are enforced.
    """
    by_path = {}
    for repo in REPOSITORIES:
        if repo in EXPECTED_EMPTY:
            continue
        for name, item in scan[repo]["tracked_files"].items():
            if name not in GENERIC_FILES and name.endswith(SOURCE_SUFFIXES):
                by_path.setdefault(name, []).append((repo, item["sha256"]))
    result = []
    for filename, members in sorted(by_path.items()):
        if len(members) > 1:
            result.append({
                "path": filename,
                "repositories": [{"name": repo, "sha256": sha}
                                 for repo, sha in members],
                "same_bytes": len(set(sha for _, sha in members)) == 1})
    return result


def audit(root: Path, *, output: Path | None = None) -> dict:
    scan = {}
    missing = []
    for repo in REPOSITORIES:
        if repo in EXPECTED_EMPTY:
            continue
        directory = root / repo
        if not directory.is_dir():
            missing.append(repo)
        else:
            scan[repo] = scan_repository(directory)
    if missing:
        raise DriftError("missing repository checkouts: " + ", ".join(missing))
    runner = verify_router_runner_family(root, scan)
    cpu = verify_cpu_worker_family(root, scan)
    contracts = verify_exact_contracts(scan)
    collisions = observed_source_collisions(scan)
    failures = runner["errors"] + cpu["errors"] + [
        v["left"] + " != " + v["right"]
        for v in contracts["contracts"] if v["status"] != "PASS"]
    ]
    report = {
        "schema": "nanlm.cross-repository-source-audit/1",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "repository_count": len(REPOSITORIES),
        "observed_repositories": sorted(scan),
        "expected_empty_repositories": sorted(EXPECTED_EMPTY),
        "repositories": scan,
        "router_runner_family": runner,
        "cpu_worker_family": cpu,
        "exact_native_and_wire_contracts": contracts,
        "shared_source_path_collisions": collisions,
        "shared_source_collisions_with_different_bytes": sum(
            not item["same_bytes"] for item in collisions),
        "result": "PASS" if not failures else "FAIL",
        "errors": failures,
        "disclaimer": ("Source-byte parity and repository inventory only. "
                       "Not running-model identity, cryptographic peer "
                       "authentication, native MTH execution or training proof."),
    }
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                          encoding="utf-8")
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--output", type=Path, default=Path("nan-cross-repo-audit.json"))
    args = ap.parse_args()
    try:
        report = audit(args.root, output=args.output)
    except (DriftError, OSError, UnicodeError) as exc:
        print("CROSS-REPO AUDIT ERROR:", exc, file=sys.stderr)
        return 2
    print(json.dumps({
        "result": report["result"], "repository_count": report["repository_count"],
        "runner": report["router_runner_family"]["status"],
        "cpu": report["cpu_worker_family"]["status"],
        "native_contracts": report["exact_native_and_wire_contracts"]["status"],
        "shared_paths_with_different_bytes": (
            report["shared_source_collisions_with_different_bytes"]),
        "errors": report["errors"], "artifact": str(args.output)}, indent=2))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
