#!/usr/bin/env python3
"""Compare host-routed and raw-guest-routed WordNet context backoff.

Both routes use the same class-memory tables, bucket count, learning rate and
split.  The only difference is who owns the k=4 exact/compact lookup and the
k=3 fallback: the old `backoff` route computes it in src/trunk_train.cpp; the
new `guestbackoff` route builds and queries it in
mth/nan16/mth_context_backoff.nas.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

EVAL_RE = re.compile(
    r"ctx_full_eval samples=(\d+) loss=([0-9.eE+-]+) accuracy=([0-9.]+)"
)
ROUTE_RE = re.compile(
    r"context_guest_backoff exact=(\d+) fallback=(\d+) threshold=(\d+) "
    r"unique=(\d+)"
)


def run_case(binary: Path, corpus: Path, log_dir: Path, name: str,
             route: str, epochs: int, fraction: str, buckets: int,
             exact: int, lr: str) -> dict:
    log = log_dir / f"{name}.log"
    cmd = [
        str(binary), "context-train", str(corpus), "0", str(epochs),
        "100000", str(buckets), "4", lr, "1", fraction, route, str(exact),
    ]
    print("+", " ".join(cmd), flush=True)
    with log.open("w", encoding="utf-8") as out:
        subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT, check=True)
    text = log.read_text(encoding="utf-8")
    match = None
    for match in EVAL_RE.finditer(text):
        pass
    if match is None:
        raise SystemExit(f"no ctx_full_eval line in {log}")
    result = {
        "name": name,
        "route": route,
        "samples": int(match.group(1)),
        "loss": float(match.group(2)),
        "accuracy": float(match.group(3)),
    }
    route_match = None
    for route_match in ROUTE_RE.finditer(text):
        pass
    if route_match is not None:
        result.update({
            "exact": int(route_match.group(1)),
            "fallback": int(route_match.group(2)),
            "threshold": int(route_match.group(3)),
            "unique": int(route_match.group(4)),
        })
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", type=Path,
                    default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--binary", type=Path,
                    default=Path("build/nanlm-universal"))
    ap.add_argument("--log-dir", type=Path, default=Path("logs/backoff_bench"))
    ap.add_argument("--buckets", type=int, default=11456)
    ap.add_argument("--exact", type=int, default=10500)
    ap.add_argument("--lr", default="0.1")
    ap.add_argument("--epochs-same", type=int, default=3)
    ap.add_argument("--epochs-holdout", type=int, default=5)
    args = ap.parse_args()

    if not args.corpus.is_file():
        print(f"corpus not found: {args.corpus}", file=sys.stderr)
        print("copy state/wordnet_corpus.txt from the main tree read-only",
              file=sys.stderr)
        return 2
    if not args.binary.is_file():
        print(f"binary not found: {args.binary}", file=sys.stderr)
        return 2
    args.log_dir.mkdir(parents=True, exist_ok=True)

    cases = [
        ("same_host", "backoff", args.epochs_same, "1.0"),
        ("same_guest", "guestbackoff", args.epochs_same, "1.0"),
        ("holdout_host", "backoff", args.epochs_holdout, "0.8"),
        ("holdout_guest", "guestbackoff", args.epochs_holdout, "0.8"),
    ]
    results = {}
    for name, route, epochs, fraction in cases:
        results[name] = run_case(
            args.binary, args.corpus, args.log_dir, name, route, epochs,
            fraction, args.buckets, args.exact, args.lr)

    for family in ("same", "holdout"):
        host = results[f"{family}_host"]
        guest = results[f"{family}_guest"]
        acc_delta = guest["accuracy"] - host["accuracy"]
        loss_delta = guest["loss"] - host["loss"]
        print(f"\n{family}:")
        print(f"  host  samples={host['samples']} loss={host['loss']:.6f} "
              f"accuracy={host['accuracy']:.4f}%")
        print(f"  guest samples={guest['samples']} loss={guest['loss']:.6f} "
              f"accuracy={guest['accuracy']:.4f}%")
        if "exact" in guest:
            print(f"  guest route exact={guest['exact']} "
                  f"fallback={guest['fallback']} "
                  f"threshold={guest['threshold']} unique={guest['unique']}")
        print(f"  delta accuracy={acc_delta:+.4f} pp  "
              f"delta loss={loss_delta:+.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
