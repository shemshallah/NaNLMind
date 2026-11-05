#!/usr/bin/env python3
"""Dispatch the 6-slot NaNLMind head ring, one slot at a time.

Each slot runs `runner.yml` in `owner/nanlm-cpu-N`, processes its head shard
for one logical epoch, writes a packet set to reporam (or a local file in dev),
and exits. This script waits for each run before dispatching the next slot, so
the ring is a synchronous handoff: preload -> shift -> publish -> next.
"""
import argparse
import json
import os
import subprocess
import sys
import time

RUNNERS = 6
# Interleaved order keeps the first slot and its mirror apart.
ORDER = [0, 3, 1, 4, 2, 5]


def gh(*args, check=True, capture=True):
    cmd = ["gh", *args]
    env = dict(os.environ)
    env.setdefault("GH_TOKEN", os.environ.get("DEEPREPO_PAT", ""))
    return subprocess.run(cmd, check=check, text=True,
                          capture_output=capture, env=env)


def latest_run(repo):
    out = gh("run", "list", "-R", repo, "--workflow", "runner.yml",
             "--limit", "1", "--json", "databaseId,status,conclusion,createdAt")
    data = json.loads(out.stdout or "[]")
    return data[0] if data else None


def dispatch(repo, slot, epoch, minutes):
    gh("workflow", "run", "runner.yml", "-R", repo,
       "-f", "op=headshift", "-f", f"slot={slot + 1}", "-f", f"epoch={epoch}",
       "-f", f"minutes={minutes}")


def await_run(repo, base_id, timeout=5400, poll=15):
    start = time.time()
    while time.time() - start < timeout:
        time.sleep(poll)
        run = latest_run(repo)
        if not run:
            continue
        if base_id is not None and run.get("databaseId") == base_id:
            continue
        if run.get("status") == "completed":
            return run
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", default=os.environ.get("GITHUB_REPOSITORY_OWNER", ""))
    ap.add_argument("--epoch", type=int, default=0)
    ap.add_argument("--minutes", type=int, default=20)
    ap.add_argument("--slots", type=int, default=RUNNERS)
    ap.add_argument("--timeout", type=int, default=5400)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.owner:
        print("owner is required", file=sys.stderr)
        return 2
    if not os.environ.get("DEEPREPO_PAT") and not os.environ.get("GH_TOKEN"):
        print("DEEPREPO_PAT or GH_TOKEN is required", file=sys.stderr)
        return 2

    slots = args.slots
    order = [s for s in ORDER if s < slots] + [s for s in range(slots) if s not in ORDER]
    summary = {"epoch": args.epoch, "owner": args.owner, "slots": [], "ok": True}
    for slot in order:
        repo = f"{args.owner}/nanlm-cpu-{slot + 1}"
        base = latest_run(repo) if not args.dry_run else None
        base_id = base.get("databaseId") if base else None
        print(f"epoch {args.epoch}: dispatch {repo} (base {base_id})", flush=True)
        if args.dry_run:
            summary["slots"].append({"slot": slot, "repo": repo, "dry_run": True})
            continue
        dispatch(repo, slot, args.epoch, args.minutes)
        run = await_run(repo, base_id, timeout=args.timeout)
        ok = bool(run and run.get("conclusion") == "success")
        summary["slots"].append({"slot": slot, "repo": repo, "run": run, "ok": ok})
        if not ok:
            summary["ok"] = False
            print(f"epoch {args.epoch}: slot {slot} failed: {run}", file=sys.stderr)
            break
    print(json.dumps(summary, indent=1))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
