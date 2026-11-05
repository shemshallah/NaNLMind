#!/usr/bin/env python3
"""Global wall-clock anchor for NaNLMind.

The logical clock orders state. This script anchors it to real time by sampling
independent HTTPS time sources, taking the median offset, estimating
uncertainty, and rejecting outliers. It writes a `nanlm/atomic` record to the
one register log (when deepcore/tiers are available) and a local JSON snapshot.

This is an anchored wall clock, not a local atomic clock. It is used for lease
expiry and human timestamps; it never reorders state transitions.
"""
import argparse
import datetime as dt
import email.utils
import json
import os
import statistics
import sys
import time
import urllib.request
from pathlib import Path

SOURCES = [
    ("github", "https://api.github.com/rate_limit"),
    ("worldtimeapi", "https://worldtimeapi.org/api/timezone/Etc/UTC"),
    ("timeapi", "https://timeapi.io/api/Time/current/zone?timeZone=UTC"),
]


def _request(url, timeout=10):
    req = urllib.request.Request(url, headers={
        "User-Agent": "NaNLMind-atomic-clock",
        "Accept": "application/json,text/plain,*/*",
    })
    t0 = time.time_ns()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
        date = r.headers.get("Date")
        t1 = time.time_ns()
    return t0, t1, body, date


def _sample_github(timeout):
    t0, t1, body, date = _request(SOURCES[0][1], timeout)
    if not date:
        raise RuntimeError("no Date header")
    parsed = email.utils.parsedate_to_datetime(date)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.timestamp(), (t1 - t0) / 2e9 + 1.0, "github-date"  # 1s granularity


def _sample_worldtime(timeout):
    t0, t1, body, _ = _request(SOURCES[1][1], timeout)
    data = json.loads(body.decode())
    return float(data["unixtime"]), (t1 - t0) / 2e9 + 0.01, "worldtimeapi"


def _sample_timeapi(timeout):
    t0, t1, body, _ = _request(SOURCES[2][1], timeout)
    data = json.loads(body.decode())
    s = data.get("dateTime") or data.get("date_time")
    if not s:
        raise RuntimeError("no dateTime")
    parsed = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.timestamp(), (t1 - t0) / 2e9 + 0.001, "timeapi"


def median_anchor(samples, max_uncertainty=5.0):
    """samples: [(unix_seconds, uncertainty_seconds, source, local_mid)]."""
    good = [s for s in samples if s[1] <= max_uncertainty]
    if len(good) < 2:
        raise RuntimeError(f"need >=2 good samples, got {len(good)}")
    offsets = sorted(s[0] - s[3] for s in good)
    median = statistics.median(offsets)
    # reject a source more than 2 s from the median (bad clock / captive portal)
    kept = [s for s in good if abs((s[0] - s[3]) - median) <= 2.0]
    if len(kept) < 2:
        raise RuntimeError("no consistent time sources")
    offsets = sorted(s[0] - s[3] for s in kept)
    median = statistics.median(offsets)
    mad = statistics.median(abs(x - median) for x in offsets) if len(offsets) > 1 else 0.0
    uncertainty = max(mad * 1.4826, max(s[1] for s in kept))
    wall = time.time() + median
    return {
        "ok": True,
        "wall_unix": wall,
        "offset_s": median,
        "uncertainty_s": uncertainty,
        "sources": [{"source": s[2], "offset_s": s[0] - s[3], "uncertainty_s": s[1]}
                    for s in kept],
        "at": int(time.time()),
    }


def collect(timeout=10):
    samples = []
    errors = []
    for fn in (_sample_github, _sample_worldtime, _sample_timeapi):
        try:
            server, unc, name = fn(timeout)
            local_mid = time.time()
            samples.append((server, unc, name, local_mid))
        except Exception as exc:
            errors.append(f"{fn.__name__}: {exc}")
    anchor = median_anchor(samples)
    anchor["errors"] = errors
    return anchor


def write_anchor(anchor, local=True, tiers=True):
    out = Path(os.environ.get("NANLM_LOCAL_STATE", "state"))
    out.mkdir(parents=True, exist_ok=True)
    (out / "atomic.json").write_text(json.dumps(anchor, indent=1))
    if not tiers:
        return
    try:
        from deepcore.runtime import Env  # type: ignore
        env = Env(writer=True)
        env.regs.put("nanlm/atomic", anchor, commit=True)
        print("wrote nanlm/atomic", file=sys.stderr)
    except Exception as exc:
        print(f"tier-anchor-unavailable: {exc}", file=sys.stderr)


def self_test():
    # Deterministic synthetic samples: local mid 1000, offsets +1, +1.1, +1.05.
    samples = [
        (1001.0, 0.5, "a", 1000.0),
        (1001.1, 0.5, "b", 1000.0),
        (1001.05, 0.5, "c", 1000.0),
        (5000.0, 0.5, "outlier", 1000.0),
    ]
    a = median_anchor(samples)
    assert abs(a["offset_s"] - 1.05) < 0.06, a
    assert a["uncertainty_s"] < 1.0, a
    assert len(a["sources"]) == 3, a
    print(json.dumps(a, indent=1))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sync", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--no-tiers", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if not args.sync:
        ap.print_help()
        return 2
    try:
        anchor = collect(args.timeout)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        return 1
    write_anchor(anchor, tiers=not args.no_tiers)
    print(json.dumps(anchor, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
