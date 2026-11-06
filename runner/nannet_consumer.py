#!/usr/bin/env python3
"""Drain validated NANNET text datasets into the canonical bootstrap head bank.

The first bridge is deliberately explicit: UTF-8 bytes become deterministic
16-dimensional trigram sketches on 256 local heads. NANNET's idempotent merge
receipt is the commit boundary; staging is released only after that receipt.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from codecs import getincrementaldecoder

MAX_CHUNK = int(os.environ.get("NANLM_CHUNK_BYTES", str(8 * 1024 * 1024)))
HEADS = 256
DIMS = 16
NODE_POINT = 1
FEATURE_SCHEMA = "utf8-byte-trigram-16d-v1"


def add_features(data: bytes, carry: bytes, counts: list[list[int]]) -> bytes:
    joined = carry + data
    try:
        import numpy as np
        values = np.frombuffer(joined, dtype=np.uint8)
        if len(values) >= 3:
            heads = values[:-2].astype(np.int32)
            middle = values[1:-1].astype(np.uint16)
            tail = values[2:].astype(np.uint16)
            dims = (((middle * 17) ^ tail) & 15).astype(np.int32)
            histogram = np.bincount(heads * DIMS + dims, minlength=HEADS * DIMS)
            for index, value in enumerate(histogram):
                if value:
                    counts[index // DIMS][index % DIMS] += int(value)
    except ImportError:
        for i in range(2, len(joined)):
            a, b, c = joined[i - 2], joined[i - 1], joined[i]
            counts[a][((b * 17) ^ c) & 15] += 1
    return joined[-2:]


def make_updates(counts: list[list[int]], tick: int) -> list[dict]:
    updates = []
    for head, row in enumerate(counts):
        total = sum(row)
        if not total:
            continue
        vector = [min(32767, (value * 32767) // total) for value in row]
        updates.append({
            "head": head,
            "layer": 0,
            "epoch": tick,
            "vector": vector,
            "strength_delta": min(32767, total),
            "route": {"kind": "corpus-trigram", "schema": FEATURE_SCHEMA},
        })
    return updates


def request(url: str, token: str, method: str = "GET", body: dict | None = None,
            idempotency: str | None = None):
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
        headers["Content-Type"] = "application/json"
    if idempotency:
        headers["Idempotency-Key"] = idempotency
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            raw = response.read(1_048_577)
            if len(raw) > 1_048_576:
                raise RuntimeError("NANNET JSON response exceeded limit")
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read(1_048_577)
        try:
            detail = json.loads(raw) if raw else {}
        except ValueError:
            detail = {"error": "invalid_error_response"}
        if exc.code == 404:
            return 404, detail
        raise RuntimeError("NANNET HTTP %d: %s" % (exc.code, detail.get("error", "request_failed")))


def fetch_chunk(base: str, token: str, dataset_id: str, index: int) -> tuple[bytes, str]:
    url = base + "/internal/datasets/%s/chunks/%d" % (dataset_id, index)
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token},
                                 method="GET")
    with urllib.request.urlopen(req, timeout=120) as response:
        data = response.read(MAX_CHUNK + 1)
        if len(data) > MAX_CHUNK:
            raise RuntimeError("chunk exceeds configured limit")
        expected = response.headers.get("X-Chunk-SHA256", "")
    actual = hashlib.sha256(data).hexdigest()
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or actual != expected:
        raise RuntimeError("chunk %d digest mismatch" % index)
    return data, actual


class TextCorpusFold:
    """Streaming UTF-8 line codec for plain text and the N16TXT/1 envelope."""
    def __init__(self, format_name: str):
        if format_name not in ("plain-text/utf8", "N16TXT/1"):
            raise RuntimeError("unsupported corpus format: " + format_name)
        self.format = format_name
        self.pending = bytearray()
        self.first_line = True
        self.header_seen = False
        self.counts = [[0] * DIMS for _ in range(HEADS)]
        self.carry = b""
        self.record_count = 0
        self.canonical_bytes = 0

    def _line(self, raw: bytes) -> None:
        if raw.endswith(b"\r"):
            raw = raw[:-1]
        if b"\r" in raw:
            raise RuntimeError("bare CR is not a canonical line ending")
        if self.first_line:
            self.first_line = False
            if raw == b"N16TXT/1":
                self.header_seen = True
                return
            if self.format == "N16TXT/1":
                raise RuntimeError("N16TXT/1 header is missing or altered")
        if not raw:
            return
        if len(raw) > 4096:
            raise RuntimeError("corpus record exceeds 4096 UTF-8 bytes")
        try:
            text = raw.decode("utf-8", "strict")
        except UnicodeDecodeError as exc:
            raise RuntimeError("invalid UTF-8 record") from exc
        for char in text:
            code = ord(char)
            if (code < 32 and code != 9) or 0x7f <= code <= 0x9f:
                raise RuntimeError("forbidden control character")
            if 0xfdd0 <= code <= 0xfdef or (code & 0xffff) in (0xfffe, 0xffff):
                raise RuntimeError("Unicode noncharacter rejected")
        self.canonical_bytes += 4 + len(raw)
        if self.format == "N16TXT/1" and self.canonical_bytes > 1_048_576:
            raise RuntimeError("N16TXT/1 canonical corpus exceeds 1 MiB")
        framed = len(raw).to_bytes(4, "little") + raw
        self.carry = add_features(framed, self.carry, self.counts)
        self.record_count += 1

    def feed(self, chunk: bytes) -> None:
        self.pending.extend(chunk)
        while True:
            try:
                index = self.pending.index(10)
            except ValueError:
                break
            line = bytes(self.pending[:index])
            del self.pending[:index + 1]
            self._line(line)
        if len(self.pending) > 4097:
            raise RuntimeError("corpus record exceeds 4096 UTF-8 bytes")

    def finish(self) -> None:
        if self.pending:
            self._line(bytes(self.pending))
            self.pending.clear()
        if self.format == "N16TXT/1" and not self.header_seen:
            raise RuntimeError("N16TXT/1 header is required")
        if self.record_count == 0:
            raise RuntimeError("corpus contains no non-empty records")


def fold_dataset(base: str, runner_token: str, dataset: dict) -> tuple[list[dict], str]:
    dataset_id = dataset["dataset_id"]
    metadata = dataset.get("metadata") or {}
    if metadata.get("encoding", "").lower().replace("_", "-") not in ("utf-8", "utf8"):
        raise RuntimeError("%s is not declared UTF-8" % dataset_id)
    if not metadata.get("license") or not metadata.get("provenance"):
        raise RuntimeError("%s lacks license/provenance metadata" % dataset_id)
    parser = TextCorpusFold(metadata.get("format", "plain-text/utf8"))
    count = int(dataset["expected_chunks"])
    if count < 1 or count > 100000:
        raise RuntimeError("invalid expected chunk count")
    expected_total = int(dataset["total_bytes"])
    expected_digest = dataset["dataset_sha256"]
    if not re.fullmatch(r"[a-f0-9]{64}", expected_digest or ""):
        raise RuntimeError("invalid dataset digest")
    digest = hashlib.sha256()
    total = 0
    for index in range(count):
        chunk, _ = fetch_chunk(base, runner_token, dataset_id, index)
        total += len(chunk)
        digest.update(chunk)
        parser.feed(chunk)
    parser.finish()
    actual = digest.hexdigest()
    if total != expected_total or actual != expected_digest:
        raise RuntimeError("%s dataset digest/size mismatch" % dataset_id)
    return make_updates(parser.counts, 1), actual


def consume_one(base: str, runner_token: str, bootstrap_token: str,
                dataset: dict) -> dict:
    dataset_id = dataset["dataset_id"]
    digest = dataset["dataset_sha256"]
    idem = hashlib.sha256((dataset_id + "\0" + digest).encode()).hexdigest()
    status, receipt = request(base + "/v1/training/receipts/" + idem, bootstrap_token)
    if status == 404:
        updates, verified_digest = fold_dataset(base, runner_token, dataset)
        _, state = request(base + "/v1/training/state/%d" % NODE_POINT, bootstrap_token)
        tick = int(state["nanclock_tick"]) + 1
        for item in updates:
            item["epoch"] = tick
        payload = {
            "source_endpoint": "bootstrap",
            "node": NODE_POINT,
            "base_generation": int(state["generation"]),
            "nanclock_tick": tick,
            "dataset_id": dataset_id,
            "dataset_sha256": verified_digest,
            "feature_schema": FEATURE_SCHEMA,
            "updates": updates,
        }
        _, receipt = request(base + "/v1/training/merge", bootstrap_token,
                             "POST", payload, idem)
    if receipt.get("dataset_sha256") not in (None, digest):
        raise RuntimeError("existing merge receipt belongs to a different dataset")
    generation = int(receipt.get("generation", 0))
    if generation < 1:
        raise RuntimeError("canonical merge returned no generation")
    _, committed = request(
        base + "/internal/datasets/%s/commit" % dataset_id,
        runner_token, "POST",
        {"generation": generation, "dataset_sha256": digest},
    )
    return {"dataset_id": dataset_id, "generation": generation,
            "dataset_sha256": digest, "merge": receipt, "staging": committed}


def main() -> int:
    base = os.environ.get("NANNET_URL", "").rstrip("/")
    runner_token = os.environ.get("NANLM_RUNNER_TOKEN", "")
    bootstrap_token = os.environ.get("NANLM_BOOTSTRAP_TOKEN", "")
    if not base.startswith("https://") or len(runner_token) < 32 or len(bootstrap_token) < 32:
        print("NANNET_URL (HTTPS), NANLM_RUNNER_TOKEN and NANLM_BOOTSTRAP_TOKEN are required",
              file=sys.stderr)
        return 2
    _, result = request(base + "/internal/datasets/validated", runner_token)
    datasets = result.get("datasets", [])
    outcomes = []
    for dataset in datasets:
        outcomes.append(consume_one(base, runner_token, bootstrap_token, dataset))
    print(json.dumps({"processed": len(outcomes), "outcomes": outcomes}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
