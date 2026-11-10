#!/usr/bin/env python3
"""Extract every WordNet 3.1 synset gloss into one byte corpus.

Host I/O only: unzip/decode the archive and write newline-delimited UTF-8
glosses. No model arithmetic is performed here.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

FILES = ("data.noun", "data.verb", "data.adj", "data.adv")


def extract(archive: Path) -> tuple[bytes, dict]:
    lines: list[bytes] = []
    files = {}
    with zipfile.ZipFile(archive) as zf:
        names = {name.rsplit("/", 1)[-1]: name for name in zf.namelist()}
        for base in FILES:
            name = names.get(base)
            if name is None:
                continue
            raw = zf.read(name)
            files[base] = hashlib.sha256(raw).hexdigest()
            for line in raw.splitlines():
                if b"|" not in line:
                    continue
                gloss = line.split(b"|", 1)[1].strip()
                if gloss:
                    lines.append(gloss)
    data = b"\n".join(lines) + b"\n"
    return data, {
        "schema": "nanlm.wordnet-corpus/1",
        "archive": str(archive),
        "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        "files": files,
        "synsets": len(lines),
        "bytes": len(data),
        "corpus_sha256": hashlib.sha256(data).hexdigest(),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--archive", type=Path,
                    default=Path("/storage/emulated/0/Download/NaNLMind/wn3.1.dict.zip"))
    ap.add_argument("--out", type=Path, default=Path("state/wordnet_corpus.txt"))
    ap.add_argument("--manifest", type=Path, default=Path("state/wordnet_corpus.json"))
    args = ap.parse_args()
    data, manifest = extract(args.archive)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    args.manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8")
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
