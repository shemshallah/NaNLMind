#!/usr/bin/env python3
"""Run the checked UTM proof and the canonical NaN0S TM gate.

Host side: the already-built C++ Turing-machine / UTM / Minsky proof tests.
Guest side: ``nan0s/tools/tm_gate.sh`` assembles one table-driven NaN16 TM and
runs it natively and under ``n16i`` (NaN16 interpreting NaN16), requiring
byte-identical output.

This is a checked-construction runner, not a mechanized theorem prover.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_NAN0S = Path(os.environ.get("NAN0S_ROOT", str(Path.home() / "nan0s")))

HOST_TESTS = (
    ("turing_machine", "build/test_turing_machine", "Turing machine tape persistence"),
    ("universal_tm", "build/test_universal_tm", "universal TM"),
    ("utm_proof", "build/test_utm_proof", "UTM proof harness"),
    ("small_utm", "build/test_small_utm", "explicit U6,4"),
    ("minsky_utm", "build/test_minsky_utm", "Minsky 23-state"),
    ("minsky_encoded", "build/test_minsky_encoded", "Minsky UTM executes"),
    ("utm_universal_desc", "build/test_utm_universal_desc", "encoded Minsky universal description"),
    ("binary_tm_compiler", "build/test_binary_tm_compiler", "TM-to-binary compiler"),
    ("binary_utm", "build/test_binary_utm", "compact binary runtime"),
    ("binary_utm_self", "build/test_binary_utm_self", "compiled binary Minsky"),
    ("tape_checkpoint", "build/test_tape_checkpoint", "tape page checkpoint"),
)

GUEST_EXPECTED = (
    "TM BINARY 1100 PASS",
    "TM UNARY 1111 PASS",
    "TM CARRY 1000 PASS",
    "TM ALL PASS",
)


def run(cmd: list[str], cwd: Path, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        capture_output=True,
        timeout=timeout,
        env={**os.environ, "LC_ALL": "C"},
    )


def build_host_tests() -> tuple[bool, str]:
    targets = [path for _, path, _ in HOST_TESTS]
    proc = run(["make", "-j1", *targets], ROOT, timeout=900)
    output = (proc.stdout + proc.stderr).strip()
    return proc.returncode == 0, output[-4000:]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nan0s-root", type=Path, default=DEFAULT_NAN0S)
    parser.add_argument("--out", type=Path, default=ROOT / "state/benchmarks/utm_proof.json")
    parser.add_argument("--require-guest", action="store_true",
                        help="fail if the canonical NaN0S checkout/gate is unavailable")
    parser.add_argument("--skip-build", action="store_true",
                        help="do not invoke make for the host test binaries")
    args = parser.parse_args(argv)

    report: dict = {
        "schema": "nanlm.utm-proof/1",
        "scope": (
            "checked construction: host table/encoded UTM tests plus a canonical "
            "NaN0S table-driven TM gate; not a mechanized proof of UTM equivalence"
        ),
        "host": {"ok": False, "tests": []},
        "guest": {"ok": False, "skipped": True},
    }

    if not args.skip_build:
        built, build_log = build_host_tests()
        report["host"]["build_ok"] = built
        report["host"]["build_log_tail"] = build_log
        if not built:
            print("HOST BUILD FAILED\n" + build_log, file=sys.stderr)
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(json.dumps(report, indent=2) + "\n")
            return 1

    host_ok = True
    for name, rel, marker in HOST_TESTS:
        binary = ROOT / rel
        if not binary.is_file():
            report["host"]["tests"].append(
                {"name": name, "ok": False, "error": f"missing {rel}"}
            )
            host_ok = False
            continue
        proc = run([str(binary)], ROOT)
        output = (proc.stdout + proc.stderr).strip()
        ok = proc.returncode == 0 and marker in output
        report["host"]["tests"].append(
            {
                "name": name,
                "ok": ok,
                "marker": marker,
                "returncode": proc.returncode,
                "output_tail": output[-1200:],
            }
        )
        if not ok:
            host_ok = False
    report["host"]["ok"] = host_ok

    nan0s = args.nan0s_root.expanduser().resolve()
    gate = nan0s / "tools" / "tm_gate.sh"
    cli = nan0s / "aarch64" / "android" / "nan_cli"
    if not gate.is_file() or not cli.is_file():
        message = f"NaN0S TM gate unavailable under {nan0s}"
        report["guest"] = {"ok": False, "skipped": True, "reason": message}
        if args.require_guest:
            print("GUEST FAILED: " + message, file=sys.stderr)
            host_ok = False
    else:
        proc = run(["sh", str(gate)], nan0s, timeout=300)
        output = (proc.stdout + proc.stderr).strip()
        missing = [line for line in GUEST_EXPECTED if line not in output]
        ok = proc.returncode == 0 and not missing and "TM GATE PASS" in output
        report["guest"] = {
            "ok": ok,
            "skipped": False,
            "root": str(nan0s),
            "gate": str(gate),
            "returncode": proc.returncode,
            "native_equals_n16i": ok and not missing,
            "expected": list(GUEST_EXPECTED),
            "missing": missing,
            "output_tail": output[-2400:],
        }
        if not ok:
            host_ok = False

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    status = "PASS" if report["host"]["ok"] and report["guest"]["ok"] else "FAIL"
    print(f"UTM PROOF {status} host={report['host']['ok']} guest={report['guest']['ok']}")
    print(f"report={args.out}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
