#!/usr/bin/env python3
"""Deterministic corpus builder for the NaNLMind demo training pipeline.

Stages are generated in memory and can also be written as JSONL:

  inverses_boolean -> deep_logic -> common_words -> repetitive_words
  -> word_choice -> sentences

The corpus is deliberately synthetic and deterministic so a runner can replay a
stage exactly.
"""
from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


COMMON_WORDS = [
    "the", "and", "for", "are", "but", "not", "you", "all", "any", "can",
    "her", "was", "one", "our", "out", "day", "get", "has", "him", "his",
    "how", "man", "new", "now", "old", "see", "two", "way", "who", "boy",
    "did", "its", "let", "put", "say", "she", "too", "use", "that", "with",
    "have", "this", "will", "your", "from", "they", "know", "want", "been",
    "good", "much", "some", "time", "very", "when", "come", "here", "just",
    "like", "long", "make", "many", "more", "only", "over", "such", "take",
    "than", "them", "well", "were", "what", "with", "work", "would", "after",
    "first", "never", "other", "right", "think", "where", "being", "every",
    "great", "might", "shall", "still", "those", "under", "while", "world",
]

SENTENCES = [
    "the quick brown fox jumps over the lazy dog",
    "a small bird can fly over the green tree",
    "the penguin cannot fly but it can swim",
    "logic gates combine simple truth values",
    "the runner trains a head and writes the result",
    "a clock orders each training step in time",
    "words carry meaning beyond their next letter",
    "the model chooses the word that fits the sentence",
    "a child reads a simple story and learns a word",
    "the same fact can be repeated in many forms",
]


@dataclass(frozen=True)
class StageSpec:
    name: str
    kind: str
    samples: int


STAGES = [
    StageSpec("inverses_boolean", "boolean", 4096),
    StageSpec("deep_logic", "logic", 2048),
    StageSpec("common_words", "words", 2048),
    StageSpec("repetitive_words", "words", 2048),
    StageSpec("word_choice", "choice", 2048),
    StageSpec("sentences", "sentence", 2048),
]


def _bool_sample(index: int, rng: random.Random) -> dict:
    # All 16 Boolean functions, plus NOT/AND/OR and inverse-expression cases.
    op = index & 15
    a = rng.randrange(2)
    b = rng.randrange(2)
    truth = (op >> (2 * a + b)) & 1
    expression = f"f{op}({a},{b})"
    inverse = f"not({expression})"
    return {
        "kind": "boolean",
        "op": op,
        "a": a,
        "b": b,
        "target": truth,
        "expression": expression,
        "inverse": inverse,
        "inverse_target": 1 - truth,
    }


def _deep_logic_sample(index: int, rng: random.Random) -> dict:
    kinds = ["bird", "fish", "animal", "machine", "runner", "clock"]
    abilities = ["fly", "swim", "run", "compute", "tick"]
    kind = kinds[index % len(kinds)]
    entity = f"{kind}_{index:05d}"
    ability = abilities[(index // len(kinds)) % len(abilities)]
    depth = 1 + (index % 4)
    chain = [entity] + [f"{kind}_{level}" for level in range(depth)] + [kind]
    negation = (index % 7) == 0
    facts = [f"{chain[i]} isa {chain[i + 1]}" for i in range(len(chain) - 1)]
    facts.append(f"{kind} can {ability}")
    if negation:
        facts.append(f"{entity} cannot {ability}")
    expected = not negation
    return {
        "kind": "logic",
        "entity": entity,
        "ability": ability,
        "depth": depth,
        "facts": facts,
        "query": f"can {entity} {ability}",
        "answer": expected,
    }


def _word_sample(index: int, rng: random.Random, repetitive: bool) -> dict:
    if repetitive:
        word = COMMON_WORDS[index % 12]
        context = " ".join([word] * (2 + index % 3))
    else:
        sentence = SENTENCES[index % len(SENTENCES)].split()
        position = 1 + (index // len(SENTENCES)) % max(1, len(sentence) - 1)
        context = " ".join(sentence[:position])
        word = sentence[position]
    return {
        "kind": "word",
        "context": context,
        "word": word,
        "repeat": repetitive,
    }


def _choice_sample(index: int, rng: random.Random) -> dict:
    sentence = SENTENCES[index % len(SENTENCES)]
    words = sentence.split()
    position = 1 + (index % max(1, len(words) - 2))
    answer = words[position]
    distractors = [
        COMMON_WORDS[(index + 7) % len(COMMON_WORDS)],
        COMMON_WORDS[(index + 19) % len(COMMON_WORDS)],
    ]
    options = [answer] + [d for d in distractors if d != answer]
    while len(options) < 3:
        options.append(COMMON_WORDS[(index + len(options) + 31) % len(COMMON_WORDS)])
    rng.shuffle(options)
    return {
        "kind": "choice",
        "context": " ".join(words[:position] + ["____"] + words[position + 1:]),
        "options": options,
        "answer": answer,
    }


def _sentence_sample(index: int, rng: random.Random) -> dict:
    sentence = SENTENCES[index % len(SENTENCES)]
    words = sentence.split()
    cut = 1 + (index // len(SENTENCES)) % max(1, len(words) - 1)
    prefix = " ".join(words[:cut])
    answer = words[cut]
    options = [answer, COMMON_WORDS[(index + 5) % len(COMMON_WORDS)],
               COMMON_WORDS[(index + 11) % len(COMMON_WORDS)]]
    options = list(dict.fromkeys(options))
    while len(options) < 3:
        options.append(COMMON_WORDS[(index + len(options) + 23) % len(COMMON_WORDS)])
    return {
        "kind": "sentence",
        "prefix": prefix,
        "options": options,
        "answer": answer,
    }


def build_stage(spec: StageSpec, seed: int = 0xD3E3) -> list[dict]:
    rng = random.Random(seed + sum(ord(c) for c in spec.name))
    out = []
    for index in range(spec.samples):
        if spec.kind == "boolean":
            out.append(_bool_sample(index, rng))
        elif spec.kind == "logic":
            out.append(_deep_logic_sample(index, rng))
        elif spec.kind == "words":
            out.append(_word_sample(index, rng, spec.name == "repetitive_words"))
        elif spec.kind == "choice":
            out.append(_choice_sample(index, rng))
        elif spec.kind == "sentence":
            out.append(_sentence_sample(index, rng))
    return out


def write_stage(spec: StageSpec, directory: Path, seed: int = 0xD3E3) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{spec.name}.jsonl"
    with path.open("w") as stream:
        for sample in build_stage(spec, seed):
            stream.write(json.dumps(sample, sort_keys=True) + "\n")
    return path


def render_line(sample: dict) -> str:
    kind = sample["kind"]
    if kind == "boolean":
        value = "true" if sample["target"] else "false"
        inverse = "true" if sample["inverse_target"] else "false"
        return f"{sample['expression']} is {value}. {sample['inverse']} is {inverse}."
    if kind == "logic":
        answer = "yes" if sample["answer"] else "no"
        return " ".join(sample["facts"]) + f" question: {sample['query']}? answer: {answer}."
    if kind == "word":
        return f"{sample['context']} {sample['word']}."
    if kind == "choice":
        return f"{sample['context']} choose: {' / '.join(sample['options'])} answer: {sample['answer']}."
    if kind == "sentence":
        return f"{sample['prefix']} next: {' / '.join(sample['options'])} answer: {sample['answer']}."
    return ""


def build_n16txt(specs: Iterable[StageSpec] = STAGES, seed: int = 0xD3E3,
                 max_bytes: int = 1_000_000) -> bytes:
    lines: list[bytes] = []
    seen: set[str] = set()
    size = len(b"N16TXT/1\n")
    for spec in specs:
        for sample in build_stage(spec, seed):
            line = render_line(sample)
            if not line or line in seen:
                continue
            encoded = line.encode("utf-8")
            if len(encoded) > 4096 or size + len(encoded) + 1 > max_bytes:
                if size + len(encoded) + 1 > max_bytes:
                    break
                continue
            seen.add(line)
            lines.append(encoded + b"\n")
            size += len(encoded) + 1
    return b"N16TXT/1\n" + b"".join(lines)


def write_n16txt(path: Path, specs: Iterable[StageSpec] = STAGES,
                  seed: int = 0xD3E3, max_bytes: int = 1_000_000) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = build_n16txt(specs, seed, max_bytes)
    path.write_bytes(data)
    path.with_suffix(".native.txt").write_bytes(
        b"".join(line + b"\n" for line in data.splitlines()[1:]))
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="data/training")
    parser.add_argument("--seed", type=int, default=0xD3E3)
    parser.add_argument("--stage", default="")
    parser.add_argument("--n16txt", default="")
    parser.add_argument("--max-bytes", type=int, default=1000000)
    args = parser.parse_args(argv)
    specs = [s for s in STAGES if not args.stage or s.name == args.stage]
    for spec in specs:
        path = write_stage(spec, Path(args.out), args.seed)
        print(f"{spec.name}: {spec.samples} samples -> {path}")
    if args.n16txt:
        path = write_n16txt(Path(args.n16txt), specs, args.seed, args.max_bytes)
        print(f"n16txt -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
