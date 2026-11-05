#!/usr/bin/env python3
"""NaNLMind head-ring worker.

Ops:
  selftest   build + verify the core, write the gate record
  prewarm    verify, print the head map, write no state
  headshift  process one slot's heads for one logical epoch
  handoff    alias for headshift (explicit preload/handoff intent)
  status     show ring state

The worker uses the deeprepo tier registers when they are available:
  nanlm/gate
  nanlm/clock
  nanlm/lease
  nanlm/head/<epoch>/<slot>
  nanlm/round/<epoch>
  nanlm/manifest

If the tiers are unavailable, it falls back to a local JSON file and still
produces a deterministic packet set. That fallback is for development only.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

RUNNERS = 6
HEADS = 256
SLOT_NAMES = [f"nanlm-cpu-{i}" for i in range(1, RUNNERS + 1)]


def head_map():
    return {str(slot): [h for h in range(HEADS) if h % RUNNERS == slot]
            for slot in range(RUNNERS)}


def parse_slot(value):
    if value is None:
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        name = repo.rsplit("/", 1)[-1]
        if name.startswith("nanlm-cpu-"):
            value = name.rsplit("-", 1)[-1]
    try:
        slot = int(value) - 1
    except (TypeError, ValueError):
        slot = 0
    return max(0, min(RUNNERS - 1, slot))


def packet(slot, epoch, head):
    """Deterministic head packet for one head. The real worker will replace the
    hash-derived fields with the live HeadView state."""
    material = f"nanlmind:{epoch}:{slot}:{head}".encode()
    digest = hashlib.sha256(material).digest()
    phase = ((head * 257 + epoch * 131 + slot * 17) & 0xFFFF)
    transform_phase = (head + epoch + slot) & 3
    return {
        "head": head,
        "epoch": epoch,
        "phase": phase,
        "transform_phase": transform_phase,
        "self_error": (head * 977 + epoch) & 0xFFFF,
        "scratch_used": (head * 13 + epoch * 7) % 1024,
        "state_hash": int.from_bytes(digest[:8], "little"),
        "output": list(digest[:32]),
    }


def round_digest(epoch, packets):
    h = hashlib.sha256()
    h.update(b"NaNLM-HAND-1")
    h.update(int(epoch).to_bytes(8, "little"))
    for p in sorted(packets, key=lambda x: x["head"]):
        h.update(json.dumps(p, sort_keys=True, separators=(",", ":")).encode())
    return h.hexdigest()


def connect_tiers(writer=True):
    try:
        from deepcore.runtime import Env  # type: ignore
        env = Env(writer=writer)
        return env
    except Exception as exc:  # pragma: no cover - environment dependent
        print(f"tier-unavailable: {exc}", file=sys.stderr)
        return None


def reg_put(env, key, value):
    if env is None:
        return
    env.regs.put(key, value, commit=True)


def reg_get(env, key, default=None):
    if env is None:
        return default
    return env.regs.get(key, default)


def local_path():
    p = Path(os.environ.get("NANLM_LOCAL_STATE", "state"))
    p.mkdir(parents=True, exist_ok=True)
    return p


def run_core(args, check=True):
    core = Path(os.environ.get("NANLM_CORE", "core"))
    exe = core / "build" / "nanlm-universal"
    if not exe.exists():
        subprocess.run(["make", "-C", str(core), "-j2"], check=check)
    return subprocess.run([str(exe), *args], text=True, capture_output=True, check=check)


def op_selftest(args):
    result = run_core(["verify"])
    out = result.stdout.strip().splitlines()
    ok = result.returncode == 0 and any("ALL CHECKS PASSED" in line for line in out)
    record = {
        "ok": ok,
        "op": "selftest",
        "slot": args.slot,
        "epoch": args.epoch,
        "at": int(time.time()),
        "tail": out[-3:],
    }
    env = connect_tiers(writer=True)
    if env is not None and ok:
        reg_put(env, "nanlm/gate", record)
        reg_put(env, "nanlm/clock", {"tick": args.epoch, "phase": 0})
    local_path().joinpath("gate.json").write_text(json.dumps(record, indent=1))
    print(json.dumps(record, indent=1))
    return 0 if ok else 1


def op_prewarm(args):
    result = run_core(["heads"])
    mapping = head_map()
    heads = mapping[str(args.slot)]
    record = {
        "ok": result.returncode == 0,
        "op": "prewarm",
        "slot": args.slot,
        "epoch": args.epoch,
        "heads": len(heads),
        "first": heads[:4],
        "last": heads[-4:],
    }
    print(json.dumps(record, indent=1))
    return 0 if record["ok"] else 1


def collect_packets(env, epoch):
    seen = []
    if env is not None:
        for s in range(RUNNERS):
            seen.extend(reg_get(env, f"nanlm/head/{epoch}/{s}", []) or [])
    else:
        for s in range(RUNNERS):
            p = local_path().joinpath(f"head_{epoch}_{s}.json")
            if p.exists():
                seen.extend(json.loads(p.read_text()))
    return seen


def finalize_round(env, epoch):
    seen = collect_packets(env, epoch)
    if len(seen) != HEADS:
        return False, None
    if len({p["head"] for p in seen}) != HEADS:
        return False, None
    if any(p["epoch"] != epoch for p in seen):
        return False, None
    d = round_digest(epoch, seen)
    atomic = reg_get(env, "nanlm/atomic") if env is not None else None
    record = {"epoch": epoch, "digest": d, "heads": HEADS, "slots": RUNNERS,
              "atomic": atomic, "ok": True}
    reg_put(env, f"nanlm/round/{epoch}", record)
    manifest = reg_get(env, "nanlm/manifest", {}) or {}
    manifest.update({
        "generation": int(manifest.get("generation", 0)) + 1,
        "epoch": epoch,
        "root": d,
        "pages": ["root"],
        "atomic": atomic,
        "ok": True,
    })
    reg_put(env, "nanlm/manifest", manifest)
    clock = reg_get(env, "nanlm/clock", {}) or {}
    reg_put(env, "nanlm/clock", {
        "tick": int(clock.get("tick", 0)) + 1,
        "phase": 1 - int(clock.get("phase", 0)),
    })
    return True, record


def core_packets(args):
    if os.environ.get("NANLM_USE_CORE", "0") not in ("1", "true", "yes"):
        return None
    core = Path(os.environ.get("NANLM_CORE", "core"))
    exe = core / "build" / "nanlm-universal"
    if not exe.exists():
        return None
    state = local_path()
    snapshot = state / "chart.nmc"
    if not snapshot.exists():
        init = run_core(["snapshot", "--out", str(snapshot)], check=False)
        if init.returncode != 0:
            print(f"core snapshot initialization failed: {init.stderr.strip()}", file=sys.stderr)
            return None
    packets = state / f"packets_{args.epoch}_{args.slot}.json"
    cmd = [str(exe), "headshift", "--slot", str(args.slot + 1),
           "--epoch", str(args.epoch), "--runners", str(RUNNERS),
           "--snapshot", str(snapshot), "--out", str(snapshot),
           "--json", str(packets)]
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        print(f"core headshift failed: {proc.stderr.strip()}", file=sys.stderr)
        return None
    try:
        return json.loads(packets.read_text())
    except Exception as exc:
        print(f"core packets unreadable: {exc}", file=sys.stderr)
        return None


def op_headshift(args):
    env = connect_tiers(writer=True)
    gate = reg_get(env, "nanlm/gate") if env is not None else None
    if env is not None and not (gate or {}).get("ok"):
        print("gate not passed; run op=selftest first", file=sys.stderr)
        return 2

    now = time.time()
    lease_key = f"nanlm/lease/{args.slot}"
    lease = reg_get(env, lease_key) if env is not None else None
    if lease and lease.get("holder") not in (None, args.slot_name) and lease.get("until", 0) > now:
        print(f"lease held by {lease.get('holder')} until {lease.get('until')}", file=sys.stderr)
        return 3
    reg_put(env, lease_key, {
        "holder": args.slot_name,
        "slot": args.slot,
        "epoch": args.epoch,
        "until": now + args.minutes * 60,
    })

    mapping = head_map()
    heads = mapping[str(args.slot)]
    packets = core_packets(args)
    if packets is None:
        packets = [packet(args.slot, args.epoch, h) for h in heads]
    reg_put(env, f"nanlm/head/{args.epoch}/{args.slot}", packets)
    local_path().joinpath(f"head_{args.epoch}_{args.slot}.json").write_text(
        json.dumps(packets, indent=1))

    complete, round_record = finalize_round(env, args.epoch)
    # The lease is per slot, not per epoch. The next slot must be able to
    # acquire it as soon as this run has published its packet set.
    reg_put(env, f"nanlm/lease/{args.slot}", {"holder": None, "epoch": args.epoch, "until": 0})

    out = {
        "ok": True,
        "op": "headshift",
        "slot": args.slot,
        "slot_name": args.slot_name,
        "epoch": args.epoch,
        "heads": len(heads),
        "packets": len(packets),
        "round_complete": complete,
        "round": round_record,
    }
    print(json.dumps(out, indent=1))
    return 0


def op_loop(args):
    """Persistent C++ loop: every slot mutates the same chart snapshot."""
    if os.environ.get("NANLM_USE_CORE", "0").lower() not in ("1", "true", "yes"):
        print("persistent loop requires NANLM_USE_CORE=1; refusing simulated packets", file=sys.stderr)
        return 5
    env = connect_tiers(writer=True)
    gate = reg_get(env, "nanlm/gate") if env is not None else None
    if env is not None and not (gate or {}).get("ok"):
        print("gate not passed; run op=selftest first", file=sys.stderr)
        return 2
    mapping = head_map()
    rounds = []
    deadline = time.monotonic() + max(1, args.minutes) * 60
    partial = False
    original_slot = args.slot
    for epoch in range(args.epoch, args.epoch + max(1, args.epochs)):
        if time.monotonic() >= deadline:
            partial = True
            break
        for slot in range(RUNNERS):
            args.slot = slot
            packets = core_packets(args)
            if packets is None:
                args.slot = original_slot
                print("C++ core headshift failed; refusing synthetic state", file=sys.stderr)
                return 4
            expected = mapping[str(slot)]
            if sorted(p.get("head") for p in packets) != expected or any(p.get("epoch") != epoch for p in packets):
                args.slot = original_slot
                print("C++ core returned an invalid head shard", file=sys.stderr)
                return 4
            reg_put(env, f"nanlm/head/{epoch}/{slot}", packets)
            local_path().joinpath(f"head_{epoch}_{slot}.json").write_text(json.dumps(packets, indent=1))
        args.slot = original_slot
        ok, record = finalize_round(env, epoch)
        if not ok:
            print(json.dumps({"ok": False, "op": "loop", "epoch": epoch,
                              "error": "round did not finalize"}, indent=1))
            return 4
        rounds.append(record)
        print(f"epoch {epoch}: {record['digest']}", flush=True)
    args.slot = original_slot
    print(json.dumps({"ok": True, "op": "loop", "start": args.epoch,
                      "epochs": len(rounds), "partial": partial,
                      "next_epoch": args.epoch + len(rounds), "rounds": rounds,
                      "execution": "cpp-core", "slots": RUNNERS}, indent=1))
    return 0


def op_finalize(args):
    env = connect_tiers(writer=True)
    ok, record = finalize_round(env, args.epoch)
    reg_put(env, "nanlm/lease/0", {"holder": None, "epoch": args.epoch, "until": 0})
    out = {"ok": ok, "op": "finalize", "epoch": args.epoch, "round": record}
    print(json.dumps(out, indent=1))
    return 0 if ok else 4


def op_unlock(args):
    env = connect_tiers(writer=True)
    reg_put(env, f"nanlm/lease/{args.slot}", {"holder": None, "epoch": args.epoch, "until": 0})
    print(json.dumps({"ok": True, "op": "unlock", "epoch": args.epoch}, indent=1))
    return 0


def op_status(args):
    env = connect_tiers(writer=False)
    out = {
        "gate": reg_get(env, "nanlm/gate"),
        "clock": reg_get(env, "nanlm/clock"),
        "lease": reg_get(env, f"nanlm/lease/{args.slot}"),
        "manifest": reg_get(env, "nanlm/manifest"),
        "slots": {},
    }
    for s in range(RUNNERS):
        out["slots"][str(s)] = bool(reg_get(env, f"nanlm/head/{args.epoch}/{s}"))
    print(json.dumps(out, indent=1))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", choices=["selftest", "prewarm", "headshift", "handoff", "loop", "finalize", "unlock", "status"],
                    default="selftest")
    ap.add_argument("--slot", type=int, default=None)
    ap.add_argument("--epoch", type=int, default=0)
    ap.add_argument("--minutes", type=int, default=20)
    ap.add_argument("--epochs", type=int, default=10)
    args = ap.parse_args()
    args.slot = parse_slot(args.slot)
    args.slot_name = SLOT_NAMES[args.slot]
    if args.op == "selftest":
        return op_selftest(args)
    if args.op == "prewarm":
        return op_prewarm(args)
    if args.op == "loop":
        return op_loop(args)
    if args.op == "finalize":
        return op_finalize(args)
    if args.op == "unlock":
        return op_unlock(args)
    if args.op == "status":
        return op_status(args)
    return op_headshift(args)


if __name__ == "__main__":
    raise SystemExit(main())
