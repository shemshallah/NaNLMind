#!/usr/bin/env python3
"""Download a fixed-size English Project Gutenberg corpus for native training.

The downloader is host-side corpus acquisition only. The context-memory
training math remains in the raw NaN16 guest.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import re
import urllib.request
from pathlib import Path

GUTENDEX = "https://gutendex.com/books?languages=en&sort=popular"
CACHE = "https://www.gutenberg.org/cache/epub/{id}/pg{id}.txt"
FILES = "https://www.gutenberg.org/files/{id}/{id}-0.txt"


def fetch(url: str, timeout: float = 20.0) -> bytes:
    last = None
    for _ in range(4):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "NaNLMind-corpus/1"})
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return response.read()
        except Exception as exc:
            last = exc
    raise last if last else RuntimeError(url)


def catalog(count: int) -> list[dict]:
    books = []
    url = GUTENDEX
    while len(books) < count and url:
        try:
            payload = json.loads(fetch(url))
        except Exception as exc:
            print(f"catalog_page_failed={exc}", flush=True)
            break
        for item in payload.get("results", []):
            formats = item.get("formats", {})
            text = formats.get("text/plain; charset=utf-8") or formats.get("text/plain")
            if not text:
                continue
            books.append({
                "id": int(item["id"]),
                "title": item.get("title", ""),
                "authors": [a.get("name", "") for a in item.get("authors", [])],
                "formats": text,
            })
            if len(books) >= count:
                break
        url = payload.get("next")
    return books


def download(book: dict, directory: Path) -> dict | None:
    book_id = book["id"]
    target = directory / f"{book_id}.txt"
    if target.is_file() and target.stat().st_size > 1024:
        data = target.read_bytes()
        source = "cache"
    else:
        data = b""
        source = ""
        for url in (CACHE.format(id=book_id), FILES.format(id=book_id), book["formats"]):
            try:
                data = fetch(url)
                if len(data) > 1024:
                    source = url
                    break
            except Exception:
                continue
        if len(data) <= 1024:
            return None
        target.write_bytes(data)
    return {
        **{k: v for k, v in book.items() if k != "formats"},
        "source": source,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "path": str(target),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=150)
    ap.add_argument("--catalog-files", nargs="*", type=Path, default=[])
    ap.add_argument("--books-dir", type=Path, default=Path("state/gutenberg_books"))
    ap.add_argument("--manifest", type=Path, default=Path("state/gutenberg_books.json"))
    ap.add_argument("--corpus", type=Path, default=Path("state/gutenberg_150_corpus.txt"))
    args = ap.parse_args()
    args.books_dir.mkdir(parents=True, exist_ok=True)
    if args.catalog_files:
        books = []
        seen = set()
        for path in args.catalog_files:
            payload = json.loads(path.read_text(encoding="utf-8"))
            for item in payload.get("results", []):
                formats = item.get("formats", {})
                text = formats.get("text/plain; charset=utf-8") or formats.get("text/plain")
                if not text or int(item["id"]) in seen:
                    continue
                seen.add(int(item["id"]))
                books.append({
                    "id": int(item["id"]),
                    "title": item.get("title", ""),
                    "authors": [a.get("name", "") for a in item.get("authors", [])],
                    "formats": text,
                })
                if len(books) >= args.count:
                    break
            if len(books) >= args.count:
                break
    else:
        books = catalog(args.count)
    print(f"catalog={len(books)}")
    records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(download, book, args.books_dir): book for book in books}
        for future in concurrent.futures.as_completed(futures):
            try:
                record = future.result()
            except Exception as exc:
                book = futures[future]
                print(f"book={book['id']} download_failed={exc}", flush=True)
                continue
            if record:
                records.append(record)
                print(f"book={record['id']} bytes={record['bytes']} {record['title'][:60]}", flush=True)
    records.sort(key=lambda r: r["id"])
    args.manifest.write_text(json.dumps({
        "schema": "nanlm.gutenberg-books/1",
        "count": len(records),
        "books": records,
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with args.corpus.open("wb") as out:
        for record in records:
            data = Path(record["path"]).read_bytes()
            out.write(data)
            if not data.endswith(b"\n"):
                out.write(b"\n")
    print(f"books={len(records)} corpus={args.corpus} bytes={args.corpus.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
