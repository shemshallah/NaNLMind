#!/usr/bin/env python3
"""Exercise the context-train backoffjoint and induction CLI routes."""
from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build" / "nanlm-universal"

EVAL_RE = re.compile(
    r"^(ctx_eval|ctx_full_eval) samples=(\d+) loss=(\S+) accuracy=(\S+)"
    r"(?: seconds=(\S+))?(?: epoch=(\d+))?$")


def make_corpus(path: Path) -> int:
    """One bucket with a high-0 majority but a much more confident low head
    under high 1.  Greedy picks (high 0, low 1); joint picks (high 1, low 0).
    """
    counts: dict[int, int] = {0x01: 165}
    spread0 = 385
    spread_lows = (0, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15)
    for low in spread_lows:
        counts[low] = spread0 // len(spread_lows)
    counts[0] += spread0 % len(spread_lows)
    counts[0x10] = 405
    spread1 = 45
    for low in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15):
        target = 0x10 | low
        counts[target] = spread1 // 15
    lines = []
    for target, count in counts.items():
        lines.extend([b"0000AAAA" + bytes([target])] * count)
    path.write_bytes(b"\n".join(lines) + b"\n")
    return sum(counts.values())


def run(args: list[str], want: int = 0) -> str:
    proc = subprocess.run([str(BINARY)] + args, cwd=ROOT, text=True,
                          capture_output=True)
    if proc.returncode != want:
        raise AssertionError(
            f"expected exit {want}, got {proc.returncode}: {' '.join(args)}\n"
            f"{proc.stdout[-3000:]}\n{proc.stderr[-2000:]}")
    return proc.stdout + proc.stderr


def final_accuracy(output: str) -> float:
    final = None
    for line in output.splitlines():
        match = EVAL_RE.match(line.strip())
        if match and match.group(1) == "ctx_full_eval":
            final = float(match.group(4))
    if final is None:
        raise AssertionError(f"missing ctx_full_eval:\n{output[-3000:]}")
    return final


def first_train_loss(output: str) -> str:
    match = re.search(r"^ctx_epoch .*?\btrain_loss=(\S+)", output, re.M)
    if match is None:
        raise AssertionError(f"missing ctx_epoch:\n{output[-3000:]}")
    return match.group(1)


def main() -> int:
    if not BINARY.is_file():
        print("SKIP context-train routes: binary missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-context-routes-"))
    try:
        corpus = tmp / "corpus.txt"
        samples = make_corpus(corpus)

        # Guest backoff baseline checkpoint, then re-score it with greedy and
        # joint selection.  Both runs use the identical table.
        guest_cp = tmp / "guest.ctx"
        baseline = run(["context-train", str(corpus), "0", "1", "1000",
                        "4", "4", "0.1", "1", "1", "guestbackoff", "0",
                        f"save={guest_cp}"])
        assert f"ctx_full_eval samples={samples}" in baseline
        assert guest_cp.is_file()
        greedy = run(["context-train", str(corpus), "0", "0", "1000",
                      "4", "4", "0.1", "1", "1", "guestbackoff", "0",
                      f"load={guest_cp}"])
        joint = run(["context-train", str(corpus), "0", "0", "1000",
                     "4", "4", "0.1", "1", "1", "backoffjoint", "0",
                     f"load={guest_cp}"])
        assert "joint_readout=1" in joint
        assert "selected=guest_backoff" in joint
        greedy_acc = final_accuracy(greedy)
        joint_acc = final_accuracy(joint)
        assert joint_acc > greedy_acc + 10.0, (greedy_acc, joint_acc)

        # The same backoffjoint route accepts a checkpoint written by the
        # legacy host backoff route and selects that matching bucket map.
        host_cp = tmp / "host.ctx"
        run(["context-train", str(corpus), "0", "1", "1000",
             "4", "4", "0.1", "1", "1", "backoff", "0",
             f"save={host_cp}"])
        host_greedy = run(["context-train", str(corpus), "0", "0", "1000",
                           "4", "4", "0.1", "1", "1", "backoff", "0",
                           f"load={host_cp}"])
        host_joint = run(["context-train", str(corpus), "0", "0", "1000",
                          "4", "4", "0.1", "1", "1", "backoffjoint", "0",
                          f"load={host_cp}"])
        assert "selected=host_backoff" in host_joint
        host_greedy_acc = final_accuracy(host_greedy)
        host_joint_acc = final_accuracy(host_joint)
        assert host_joint_acc > host_greedy_acc + 10.0, (
            host_greedy_acc, host_joint_acc)

        # A fresh backoffjoint run trains through the same guest backoff route
        # and evaluates with the joint rule.
        fresh_joint = run(["context-train", str(corpus), "0", "2", "1000",
                           "4", "4", "0.1", "1", "1", "backoffjoint", "0"])
        assert f"ctx_full_eval samples={samples}" in fresh_joint
        assert "context_guest_backoff" in fresh_joint
        assert "joint_readout=1" in fresh_joint
        final_accuracy(fresh_joint)

        # Induction trains the guest 4-byte memory plus the 2-byte suffix
        # copy table in one route.  The shared memory trajectory must match
        # the guest backoff route with the same exact-key selection.
        guest_exact = run(["context-train", str(corpus), "0", "1", "1000",
                           "4", "4", "0.1", "1", "1", "guestbackoff", "1"])
        induction = run(["context-train", str(corpus), "0", "1", "1000",
                         "4", "4", "0.1", "1", "1", "induction", "1",
                         "aux=4", "weight=0.15"])
        assert f"ctx_full_eval samples={samples}" in induction
        assert "context_induction exact=1" in induction
        assert "route=induction" in induction
        assert "joint_readout=0" in induction
        assert first_train_loss(induction) == first_train_loss(guest_exact)
        final_accuracy(induction)

        # The suffix table has no checkpoint format yet: reject both
        # directions instead of silently writing a partial checkpoint.
        for option in (f"save={tmp / 'induction.ctx'}",
                       f"load={guest_cp}"):
            failed = run(["context-train", str(corpus), "0", "1", "1000",
                          "4", "4", "0.1", "1", "1", "induction", "1",
                          "aux=4", "weight=0.15", option], want=2)
            assert "induction does not persist" in failed
            assert "checkpointed" in failed
        assert not (tmp / "induction.ctx").exists()
        print("PASS context-train backoffjoint and induction routes")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
