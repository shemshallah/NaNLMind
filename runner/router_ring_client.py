"""Authenticated client for MC0:0 runner-ring registry reconciliation."""
from __future__ import annotations

import json
import urllib.request
from urllib.parse import urlsplit


class RouterRingClientError(RuntimeError):
    pass


def _request_json(url: str, token: str, method: str = "GET",
                  payload: dict | None = None, timeout: float = 10.0) -> dict:
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json"}
    data = None
    if payload is not None:
        data = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except Exception as exc:
        raise RouterRingClientError(f"NaNROUTER request failed: {type(exc).__name__}") from exc
    try:
        result = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RouterRingClientError("NaNROUTER returned invalid JSON") from exc
    if not isinstance(result, dict):
        raise RouterRingClientError("NaNROUTER response must be a JSON object")
    return result


def submit_heartbeat(base_url: str, token: str, slot: int,
                     nanclock_tick: int, timeout: float = 10.0) -> dict:
    if not isinstance(slot, int) or not 0 <= slot < 6:
        raise RouterRingClientError("runner slot must be in 0..5")
    if not isinstance(nanclock_tick, int) or nanclock_tick < 0:
        raise RouterRingClientError("NaN clock tick must be nonnegative")
    if not token or len(token) < 32:
        raise RouterRingClientError("router worker token must be 32+ characters")
    parsed = urlsplit(base_url)
    if parsed.scheme not in ("https", "http") or not parsed.netloc or parsed.query or parsed.fragment:
        raise RouterRingClientError("router URL must be an absolute HTTP(S) origin")
    if parsed.scheme != "https" and parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise RouterRingClientError("non-local router endpoints require HTTPS")
    base = base_url.rstrip("/")
    volumes = _request_json(base + "/v1/riddle/volumes", token, timeout=timeout)
    registry = volumes.get("registry")
    if not isinstance(registry, dict):
        raise RouterRingClientError("volume response omitted registry summary")
    generation = registry.get("generation")
    digest = registry.get("registry_digest")
    if not isinstance(generation, int) or generation < 1:
        raise RouterRingClientError("volume registry generation is invalid")
    if not isinstance(digest, str) or len(digest) != 64:
        raise RouterRingClientError("volume registry digest is invalid")
    response = _request_json(
        base + "/v1/riddle/ring/heartbeat", token, method="POST",
        payload={
            "slot": slot,
            "runner_id": f"MC0:0/R{slot}",
            "registry_generation": generation,
            "registry_digest": digest,
            "nanclock_tick": nanclock_tick,
        },
        timeout=timeout,
    )
    if response.get("accepted") is not True or not isinstance(response.get("runner_ring"), dict):
        raise RouterRingClientError("router did not accept runner-ring heartbeat")
    return response["runner_ring"]

def _checked_origin(base_url: str, token: str) -> str:
    if not token or len(token) < 32:
        raise RouterRingClientError("router worker token must be 32+ characters")
    parsed = urlsplit(base_url)
    if parsed.scheme not in ("https", "http") or not parsed.netloc or parsed.query or parsed.fragment:
        raise RouterRingClientError("router URL must be an absolute HTTP(S) origin")
    if parsed.scheme != "https" and parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise RouterRingClientError("non-local router endpoints require HTTPS")
    return base_url.rstrip("/")

def lease_source(base_url: str, token: str, owner: str, now_tick: int,
                 source_kind: str = "clocked-evidence", lease_ticks: int = 64,
                 timeout: float = 10.0) -> dict | None:
    if not owner or not isinstance(now_tick, int) or now_tick < 0 or lease_ticks < 1:
        raise RouterRingClientError("invalid source lease parameters")
    base = _checked_origin(base_url, token)
    response = _request_json(base + "/v1/riddle/lease", token, method="POST",
        payload={"owner": owner, "now_tick": now_tick, "lease_ticks": lease_ticks,
                 "source_kind": source_kind}, timeout=timeout)
    if response.get("event") is None and "event_id" not in response:
        return None
    if not isinstance(response.get("event_id"), str) or not isinstance(response.get("payload_hex"), str):
        raise RouterRingClientError("router lease omitted event identity or payload")
    return response

def ack_source(base_url: str, token: str, event_id: str, owner: str,
               result_digest: str, result_generation: int, trace: dict,
               timeout: float = 10.0) -> dict:
    base = _checked_origin(base_url, token)
    response = _request_json(base + "/v1/riddle/ack", token, method="POST",
        payload={"event_id": event_id, "owner": owner, "result_digest": result_digest,
                 "result_generation": result_generation, "trace": trace}, timeout=timeout)
    if response.get("acknowledged") is not True:
        raise RouterRingClientError("router did not acknowledge the source receipt")
    return response

def retry_source(base_url: str, token: str, event_id: str, owner: str,
                 timeout: float = 10.0) -> dict:
    base = _checked_origin(base_url, token)
    return _request_json(base + "/v1/riddle/retry", token, method="POST",
        payload={"event_id": event_id, "owner": owner}, timeout=timeout)
