#!/usr/bin/env python3
"""Hardware-neutral NaNLMind endpoint observation publisher (stdlib only)."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

HEX64 = re.compile(r"^[a-f0-9]{64}$")


def intake_url() -> str:
    value = os.environ.get("NANLM_INTAKE_URL", "").strip()
    if not value:
        raise ValueError("NANLM_INTAKE_URL is required")
    parsed = urlparse(value)
    if parsed.scheme not in ("https", "http") or not parsed.netloc:
        raise ValueError("NANLM_INTAKE_URL must be HTTP(S)")
    if parsed.scheme != "https" and parsed.hostname not in ("localhost", "127.0.0.1", "::1"):
        raise ValueError("HTTPS is required except for localhost")
    return value.rstrip("/") + "/v1/observations"


def token_from_env() -> str:
    # Device/demo tokens are scoped and revocable. Never fall back to the
    # privileged CLOCKED_API_KEY.
    token = (os.environ.get("NANLM_DEVICE_TOKEN") or
             os.environ.get("HERMES_DEMO_API") or
             os.environ.get("CLOCKED_USER_API") or "")
    if not token or len(token) > 512:
        raise ValueError("a scoped endpoint token is required")
    return token


def validate_event(event: dict) -> dict:
    if not isinstance(event, dict):
        raise ValueError("event must be a JSON object")
    if event.get("protocol") != "nanlm.endpoint-observation" or event.get("version") != 1:
        raise ValueError("unsupported endpoint observation protocol")
    event_id = event.get("event_id")
    generation = event.get("base_generation")
    heads = event.get("active_heads", [])
    if not isinstance(event_id, str) or not HEX64.fullmatch(event_id):
        raise ValueError("event_id must be lowercase SHA-256 hex")
    if isinstance(generation, bool) or not isinstance(generation, int) or generation < 0:
        raise ValueError("base_generation must be a nonnegative integer")
    if not isinstance(heads, list) or len(heads) > 256 or any(
        isinstance(head, bool) or not isinstance(head, int) or head < 0 or head > 255
        for head in heads
    ):
        raise ValueError("active_heads must contain integers in [0,255]")
    if event.get("outcome_verified", False) is not False or "correct" in event:
        raise ValueError("endpoint clients cannot assert correctness")
    # Only the protocol allowlist crosses the network.
    return {
        "protocol": "nanlm.endpoint-observation",
        "version": 1,
        "event_id": event_id,
        "base_generation": generation,
        "active_heads": sorted(set(heads)),
        "outcome_verified": False,
    }


def make_request(url: str, token: str, event: dict) -> Request:
    body = json.dumps(validate_event(event), sort_keys=True, separators=(",", ":")).encode("utf-8")
    return Request(url, data=body, headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
        "Accept": "application/json",
    }, method="POST")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("event", type=Path, help="version-1 endpoint observation JSON")
    args = parser.parse_args(argv)
    try:
        event = json.loads(args.event.read_text(encoding="utf-8"))
        request = make_request(intake_url(), token_from_env(), event)
        with urlopen(request, timeout=20) as response:
            result = json.loads(response.read().decode("utf-8"))
        print(json.dumps(result, sort_keys=True))
        return 0
    except HTTPError as exc:
        print("Endpoint intake rejected the event (HTTP %d)." % exc.code, file=sys.stderr)
        return 1
    except (OSError, UnicodeError, ValueError, URLError, json.JSONDecodeError) as exc:
        print("Endpoint publisher failed (%s)." % type(exc).__name__, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
