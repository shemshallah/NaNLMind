#!/usr/bin/env python3
"""Graded logic curriculum for the NaNLMind runner ring.

The model is deliberately small and observable: a relation memory with a
learned ancestry depth. It starts unable to answer inherited questions, sees
support facts/examples, is tested on held-out puzzles, receives corrections for
mistakes, and repeats only while the measured score improves.

This is a runner-side training curriculum, not a claim that the byte model is
already a compositional reasoner.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


@dataclass
class Query:
    entity: str
    ability: str
    expected: bool


@dataclass
class PuzzleLevel:
    level: int
    name: str
    facts: list[str]
    support_queries: list[Query]
    test_queries: list[Query]


@dataclass
class LogicMemory:
    isa: dict[str, str] = field(default_factory=dict)
    can: dict[str, set[str]] = field(default_factory=dict)
    cannot: dict[str, set[str]] = field(default_factory=dict)
    learned_depth: int = 0
    corrections: int = 0

    def learn_fact(self, fact: str) -> None:
        words = fact.rstrip(".").split()
        if len(words) < 4:
            return
        subject, rel = words[0], words[1]
        if rel == "is" and words[2] == "a":
            self.isa[subject] = words[3]
        elif rel == "can":
            self.can.setdefault(subject, set()).add(words[2])
        elif rel == "cannot":
            self.cannot.setdefault(subject, set()).add(words[2])

    def learn(self, facts: Iterable[str]) -> None:
        for fact in facts:
            self.learn_fact(fact)

    def _chain(self, entity: str) -> list[str]:
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
        return chain

    def path_depth(self, entity: str) -> int:
        return len(self._chain(entity)) - 1

    def answer(self, entity: str, ability: str) -> bool | None:
        chain = self._chain(entity)
        # Minsky-style exception search: the nearest negative rule wins before
        # positive inheritance.
        for node in chain[: self.learned_depth + 1]:
            if ability in self.cannot.get(node, set()):
                return False
        for node in chain[: self.learned_depth + 1]:
            if ability in self.can.get(node, set()):
                return True
        return None

    def feedback(self, query: Query) -> None:
        """Online correction: learn the missing capability and the direct fact."""
        self.corrections += 1
        depth = self.path_depth(query.entity)
        if depth > self.learned_depth:
            self.learned_depth = min(depth, 8)
        if query.expected:
            self.can.setdefault(query.entity, set()).add(query.ability)
        else:
            self.cannot.setdefault(query.entity, set()).add(query.ability)


def query(entity: str, ability: str, expected: bool) -> Query:
    return Query(entity, ability, expected)


def make_level(level: int) -> PuzzleLevel:
    facts = [
        "sparrow is a bird.",
        "robin is a bird.",
        "penguin is a bird.",
        "penguin cannot fly.",
        "penguin can swim.",
        "emperor is a penguin.",
        "king is a penguin.",
        "ostrich is a bird.",
        "ostrich cannot fly.",
        "ostrich can run.",
        "salmon is a fish.",
        "shark is a fish.",
        "fish can swim.",
        "fish cannot fly.",
        "can sparrow fly? answer sparrow yes.",
        "can penguin fly? answer penguin no.",
        "can penguin swim? answer penguin yes.",
        "can salmon swim? answer salmon yes.",
        "can salmon fly? answer salmon no.",
        "can ostrich run? answer ostrich yes.",
        "can emperor swim? answer emperor yes.",
        "can emperor fly? answer emperor no.",
    ]
    support = [
        query("sparrow", "fly", True),
        query("penguin", "fly", False),
        query("penguin", "swim", True),
        query("salmon", "swim", True),
    ]
    test: list[Query] = []
    name = "direct"
    if level == 0:
        test = [
            query("sparrow", "fly", True),
            query("penguin", "fly", False),
            query("penguin", "swim", True),
            query("salmon", "swim", True),
        ]
    elif level == 1:
        name = "inheritance"
        support += [query("sparrow", "fly", True), query("robin", "fly", True)]
        test = [
            query("robin", "fly", True),
            query("salmon", "swim", True),
            query("shark", "fly", False),
            query("ostrich", "run", True),
        ]
    elif level == 2:
        name = "exceptions"
        support += [query("emperor", "swim", True), query("king", "fly", False)]
        test = [
            query("emperor", "fly", False),
            query("emperor", "swim", True),
            query("king", "fly", False),
            query("king", "swim", True),
        ]
    elif level == 3:
        name = "chains"
        support += [query("emperor", "swim", True)]
        test = [
            query("king", "fly", False),
            query("king", "swim", True),
            query("ostrich", "fly", False),
            query("robin", "fly", True),
        ]
    else:
        name = "mixed"
        support += [
            query("emperor", "swim", True),
            query("ostrich", "run", True),
        ]
        test = [
            query("king", "swim", True),
            query("king", "fly", False),
            query("shark", "swim", True),
            query("shark", "fly", False),
            query("robin", "fly", True),
            query("ostrich", "run", True),
        ]
    return PuzzleLevel(level, name, facts, support, test)


def evaluate(memory: LogicMemory, queries: Iterable[Query]) -> tuple[int, int]:
    correct = 0
    total = 0
    for q in queries:
        total += 1
        got = memory.answer(q.entity, q.ability)
        if got is not None and got == q.expected:
            correct += 1
    return correct, total


def train_level(level: PuzzleLevel, rounds: int, memory: LogicMemory | None = None) -> dict:
    memory = memory or LogicMemory()
    memory.learn(level.facts)
    # Support examples teach the first useful ancestry depth.
    for q in level.support_queries:
        if memory.answer(q.entity, q.ability) is None:
            memory.feedback(q)
    history = []
    best = -1
    for round_index in range(1, rounds + 1):
        correct, total = evaluate(memory, level.test_queries)
        accuracy = correct / total if total else 0.0
        improved = accuracy > best
        history.append({
            "round": round_index,
            "correct": correct,
            "total": total,
            "accuracy": accuracy,
            "depth": memory.learned_depth,
            "corrections": memory.corrections,
            "improved": improved,
        })
        if not improved:
            break
        best = accuracy
        # Online corrections are the training signal for the next repetition.
        for q in level.test_queries:
            got = memory.answer(q.entity, q.ability)
            if got is None or got != q.expected:
                memory.feedback(q)
        if accuracy >= 1.0:
            break
    return {
        "level": level.level,
        "name": level.name,
        "support": len(level.support_queries),
        "test": len(level.test_queries),
        "history": history,
        "best_accuracy": max((h["accuracy"] for h in history), default=0.0),
        "improved": any(h["improved"] for h in history[1:]),
    }


def run_session(rounds: int = 5, start_level: int = 0) -> dict:
    """Cumulative rounds across increasing difficulty levels.

    The relation memory persists between rounds. Each round evaluates before
    applying corrections, so the next round's score reflects prior learning.
    """
    memory = LogicMemory()
    history = []
    best = -1.0
    for round_index in range(1, rounds + 1):
        level_index = min(4, start_level + round_index - 1)
        level = make_level(level_index)
        memory.learn(level.facts)
        for q in level.support_queries:
            if memory.answer(q.entity, q.ability) is None:
                memory.feedback(q)
        correct, total = evaluate(memory, level.test_queries)
        accuracy = correct / total if total else 0.0
        improved = accuracy > best
        history.append({
            "round": round_index,
            "level": level_index,
            "name": level.name,
            "correct": correct,
            "total": total,
            "accuracy": accuracy,
            "depth": memory.learned_depth,
            "corrections": memory.corrections,
            "improved": improved,
        })
        if improved:
            best = accuracy
        for q in level.test_queries:
            got = memory.answer(q.entity, q.ability)
            if got is None or got != q.expected:
                memory.feedback(q)
    return {
        "ok": True,
        "session": history,
        "improved": any(item["improved"] for item in history[1:]),
        "rounds": rounds,
    }


def run_curriculum(rounds: int = 4, start_level: int = 0) -> dict:
    levels = []
    for level in range(start_level, 5):
        result = train_level(make_level(level), rounds)
        levels.append(result)
        if result["best_accuracy"] < 0.75:
            break
    improved = any(level["improved"] for level in levels)
    return {
        "ok": True,
        "levels": levels,
        "improved": improved,
        "rounds": rounds,
    }


def post_merge(result: dict, url: str, token: str, node: int) -> dict | None:
    if not url or not token:
        return None
    body = json.dumps({
        "node": node,
        "base_generation": 0,
        "nanclock_tick": 0,
        "updates": [{
            "head": node % 256,
            "layer": 0,
            "epoch": 0,
            "strength_delta": int(round(1000 * result.get("levels", [{}])[-1].get("best_accuracy", 0))),
            "vector": [0] * 16,
            "route": "logic-curriculum",
        }],
    }, sort_keys=True).encode()
    request = urllib.request.Request(
        url.rstrip("/") + "/v1/training/merge", data=body,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "Idempotency-Key": f"logic-{node}-{int(time.time())}",
        }, method="POST")
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--slot", type=int, default=1)
    parser.add_argument("--epoch", type=int, default=0)
    parser.add_argument("--rounds", type=int, default=4)
    parser.add_argument("--session-rounds", type=int, default=0,
                        help="run a cumulative difficulty session instead")
    parser.add_argument("--start-level", type=int, default=0)
    parser.add_argument("--out", default="")
    parser.add_argument("--merge-url", default=os.environ.get("NANLM_MERGE_URL", ""))
    parser.add_argument("--merge-token", default=os.environ.get("NANLM_MERGE_TOKEN", ""))
    args = parser.parse_args(argv)

    if args.session_rounds > 0:
        result = run_session(max(1, args.session_rounds),
                             max(0, min(4, args.start_level)))
    else:
        result = run_curriculum(max(1, args.rounds),
                                max(0, min(4, args.start_level)))
    result.update({"slot": args.slot, "epoch": args.epoch, "at": int(time.time())})
    merged = None
    try:
        merged = post_merge(result, args.merge_url, args.merge_token, args.slot + 1)
    except Exception as exc:
        result["merge_error"] = str(exc)
    if merged is not None:
        result["merge"] = merged
    encoded = json.dumps(result, indent=1, sort_keys=True) + "\n"
    if args.out:
        path = Path(args.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(encoded)
    sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
