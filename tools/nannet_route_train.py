#!/usr/bin/env python3
"""Resolve a NANNET training-route manifest to a local raw-kernel trainer.

Routing is host/network control-plane work. The model arithmetic remains in
the NaN16 guest. HW4/HW5 are job labels here, not instantiated HW nodes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "spec" / "nannet_training_routes.v1.json"
OBJECTS = ROOT / "spec" / "nannet_corpus_objects.v1.json"


def load_routes(path: Path = MANIFEST) -> dict:
    doc = json.loads(path.read_text(encoding="utf-8"))
    if doc.get("schema") != "nanlm.nannet.training-routes/1":
        raise ValueError("unsupported NANNET training-route schema")
    if doc.get("canonical_universe") != "HW0::BS0":
        raise ValueError("route manifest must keep the canonical HW0::BS0 universe")
    return doc


def route_receipt(route: str, *, execute: bool = False,
                  max_lines: int = 0) -> dict:
    doc = load_routes()
    spec = doc["routes"].get(route)
    if spec is None:
        raise ValueError("unknown training route: " + route)
    corpus = ROOT / spec["corpus"]
    digest = hashlib.sha256(corpus.read_bytes()).hexdigest() if corpus.is_file() else ""
    object_manifest = json.loads(OBJECTS.read_text(encoding="utf-8"))
    object_entry = object_manifest["routes"][route]
    object_path = ROOT / object_entry["object_file"]
    object_row = json.loads(object_path.read_text(encoding="utf-8"))
    receipt = {
        "schema": "nanlm.nannet.training-receipt/1",
        "route": route,
        "route_uri": spec["route"],
        "route_id": spec["route_id"],
        "job": spec["job"],
        "canonical_universe": doc["canonical_universe"],
        "ring_route": doc["ring_route"],
        "node_instantiated": False,
        "route_object": {
            "kind": spec["object_kind"],
            "id": spec["object_id"],
            "file": spec["object_file"],
            "matrix_pairs": spec["matrix_pairs"],
            "matrix_sha256": object_row["matrix_sha256"],
            "nonzero_pairs": object_row["nonzero_pairs"],
        },
        "trainer": spec["trainer"],
        "corpus": str(corpus.relative_to(ROOT)),
        "eval_corpus": spec.get("eval_corpus", ""),
        "corpus_sha256": digest,
        "checkpoint": spec["checkpoint"],
        "epochs": spec["epochs"],
        "executed": False,
    }
    if execute:
        cmd = [
            str(ROOT / "build" / "nanlm-universal"),
            spec["trainer"], str(corpus), str(max_lines), str(spec["epochs"]),
            "100000", "11456", "4", "0.1", "1", "1.0", "none", "8192",
            "load=" + spec["checkpoint"],
            "save=" + spec["checkpoint"],
        ]
        if spec.get("eval_corpus"):
            cmd.append("eval=" + spec["eval_corpus"])
        subprocess.run(cmd, cwd=ROOT, check=True)
        receipt["executed"] = True
    receipt["receipt_digest"] = hashlib.sha256(
        json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    return receipt


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("route", choices=["HW4", "HW5"])
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--max-lines", type=int, default=0)
    args = ap.parse_args()
    print(json.dumps(route_receipt(args.route, execute=args.execute,
                                  max_lines=args.max_lines),
                     indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
