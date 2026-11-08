"""Single-purpose NANNET -> NaNROUTER HERMES lease delegation adapter.

No public request may select the upstream origin or supply a router token.
This file is transport glue only: issuer, installation signature and scopes
are checked by the portal *before* calling this adapter.
"""
from __future__ import annotations

import ipaddress
import json
import os
import urllib.error
import urllib.request
from urllib.parse import urlsplit


class HermesDelegationError(ValueError):
    pass


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def _endpoint():
    raw = os.environ.get("NANNET_HERMES_ROUTER_URL", "").strip().rstrip("/")
    parts = urlsplit(raw)
    try:
        loopback = ipaddress.ip_address(parts.hostname or "").is_loopback
    except ValueError:
        loopback = (parts.hostname or "").lower() == "localhost"
    if not (parts.hostname and not parts.username and not parts.password
            and not parts.path and not parts.query and not parts.fragment
            and (parts.scheme == "https" or (parts.scheme == "http" and loopback))):
        raise HermesDelegationError("trusted NaNROUTER HTTPS origin is not configured")
    token = os.environ.get("NANNET_HERMES_DELEGATION_TOKEN", "")
    if len(token) < 32:
        raise HermesDelegationError("NANNET portal-to-router delegation credential is not configured")
    return raw, token


def delegate_hermes_lease(action: str, payload: dict, installation_id: str) -> dict:
    if action not in ("open", "resolve", "renew", "release", "dispatch", "ack", "inspect"):
        raise HermesDelegationError("unsupported HERMES lease action")
    if not isinstance(payload, dict) or not isinstance(installation_id, str):
        raise HermesDelegationError("invalid delegated lease request")
    if len(installation_id) < 8 or len(installation_id) > 128:
        raise HermesDelegationError("invalid installation identity")
    origin, token = _endpoint()
    forwarded = {"installation_id": installation_id}
    if action == "open":
        forwarded.update({
            "request_id": payload["request_id"],
            "ttl_seconds": payload.get("ttl_seconds", 900),
            # HERMES is the reserved HW2 endpoint, point 3. NEVER
            # forward a client-provided node point or installation ID.
            "node_point": 3,
        })
    else:
        forwarded["receipt"] = payload["receipt"]
        if action in ("resolve", "dispatch", "ack", "inspect"):
            forwarded["head_index"] = payload["head_index"]
        if action in ("dispatch", "ack", "inspect"):
            forwarded["dispatch_id"] = payload["dispatch_id"]
        if action == "dispatch":
            forwarded["frame_hex"] = payload["frame_hex"]
        if action == "ack":
            forwarded["response_sha256"] = payload["response_sha256"]
        if action == "renew":
            forwarded["ttl_seconds"] = payload.get("ttl_seconds", 900)
    raw = json.dumps(forwarded, separators=(",", ":"), sort_keys=True).encode("utf-8")
    if len(raw) > (150000 if action == "dispatch" else 16384):
        raise HermesDelegationError("delegated HERMES request exceeds configured bound")
    request = urllib.request.Request(
        origin + "/v1/hermes/leases/" + action, data=raw,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "Accept": "application/json",
        }, method="POST")
    try:
        with urllib.request.build_opener(_NoRedirect).open(request, timeout=8) as response:
            if response.status != 200 or response.headers.get_content_type() != "application/json":
                raise HermesDelegationError("NaNROUTER returned an unsupported lease response")
            bound = 155000 if action in ("dispatch", "inspect") else 32768
            response_raw = response.read(bound + 1)
            if len(response_raw) > bound:
                raise HermesDelegationError("NaNROUTER lease response is too large")
    except urllib.error.HTTPError as exc:
        raise HermesDelegationError("NaNROUTER rejected HERMES lease operation (HTTP " + str(exc.code) + ")") from None
    except (OSError, TimeoutError, urllib.error.URLError) as exc:
        raise HermesDelegationError("NaNROUTER lease authority is unavailable") from None
    try:
        result = json.loads(response_raw.decode("utf-8"))
        if not isinstance(result, dict):
            raise ValueError("lease response not an object")
    except (ValueError, UnicodeError) as exc:
        raise HermesDelegationError("NaNROUTER lease response is invalid") from exc
    return result
