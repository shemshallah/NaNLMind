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
import urllib.request
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
    def __init__(self, native_binary: str, state_path: str, token: str = "",
                 auth_url: str = ""):
        self.native_binary = str(Path(native_binary).expanduser())
        self.state_path = str(Path(state_path).expanduser())
        self.token = token
        self.auth_url = auth_url.rstrip("/")

    def __call__(self, environ, start_response):
        method = environ.get("REQUEST_METHOD", "GET").upper()
        path = environ.get("PATH_INFO", "/")
        if method == "GET" and path == "/healthz":
            ready = (Path(self.native_binary).is_file() and Path(self.state_path).is_file())
            return _json_response(start_response, "200 OK" if ready else "503 Service Unavailable",
                                  {"status": "ok" if ready else "not_ready",
                                   "protocol": "nanlm.head-cortex-response",
                                   "read_only": True})
        if method != "POST" or path not in (
                "/v1/head-cortex/process", "/v1/head-cortex/candidate"):
            return _json_response(start_response, "404 Not Found", {"error": "not_found"})
        auth = environ.get("HTTP_AUTHORIZATION", "")
        supplied = auth[7:] if auth.startswith("Bearer ") else ""
        required_scope = "training:execute" if path.endswith("/candidate") else "universe:read"
        if not self._authorized(supplied, required_scope):
            return _json_response(start_response, "401 Unauthorized", {"error": "unauthorized"})
        try:
            length = int(environ.get("CONTENT_LENGTH") or "0")
            if length <= 0 or length > MAX_BODY:
                raise ValueError("body_size_out_of_range")
            raw = environ["wsgi.input"].read(length)
            package = json.loads(raw.decode("utf-8"))
            if path.endswith("/candidate"):
                result = self._create_candidate(package)
            else:
                self._validate_package(package)
                result = self._infer(package)
            return _json_response(start_response, "200 OK", result)
        except ValueError as exc:
            return _json_response(start_response, "400 Bad Request",
                                  {"error": str(exc)[:96]})
        except (OSError, subprocess.TimeoutExpired):
            return _json_response(start_response, "503 Service Unavailable",
                                  {"error": "native_inference_unavailable"})

    def _authorized(self, supplied: str, scope: str = "universe:read") -> bool:
        if not supplied or len(supplied) > 512:
            return False
        if self.auth_url:
            try:
                body = canonical({"scope": scope})
                request = urllib.request.Request(
                    self.auth_url + "/v1/authorize", data=body,
                    headers={"Authorization": "Bearer " + supplied,
                             "Content-Type": "application/json",
                             "Accept": "application/json"}, method="POST")
                with urllib.request.urlopen(request, timeout=10) as response:
                    result = json.loads(response.read(16384).decode("utf-8"))
                return result.get("authorized") is True and result.get("scope") == scope
            except Exception:
                return False
        return bool(self.token) and hmac.compare_digest(supplied, self.token)

    def _create_candidate(self, request):
        if not isinstance(request, dict) or request.get("schema") != "nanlm.head-candidate-request/1":
            raise ValueError("unsupported_candidate_request")
        mutation_id = request.get("mutation_id")
        if not isinstance(mutation_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", mutation_id):
            raise ValueError("invalid_mutation_id")
        head_index = request.get("head_index")
        patch_mask = request.get("patch_mask")
        if isinstance(head_index, bool) or not isinstance(head_index, int) or not 0 <= head_index <= 255:
            raise ValueError("invalid_head_index")
        if isinstance(patch_mask, bool) or not isinstance(patch_mask, int) or not 1 <= patch_mask <= 65535:
            raise ValueError("invalid_patch_mask")
        base_digest = request.get("base_topology_digest")
        if not isinstance(base_digest, str) or not HEX64.fullmatch(base_digest):
            raise ValueError("invalid_base_topology_digest")
        if not Path(self.native_binary).is_file() or not Path(self.state_path).is_file():
            raise OSError("native_state_or_binary_missing")
        candidate_dir = Path(os.environ.get(
            "NANLM_HEAD_CANDIDATE_DIR",
            str(Path(self.state_path).parent / "candidates"))).expanduser()
        candidate_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(candidate_dir, 0o700)
        candidate_state = candidate_dir / (mutation_id + ".nmg")
        manifest_path = candidate_dir / (mutation_id + ".json")
        if candidate_state.exists() or manifest_path.exists():
            raise ValueError("mutation_id_already_exists")
        with tempfile.TemporaryDirectory(prefix="nanlm-head-candidate-") as temp:
            probe = Path(temp) / "probe.n16rel"
            probe.write_text(
                "N16REL/1\\ntest\\t5\\t+\\t0\\t70726f6265\\t7374617465\\t646967657374\\t" + "0" * 64 + "\\n",
                encoding="ascii")
            base = subprocess.run(
                [self.native_binary, "relation-eval", str(probe), self.state_path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                encoding="utf-8", errors="replace", timeout=30, check=False)
        match = re.search(r"generation=(\\d+) state_digest=([a-f0-9]{64})", base.stdout)
        if base.returncode != 0 or not match:
            raise OSError("cannot_read_base_topology_digest")
        if match.group(2) != base_digest:
            raise ValueError("stale_base_topology_digest")
        candidate = subprocess.run(
            [self.native_binary, "head-candidate", self.state_path,
             str(head_index), hex(patch_mask), str(candidate_state)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            encoding="utf-8", errors="replace", timeout=30, check=False)
        if candidate.returncode != 0:
            raise ValueError("native_candidate_mutation_rejected")
        try:
            receipt = json.loads(candidate.stdout)
        except json.JSONDecodeError as exc:
            raise OSError("native_candidate_receipt_invalid") from exc
        if receipt.get("status") != "candidate_only" or receipt.get("canonical_state_modified") is not False:
            raise OSError("native_candidate_receipt_invalid")
        manifest = {
            "schema": "nanlm.head-candidate-manifest/1",
            "mutation_id": mutation_id, "head_index": head_index,
            "patch_mask": patch_mask, "base_topology_digest": base_digest,
            "candidate_digest": receipt.get("candidate_digest"),
            "candidate_state_file": candidate_state.name,
            "created_at": __import__("datetime").datetime.now(
                __import__("datetime").timezone.utc).isoformat(),
            "status": "candidate_only", "promotion_allowed": False,
        }
        manifest_path.write_bytes(canonical(manifest))
        os.chmod(candidate_state, 0o600)
        os.chmod(manifest_path, 0o600)
        return {
            "schema": "nanlm.head-candidate-response/1",
            "mutation_id": mutation_id, "status": "candidate_only",
            "head_index": head_index, "patch_mask": patch_mask,
            "base_topology_digest": base_digest,
            "candidate_digest": receipt.get("candidate_digest"),
            "boolean_mask_before": receipt.get("boolean_mask_before"),
            "boolean_mask_after": receipt.get("boolean_mask_after"),
            "boolean_rule_before": receipt.get("boolean_rule_before"),
            "boolean_rule_after": receipt.get("boolean_rule_after"),
            "canonical_state_modified": False, "promotion_allowed": False,
        }

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
        evidence_texts = []
        for entry in package["evidence_entries"]:
            if entry.get("lane") == "evidence_atoms":
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
                              source_digest, resolution, False))
                evidence_texts.append((entry.get("entry_id", ""), obj))
            elif entry.get("lane") == "hermes_synthesis" and package.get("purpose") == "ANSWER_VALIDATION":
                draft_payload = entry.get("payload")
                draft = draft_payload.get("draft") if isinstance(draft_payload, dict) else None
                if not isinstance(draft, str) or not draft.strip():
                    continue
                draft_digest = hashlib.sha256(draft.encode("utf-8")).hexdigest()
                sentences = re.split(r"(?<=[.!?])\s+", draft)
                for index, sentence in enumerate(sentences[:128]):
                    sentence = sentence.strip()
                    if not sentence:
                        continue
                    atoms.append((entry.get("entry_id", "") + "-claim-" + str(index),
                                  "hermes_answer", "asserts_claim", sentence[:2048],
                                  draft_digest, 7, True))
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
        for _, subject, predicate, obj, source_digest, resolution, _ in atoms:
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
            relation = {
                "subject": atom[1], "predicate": atom[2], "object": atom[3],
                "truth_state": prediction["truth_state"],
                "premises": [atom[0]], "rule_id": "boolean-head:%d:%d" % (
                    prediction["head_id"], prediction["rule_id"]),
                "head_id": prediction["head_id"], "votes": prediction["votes"],
            }
            if atom[6]:
                claim_tokens = set(re.findall(r"[a-z0-9]+", atom[3].casefold()))
                matched = []
                best = 0.0
                for evidence_id, evidence_text in evidence_texts:
                    evidence_tokens = set(re.findall(r"[a-z0-9]+", evidence_text.casefold()))
                    ratio = len(claim_tokens & evidence_tokens) / max(1, len(claim_tokens))
                    best = max(best, ratio)
                    if ratio >= 0.5:
                        matched.append(evidence_id)
                relation["lexical_coverage"] = round(best, 4)
                relation["matched_evidence_entry_ids"] = matched[:32]
                relation["coverage_signal"] = "heuristic_only"
            relations.append(relation)
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
                "answer_draft_processed": package.get("purpose") == "ANSWER_VALIDATION",
            },
            "mutation_proposals": [],
        }


def main():
    native = os.environ.get("NANLM_NATIVE_BINARY", "build/nanlm-universal")
    state = os.environ.get("NANLM_HEAD_STATE", "state/hermes-universe.nmg")
    token = os.environ.get("NANLM_HEAD_CORTEX_TOKEN", "")
    auth_url = os.environ.get("NANNET_AUTH_URL", "").rstrip("/")
    host = os.environ.get("NANLM_HEAD_CORTEX_HOST", "127.0.0.1")
    port = int(os.environ.get("NANLM_HEAD_CORTEX_PORT", "8765"))
    if not auth_url and len(token) < 32:
        raise SystemExit("configure NANNET_AUTH_URL for scoped NANNET authorization, or a 32+ character NANLM_HEAD_CORTEX_TOKEN for isolated local use")
    app = HeadCortexService(native, state, token, auth_url)
    with make_server(host, port, app) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
