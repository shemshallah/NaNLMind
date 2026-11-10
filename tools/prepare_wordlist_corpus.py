#!/usr/bin/env python3
"""Convert recursive wordlist bundles into the canonical corpus line format.

The training stack consumes one word per line. Source bundles under
NaNROUTER/corpora/wordlists contain plain text, CSV/TSV, JSON, JSONL and gzip
files; this tool normalizes them without loading the whole tree into memory.
No vector, PQ, matrix or checkpoint arithmetic is performed here.
"""
from __future__ import annotations

import argparse
import csv
import fnmatch
import gzip
import hashlib
import io
import json
import os
import sys
from pathlib import Path
from typing import Iterable, Iterator


SKIP_NAMES = {
    "readme.md", "sources.json", "manifest.json", "sha256sums",
    "sha256sums.parts", ".gitignore",
}


def source_files(root: Path, includes: list[str],
                  excludes: list[str]) -> Iterator[Path]:
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = str(path.relative_to(root))
        if any(part.startswith(".") for part in path.relative_to(root).parts):
            continue
        if path.name.lower() in SKIP_NAMES:
            continue
        if includes and not any(fnmatch.fnmatch(relative, pattern) or
                                fnmatch.fnmatch(path.name, pattern)
                                for pattern in includes):
            continue
        if any(fnmatch.fnmatch(relative, pattern) or
               fnmatch.fnmatch(path.name, pattern) for pattern in excludes):
            continue
        yield path


def normalized_word(value: str, lower: bool) -> str | None:
    value = value.strip().strip("\ufeff")
    if not value:
        return None
    # Wordlists frequently append a frequency/count column. The first token is
    # the lexical item; phrases are not split into separate corpus words here.
    parts = value.split()
    token = parts[0]
    if token.isdigit() and len(parts) > 1:
        token = parts[1]
    if lower:
        token = token.lower()
    if not token or len(token.encode("utf-8", "ignore")) > 64:
        return None
    if any(ord(ch) < 32 or ch.isspace() for ch in token):
        return None
    return token


def json_words(value: object) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from json_words(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from json_words(item)


def text_words(handle: io.TextIOBase, csv_mode: str | None,
               lower: bool) -> Iterator[str]:
    if csv_mode:
        reader = csv.reader(handle, delimiter="\t" if csv_mode == "tsv" else ",")
        for row in reader:
            if not row:
                continue
            lowered = [cell.strip().lower() for cell in row]
            if any(cell in {"word", "words", "password", "term", "token",
                            "rank", "frequency", "count"}
                   for cell in lowered):
                continue
            for cell in row:
                word = normalized_word(cell, lower)
                if word and not word.isdigit():
                    yield word
                    break
        return
    for line in handle:
        word = normalized_word(line, lower)
        if word:
            yield word


def file_words(path: Path, lower: bool) -> Iterator[str]:
    raw = path.open("rb")
    probe = raw.read(4096)
    raw.seek(0)
    magic = probe[:2]
    if magic != b"\x1f\x8b" and b"\x00" in probe:
        raw.close()
        return
    try:
        if magic == b"\x1f\x8b" or path.suffix.lower() == ".gz":
            text = gzip.open(raw, "rt", encoding="utf-8", errors="ignore")
        else:
            text = io.TextIOWrapper(raw, encoding="utf-8", errors="ignore")
        try:
            suffix = path.suffix.lower()
            if suffix == ".json":
                payload = json.load(text)
                for value in json_words(payload):
                    yield value
                return
            if suffix == ".jsonl":
                for line in text:
                    try:
                        payload = json.loads(line)
                    except json.JSONDecodeError:
                        yield line
                        continue
                    yield from json_words(payload)
                return
            csv_mode = "csv" if suffix == ".csv" else "tsv" if suffix == ".tsv" else None
            yield from text_words(text, csv_mode, lower)
        finally:
            text.close()
    finally:
        if not raw.closed:
            raw.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path,
                        default=Path("../NaNROUTER/corpora/wordlists"),
                        help="recursive wordlist bundle root")
    parser.add_argument("--out", type=Path, default=Path("state/wordlists.corpus.txt"))
    parser.add_argument("--manifest", type=Path, default=None)
    parser.add_argument("--max-words", type=int, default=0,
                        help="0 means unlimited")
    parser.add_argument("--min-length", type=int, default=1)
    parser.add_argument("--lower", action="store_true",
                        help="lowercase every normalized word")
    parser.add_argument("--dedupe", action="store_true",
                        help="keep first occurrence only (may use memory)")
    parser.add_argument("--allow-empty", action="store_true",
                        help="write an empty corpus instead of failing")
    parser.add_argument("--include", action="append", default=[],
                        help="glob to include (repeatable; matching file name or relative path)")
    parser.add_argument("--exclude", action="append", default=[],
                        help="glob to exclude (repeatable)")
    args = parser.parse_args()
    if not args.root.is_dir():
        print(f"wordlist root is not a directory: {args.root}", file=sys.stderr)
        return 2
    if args.min_length < 1 or args.min_length > 64:
        print("min-length must be 1..64", file=sys.stderr)
        return 2
    args.out.parent.mkdir(parents=True, exist_ok=True)
    manifest_path = args.manifest or args.out.with_suffix(args.out.suffix + ".json")
    digest = hashlib.sha256()
    seen: set[str] = set()
    total = 0
    files = 0
    sources: list[dict[str, object]] = []
    with args.out.open("w", encoding="utf-8", newline="\n") as out:
        for path in source_files(args.root, args.include, args.exclude):
            count = 0
            try:
                for raw_word in file_words(path, args.lower):
                    word = normalized_word(raw_word, args.lower)
                    if word is None or len(word) < args.min_length:
                        continue
                    if args.dedupe:
                        if word in seen:
                            continue
                        seen.add(word)
                    line = word + "\n"
                    encoded = line.encode("utf-8")
                    out.write(line)
                    digest.update(encoded)
                    count += 1
                    total += 1
                    if args.max_words and total >= args.max_words:
                        break
            except (OSError, UnicodeError, csv.Error, json.JSONDecodeError) as exc:
                print(f"skip {path}: {exc}", file=sys.stderr)
                continue
            if count:
                files += 1
                sources.append({"path": str(path.relative_to(args.root)),
                                "words": count})
            if args.max_words and total >= args.max_words:
                break
    manifest = {
        "schema": "nanlm.wordlist-corpus/1",
        "root": str(args.root),
        "output": str(args.out),
        "source_files": files,
        "words": total,
        "sha256": digest.hexdigest(),
        "lowercase": args.lower,
        "dedupe": args.dedupe,
        "min_length": args.min_length,
        "sources": sources,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    if total == 0 and not args.allow_empty:
        print("WORDLIST_CORPUS FAIL no lexical items found", file=sys.stderr)
        return 1
    print(f"WORDLIST_CORPUS PASS words={total} files={files} "
          f"sha256={manifest['sha256']} output={args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
