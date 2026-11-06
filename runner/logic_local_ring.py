#!/usr/bin/env python3
"""Run the six logic-curriculum runners locally in parallel.

This is the local rehearsal for the GitHub runner workflow: each slot is a
separate `nanlm_worker.py --op logic` process with its own state directory.
Slots start at different curriculum levels so the ring exercises several
difficulties at once.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "runner" / "nanlm_worker.py"
LEVELS = 5


def run_slot(slot: int, epoch: int, rounds: int, session_rounds: int,
             start_override: int, op: str, state_root: Path) -> dict:
    state = state_root / f"slot{slot}"
    state.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["NANLM_LOCAL_STATE"] = str(state)
    start = start_override if start_override >= 0 else (slot - 1) % LEVELS
    cmd = [
        sys.executable, str(WORKER), "--op", op,
        "--slot", str(slot), "--epoch", str(epoch),
        "--rounds", str(rounds), "--session-rounds", str(session_rounds),
        "--start-level", str(start),
    ]
    result = subprocess.run(cmd, text=True, capture_output=True, env=env)
    prefix = "logic_core" if op == "logic-core" else "logic"
    out = state / f"{prefix}_{epoch}_{slot - 1}.json"
    record = None
    if out.exists():
        try:
            record = json.loads(out.read_text())
        except Exception:
            record = None
    return {
        "slot": slot,
        "start_level": start,
        "returncode": result.returncode,
        "ok": result.returncode == 0 and bool(record and record.get("ok")),
        "record": record,
        "stderr": result.stderr[-500:],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--slots", type=int, default=6)
    parser.add_argument("--epoch", type=int, default=0)
    parser.add_argument("--rounds", type=int, default=4)
    parser.add_argument("--session-rounds", type=int, default=0)
    parser.add_argument("--start-level", type=int, default=-1,
                        help="override the per-slot start level")
    parser.add_argument("--op", choices=["logic", "logic-core"], default="logic")
    parser.add_argument("--state-root", default="state/logic_ring")
    parser.add_argument("--out", default="")
    args = parser.parse_args(argv)

    slots = max(1, min(6, args.slots))
    root = Path(args.state_root)
    results = []
    with ThreadPoolExecutor(max_workers=slots) as pool:
        futures = {
            pool.submit(run_slot, slot, args.epoch, args.rounds,
                        args.session_rounds, args.start_level, args.op, root): slot
            for slot in range(1, slots + 1)
        }
        for future in as_completed(futures):
            results.append(future.result())
    results.sort(key=lambda item: item["slot"])
    summary = {
        "ok": all(item["ok"] for item in results),
        "epoch": args.epoch,
        "slots": slots,
        "start_level": args.start_level,
        "improved": any(
            item["record"] and item["record"].get("improved")
            for item in results
        ),
        "results": results,
    }
    encoded = json.dumps(summary, indent=1, sort_keys=True) + "\n"
    if args.out:
        path = Path(args.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(encoded)
    sys.stdout.write(encoded)
    if not summary["ok"]:
        for item in results:
            if not item["ok"]:
                detail = item.get("stderr") or "worker exited without a recorded error"
                print(f"logic ring slot {item['slot']} failed (exit {item['returncode']}): {detail}",
                      file=sys.stderr)
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
