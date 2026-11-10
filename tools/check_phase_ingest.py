#!/usr/bin/env python3
"""Validate the raw phase-ingest artifacts and their manifest."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "state")
    manifest_path = root / "phase_vectors.json"
    if not manifest_path.exists():
        print(f"missing {manifest_path}", file=sys.stderr)
        return 1
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("schema") != "nanlm.phase-vectors/1":
        print("unexpected phase-vector schema", file=sys.stderr)
        return 1
    samples = int(manifest["samples"])
    dim = int(manifest["dim"])
    if samples <= 0 or dim <= 0:
        print("empty phase ingest", file=sys.stderr)
        return 1
    vectors = (root / "phase_vectors.bin").read_bytes()
    expected_vectors = samples * dim * 2 * 4
    if len(vectors) != expected_vectors:
        print(f"phase vectors size {len(vectors)} != {expected_vectors}", file=sys.stderr)
        return 1
    words = struct.unpack(f"<{len(vectors) // 4}i", vectors)
    nonzero = sum(value != 0 for value in words)
    if nonzero == 0:
        print("phase vectors are all zero", file=sys.stderr)
        return 1

    pipeline = manifest.get("pipeline", {})
    pipeline_samples = int(pipeline.get("samples", 0))
    pipeline_dim = int(pipeline.get("dim", 0))
    codes = (root / "phase_codes.bin").read_bytes()
    if len(codes) != pipeline_samples * 8:
        print("phase codes size mismatch", file=sys.stderr)
        return 1
    knn = (root / "phase_knn.bin").read_bytes()
    if len(knn) != pipeline_samples * 8:
        print("phase kNN size mismatch", file=sys.stderr)
        return 1
    spectral = (root / "phase_spectral.bin").read_bytes()
    if len(spectral) != 8 * 4:
        print("phase spectral size mismatch", file=sys.stderr)
        return 1
    if pipeline_dim <= 0 or pipeline_dim > 64:
        print("invalid phase pipeline dimension", file=sys.stderr)
        return 1

    print(
        "PHASE_INGEST PASS "
        f"samples={samples} dim={dim} nonzero={nonzero} "
        f"pipeline_samples={pipeline_samples} pq_codewords={pipeline.get('pq_codewords')} "
        f"knn_bank={pipeline.get('knn_bank')} pipeline_dim={pipeline_dim}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
