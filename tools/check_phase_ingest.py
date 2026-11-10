#!/usr/bin/env python3
"""Validate the raw phase-ingest artifacts and their manifest."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def main() -> int:
    prefix = Path(sys.argv[1] if len(sys.argv) > 1 else "state/phase_vectors")
    manifest_path = prefix.with_suffix(".json")
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
    vectors = prefix.with_suffix(".bin").read_bytes()
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
    if pipeline_dim <= 0 or pipeline_dim > 128:
        print("invalid phase pipeline dimension", file=sys.stderr)
        return 1

    codebook = Path(str(prefix) + ".codebook.bin").read_bytes()
    if len(codebook) != int(pipeline.get("pq_codewords", 0)) * pipeline_dim * 4:
        print("phase codebook size mismatch", file=sys.stderr)
        return 1
    codes = Path(str(prefix) + ".codes.bin").read_bytes()
    if len(codes) != pipeline_samples * 8:
        print("phase codes size mismatch", file=sys.stderr)
        return 1
    residuals = Path(str(prefix) + ".residuals.bin").read_bytes()
    if len(residuals) != pipeline_samples * pipeline_dim * 4:
        print("phase residual size mismatch", file=sys.stderr)
        return 1
    knn = Path(str(prefix) + ".knn.bin").read_bytes()
    if len(knn) != pipeline_samples * 8:
        print("phase kNN size mismatch", file=sys.stderr)
        return 1
    spectral = Path(str(prefix) + ".spectral.bin").read_bytes()
    if len(spectral) != 8 * 4:
        print("phase spectral size mismatch", file=sys.stderr)
        return 1

    matrix_path = Path(str(prefix) + ".matrix.bin")
    if not matrix_path.exists():
        print(f"missing {matrix_path}", file=sys.stderr)
        return 1
    matrix = matrix_path.read_bytes()
    if len(matrix) != 32640 * 4:
        print("vector matrix size mismatch", file=sys.stderr)
        return 1
    cells = struct.unpack("<32640i", matrix)
    if int(pipeline.get("matrix_updates", 0)) > 0 and not any(cells):
        print("vector matrix has updates but is empty", file=sys.stderr)
        return 1

    triads = Path(str(prefix) + ".triads.bin").read_bytes()
    if len(triads) != 255:
        print("vector triad size mismatch", file=sys.stderr)
        return 1
    hot_heads = int(pipeline.get("hot_heads", 0))
    hot_triads = int(pipeline.get("hot_triads", 0))
    if hot_triads != hot_heads // 3:
        print("vector hot-triad count mismatch", file=sys.stderr)
        return 1
    field_hot = bool(pipeline.get("field_hot", False))
    if field_hot != (hot_triads >= 43):
        print("vector field gate mismatch", file=sys.stderr)
        return 1

    print(
        "PHASE_INGEST PASS "
        f"samples={samples} dim={dim} nonzero={nonzero} "
        f"pipeline_samples={pipeline_samples} pq_codewords={pipeline.get('pq_codewords')} "
        f"knn_bank={pipeline.get('knn_bank')} pipeline_dim={pipeline_dim} "
        f"matrix_updates={pipeline.get('matrix_updates')} "
        f"probe_head={pipeline.get('probe_head')} "
        f"hot_heads={hot_heads} hot_triads={hot_triads} "
        f"field_hot={str(field_hot).lower()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
