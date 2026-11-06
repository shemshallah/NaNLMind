#!/usr/bin/env python3
"""Dispatch the 6-slot NaNLMind head ring, one slot at a time.

Each slot runs `runner.yml` in `owner/nanlm-cpu-N`, processes its head shard
for one logical epoch, writes a packet set to the NaNLMind head store (or a local file in dev),
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


def gh(*args, check=True, capture=True, retries=4):
    cmd = ["gh", *args]
    env = dict(os.environ)
    env.setdefault("GH_TOKEN", os.environ.get("DEEPREPO_PAT", ""))
    last = None
    for attempt in range(retries):
        try:
            return subprocess.run(cmd, check=check, text=True,
                                  capture_output=capture, env=env)
        except subprocess.CalledProcessError as exc:
            last = exc
            text = ((exc.stderr or "") + (exc.stdout or "") + repr(exc)).lower()
            if "rate limit" in text or "403" in text:
                time.sleep(60)
            else:
                time.sleep(min(30, 3 * (attempt + 1)))
    if check:
        raise last
    return last


def latest_run(repo):
    try:
        out = gh("run", "list", "-R", repo, "--workflow", "runner.yml",
                 "--limit", "1", "--json", "databaseId,status,conclusion,createdAt",
                 check=False)
    except Exception:
        return None
    if out is None or not getattr(out, "stdout", ""):
        return None
    try:
        data = json.loads(out.stdout or "[]")
    except Exception:
        return None
    return data[0] if data else None


def dispatch(repo, op, slot, epoch, minutes, epochs=10):
    gh("workflow", "run", "runner.yml", "-R", repo,
       "-f", f"op={op}", "-f", f"slot={slot + 1}", "-f", f"epoch={epoch}",
       "-f", f"minutes={minutes}", "-f", f"epochs={epochs}")


def read_clock():
    try:
        from deepcore.runtime import Env  # type: ignore
        env = Env(writer=False)
        clock = env.regs.get("nanlm/clock") or {}
        tick = int(clock.get("tick", -1))
        return tick if tick >= 0 else None
    except Exception:
        return None


def await_run(repo, base_id, timeout=21600, poll=60):
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
    ap.add_argument("--timeout", type=int, default=21600)
    ap.add_argument("--poll", type=int, default=60)
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--op", choices=["headshift", "logic", "logic-core", "training"], default="headshift")
    ap.add_argument("--persistent", action="store_true",
                    help="one loop job processes many epochs in one workspace")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--parallel", dest="parallel", action="store_true", default=False,
                    help="experimental: six writers at once (unsafe for the single NaNLMind head journal)")
    ap.add_argument("--sequential", dest="parallel", action="store_false")
    args = ap.parse_args()

    if not args.owner:
        print("owner is required", file=sys.stderr)
        return 2
    if not os.environ.get("DEEPREPO_PAT") and not os.environ.get("GH_TOKEN"):
        print("DEEPREPO_PAT or GH_TOKEN is required", file=sys.stderr)
        return 2

    slots = args.slots
    order = [s for s in ORDER if s < slots] + [s for s in range(slots) if s not in ORDER]
    summary = {"epoch": args.epoch, "owner": args.owner, "parallel": args.parallel,
               "slots": [], "ok": True}

    def repo_for(slot):
        return f"{args.owner}/nanlm-cpu-{slot + 1}"

    if args.op in ("logic", "logic-core", "training"):
        for slot in order:
            repo = repo_for(slot)
            base = latest_run(repo) if not args.dry_run else None
            base_id = base.get("databaseId") if base else None
            print(f"epoch {args.epoch}: dispatch {args.op} {repo}", flush=True)
            if args.dry_run:
                summary["slots"].append({"slot": slot, "repo": repo, "dry_run": True})
                continue
            dispatch(repo, args.op, slot, args.epoch, args.minutes)
            run = await_run(repo, base_id, timeout=args.timeout, poll=args.poll)
            ok = bool(run and run.get("conclusion") == "success")
            summary["slots"].append({"slot": slot, "repo": repo, "run": run, "ok": ok})
            if not ok:
                summary["ok"] = False
                break
        print(json.dumps(summary, indent=1))
        return 0 if summary["ok"] else 1

    if args.persistent:
        slot = args.epoch % max(1, slots)
        repo = repo_for(slot)
        base = latest_run(repo) if not args.dry_run else None
        base_id = base.get("databaseId") if base else None
        print(f"epoch {args.epoch}: persistent loop on {repo}", flush=True)
        if not args.dry_run:
            dispatch(repo, "loop", slot, args.epoch, args.minutes, args.epochs)
            run = await_run(repo, base_id, timeout=args.timeout, poll=args.poll)
            ok = bool(run and run.get("conclusion") == "success")
            summary["slots"].append({"slot": slot, "repo": repo, "run": run, "ok": ok})
            summary["epochs"] = args.epochs
            summary["next_epoch"] = read_clock() or (args.epoch + args.epochs)
            summary["ok"] = ok
        print(json.dumps(summary, indent=1))
        return 0 if summary["ok"] else 1

    if args.parallel:
        # Two-phase prepare: all slots preload/publish their packets, then a
        # single finalize run verifies the 256-head round and flips the manifest.
        bases = {}
        for slot in order:
            repo = repo_for(slot)
            base = latest_run(repo) if not args.dry_run else None
            bases[slot] = base.get("databaseId") if base else None
            print(f"epoch {args.epoch}: dispatch {repo} (base {bases[slot]})", flush=True)
            if not args.dry_run:
                dispatch(repo, args.op, slot, args.epoch, args.minutes)
        for slot in order:
            repo = repo_for(slot)
            if args.dry_run:
                summary["slots"].append({"slot": slot, "repo": repo, "dry_run": True})
                continue
            run = await_run(repo, bases[slot], timeout=args.timeout, poll=args.poll)
            ok = bool(run and run.get("conclusion") == "success")
            summary["slots"].append({"slot": slot, "repo": repo, "run": run, "ok": ok})
            if not ok:
                summary["ok"] = False
                print(f"epoch {args.epoch}: slot {slot} failed: {run}", file=sys.stderr)
    else:
        for slot in order:
            repo = repo_for(slot)
            base = latest_run(repo) if not args.dry_run else None
            base_id = base.get("databaseId") if base else None
            print(f"epoch {args.epoch}: dispatch {repo} (base {base_id})", flush=True)
            if args.dry_run:
                summary["slots"].append({"slot": slot, "repo": repo, "dry_run": True})
                continue
            dispatch(repo, args.op, slot, args.epoch, args.minutes)
            run = await_run(repo, base_id, timeout=args.timeout, poll=args.poll)
            ok = bool(run and run.get("conclusion") == "success")
            summary["slots"].append({"slot": slot, "repo": repo, "run": run, "ok": ok})
            if not ok:
                summary["ok"] = False
                print(f"epoch {args.epoch}: slot {slot} failed: {run}", file=sys.stderr)
                break

    if summary["ok"] and not args.dry_run:
        repo = repo_for(0)
        base = latest_run(repo)
        base_id = base.get("databaseId") if base else None
        print(f"epoch {args.epoch}: finalize round on {repo}", flush=True)
        dispatch(repo, "finalize", 0, args.epoch, args.minutes)
        run = await_run(repo, base_id, timeout=args.timeout, poll=args.poll)
        ok = bool(run and run.get("conclusion") == "success")
        summary["finalize"] = {"repo": repo, "run": run, "ok": ok}
        if not ok:
            summary["ok"] = False
    print(json.dumps(summary, indent=1))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
