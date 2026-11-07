#!/usr/bin/env python3
"""Read-only NaNLMind Boolean-head inference service for HERMES evidence packages.

This service delegates to the canonical native relation-eval command. It never
runs relation-train, changes the topology, or participates in the runner ring.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any
from wsgiref.simple_server import make_server

MAX_BODY = 4 * 1024 * 1024
HEX64 = re.compile(r"^[a-f0-9]{64}$")


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False).encode("utf-8")


def _hex_text(value: str) -> str:
    return value.encode("utf-8").hex()


def _json_response(start_response, status: str, payload: dict):
    body = canonical(payload)
    start_response(status, [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
        ("X-Content-Type-Options", "nosniff"),
    ])
    return [body]


class HeadCortexService:
    def __init__(self, native_binary: str, state_path: str, token: str):
        self.native_binary = str(Path(native_binary).expanduser())
        self.state_path = str(Path(state_path).expanduser())
        self.token = token

    def __call__(self, environ, start_response):
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        if method == "GET" and path == "/healthz":
            ready = (Path(self.native_binary).is_file() and Path(self.state_path).is_file())
            return _json_response(start_response, "200 OK" if ready else "503 Service Unavailable",
                                  {"status": "ok" if ready else "not_ready",
                                   "protocol": "nanlm.head-cortex-response",
                                   "read_only": True})
        if method != "POST" or path != "/v1/head-cortex/process":
            return _json_response(start_response, "404 Not Found", {"error": "not_found"})
        auth = environ.get("HTTP_AUTHORIZATION", "")
        supplied = auth[7:] if auth.startswith("Bearer ") else ""
        if not self.token or not hmac.compare_digest(supplied, self.token):
            return _json_response(start_response, "401 Unauthorized", {"error": "unauthorized"})
        try:
            length = int(environ.get("CONTENT_LENGTH") or "0")
            if length <= 0 or length > MAX_BODY:
                raise ValueError("body_size_out_of_range")
            raw = environ["wsgi.input"].read(length)
            package = json.loads(raw.decode("utf-8"))
            self._validate_package(package)
            result = self._infer(package)
            return _json_response(start_response, "200 OK", result)
        except ValueError as exc:
            return _json_response(start_response, "400 Bad Request",
                                  {"error": str(exc)[:96]})
        except (OSError, subprocess.TimeoutExpired):
            return _json_response(start_response, "503 Service Unavailable",
                                  {"error": "native_inference_unavailable"})

    def _validate_package(self, package):
        if not isinstance(package, dict) or package.get("schema") != "nanlm.hermes-evidence-package":
            raise ValueError("unsupported_evidence_package")
        if package.get("version") != 1 or package.get("purpose") not in (
                "EVIDENCE_COGNITION", "ANSWER_VALIDATION"):
            raise ValueError("unsupported_evidence_package_version")
        claimed = package.get("package_sha256")
        unsigned = dict(package)
        unsigned.pop("package_sha256", None)
        if not isinstance(claimed, str) or not HEX64.fullmatch(claimed):
            raise ValueError("invalid_package_digest")
        if hashlib.sha256(canonical(unsigned)).hexdigest() != claimed:
            raise ValueError("package_digest_mismatch")
        if not isinstance(package.get("question"), str) or not package["question"].strip():
            raise ValueError("question_required")
        entries = package.get("evidence_entries")
        if not isinstance(entries, list) or len(entries) > 10000:
            raise ValueError("invalid_evidence_entries")
        if package.get("truth_states") != ["TRUE", "FALSE", "UNKNOWN", "CONFLICT"]:
            raise ValueError("truth_state_contract_mismatch")
        policy = package.get("policy", {})
        if not isinstance(policy, dict) or policy.get("clocked_outputs_are_not_ground_truth") is not True:
            raise ValueError("clocked_trust_policy_required")

    def _infer(self, package):
        atoms = []
        for entry in package["evidence_entries"]:
            if entry.get("lane") != "evidence_atoms":
                continue
            atom = entry.get("payload")
            if not isinstance(atom, dict):
                continue
            subject, predicate, obj = atom.get("subject"), atom.get("predicate"), atom.get("object")
            source_digest = atom.get("source_digest")
            resolution = atom.get("resolution", 5)
            if not all(isinstance(x, str) and x.strip() for x in (subject, predicate, obj)):
                continue
            if not isinstance(source_digest, str) or not HEX64.fullmatch(source_digest):
                continue
            if isinstance(resolution, bool) or not isinstance(resolution, int) or not 0 <= resolution <= 9:
                continue
            atoms.append((entry.get("entry_id", ""), subject, predicate, obj,
                          source_digest, resolution))
        if not atoms:
            return {
                "schema": "nanlm.head-cortex-response", "version": 1,
                "request_sha256": package["package_sha256"], "generation": 0,
                "truth_state": "UNKNOWN", "relations": [], "active_heads": [],
                "abstentions": [{"reason": "no_valid_relation_atoms"}],
                "provenance": {"read_only": True, "engine": "nanlm-universal relation-eval"},
                "mutation_proposals": [],
            }
        if not Path(self.native_binary).is_file() or not Path(self.state_path).is_file():
            raise OSError("native state or binary missing")
        lines = ["N16REL/1"]
        for _, subject, predicate, obj, source_digest, resolution in atoms:
            lines.append("\t".join(("test", str(resolution), "+", "0",
                                     _hex_text(subject), _hex_text(predicate),
                                     _hex_text(obj), source_digest)))
        with tempfile.TemporaryDirectory(prefix="nanlm-head-cortex-") as temp:
            records = Path(temp) / "evidence.n16rel"
            records.write_text("\n".join(lines) + "\n", encoding="ascii")
            proc = subprocess.run(
                [self.native_binary, "relation-eval", str(records), self.state_path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                encoding="utf-8", errors="replace", timeout=30, check=False)
        if proc.returncode != 0:
            raise OSError("native relation evaluation failed")
        header = re.search(r"generation=(\d+) state_digest=([a-f0-9]+)", proc.stdout)
        if not header:
            raise OSError("native relation evaluation returned invalid receipt")
        rows = {}
        for match in re.finditer(
            r"relation_eval_row index=(\d+) head=(\d+) votes=(\d+) truth_state=(TRUE|FALSE|UNKNOWN) rule=(\d+)",
            proc.stdout):
            rows[int(match.group(1))] = {
                "head_id": int(match.group(2)), "votes": int(match.group(3)),
                "truth_state": match.group(4), "rule_id": int(match.group(5)),
            }
        relations = []
        active = set()
        states = set()
        for index, atom in enumerate(atoms):
            prediction = rows.get(index)
            if prediction is None:
                continue
            active.add(prediction["head_id"])
            states.add(prediction["truth_state"])
            relations.append({
                "subject": atom[1], "predicate": atom[2], "object": atom[3],
                "truth_state": prediction["truth_state"],
                "premises": [atom[0]], "rule_id": "boolean-head:%d:%d" % (
                    prediction["head_id"], prediction["rule_id"]),
                "head_id": prediction["head_id"], "votes": prediction["votes"],
            })
        if "TRUE" in states and "FALSE" in states:
            aggregate = "CONFLICT"
        elif not states or "UNKNOWN" in states:
            aggregate = "UNKNOWN"
        else:
            aggregate = next(iter(states))
        return {
            "schema": "nanlm.head-cortex-response", "version": 1,
            "request_sha256": package["package_sha256"],
            "generation": int(header.group(1)), "truth_state": aggregate,
            "relations": relations, "active_heads": sorted(active),
            "abstentions": [{"reason": "model_output_is_inference_not_ground_truth"}],
            "provenance": {
                "read_only": True, "engine": "nanlm-universal relation-eval",
                "state_digest": header.group(2),
                "source_entry_ids": [atom[0] for atom in atoms],
                "clocked_outputs_are_ground_truth": False,
            },
            "mutation_proposals": [],
        }


def main():
    native = os.environ.get("NANLM_NATIVE_BINARY", "build/nanlm-universal")
    state = os.environ.get("NANLM_HEAD_STATE", "state/hermes-universe.nmg")
    token = os.environ.get("NANLM_HEAD_CORTEX_TOKEN", "")
    host = os.environ.get("NANLM_HEAD_CORTEX_HOST", "127.0.0.1")
    port = int(os.environ.get("NANLM_HEAD_CORTEX_PORT", "8765"))
    if not token or len(token) < 32:
        raise SystemExit("NANLM_HEAD_CORTEX_TOKEN must be a scoped random secret of at least 32 characters")
    app = HeadCortexService(native, state, token)
    with make_server(host, port, app) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
