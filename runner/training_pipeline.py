#!/usr/bin/env python3
"""Staged demo training pipeline for NaNLMind HERMES/Clocked runners.

Stages:
  inverses_boolean -> deep_logic -> common_words -> repetitive_words
  -> word_choice -> sentences

Every stage has a wall-clock budget. `--single STAGE` runs one test stage only.
The pipeline is deliberately dependency-free so the runner, HERMES, and Clocked
adapters can all drive the same curriculum.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from training_corpus import STAGES, StageSpec, build_stage, write_n16txt

DEFAULT_SECONDS = {
    "inverses_boolean": 1.0,
    "deep_logic": 1.0,
    "common_words": 1.0,
    "repetitive_words": 1.0,
    "word_choice": 1.5,
    "sentences": 1.5,
}


@dataclass
class StageReport:
    name: str
    kind: str
    seconds: float
    samples: int
    train_samples: int
    test_samples: int
    cycles: int
    accuracy: float
    passed: bool
    detail: str = ""


@dataclass
class PipelineConfig:
    seed: int = 0xD3E3
    stage_seconds: dict[str, float] = field(default_factory=lambda: dict(DEFAULT_SECONDS))
    single_stage: str = ""
    stage_names: list[str] = field(default_factory=list)
    slot: int = 1
    epoch: int = 0
    state_dir: str = "state/training_pipeline"
    corpus_path: str = "state/training_pipeline/curriculum.n16txt"
    max_samples: int = 0
    max_corpus_bytes: int = 1_000_000


class BooleanModel:
    def __init__(self) -> None:
        self.counts = [[0, 0] for _ in range(16 * 4)]

    def observe(self, sample: dict) -> None:
        op = int(sample["op"]) & 15
        index = 2 * int(sample["a"]) + int(sample["b"])
        self.counts[op * 4 + index][int(bool(sample["target"]))] += 1

    def predict(self, sample: dict) -> bool:
        op = int(sample["op"]) & 15
        index = 2 * int(sample["a"]) + int(sample["b"])
        return self.counts[op * 4 + index][1] >= self.counts[op * 4 + index][0]


class WordModel:
    def __init__(self) -> None:
        self.unigram: Counter[str] = Counter()
        self.bigram: dict[str, Counter[str]] = defaultdict(Counter)

    def observe(self, sample: dict) -> None:
        kind = sample.get("kind")
        if kind == "word":
            word = sample["word"]
            self.unigram[word] += 1
            tokens = sample.get("context", "").split()
            if tokens:
                self.bigram[tokens[-1]][word] += 1
        elif kind in ("choice", "sentence"):
            answer = sample["answer"]
            self.unigram[answer] += 1
            prefix = sample.get("context", sample.get("prefix", "")).split()
            if prefix:
                self.bigram[prefix[-1]][answer] += 1

    def predict_word(self, sample: dict) -> str:
        tokens = sample.get("context", "").split()
        if tokens and self.bigram[tokens[-1]]:
            return self.bigram[tokens[-1]].most_common(1)[0][0]
        return self.unigram.most_common(1)[0][0] if self.unigram else ""

    def predict_choice(self, sample: dict) -> str:
        options = sample["options"]
        prefix = sample.get("context", sample.get("prefix", "")).split()
        last = prefix[-1] if prefix else ""

        def score(option: str) -> tuple[int, int]:
            return (self.bigram[last][option], self.unigram[option])
        return max(options, key=score)


class LogicModel:
    def __init__(self) -> None:
        self.isa: dict[str, str] = {}
        self.can: dict[str, set[str]] = defaultdict(set)
        self.cannot: dict[str, set[str]] = defaultdict(set)
        self.depth = 0

    def observe(self, sample: dict) -> None:
        for fact in sample["facts"]:
            words = fact.rstrip(".").split()
            if len(words) >= 3 and words[1] == "isa":
                self.isa[words[0]] = words[2]
            elif len(words) >= 4 and words[1] == "is" and words[2] == "a":
                self.isa[words[0]] = words[3]
            elif len(words) >= 3 and words[1] == "can":
                self.can[words[0]].add(words[2])
            elif len(words) >= 3 and words[1] == "cannot":
                self.cannot[words[0]].add(words[2])
        depth = int(sample["depth"])
        if depth > self.depth:
            self.depth = min(depth, 8)

    def answer(self, entity: str, ability: str) -> bool | None:
        chain = [entity]
        seen = {entity}
        current = entity
        for _ in range(64):
            parent = self.isa.get(current)
            if parent is None or parent in seen:
                break
            chain.append(parent)
            seen.add(parent)
            current = parent
        for node in chain[: self.depth + 2]:
            if ability in self.cannot[node]:
                return False
        for node in chain[: self.depth + 2]:
            if ability in self.can[node]:
                return True
        return None


def _split(samples: list[dict]) -> tuple[list[dict], list[dict]]:
    cut = max(1, int(len(samples) * 0.8))
    if cut >= len(samples):
        cut = len(samples) - 1
    return samples[:cut], samples[cut:]


def _evaluate(kind: str, model, test: list[dict]) -> tuple[int, int, str]:
    correct = 0
    for sample in test:
        if kind == "boolean":
            got = model.predict(sample)
            expected = bool(sample["target"])
        elif kind == "logic":
            # Facts are part of the puzzle context at inference time.
            model.observe(sample)
            got = model.answer(sample["entity"], sample["ability"])
            expected = bool(sample["answer"])
        elif kind == "words":
            got = model.predict_word(sample)
            expected = sample["word"]
        else:
            got = model.predict_choice(sample)
            expected = sample["answer"]
        if got == expected:
            correct += 1
    return correct, len(test), ""


def _make_model(kind: str):
    if kind == "boolean":
        return BooleanModel()
    if kind == "logic":
        return LogicModel()
    return WordModel()


def run_stage(spec: StageSpec, seconds: float, seed: int,
              max_samples: int = 0) -> StageReport:
    samples = build_stage(spec, seed)
    if max_samples > 0:
        samples = samples[:max_samples]
    if len(samples) < 2:
        return StageReport(spec.name, spec.kind, seconds, len(samples), 0, 0, 0, 0.0,
                           False, "not enough samples")
    train, test = _split(samples)
    model = _make_model(spec.kind)
    deadline = time.monotonic() + max(0.001, seconds)
    cycles = 0
    while time.monotonic() < deadline or cycles == 0:
        for sample in train:
            model.observe(sample)
        cycles += 1
        if cycles >= 200 and time.monotonic() < deadline:
            # Prevent a fast model from spinning; the budget remains honoured
            # by the next stage but this stage is already saturated.
            break
    correct, total, detail = _evaluate(spec.kind, model, test)
    accuracy = correct / total if total else 0.0
    # Boolean and logic gates must be exact; word stages are diagnostic.
    threshold = 0.999 if spec.kind in ("boolean", "logic") else 0.50
    return StageReport(
        spec.name, spec.kind, seconds, len(samples), len(train), len(test),
        cycles, accuracy, accuracy >= threshold, detail)


def run_pipeline(config: PipelineConfig) -> dict:
    selected = [s for s in STAGES
                if (not config.stage_names or s.name in config.stage_names)
                and (not config.single_stage or s.name == config.single_stage)]
    if not selected:
        raise ValueError(f"unknown stage: {config.single_stage}")
    corpus = Path(config.corpus_path)
    write_n16txt(corpus, selected, config.seed, config.max_corpus_bytes)
    corpus_digest = hashlib.sha256(corpus.read_bytes()).hexdigest()
    reports = []
    for spec in selected:
        seconds = float(config.stage_seconds.get(spec.name, 1.0))
        report = run_stage(spec, seconds, config.seed, config.max_samples)
        reports.append(report)
        print(f"stage={report.name} kind={report.kind} seconds={seconds} "
              f"samples={report.samples} cycles={report.cycles} "
              f"test={report.test_samples} accuracy={report.accuracy:.4f} "
              f"passed={'yes' if report.passed else 'no'}", flush=True)
        if not report.passed:
            break
    return {
        "ok": all(report.passed for report in reports),
        "slot": config.slot,
        "epoch": config.epoch,
        "corpus_path": str(corpus),
        "corpus_native_path": str(corpus.with_suffix(".native.txt")),
        "corpus_sha256": corpus_digest,
        "corpus_bytes": corpus.stat().st_size,
        "stages": [report.__dict__ for report in reports],
    }


class RunnerSink:
    def __init__(self, state_dir: str) -> None:
        self.state_dir = Path(state_dir)
        self.state_dir.mkdir(parents=True, exist_ok=True)

    def emit(self, result: dict) -> None:
        path = self.state_dir / f"training_{result['epoch']}_{result['slot']}.json"
        path.write_text(json.dumps(result, indent=1, sort_keys=True) + "\n")


class MemoryMergeClient:
    def __init__(self, url: str = "", token: str = "") -> None:
        self.url = url
        self.token = token

    def emit(self, result: dict) -> dict | None:
        if not self.url or not self.token:
            return None
        stages = result.get("stages", [])
        score = sum(item.get("accuracy", 0.0) for item in stages) / max(1, len(stages))
        body = json.dumps({
            "node": int(result.get("slot", 1)),
            "base_generation": 0,
            "nanclock_tick": int(result.get("epoch", 0)),
            "updates": [{
                "head": int(result.get("slot", 1)) % 256,
                "layer": 0,
                "epoch": int(result.get("epoch", 0)),
                "strength_delta": int(score * 1000),
                "vector": [0] * 16,
                "route": "staged-logic-pipeline",
            }],
        }, sort_keys=True).encode()
        request = urllib.request.Request(
            self.url.rstrip("/") + "/v1/training/merge", data=body,
            headers={
                "Authorization": "Bearer " + self.token,
                "Content-Type": "application/json",
                "Idempotency-Key": f"pipeline-{result.get('slot')}-{result.get('epoch')}",
            }, method="POST")
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)


def parse_stage_seconds(value: str) -> dict[str, float]:
    if not value:
        return dict(DEFAULT_SECONDS)
    result = dict(DEFAULT_SECONDS)
    if "=" not in value:
        seconds = float(value)
        return {spec.name: seconds for spec in STAGES}
    for item in value.split(","):
        name, seconds = item.split("=", 1)
        result[name.strip()] = float(seconds)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--epoch", type=int, default=0)
    parser.add_argument("--seed", type=int, default=0xD3E3)
    parser.add_argument("--single", default="", metavar="STAGE",
                        help="run one stage only, e.g. inverses_boolean")
    parser.add_argument("--stage-seconds", default="1.0",
                        help="seconds for all stages or name=seconds,...")
    parser.add_argument("--max-samples", type=int, default=0)
    parser.add_argument("--state-dir", default="state/training_pipeline")
    parser.add_argument("--corpus", default="state/training_pipeline/curriculum.n16txt")
    parser.add_argument("--max-corpus-bytes", type=int, default=1_000_000)
    parser.add_argument("--out", default="")
    parser.add_argument("--merge-url", default=os.environ.get("NANLM_MERGE_URL", ""))
    parser.add_argument("--merge-token", default=os.environ.get("NANLM_MERGE_TOKEN", ""))
    args = parser.parse_args(argv)

    config = PipelineConfig(
        seed=args.seed, stage_seconds=parse_stage_seconds(args.stage_seconds),
        single_stage=args.single, slot=args.slot, epoch=args.epoch,
        state_dir=args.state_dir, corpus_path=args.corpus,
        max_samples=args.max_samples, max_corpus_bytes=args.max_corpus_bytes)
    result = run_pipeline(config)
    RunnerSink(args.state_dir).emit(result)
    try:
        result["merge"] = MemoryMergeClient(args.merge_url, args.merge_token).emit(result)
    except Exception as exc:
        result["merge_error"] = str(exc)
    encoded = json.dumps(result, indent=1, sort_keys=True) + "\n"
    if args.out:
        path = Path(args.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(encoded)
    sys.stdout.write(encoded)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
