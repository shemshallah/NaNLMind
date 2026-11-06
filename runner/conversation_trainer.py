#!/usr/bin/env python3
"""Conversational training loop for HERMES and standalone demos.

The loop is deliberately explicit:

  host/model prompt -> JSON training intent -> pipeline stage
  -> metrics -> memory merge -> reflection prompt -> next intent

A model client can be:
  * an OpenAI-compatible HTTP endpoint;
  * a HERMES context's `ctx.llm.complete` through a tiny wrapper;
  * a deterministic local fallback used for tests and demos.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

from training_corpus import STAGES
from training_pipeline import (
    MemoryMergeClient,
    PipelineConfig,
    run_pipeline,
)


class ModelClient(Protocol):
    def complete(self, messages: list[dict], **kwargs: Any) -> str: ...


class OpenAICompatibleClient:
    """Minimal client for an OpenAI-compatible /chat/completions endpoint."""

    def __init__(self, base_url: str, model: str, token: str = "",
                 timeout: int = 120):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.token = token
        self.timeout = timeout

    def complete(self, messages: list[dict], **kwargs: Any) -> str:
        body = json.dumps({
            "model": self.model,
            "messages": messages,
            "temperature": kwargs.get("temperature", 0.4),
            "max_tokens": kwargs.get("max_tokens", 1200),
        }).encode()
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        request = urllib.request.Request(
            self.base_url + "/chat/completions", data=body,
            headers=headers, method="POST")
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            payload = json.load(response)
        return payload["choices"][0]["message"]["content"]


class HermesModelClient:
    """Wrap a HERMES/OpenCode-style context exposing ctx.llm.complete."""

    def __init__(self, ctx: Any):
        self.ctx = ctx

    def complete(self, messages: list[dict], **kwargs: Any) -> str:
        result = self.ctx.llm.complete(
            messages=messages,
            temperature=kwargs.get("temperature", 0.4),
            max_tokens=kwargs.get("max_tokens", 1200),
            timeout=kwargs.get("timeout", 180),
            purpose=kwargs.get("purpose", "nanlmind-conversation-training"),
        )
        return getattr(result, "text", "")


class DeterministicPlanner:
    """Fallback planner for Termux demos and deterministic tests."""

    def __init__(self, stages: list[str] | None = None):
        self.stages = stages or [stage.name for stage in STAGES]
        self.index = 0

    def complete(self, messages: list[dict], **kwargs: Any) -> str:
        last = messages[-1]["content"] if messages else ""
        if "training result" in last.lower() or "next action" in last.lower():
            return "The measured result is recorded; I will continue with the next unmastered stage."
        message = "I will start with Boolean inverses, then deep logic, words, and sentences."
        stage = self.stages[self.index % len(self.stages)]
        self.index += 1
        return json.dumps({"stage": stage, "message": message})


@dataclass
class LoopRound:
    index: int
    stage: str
    model_message: str
    plan: dict
    result: dict
    reflection: str
    accuracy: float
    improved: bool


@dataclass
class ConversationConfig:
    rounds: int = 5
    seconds: float = 0.5
    max_samples: int = 1024
    initial_stage: str = "inverses_boolean"
    state_dir: str = "state/conversation_training"
    slot: int = 1
    epoch: int = 0
    merge_url: str = ""
    merge_token: str = ""


def _json_object(text: str) -> dict:
    candidate = text.strip()
    if candidate.startswith("```"):
        candidate = re.sub(r"^```(?:json)?\s*|\s*```$", "", candidate, flags=re.I)
    try:
        value = json.loads(candidate)
    except json.JSONDecodeError:
        start, end = candidate.find("{"), candidate.rfind("}")
        if start < 0 or end <= start:
            return {}
        try:
            value = json.loads(candidate[start:end + 1])
        except json.JSONDecodeError:
            return {}
    return value if isinstance(value, dict) else {}


def validate_stage(value: Any, fallback: str = "inverses_boolean") -> str:
    names = {stage.name for stage in STAGES}
    return value if isinstance(value, str) and value in names else fallback


class ConversationTrainer:
    def __init__(self, model: ModelClient, config: ConversationConfig):
        self.model = model
        self.config = config
        self.state = Path(config.state_dir)
        self.state.mkdir(parents=True, exist_ok=True)
        self.merge = MemoryMergeClient(config.merge_url, config.merge_token)
        self.transcript_path = self.state / f"conversation_{config.epoch}_{config.slot}.jsonl"

    def _messages(self, previous: list[LoopRound], next_stage: str) -> list[dict]:
        stages = [
            {"name": s.name, "kind": s.kind, "samples": s.samples}
            for s in STAGES
        ]
        history = [
            {
                "stage": item.stage,
                "accuracy": item.accuracy,
                "improved": item.improved,
                "model_message": item.model_message,
            }
            for item in previous
        ]
        prompt = {
            "task": "You are HERMES. Choose the next NaNLMind training action.",
            "available_stages": stages,
            "suggested_stage": next_stage,
            "history": history,
            "rules": [
                "Return only JSON.",
                "The stage must be one of available_stages.",
                "Prefer logic before words when logic is not yet passing.",
                "Use word_choice before sentences.",
                "Include a short conversational message explaining the choice.",
            ],
            "schema": {"stage": "stage name", "message": "short text"},
        }
        return [
            {"role": "system", "content": "You are HERMES' conversational training controller. Return valid JSON."},
            {"role": "user", "content": json.dumps(prompt, ensure_ascii=False)},
        ]

    def _reflect(self, item: LoopRound) -> str:
        messages = [
            {"role": "system", "content": "You are HERMES reflecting on a training result. Be concise."},
            {"role": "user", "content": json.dumps({
                "task": "Reflect on this training result and state the next action.",
                "stage": item.stage,
                "accuracy": item.accuracy,
                "improved": item.improved,
                "result": item.result.get("stages", []),
                "rules": ["Do not claim proof from a single score.", "Mention what to repeat or diversify."],
            }, ensure_ascii=False)},
        ]
        reply = self.model.complete(messages, temperature=0.2, max_tokens=400)
        return reply.strip() or "Continue based on the recorded metric."

    def run(self, initial_message: str = "") -> dict:
        rounds: list[LoopRound] = []
        best = -1.0
        stage = validate_stage(self.config.initial_stage)
        next_stage = stage
        for index in range(1, max(1, self.config.rounds) + 1):
            messages = self._messages(rounds, next_stage)
            if initial_message and index == 1:
                messages.append({"role": "user", "content": initial_message})
            reply = self.model.complete(messages, temperature=0.4, max_tokens=600)
            plan = _json_object(reply)
            stage = validate_stage(plan.get("stage"), next_stage)
            model_message = str(plan.get("message", reply[:500]))
            config = PipelineConfig(
                stage_seconds={s.name: self.config.seconds for s in STAGES},
                single_stage=stage,
                slot=self.config.slot, epoch=self.config.epoch,
                state_dir=str(self.state),
                corpus_path=str(self.state / f"corpus_{self.config.epoch}_{self.config.slot}_{index}.n16txt"),
                max_samples=self.config.max_samples,
            )
            with contextlib.redirect_stdout(io.StringIO()):
                result = run_pipeline(config)
            accuracy = result["stages"][0]["accuracy"] if result.get("stages") else 0.0
            improved = accuracy > best
            if improved:
                best = accuracy
            item = LoopRound(index, stage, model_message, plan, result,
                             "", accuracy, improved)
            item.reflection = self._reflect(item)
            rounds.append(item)
            self._append(item)
            try:
                merged = self.merge.emit(result)
                if merged is not None:
                    item.plan["merge"] = merged
            except Exception as exc:
                item.plan["merge_error"] = str(exc)
            next_stage = self._next_stage(stage, rounds)
            if result.get("ok"):
                # Keep the conversation going for demonstration; the caller can
                # stop earlier by setting rounds.
                pass
        summary = {
            "ok": True,
            "slot": self.config.slot,
            "epoch": self.config.epoch,
            "rounds": [{
                "round": item.index,
                "stage": item.stage,
                "accuracy": item.accuracy,
                "improved": item.improved,
                "model_message": item.model_message,
                "reflection": item.reflection,
                "corpus": item.result.get("corpus_path"),
            } for item in rounds],
            "transcript": str(self.transcript_path),
            "best_accuracy": max((item.accuracy for item in rounds), default=0.0),
        }
        (self.state / f"summary_{self.config.epoch}_{self.config.slot}.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n")
        return summary

    def _next_stage(self, current: str, rounds: list[LoopRound]) -> str:
        names = [stage.name for stage in STAGES]
        try:
            index = names.index(current)
        except ValueError:
            index = 0
        # Logic gates before words; word choice before sentences. If a stage is
        # already passing, move forward; otherwise offer the same stage again.
        last = rounds[-1]
        if not last.result.get("ok"):
            return current
        return names[(index + 1) % len(names)]

    def _append(self, item: LoopRound) -> None:
        row = {
            "round": item.index,
            "stage": item.stage,
            "model_message": item.model_message,
            "plan": item.plan,
            "accuracy": item.accuracy,
            "improved": item.improved,
            "reflection": item.reflection,
            "corpus_sha256": item.result.get("corpus_sha256"),
        }
        with self.transcript_path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(row, sort_keys=True) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--seconds", type=float, default=0.5)
    parser.add_argument("--max-samples", type=int, default=1024)
    parser.add_argument("--initial-stage", default="inverses_boolean")
    parser.add_argument("--state-dir", default="state/conversation_training")
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--epoch", type=int, default=0)
    parser.add_argument("--message", default="")
    parser.add_argument("--model-url", default=os.environ.get("NANLM_MODEL_URL", ""))
    parser.add_argument("--model", default=os.environ.get("NANLM_MODEL", "hermes"))
    parser.add_argument("--model-token", default=os.environ.get("NANLM_MODEL_TOKEN", ""))
    parser.add_argument("--merge-url", default=os.environ.get("NANLM_MERGE_URL", ""))
    parser.add_argument("--merge-token", default=os.environ.get("NANLM_MERGE_TOKEN", ""))
    parser.add_argument("--out", default="")
    args = parser.parse_args(argv)

    if args.model_url:
        model: ModelClient = OpenAICompatibleClient(
            args.model_url, args.model, args.model_token)
    else:
        model = DeterministicPlanner()
    config = ConversationConfig(
        rounds=max(1, args.rounds), seconds=max(0.001, args.seconds),
        max_samples=max(0, args.max_samples), initial_stage=args.initial_stage,
        state_dir=args.state_dir, slot=args.slot, epoch=args.epoch,
        merge_url=args.merge_url, merge_token=args.merge_token)
    summary = ConversationTrainer(model, config).run(args.message)
    encoded = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.out:
        path = Path(args.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(encoded)
    sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
