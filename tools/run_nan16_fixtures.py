#!/usr/bin/env python3
"""Assemble and execute the raw NaN16 adaptive-field fixtures.

The fixtures are the authority for the new mathematical path. This script only
invokes the canonical NaN0S assembler and guest runner; it performs no Boolean,
triad, field, or trig arithmetic itself.

Default NaN0S root: $NAN0S_ROOT or ~/nan0s. On a host without NaN0S the script
prints SKIP unless NAN16_REQUIRE=1 is set.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_NAN0S = Path(os.environ.get("NAN0S_ROOT", str(Path.home() / "nan0s")))
STEP_RE = re.compile(r"(\d+) steps")


@dataclass(frozen=True)
class Fixture:
    name: str
    path: str
    steps: int
    marker: str


FIXTURES = (
    Fixture("triad_vote", "mth/tests/mth_triad_vote_test.nas", 200_000,
            "MTH TRIAD VOTE PASS"),
    Fixture("field_vote", "mth/tests/mth_field_vote_test.nas", 200_000,
            "MTH FIELD VOTE PASS"),
    Fixture("q16_sin_cos", "mth/tests/mth_q16_sin_cos_test.nas", 200_000,
            "MTH Q16 SIN COS PASS"),
    Fixture("triad_remap", "mth/tests/mth_remap_test.nas", 200_000,
            "MTH TRIAD REMAP PASS"),
    Fixture("triad_remap_general", "mth/tests/mth_remap_general_test.nas", 200_000,
            "MTH GENERAL REMAP PASS"),
    Fixture("field_coherence", "mth/tests/mth_field_coherence_test.nas", 2_000_000,
            "MTH FIELD COHERENCE PASS"),
    Fixture("field_driver", "mth/tests/mth_field_driver_test.nas", 5_000_000,
            "MTH FIELD DRIVER PASS"),
)


def run_one(fixture: Fixture, nan0s: Path, out_dir: Path) -> tuple[bool, str]:
    source = ROOT / fixture.path
    if not source.is_file():
        return False, f"missing source {fixture.path}"
    image = out_dir / f"{fixture.name}.nan"
    assemble = subprocess.run(
        ["awk", "-f", str(nan0s / "tools" / "nmk.awk"), "-v", "CMD=emit", str(source)],
        cwd=ROOT, text=True, capture_output=True,
    )
    if assemble.returncode != 0 or not assemble.stdout.strip():
        return False, "assemble failed: " + (assemble.stderr.strip()[-1200:] or "empty image")
    image.write_text(assemble.stdout, encoding="utf-8")
    execute = subprocess.run(
        [str(nan0s / "aarch64" / "android" / "nan_cli"),
         "--img", str(image), "--steps", str(fixture.steps), "--serial"],
        cwd=ROOT, text=True, capture_output=True,
    )
    output = execute.stdout + execute.stderr
    match = STEP_RE.search(output)
    steps = match.group(1) if match else "?"
    if fixture.marker not in output:
        return False, f"marker missing ({fixture.marker}); steps={steps}\n{output.strip()[-1200:]}"
    return True, f"steps={steps} marker={fixture.marker}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nan0s-root", type=Path, default=DEFAULT_NAN0S)
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)
    if args.list:
        for fixture in FIXTURES:
            print(f"{fixture.name}\t{fixture.path}")
        return 0
    missing = []
    if not (args.nan0s_root / "tools" / "nmk.awk").is_file():
        missing.append(str(args.nan0s_root / "tools" / "nmk.awk"))
    if not (args.nan0s_root / "aarch64" / "android" / "nan_cli").is_file():
        missing.append(str(args.nan0s_root / "aarch64" / "android" / "nan_cli"))
    if missing:
        message = "NaN0S toolchain missing: " + ", ".join(missing)
        if os.environ.get("NAN16_REQUIRE") == "1":
            print("FAIL " + message, file=sys.stderr)
            return 2
        print("SKIP " + message)
        return 0
    selected = set(args.only)
    fixtures = [f for f in FIXTURES if not selected or f.name in selected]
    unknown = selected - {f.name for f in fixtures}
    if unknown:
        print(f"unknown fixture(s): {sorted(unknown)}", file=sys.stderr)
        return 2
    failures = 0
    with tempfile.TemporaryDirectory(prefix="nan16-fixtures-") as temp:
        out_dir = Path(temp)
        for fixture in fixtures:
            ok, detail = run_one(fixture, args.nan0s_root, out_dir)
            print(f"[{'PASS' if ok else 'FAIL'}] {fixture.name}: {detail}")
            failures += 0 if ok else 1
    print(f"{len(fixtures) - failures}/{len(fixtures)} raw NaN16 fixtures passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
