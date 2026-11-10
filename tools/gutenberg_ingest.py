#!/usr/bin/env python3
"""Clean Gutenberg books and build a book-disjoint ingestion manifest.

This is host-side corpus ingestion only. The training math remains in the raw
NaN16 guest.

Outputs:
  state/gutenberg_clean/<id>.txt      cleaned per-book text
  state/gutenberg_150_train.txt       training books
  state/gutenberg_150_heldout.txt     held-out books
  state/gutenberg_150_clean_corpus.txt full cleaned corpus
  state/gutenberg_150_ingest.json     split/provenance manifest
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
from pathlib import Path

START = re.compile(
    rb"\*\*\*[ \t]*(?:START|BEGIN) OF (?:THE|THIS) PROJECT GUTENBERG EBOOK.*?\*\*\*",
    re.IGNORECASE | re.DOTALL,
)
END = re.compile(
    rb"\*\*\*[ \t]*(?:END) OF (?:THE|THIS) PROJECT GUTENBERG EBOOK.*?\*\*\*",
    re.IGNORECASE | re.DOTALL,
)


def clean(raw: bytes) -> tuple[bytes, bool]:
    start = START.search(raw)
    end = END.search(raw, start.end() if start else 0)
    if start and end and end.start() > start.end():
        body = raw[start.end():end.start()]
        stripped = True
    else:
        body = raw
        stripped = False
    body = body.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    body = body.replace(b"\x00", b"")
    body = b"\n".join(line.rstrip() for line in body.split(b"\n"))
    body = body.strip(b"\n") + b"\n"
    return body, stripped


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, default=Path("state/gutenberg_150_books.json"))
    ap.add_argument("--out-dir", type=Path, default=Path("state/gutenberg_clean"))
    ap.add_argument("--train-corpus", type=Path, default=Path("state/gutenberg_150_train.txt"))
    ap.add_argument("--heldout-corpus", type=Path, default=Path("state/gutenberg_150_heldout.txt"))
    ap.add_argument("--full-corpus", type=Path, default=Path("state/gutenberg_150_clean_corpus.txt"))
    ap.add_argument("--ingest-manifest", type=Path, default=Path("state/gutenberg_150_ingest.json"))
    ap.add_argument("--train-fraction", type=float, default=0.8)
    ap.add_argument("--seed", type=int, default=99)
    args = ap.parse_args()
    raw_manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    books = list(raw_manifest["books"])
    ids = [int(book["id"]) for book in books]
    random.Random(args.seed).shuffle(ids)
    n_train = max(1, min(len(ids) - 1, int(args.train_fraction * len(ids))))
    train_ids = set(ids[:n_train])
    args.out_dir.mkdir(parents=True, exist_ok=True)
    records = []
    train_bytes = []
    heldout_bytes = []
    full_bytes = []
    for book in sorted(books, key=lambda b: int(b["id"])):
        book_id = int(book["id"])
        raw = Path(book["path"]).read_bytes()
        body, stripped = clean(raw)
        out = args.out_dir / f"{book_id}.txt"
        out.write_bytes(body)
        split = "train" if book_id in train_ids else "heldout"
        (train_bytes if split == "train" else heldout_bytes).append(body)
        full_bytes.append(body)
        records.append({
            "id": book_id,
            "title": book.get("title", ""),
            "authors": book.get("authors", []),
            "split": split,
            "raw_bytes": len(raw),
            "clean_bytes": len(body),
            "clean_sha256": hashlib.sha256(body).hexdigest(),
            "stripped_gutenberg_markers": stripped,
            "source": book.get("source", ""),
            "path": str(out),
        })
    args.train_corpus.write_bytes(b"\n".join(train_bytes))
    args.heldout_corpus.write_bytes(b"\n".join(heldout_bytes))
    args.full_corpus.write_bytes(b"\n".join(full_bytes))
    manifest = {
        "schema": "nanlm.gutenberg-ingest/1",
        "source_manifest": str(args.manifest),
        "books": len(records),
        "train_books": sum(r["split"] == "train" for r in records),
        "heldout_books": sum(r["split"] == "heldout" for r in records),
        "train_bytes": args.train_corpus.stat().st_size,
        "heldout_bytes": args.heldout_corpus.stat().st_size,
        "full_bytes": args.full_corpus.stat().st_size,
        "train_corpus": str(args.train_corpus),
        "heldout_corpus": str(args.heldout_corpus),
        "full_corpus": str(args.full_corpus),
        "train_corpus_sha256": hashlib.sha256(args.train_corpus.read_bytes()).hexdigest(),
        "heldout_corpus_sha256": hashlib.sha256(args.heldout_corpus.read_bytes()).hexdigest(),
        "split": "book-disjoint deterministic split",
        "seed": args.seed,
        "records": records,
    }
    args.ingest_manifest.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({k: manifest[k] for k in (
        "books", "train_books", "heldout_books", "train_bytes",
        "heldout_bytes", "full_bytes", "train_corpus", "heldout_corpus",
        "full_corpus", "train_corpus_sha256", "heldout_corpus_sha256")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
