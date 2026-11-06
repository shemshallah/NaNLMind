#!/usr/bin/env python3
"""HERMES/Clocked adapter for the staged training pipeline.

HERMES consumes strict N16TXT/1 corpora, trains the native 256-head topology,
and merges structured discoveries into its additive memory ledger. This adapter
prepares the same corpus, runs the staged curriculum, emits layer-tagged
discovery records, and exposes a prompt-to-plan interface for HERMES.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from training_corpus import STAGES, write_n16txt
from training_pipeline import (
    PipelineConfig,
    MemoryMergeClient,
    run_pipeline,
)

LAYER = {
    "inverses_boolean": 3,  # operators
    "deep_logic": 4,        # equations
    "common_words": 2,      # relations
    "repetitive_words": 2,
    "word_choice": 5,       # hypotheses
    "sentences": 5,
}


def plan_for_prompt(text: str) -> list[str]:
    value = text.lower()
    if any(word in value for word in ("boolean", "inverse", "truth")):
        return ["inverses_boolean"]
    if any(word in value for word in ("deep", "chain", "adder", "circuit")):
        return ["deep_logic"]
    if any(word in value for word in ("sentence", "next word")):
        return ["sentences"]
    if any(word in value for word in ("word", "choose", "choice", "vocab")):
        return ["common_words", "word_choice"]
    return [stage.name for stage in STAGES]


class HermesPipeline:
    def __init__(self, state_dir: str = "state/hermes_pipeline",
                 corpus: str = "state/hermes_pipeline/curriculum.n16txt",
                 stage_seconds: dict[str, float] | None = None,
                 slot: int = 1, epoch: int = 0):
        self.state_dir = Path(state_dir)
        self.corpus = Path(corpus)
        self.stage_seconds = stage_seconds or {}
        self.slot = slot
        self.epoch = epoch

    def prepare(self, names: list[str] | None = None) -> dict:
        specs = [stage for stage in STAGES if not names or stage.name in names]
        write_n16txt(self.corpus, specs, max_bytes=1_000_000)
        raw = self.corpus.read_bytes()
        return {
            "corpus": str(self.corpus),
            "native_corpus": str(self.corpus.with_suffix(".native.txt")),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw),
            "records": max(0, len(raw.splitlines()) - 1),
        }

    def train(self, names: list[str] | None = None, max_samples: int = 0) -> dict:
        selected = names or [stage.name for stage in STAGES]
        self.prepare(selected)
        config = PipelineConfig(
            stage_seconds={name: self.stage_seconds.get(name, 0.25) for name in selected},
            stage_names=selected,
            slot=self.slot, epoch=self.epoch,
            state_dir=str(self.state_dir), corpus_path=str(self.corpus),
            max_samples=max_samples)
        result = run_pipeline(config)
        result["hermes"] = self.discoveries(result)
        return result

    def discoveries(self, result: dict) -> list[dict]:
        digest = result["corpus_sha256"]
        events = []
        for stage in result.get("stages", []):
            name = stage["name"]
            events.append({
                "kind": "operator" if name == "inverses_boolean" else (
                    "equation" if name == "deep_logic" else "hypothesis"),
                "subject": f"pipeline/{name}",
                "predicate": "heldout_accuracy",
                "object": stage["accuracy"],
                "layer": LAYER.get(name, 0),
                "head": (self.slot - 1) % 256,
                "confidence": stage["accuracy"],
                "evidence": {
                    "samples": stage["samples"],
                    "test_samples": stage["test_samples"],
                    "correct": int(round(stage["accuracy"] * stage["test_samples"])),
                },
                "provenance": {
                    "pipeline": "training_pipeline",
                    "slot": self.slot,
                    "epoch": self.epoch,
                    "source_sha256": digest,
                },
                "polarity": "supports" if stage["passed"] else "refutes",
            })
        return events

    def ingest_memory(self, result: dict, path: str = "") -> dict:
        """Optional HERMES memory-ledger ingestion; bundle output remains canonical."""
        try:
            from nanlmind_hermes.memory import MemoryStore
        except Exception as exc:
            return {"available": False, "error": str(exc), "discoveries": len(result.get("hermes", []))}
        store = MemoryStore(path or str(self.state_dir / "mathematical_memory.sqlite3"),
                            heads=256, layers=7)
        records = [{
            "item": event,
            "source_digest": result["corpus_sha256"],
            "head": event["head"],
            "layer": event["layer"],
        } for event in result.get("hermes", [])]
        merge = store.merge(records)
        reorganization = store.reorganize()
        return {"available": True, "merge": merge,
                "reorganization": reorganization, "status": store.status()}

    def write_bundle(self, result: dict) -> Path:
        bundle = self.state_dir / "bundle"
        bundle.mkdir(parents=True, exist_ok=True)
        (bundle / "corpus.n16txt").write_bytes(self.corpus.read_bytes())
        (bundle / "discoveries.jsonl").write_text(
            "".join(json.dumps(event, sort_keys=True) + "\n"
                    for event in result.get("hermes", [])))
        (bundle / "manifest.json").write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n")
        return bundle

    def prompt(self, text: str, run: bool = True) -> dict:
        names = plan_for_prompt(text)
        if not run:
            return {"prompt": text, "plan": names, "trained": False}
        result = self.train(names, max_samples=512)
        return {
            "prompt": text,
            "plan": names,
            "trained": True,
            "ok": result["ok"],
            "stages": result.get("stages", []),
            "response": (
                "Training plan: " + ", ".join(names) +
                ". Result: " + ("PASS" if result["ok"] else "FAIL")
            ),
        }


class ClockedAdapter:
    """Attach the same curriculum to the runner/Clocked epoch loop."""

    def __init__(self, pipeline: HermesPipeline, clock=None):
        self.pipeline = pipeline
        self.clock = clock

    def tick(self, epoch: int | None = None) -> dict:
        if epoch is not None:
            self.pipeline.epoch = epoch
        elif self.clock is not None:
            self.pipeline.epoch = int(getattr(self.clock, "tick", lambda: self.pipeline.epoch)())
        result = self.pipeline.train()
        result["clock"] = {"epoch": self.pipeline.epoch, "attached": True}
        return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", default="state/hermes_pipeline")
    parser.add_argument("--corpus", default="")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--stage", default="")
    parser.add_argument("--seconds", type=float, default=0.25)
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--epoch", type=int, default=0)
    parser.add_argument("--no-train", action="store_true")
    parser.add_argument("--merge-url", default="")
    parser.add_argument("--merge-token", default="")
    parser.add_argument("--ingest-memory", action="store_true")
    parser.add_argument("--memory-path", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args(argv)

    corpus = args.corpus or str(Path(args.state_dir) / "curriculum.n16txt")
    pipeline = HermesPipeline(args.state_dir, corpus, {"": args.seconds},
                              args.slot, args.epoch)
    pipeline.stage_seconds = {stage.name: args.seconds for stage in STAGES}
    if args.prompt:
        result = pipeline.prompt(args.prompt, run=not args.no_train)
    else:
        names = [args.stage] if args.stage else None
        result = pipeline.train(names, max_samples=512 if args.stage else 0)
    if not args.no_train:
        try:
            result["merge"] = MemoryMergeClient(args.merge_url, args.merge_token).emit(result)
        except Exception as exc:
            result["merge_error"] = str(exc)
        if args.ingest_memory:
            result["memory"] = pipeline.ingest_memory(result, args.memory_path)
        bundle = pipeline.write_bundle(result)
        result["bundle"] = str(bundle)
    encoded = json.dumps(result, indent=1, sort_keys=True) + "\n"
    if args.out:
        path = Path(args.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(encoded)
    sys.stdout.write(encoded)
    return 0 if result.get("ok", True) else 1


if __name__ == "__main__":
    raise SystemExit(main())
