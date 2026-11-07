"""Digest-only Clocked evidence consumer for the six-slot NaNLMind ring."""
from __future__ import annotations

import hashlib
import json
import re

from router_ring_client import ack_source, lease_source, retry_source

_HEX64 = re.compile(r"^[0-9a-f]{64}$")


def consume_clocked_sources(base_url: str, token: str, slot: int, now_tick: int,
                            max_events: int = 8) -> dict:
    """Lease and durably ACK bounded Clocked receipts; never update model heads."""
    if not isinstance(slot, int) or not 0 <= slot < 6:
        raise ValueError("runner slot must be in 0..5")
    if not isinstance(now_tick, int) or now_tick < 0:
        raise ValueError("NaN clock tick must be nonnegative")
    if not 1 <= max_events <= 64:
        raise ValueError("max_events must be in 1..64")
    owner = f"HW0::BS0/R{slot}"
    processed = 0
    failed = 0
    errors = []
    for _ in range(max_events):
        event = lease_source(base_url, token, owner, now_tick,
                             source_kind="clocked-evidence")
        if event is None:
            break
        event_id = event["event_id"]
        try:
            raw = bytes.fromhex(event["payload_hex"])
            payload = json.loads(raw.decode("utf-8"))
            if not isinstance(payload, dict) or payload.get("schema") != "nanlm.clocked-router-source.v1":
                raise ValueError("unsupported_clocked_router_payload")
            if event.get("universe_id") != "BS0:0" or event.get("source_kind") != "clocked-evidence":
                raise ValueError("clocked_router_route_mismatch")
            if int(payload.get("node_point", -1)) != int(event.get("node_point", -2)):
                raise ValueError("clocked_router_node_point_mismatch")
            if int(payload.get("base_generation", -1)) < 0:
                raise ValueError("clocked_router_generation_invalid")
            for field in ("clocked_event_id", "input_sha256", "response_sha256"):
                if not isinstance(payload.get(field), str) or not _HEX64.fullmatch(payload[field]):
                    raise ValueError("clocked_router_digest_invalid:" + field)
            if payload.get("outcome_verified") is not False or payload.get("raw_text_persisted") is not False:
                raise ValueError("clocked_router_must_remain_unverified_and_digest_only")
            head_index = int(event["head_index"])
            trace = {
                "schema": "nanrouter.trace.v1",
                "source_ref": "clocked:" + payload["clocked_event_id"],
                "target_ref": f"HW0::BS0/R{slot}/H{head_index}",
                "source_hash": event["source_hash"],
                "acl_digest": event["acl_digest"],
                "universe_id": event["universe_id"],
                "nanclock_tick": now_tick,
                "correct": False,
                "outcome_verified": False,
                "evidence_only": True,
            }
            result_digest = hashlib.sha256(json.dumps(
                trace, sort_keys=True, separators=(",", ":")
            ).encode("utf-8")).hexdigest()
            ack_source(base_url, token, event_id, owner, result_digest,
                       int(payload["base_generation"]), trace)
            processed += 1
        except Exception as exc:
            try:
                retry_source(base_url, token, event_id, owner)
            except Exception:
                pass
            failed += 1
            errors.append(type(exc).__name__)
    return {"enabled": True, "slot": slot, "processed": processed,
            "failed": failed, "errors": errors, "source_kind": "clocked-evidence",
            "model_update": False}

