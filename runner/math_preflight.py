"""Worker-side launcher for the canonical NaN16 mathematical preflight guest.

This module is orchestration only: all parsing, contract resolution, shape
validation, and mathematical checks execute in the NaN16 guest sources owned
by NaN0S and NaNROUTER. Python only assembles, launches, and records evidence.
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any

_STATUS_RE = re.compile(r"\brc=(\d+),\s*pc=(\d+),\s*trap='([^']*)'")


class MathPreflightError(RuntimeError):
    """The canonical NaN16 preflight guest could not be verified."""


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _bundle_digest(root: Path, paths: tuple[str, ...]) -> str:
    digest = hashlib.sha256()
    for relative in paths:
        path = root / relative
        if not path.is_file():
            raise MathPreflightError(f"required native math source missing: {relative}")
        raw = path.read_bytes()
        digest.update(relative.encode("utf-8"))
        digest.update(len(raw).to_bytes(8, "little"))
        digest.update(raw)
    return digest.hexdigest()


def run_preflight(*, runner_id: str, timeout_seconds: int = 90) -> dict[str, Any]:
    """Assemble and execute the real :: linker -> registry -> MTH preflight guest."""
    router_root = Path(os.environ.get("NANROUTER_ROOT", "nanrouter")).resolve()
    nan0s_root = Path(os.environ.get("NAN0S_ROOT", str(router_root / "nan0s"))).resolve()
    fixture_rel = "mth/tests/mth_linker_preflight_test.nas"
    fixture = router_root / fixture_rel
    assembler = nan0s_root / "tools" / "nmk.awk"
    nan_cli = nan0s_root / "aarch64" / "android" / "nan_cli"
    if not fixture.is_file() or not assembler.is_file() or not nan_cli.is_file():
        raise MathPreflightError("NaNROUTER fixture, NaN0S assembler, or native guest runner is missing")

    router_sources = (
        "mth/nan16/mth_preflight.nas",
        "mth/tests/mth_linker_preflight_test.nas",
    )
    registry_sources = (
        "src/nannet/route_address.nas",
        "src/nannet/object_key_decode.nas",
        "src/nannet/math_registry.nas",
        "src/nannet/route_object_resolve.nas",
        "src/nannet/vector_ops.nas",
        "src/nannet/mc0db_scratch.nas",
        "src/nannet/math_expression.nas",
    )
    with tempfile.TemporaryDirectory(prefix="nanlm-math-preflight-") as tmp:
        image = Path(tmp) / "linker-preflight.nan"
        assembled = subprocess.run(
            ["awk", "-f", str(assembler), "-v", "CMD=emit", str(fixture)],
            cwd=router_root, text=True, capture_output=True,
            timeout=timeout_seconds, check=False,
        )
        if assembled.returncode != 0 or not assembled.stdout.strip():
            raise MathPreflightError(
                "NaN16 assembly failed: " + (assembled.stderr.strip() or assembled.stdout[-1200:])
            )
        image.write_text(assembled.stdout, encoding="utf-8")
        executed = subprocess.run(
            [str(nan_cli), "--img", str(image), "--steps", "3000000", "--serial"],
            cwd=router_root, text=True, capture_output=True,
            timeout=timeout_seconds, check=False,
        )
        status = _STATUS_RE.search(executed.stderr)
        marker = "MTH LINKER PREFLIGHT PASS"
        if (marker not in executed.stdout or not status or status.group(1) != "3"
                or status.group(3) or executed.returncode != 0):
            raise MathPreflightError(
                "NaN16 guest did not complete the linker/preflight contract: "
                + (executed.stdout[-800:] + " " + executed.stderr[-800:])
            )
        return {
            "ok": True,
            "protocol": "NAN16-MTH-PREFLIGHT/1",
            "runner_id": runner_id,
            "guest": "nan://...::op:77::nan://...",
            "result_marker": marker,
            "guest_exit": int(status.group(1)),
            "guest_pc": int(status.group(2)),
            "trap": status.group(3),
            "fixture_sha256": _digest(fixture),
            "router_source_sha256": _bundle_digest(router_root, router_sources),
            "registry_source_sha256": _bundle_digest(nan0s_root, registry_sources),
            "assembler_sha256": _digest(assembler),
            "nan_cli_sha256": _digest(nan_cli),
            "assembly_image_lines": sum(1 for line in assembled.stdout.splitlines() if line.strip()),
            "guest_stdout_tail": executed.stdout.strip().splitlines()[-4:],
        }
