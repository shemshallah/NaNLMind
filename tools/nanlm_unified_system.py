#!/usr/bin/env python3
"""One orchestration entry point for the native NaNLMind system.

This tool never performs model mathematics. It reports existing artifacts and
delegates training/evaluation/context commands to the native binaries.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
STATE = ROOT / "state" / "benchmarks"


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def collect_status() -> dict:
    artifacts = {
        "byte_direct256": STATE / "system_byte_direct256.json",
        "word_native": STATE / "word_native.json",
        "token_1b": STATE / "train_1b.json",
        "token_full_100k": STATE / "train_100k_full.json",
        "unified_tests": STATE / "unified_test_base.json",
    }
    components = {}
    for name, path in artifacts.items():
        payload = read_json(path)
        components[name] = {
            "status": "present" if payload is not None else "missing",
            "artifact": str(path.relative_to(ROOT)),
            "schema": payload.get("schema") if isinstance(payload, dict) else None,
        }
    tests = read_json(STATE / "unified_test_base.json")
    test_summary = tests.get("summary") if isinstance(tests, dict) else None
    return {
        "schema": "nanlm.unified-system-status/1",
        "mode": "host orchestration only; native projection/context math",
        "components": {
            "projection_runtime": "include/nanlm/projection_runtime.hpp",
            "context_runtime": "include/nanlm/unified_context_runtime.hpp",
            "byte_readout": "mth/nan16/mth_context_direct256.nas",
            "word_projection": "mth/nan16/mth_word_projection.nas",
            "token_projection": "mth/nan16/mth_token_projection.nas",
        },
        "artifacts": components,
        "tests": test_summary,
        "commands": {
            "byte": "build/direct256-bench",
            "word": "build/word-native",
            "token_1b": "build/train-1b",
            "token_full": "build/train-1b-full",
            "context": "build/nanlm-unified-context",
            "check": "tools/unified_test_base.py",
        },
    }


COMMANDS = {
    "byte": BUILD / "direct256-bench",
    "word": BUILD / "word-native",
    "token-1b": BUILD / "train-1b",
    "token-full": BUILD / "train-1b-full",
    "context": BUILD / "nanlm-unified-context",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status", help="report integrated components and artifacts")
    status.add_argument("--out", type=Path)
    for name, binary in COMMANDS.items():
        p = sub.add_parser(name, help=f"delegate to {binary.relative_to(ROOT)}")
        p.add_argument("args", nargs=argparse.REMAINDER)
    check = sub.add_parser("check", help="run the unified native test base")
    check.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.command == "status":
        result = collect_status()
        encoded = json.dumps(result, indent=2)
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(encoded + "\n", encoding="utf-8")
        print(encoded)
        return 0
    if args.command == "check":
        command = [sys.executable, str(ROOT / "tools" / "unified_test_base.py")]
        command += args.args
        return subprocess.run(command, cwd=ROOT, check=False).returncode
    binary = COMMANDS[args.command]
    if not binary.is_file():
        print(f"unified_system_error: missing binary {binary}", file=sys.stderr)
        return 2
    return subprocess.run([str(binary)] + args.args, cwd=ROOT,
                          check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
