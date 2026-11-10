#!/usr/bin/env python3
"""Smoke-test wordlist normalization and short-word phase intake."""
from __future__ import annotations

import gzip
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="nanlm-wordlist-") as tmp:
        src = Path(tmp) / "wordlists"
        (src / "nested").mkdir(parents=True)
        (src / "plain.txt").write_text("apple\nbanana\ncat\n")
        (src / "nested" / "ranked.csv").write_text(
            "rank,word\n1,dog\n2,eagle\n", encoding="utf-8")
        (src / "list.json").write_text('["fox", "grape"]\n', encoding="utf-8")
        (src / "records.jsonl").write_text(
            '{"word":"house"}\n{"word":"igloo"}\n', encoding="utf-8")
        with gzip.open(src / "zipped.txt.gz", "wt", encoding="utf-8") as out:
            out.write("1 zebra\n2 yak\n")
        corpus = Path(tmp) / "wordlists.corpus.txt"
        manifest = Path(tmp) / "wordlists.corpus.json"
        subprocess.run(
            [sys.executable, str(root / "tools" / "prepare_wordlist_corpus.py"),
             "--root", str(src), "--out", str(corpus),
             "--manifest", str(manifest), "--lower", "--dedupe"],
            check=True, cwd=root)
        words = corpus.read_text().splitlines()
        expected = {"apple", "banana", "cat", "dog", "eagle", "fox", "grape",
                    "house", "igloo", "zebra", "yak"}
        if set(words) != expected:
            print(f"unexpected words: {words}", file=sys.stderr)
            return 1
        data = json.loads(manifest.read_text())
        if int(data["words"]) != len(words) or int(data["source_files"]) < 5:
            print("wordlist manifest mismatch", file=sys.stderr)
            return 1
        output = Path(tmp) / "phase"
        subprocess.run(
            [str(root / "build" / "nanlm-universal"), "phase-ingest",
             str(corpus), "0", "8", "32", "100", str(output)],
            check=True, cwd=root, stdout=subprocess.DEVNULL)
        if (output.with_suffix(".bin")).stat().st_size == 0:
            print("short-word phase ingest produced no vectors", file=sys.stderr)
            return 1
    print("WORDLIST_INTAKE PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
