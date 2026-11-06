#!/usr/bin/env python3
"""NaNLMind head-ring worker.

Ops:
  selftest   build + verify the core, write the gate record
  prewarm    verify, print the head map, write no state
  headshift  process one slot's heads for one logical epoch
  logic      run one slot of the graded logic curriculum
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

# Worker subprocesses may be launched with PYTHONPATH=runner; add the
# repository root so the shared NaN16DE/N16B implementation remains importable.
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from nanlmind_nannet.bridge import BridgeFrame, BridgeMailbox, RunnerRoute
from nanlmind_nannet.nan16de import NanWord

PORTAL_TOKEN = None
PORTAL_ROUTE = None
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


def native_bridge_mailbox():
    """Open the native N16B mailbox; point this at shared storage for cross-host use."""
    configured = os.environ.get("NANNET_NATIVE_MAILBOX", "").strip()
    database = Path(configured) if configured else local_path() / "nannet_native_bridge.sqlite"
    return BridgeMailbox(database)


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


def op_training(args):
    """Run the staged corpus pipeline through one runner slot."""
    script = Path(__file__).with_name("training_pipeline.py")
    state = local_path()
    corpus = state / f"curriculum_{args.epoch}_{args.slot}.n16txt"
    out = state / f"training_{args.epoch}_{args.slot}.json"
    cmd = [sys.executable, str(script),
           "--slot", str(args.slot + 1), "--epoch", str(args.epoch),
           "--stage-seconds", str(args.stage_seconds),
           "--corpus", str(corpus),
           "--state-dir", str(state),
           "--out", str(out)]
    if args.single:
        cmd += ["--single", args.single]
    if args.max_samples > 0:
        cmd += ["--max-samples", str(args.max_samples)]
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        return result.returncode
    print(result.stdout)
    try:
        record = json.loads(out.read_text())
    except Exception as exc:
        print(f"training output unreadable: {exc}", file=sys.stderr)
        return 5
    env = connect_tiers(writer=True)
    reg_put(env, f"nanlm/training/{args.epoch}/{args.slot}",
            {"ok": record.get("ok", False), "stages": record.get("stages", []),
             "corpus": record.get("corpus_path"), "slot": args.slot,
             "epoch": args.epoch})
    return 0 if record.get("ok") else 4


def op_logic_core(args):
    """Run the staged core logic session through the runner."""
    result = run_core(["logic-train", str(args.boolean_reps),
                       str(args.circuit_reps)], check=False)
    record = {
        "ok": result.returncode == 0,
        "op": "logic-core",
        "slot": args.slot,
        "epoch": args.epoch,
        "boolean_reps": args.boolean_reps,
        "circuit_reps": args.circuit_reps,
        "stdout": result.stdout.strip().splitlines(),
        "stderr": result.stderr.strip(),
    }
    state = local_path()
    state.joinpath(f"logic_core_{args.epoch}_{args.slot}.json").write_text(
        json.dumps(record, indent=1))
    env = connect_tiers(writer=True)
    reg_put(env, f"nanlm/logic-core/{args.epoch}/{args.slot}", record)
    print(json.dumps(record, indent=1))
    return 0 if record["ok"] else 4


def op_logic(args):
    """Run one slot of the graded logic curriculum."""
    script = Path(__file__).with_name("logic_curriculum.py")
    state = local_path()
    out = state / f"logic_{args.epoch}_{args.slot}.json"
    cmd = [sys.executable, str(script),
           "--slot", str(args.slot + 1),
           "--epoch", str(args.epoch),
           "--rounds", str(args.rounds),
           "--session-rounds", str(args.session_rounds),
           "--start-level", str(args.start_level),
           "--out", str(out)]
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        return result.returncode
    print(result.stdout)
    try:
        record = json.loads(out.read_text())
    except Exception as exc:
        print(f"logic output unreadable: {exc}", file=sys.stderr)
        return 5
    env = connect_tiers(writer=True)
    reg_put(env, f"nanlm/logic/{args.epoch}/{args.slot}",
            {"ok": record.get("ok", False),
             "improved": record.get("improved", False),
             "levels": record.get("levels", []),
             "slot": args.slot, "epoch": args.epoch})
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
            portal_heartbeat()
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



def verify_portal_identity(slot):
    """Verify both execution and binary-bridge scopes for the assigned BSR route."""
    global PORTAL_TOKEN, PORTAL_ROUTE
    import urllib.request
    base = os.environ.get("NANNET_PORTAL_API", "").rstrip("/")
    token = os.environ.get("NANNET_BSR_TOKEN", "")
    PORTAL_ROUTE = RunnerRoute(bsr=slot)
    if not base:
        print("nannet-native: route=" + PORTAL_ROUTE.text(), file=sys.stderr)
        return
    if not token:
        raise RuntimeError("NANNET portal is configured but no BSR token was issued")
    for scope in ("training:execute", "universe:register"):
        body = json.dumps({"scope": scope}).encode()
        request = urllib.request.Request(
            base + "/v1/authorize", data=body,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
            method="POST")
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.load(response)
        if not result.get("authorized") or result.get("scope") != scope:
            raise RuntimeError("NANNET portal rejected BSR scope: " + scope)
        advertised = result.get("route")
        if advertised and RunnerRoute.parse(advertised) != PORTAL_ROUTE:
            raise RuntimeError("NANNET route does not match this GitHub runner slot")
        route_bytes = result.get("route_bytes")
        if route_bytes and route_bytes != PORTAL_ROUTE.bytes().hex():
            raise RuntimeError("NANNET route binary translation does not match canonical URI")
        if result.get("universe_point", 0) != 0 or result.get("translator") != "N16B/1":
            raise RuntimeError("NANNET authority did not advertise the point-zero N16B translator")
    PORTAL_TOKEN = token
    print("nannet-authenticated: " + result.get("installation_id", "unknown") +
          " route=" + PORTAL_ROUTE.text() +
          " scopes=training:execute,universe:register", file=sys.stderr)


def portal_bridge_send(frame):
    """Send one raw NaN16DE bridge frame and validate its reverse-rail ACK."""
    import urllib.request
    base = os.environ.get("NANNET_PORTAL_API", "").rstrip("/")
    if not base:
        mailbox = native_bridge_mailbox()
        if frame.payload == b"BSR_ACK":
            mailbox.acknowledge_and_put(frame.destination, frame.source,
                                        frame.sequence, frame)
        elif frame.payload == b"ACK":
            mailbox.acknowledge(frame.destination, frame.source, frame.sequence)
        else:
            mailbox.put(frame)
        return None
    if not PORTAL_TOKEN:
        raise RuntimeError("NANNET portal is configured but runner has no portal token")
    request = urllib.request.Request(
        base + "/v1/nannet/bridge", data=frame.encode(),
        headers={"Authorization": "Bearer " + PORTAL_TOKEN,
                 "Content-Type": "application/vnd.nan16.n16b"},
        method="POST")
    with urllib.request.urlopen(request, timeout=20) as response:
        ack = BridgeFrame.decode(response.read())
    if (ack.source != frame.destination or ack.destination != frame.source or
            ack.sequence != frame.sequence or ack.payload != b"ACK"):
        raise RuntimeError("NANNET bridge acknowledgement mismatch")
    return ack


def portal_bridge_poll():
    """Poll this runner's durable Koyeb mailbox for one binary frame."""
    import urllib.parse
    import urllib.request
    base = os.environ.get("NANNET_PORTAL_API", "").rstrip("/")
    if PORTAL_ROUTE is None:
        return None
    if not base:
        raw = native_bridge_mailbox().claim(PORTAL_ROUTE)
        return BridgeFrame.decode(raw) if raw else None
    if not PORTAL_TOKEN:
        raise RuntimeError("NANNET portal is configured but runner has no portal token")
    query = urllib.parse.urlencode({"route": PORTAL_ROUTE.text()})
    request = urllib.request.Request(
        base + "/v1/nannet/bridge/poll?" + query,
        headers={"Authorization": "Bearer " + PORTAL_TOKEN},
        method="GET")
    with urllib.request.urlopen(request, timeout=20) as response:
        raw = response.read()
    return BridgeFrame.decode(raw) if raw else None


def portal_bridge_drain(epoch, limit=16):
    """Lease, persist, and acknowledge incoming frames on the reverse rail."""
    if PORTAL_ROUTE is None:
        return 0
    received = []
    for _ in range(limit):
        frame = portal_bridge_poll()
        if frame is None:
            break
        received.append(frame)
    if received:
        path = local_path() / ("nannet_inbox_" + str(epoch) + "_" + str(PORTAL_ROUTE.bsr) + ".bin")
        with path.open("ab") as stream:
            for frame in received:
                raw = frame.encode()
                stream.write(len(raw).to_bytes(4, "little") + raw)
    # Two-phase receipt: BSR_ACK confirms the data frame; ACK consumes that receipt.
    for frame in received:
        if frame.payload == b"ACK":
            continue
        payload = b"ACK" if frame.payload == b"BSR_ACK" else b"BSR_ACK"
        reply = BridgeFrame(PORTAL_ROUTE, frame.source, frame.sequence,
                            NanWord.from_bits(3, 3, frame.sequence), payload)
        portal_bridge_send(reply)
    return len(received)


def portal_bridge_startup(slot, epoch):
    """Announce the runner to BSR0 and drain any already queued frames."""
    if PORTAL_ROUTE is None:
        return {"enabled": False, "transport": "unavailable", "route": None, "received": 0}
    hosted = bool(os.environ.get("NANNET_PORTAL_API", "").strip())
    transport = "koyeb" if hosted else "native"
    root = RunnerRoute(bsr=0)
    sent = False
    if slot != 0:
        seq = int(epoch) & 0xFFFFFFFF
        frame = BridgeFrame(PORTAL_ROUTE, root, seq,
                            NanWord.from_bits(0, 0, seq), b"BSR_ONLINE")
        portal_bridge_send(frame)
        sent = True
    received = portal_bridge_drain(epoch)
    return {"enabled": True, "transport": transport, "route": PORTAL_ROUTE.text(),
            "announced_to_root": sent, "received": received}


def portal_heartbeat():
    global PORTAL_TOKEN
    base = os.environ.get("NANNET_PORTAL_API", "").rstrip("/")
    if base:
        if not PORTAL_TOKEN:
            raise RuntimeError("NANNET BSR identity is not initialized")
        import urllib.request
        request = urllib.request.Request(
            base + "/v1/bootstrap/heartbeat", data=b"{}",
            headers={"Authorization": "Bearer " + PORTAL_TOKEN, "Content-Type": "application/json"},
            method="POST")
        with urllib.request.urlopen(request, timeout=20) as response:
            renewed = json.load(response)
        if not renewed.get("token"):
            raise RuntimeError("NANNET BSR heartbeat did not rotate the credential")
        if renewed.get("identity") and not renewed["identity"].endswith(
                f"/nanlm-cpu-{PORTAL_ROUTE.bsr + 1}"):
            raise RuntimeError("NANNET heartbeat identity changed runner route")
        advertised = renewed.get("route")
        if advertised and RunnerRoute.parse(advertised) != PORTAL_ROUTE:
            raise RuntimeError("NANNET heartbeat changed the canonical runner route")
        route_bytes = renewed.get("route_bytes")
        if route_bytes and route_bytes != PORTAL_ROUTE.bytes().hex():
            raise RuntimeError("NANNET heartbeat route bytes do not match its URI")
        if renewed.get("universe_point", 0) != 0 or renewed.get("translator") != "N16B/1":
            raise RuntimeError("NANNET heartbeat did not preserve point-zero N16B translation")
        PORTAL_TOKEN = renewed["token"]
    portal_bridge_drain(int(time.time()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", choices=["selftest", "prewarm", "headshift", "handoff", "logic", "logic-core", "training", "loop", "finalize", "unlock", "status"],
                    default="selftest")
    ap.add_argument("--slot", type=int, default=None)
    ap.add_argument("--epoch", type=int, default=0)
    ap.add_argument("--minutes", type=int, default=20)
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--rounds", type=int, default=4)
    ap.add_argument("--session-rounds", type=int, default=0)
    ap.add_argument("--start-level", type=int, default=0)
    ap.add_argument("--boolean-reps", type=int, default=32)
    ap.add_argument("--circuit-reps", type=int, default=64)
    ap.add_argument("--stage-seconds", default="1.0")
    ap.add_argument("--single", default="")
    ap.add_argument("--max-samples", type=int, default=0)
    args = ap.parse_args()
    args.slot = parse_slot(args.slot)
    args.slot_name = SLOT_NAMES[args.slot]
    verify_portal_identity(args.slot)
    bridge_status = portal_bridge_startup(args.slot, args.epoch)
    if bridge_status.get("enabled"):
        print("nannet-bridge: " + json.dumps(bridge_status, sort_keys=True), file=sys.stderr)
    if args.op == "selftest":
        return op_selftest(args)
    if args.op == "prewarm":
        return op_prewarm(args)
    if args.op == "logic":
        return op_logic(args)
    if args.op == "logic-core":
        return op_logic_core(args)
    if args.op == "training":
        return op_training(args)
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
