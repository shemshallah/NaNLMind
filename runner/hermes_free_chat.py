#!/usr/bin/env python3
"""Native-logic-gated free HERMES chat with isolated NaNLMind teaching.

This is an orchestration/protocol adapter, NOT a Python math or model trainer:
the real compiled nanlm-universal executes logic-train and relation-train.
Nothing in this module merges a scratch candidate into the canonical universe.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any, Protocol


class ChatModel(Protocol):
    def complete(self, messages: list[dict], **kwargs: Any) -> str: ...


class NativeTrainingError(RuntimeError):
    pass


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _text(value: str, label: str, maximum: int = 256) -> bytes:
    if not isinstance(value, str):
        raise NativeTrainingError(label + " must be UTF-8 text")
    raw = value.encode("utf-8")
    if not 1 <= len(raw) <= maximum or b"\x00" in raw:
        raise NativeTrainingError(label + f" must be 1..{maximum} UTF-8 bytes without NUL")
    return raw


class HermesFreeChat:
    """One conversational session using one native scratch topology.

    There is a strict order: native logic PASS -> chat -> optional explicit
    N16REL/1 teaching -> native scratch update -> Hermes reflection.
    The canonical topology is read-only. BS0/MC0 remain merge authorities.
    """

    def __init__(
        self,
        model: ChatModel,
        *,
        core: str | Path = "build/nanlm-universal",
        state_dir: str | Path = "state/hermes_free_chat",
        base_state: str | Path | None = None,
        slot: int = 1,
        epoch: int = 0,
        session_id: str | None = None,
        core_sha256: str | None = None,
        native_runner=None,
    ) -> None:
        if type(slot) is not int or not 1 <= slot <= 6:
            raise NativeTrainingError("invalid runner slot")
        if type(epoch) is not int or not 0 <= epoch <= 0x7fffffff:
            raise NativeTrainingError("invalid clocked epoch")
        self.model = model
        self.core = Path(core).resolve()
        self.base_state = Path(base_state).resolve() if base_state else None
        self.expected_core_hash = core_sha256
        self.slot, self.epoch = slot, epoch
        self.session_id = session_id or secrets.token_hex(12)
        if not re.fullmatch(r"[A-Za-z0-9_-]{8,64}", self.session_id):
            raise NativeTrainingError("invalid session id")
        self.directory = Path(state_dir) / self.session_id
        self.scratch = self.directory / "candidate_universe.nmg"
        self.transcript = self.directory / "chat.jsonl"
        self.runner = native_runner or subprocess.run
        self._lock = threading.RLock()
        self._gate: dict | None = None
        self._clock = 0
        self._last_hash = "0" * 64
        self._history: list[dict] = []

    def _native(self, *args: str):
        try:
            return self.runner(
                [str(self.core), *args],
                capture_output=True, text=True, timeout=180,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise NativeTrainingError("native executable unavailable or timed out") from exc

    def start(self) -> dict:
        with self._lock:
            if self._gate is not None:
                return dict(self._gate)
            if not self.core.is_file():
                raise NativeTrainingError("compiled native nanlm-universal is missing")
            binary_sha = _sha(self.core)
            if self.expected_core_hash is not None and binary_sha != self.expected_core_hash:
                raise NativeTrainingError("native executable does not match the pinned SHA-256")
            # A fresh session never aliases an existing or canonical topology.
            if self.directory.exists():
                raise NativeTrainingError("scratch session already exists; use a fresh session id")
            self.directory.mkdir(parents=True)
            base_digest = None
            if self.base_state is not None:
                if not self.base_state.is_file():
                    raise NativeTrainingError("canonical base topology does not exist")
                if self.base_state == self.scratch:
                    raise NativeTrainingError("canonical topology may not be its own scratch")
                base_digest = _sha(self.base_state)
                shutil.copyfile(self.base_state, self.scratch)
            proc = self._native("logic-train", "32", "64", str(self.scratch))
            lines = (proc.stdout or "").splitlines()
            # Do not trust exit zero or a single generic PASS string.
            boolean = any(re.search(
                r"^stage=boolean_foundation\s+passed=yes\s+correct=1024/1024(?:\s|$)", line
            ) for line in lines)
            circuits = any(re.search(
                r"^stage=deep_logic_circuits\s+passed=yes\s+correct=32/32(?:\s|$)", line
            ) for line in lines)
            passed = (proc.returncode == 0 and boolean and circuits
                      and any(line.strip() == "result=PASS" for line in lines)
                      and self.scratch.is_file())
            if not passed:
                raise NativeTrainingError("mandatory native Boolean/deep-logic gate did not pass")
            self._gate = {
                "schema": "nanlm.hermes.logic-gate.v1",
                "passed": True,
                "boolean_correct": "1024/1024",
                "circuits_correct": "32/32",
                "binary_sha256": binary_sha,
                "stdout_sha256": hashlib.sha256((proc.stdout or "").encode()).hexdigest(),
                "base_state_sha256": base_digest,
                "scratch_sha256": _sha(self.scratch),
                "epoch": self.epoch,
                "slot": self.slot,
                "session_id": self.session_id,
            }
            (self.directory / "logic_gate.json").write_bytes(_canonical(self._gate) + b"\n")
            return dict(self._gate)

    def _record(self, kind: str, payload: dict) -> dict:
        self._clock += 1
        row = {
            "schema": "nanlm.hermes.clocked-chat.v1",
            "session_id": self.session_id,
            "tick": self._clock,
            "epoch": self.epoch, "slot": self.slot,
            "kind": kind,
            "previous_sha256": self._last_hash,
            "payload": payload,
        }
        row["sha256"] = hashlib.sha256(_canonical(row)).hexdigest()
        with self.transcript.open("ab") as stream:
            stream.write(_canonical(row) + b"\n")
            stream.flush()
            os.fsync(stream.fileno())
        self._last_hash = row["sha256"]
        return row

    def chat(self, message: str) -> dict:
        with self._lock:
            self.start()
            _text(message, "chat message", maximum=8192)
            messages = [{
                "role": "system",
                "content": (
                    "You are HERMES, teaching one existing NaNLMind state. "
                    "The native Boolean and circuit logic gate has PASSED. "
                    "You may converse freely and propose experiments, but you "
                    "must not claim the native student learned from ordinary "
                    "chat. Explicit /teach events are native relation-training "
                    "candidates and remain scratch-only until BS0/MC0 merge."
                ),
            }, *self._history[-24:], {"role": "user", "content": message}]
            reply = self.model.complete(messages, temperature=0.5, max_tokens=900)
            if not isinstance(reply, str) or not reply.strip():
                raise NativeTrainingError("HERMES returned an empty chat response")
            reply = reply.strip()[:6000]
            self._history.extend([
                {"role": "user", "content": message},
                {"role": "assistant", "content": reply},
            ])
            row = self._record("chat", {
                "user": message, "hermes": reply,
                "native_student_trained": False,
                "scratch_state_sha256": _sha(self.scratch),
            })
            return {"reply": reply, "tick": row["tick"],
                    "transcript_sha256": row["sha256"], "trained": False}

    def teach(self, subject: str, predicate: str, obj: str, polarity: str,
              *, resolution: int = 7, confidence_q16: int = 65535) -> dict:
        with self._lock:
            self.start()
            fields = [_text(subject, "subject"), _text(predicate, "predicate"),
                      _text(obj, "object")]
            if polarity not in ("+", "-"):
                raise NativeTrainingError("polarity must be + or -")
            if type(resolution) is not int or not 0 <= resolution <= 9:
                raise NativeTrainingError("resolution must be 0..9")
            if type(confidence_q16) is not int or not 1 <= confidence_q16 <= 65535:
                raise NativeTrainingError("confidence_q16 must be 1..65535")
            source = {
                "session_id": self.session_id, "event": self._clock + 1,
                "subject": subject, "predicate": predicate, "object": obj,
                "polarity": polarity, "resolution": resolution,
                "confidence_q16": confidence_q16,
            }
            source_sha = hashlib.sha256(_canonical(source)).hexdigest()
            row = "\t".join([
                "train", str(resolution), polarity, str(confidence_q16),
                *(value.hex() for value in fields), source_sha,
            ])
            records = self.directory / f"teach_{self._clock + 1:06}.n16rel"
            records.write_text("N16REL/1\n" + row + "\n", encoding="ascii")
            before = _sha(self.scratch)
            proc = self._native("relation-train", str(records), str(self.scratch), "1")
            status = re.search(r"(?m)^relation_train status=(updated|no_op)\b",
                               proc.stdout or "")
            if proc.returncode != 0 or status is None:
                raise NativeTrainingError("native N16REL scratch teaching failed")
            after = _sha(self.scratch)
            evidence = {
                "native_training_status": status.group(1),
                "source_sha256": source_sha,
                "records_sha256": _sha(records),
                "scratch_before_sha256": before,
                "scratch_after_sha256": after,
                "native_output_sha256": hashlib.sha256((proc.stdout or "").encode()).hexdigest(),
                "canonical_merge_committed": False,
            }
            # Return the native student's measured result to HERMES for
            # reflection. The response is conversational evidence, not an
            # authorized merge or an additional native training signal.
            try:
                feedback = self.model.complete([
                    {"role": "system", "content": (
                        "You are HERMES. Reflect on NaNLMind's actual native "
                        "scratch training status. Never claim canonical merge, "
                        "mathematical proof or conversational fluency from a hash."
                    )},
                    {"role": "user", "content": json.dumps({
                        "subject": subject, "predicate": predicate,
                        "object": obj, "polarity": polarity,
                        "resolution": resolution, "native_evidence": evidence,
                        "task": "Interpret the result and suggest a measurable next experiment."
                    }, sort_keys=True)},
                ], temperature=0.2, max_tokens=400)
                if isinstance(feedback, str) and feedback.strip():
                    evidence["hermes_reflection"] = feedback.strip()[:2000]
                    self._history.extend([
                        {"role": "user", "content": (
                            f"Teach: {subject} {predicate} {obj} ({polarity})"
                        )},
                        {"role": "assistant", "content": evidence["hermes_reflection"]},
                    ])
            except Exception:
                # A model outage cannot erase already committed native scratch
                # state; return evidence, do not claim a reflection occurred.
                evidence["hermes_reflection_unavailable"] = True
            entry = self._record("native_relation_teach", evidence)
            return {**evidence, "tick": entry["tick"],
                    "transcript_sha256": entry["sha256"],
                    "scratch_state": str(self.scratch)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Logic-gated free Hermes chat")
    parser.add_argument("--core", default="build/nanlm-universal")
    parser.add_argument("--core-sha256", default=os.environ.get("NANLM_CORE_SHA256"))
    parser.add_argument("--base-state", default="")
    parser.add_argument("--state-dir", default="state/hermes_free_chat")
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--epoch", type=int, default=0)
    parser.add_argument("--session-id", default="")
    parser.add_argument("--model-url", default=os.environ.get("NANLM_MODEL_URL", ""))
    parser.add_argument("--model", default=os.environ.get("NANLM_MODEL", "hermes"))
    parser.add_argument("--model-token", default=os.environ.get("NANLM_MODEL_TOKEN", ""))
    parser.add_argument("--message", action="append", default=[])
    parser.add_argument("--teach", action="append", default=[],
                        help="SUBJECT|PREDICATE|OBJECT|(+ or -)|RESOLUTION")
    parser.add_argument("--interactive", action="store_true")
    args = parser.parse_args(argv)

    if not args.model_url:
        parser.error("a live HERMES/OpenAI-compatible model endpoint is required")
    from conversation_trainer import OpenAICompatibleClient
    model = OpenAICompatibleClient(args.model_url, args.model, args.model_token)
    chat = HermesFreeChat(
        model, core=args.core, core_sha256=args.core_sha256,
        base_state=args.base_state or None,
        state_dir=args.state_dir, slot=args.slot, epoch=args.epoch,
        session_id=args.session_id or None,
    )
    try:
        print(json.dumps({"logic_gate": chat.start()}, sort_keys=True))
        for raw in args.teach:
            parts = raw.split("|")
            if len(parts) != 5:
                raise NativeTrainingError("teach expects subject|predicate|object|polarity|resolution")
            print(json.dumps(chat.teach(parts[0], parts[1], parts[2],
                                        parts[3], resolution=int(parts[4])),
                             sort_keys=True))
        for message in args.message:
            print(json.dumps(chat.chat(message), sort_keys=True))
        if args.interactive:
            for line in sys.stdin:
                message = line.rstrip("\n")
                if message in ("/exit", "/quit"):
                    break
                if message.startswith("/teach "):
                    parts = message[7:].split("|")
                    if len(parts) != 5:
                        raise NativeTrainingError("teach expects subject|predicate|object|polarity|resolution")
                    result = chat.teach(parts[0], parts[1], parts[2],
                                        parts[3], resolution=int(parts[4]))
                else:
                    result = chat.chat(message)
                print(json.dumps(result, sort_keys=True), flush=True)
    except (NativeTrainingError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
