#!/usr/bin/env python3
"""Run the complete local UTM proof/execution evidence gate.

The Coq kernel proof itself runs in GitHub Actions (or locally with Coq);
this gate collects the executable evidence that does not require a local Coq
install: native NaN16 Minsky execution, C++ runtime trace conformance,
exhaustive C++ chart conformance, host UTM proof tests, and the canonical NaN0S
TM gate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CHECKS = [
    ("native_minsky", ["python3", "tools/run_nan16_fixtures.py", "--only", "minsky_table"],
     "MTH MINSKY NATIVE PASS"),
    ("native_minsky_encoded", ["python3", "tools/run_nan16_fixtures.py", "--only", "minsky_encoded"],
     "MTH MINSKY NATIVE PASS"),
    ("cpp_trace", ["python3", "tools/check_minsky_trace.py"],
     "MINSKY C++ TRACE CONFORMANCE PASS"),
    ("cpp_chart", ["make", "-j2", "minsky-bridge-check"],
     "PASS Minsky chart refinement"),
    ("host_utm_gate", ["make", "-j2", "utm-proof"],
     "UTM PROOF PASS"),
]

THEOREMS = [
    "UTMEquivalence.UTM_halting_equivalence",
    "UTMEquivalence.UTM_halting_undecidable",
    "InterpreterRefinement.utm_run_refines",
    "MinskyTable.find_entry_scan_all",
    "MinskyTable.step_indexed_scan_agree_all",
    "MinskyTable.run_indexed_scan_agree_all",
    "MinskyTable.minsky_trace_100",
    "MinskyTable.minsky_halt_updates_before_flag",
    "MinskyAddressRefinement.zipper_address_step_bisim",
    "MinskyAddressRefinement.zipper_address_run_bisim",
    "MinskyAddressRefinement.address_halt_writes_before_flag",
    "MinskyAddressRefinement.address_trace_100",
]

FILES = [
    "formal/utm/UTMEquivalence.v",
    "formal/utm/InterpreterRefinement.v",
    "formal/utm/MinskyTable.v",
    "formal/utm/MinskyTableData.v",
    "formal/utm/MinskyAddressRefinement.v",
    "tests/minsky_table.inc",
    "mth/tests/mth_minsky_test.nas",
]

def run(cmd: list[str], timeout: int = 900) -> tuple[int, str]:
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True,
                          timeout=timeout)
    return proc.returncode, (proc.stdout + proc.stderr).strip()

def sha(path: str) -> str:
    h = hashlib.sha256()
    h.update((ROOT / path).read_bytes())
    return h.hexdigest()

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path,
                    default=ROOT / "state/benchmarks/utm_publication_gate.json")
    ap.add_argument("--coq-run-url", default="")
    args = ap.parse_args(argv)
    checks = []
    ok = True
    for name, cmd, marker in CHECKS:
        rc, output = run(cmd)
        passed = rc == 0 and marker in output
        checks.append({"name": name, "command": cmd, "ok": passed,
                       "marker": marker, "output_tail": output[-2500:]})
        if not passed:
            ok = False
    trace_hash = ""
    trace_lines = 0
    trace_tool = ROOT / "build" / "minsky-trace-dump"
    if trace_tool.is_file():
        trace = subprocess.check_output([str(trace_tool)], text=True)
        trace_hash = hashlib.sha256(trace.encode()).hexdigest()
        trace_lines = len([line for line in trace.splitlines()
                           if line.startswith("TRACE ")])
    report = {
        "schema": "nanlm.utm-publication-gate/1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "status": "pass" if ok else "fail",
        "coq_run_url": args.coq_run_url,
        "checks": checks,
        "trace_sha256": trace_hash,
        "trace_lines": trace_lines,
        "theorems": THEOREMS,
        "source_sha256": {p: sha(p) for p in FILES},
        "scope": {
            "proved": "fixed-UTM halting equivalence; concrete 184-entry Minsky table; indexed/scan agreement; signed-address zipper bisimulation for every fuel-bounded run; halt-write ordering.",
            "executed": "native NaN16 100-step Minsky trace; exhaustive C++ 184-entry chart conformance; C++ trace conformance; canonical NaN0S TM gate.",
            "not_claimed": "full universality of the concrete 23x8 table for arbitrary encoded machines; formal extraction/link of the compiled C++ binary; chart allocator/compiler refinement."
        }
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"UTM PUBLICATION GATE {'PASS' if ok else 'FAIL'}")
    print(f"report={args.out}")
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())
