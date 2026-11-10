#!/usr/bin/env python3
"""Build actual NANNET C(256,2) corpus-route objects for HW4 and HW5.

Each route carries a 32,640-entry unordered byte-pair matrix and a typed
object reference. These are route definitions/objects in the NANNET registry,
not fake job labels. The raw math remains in the NaN16 guest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from nanlmind_nannet.rawroute import RawRoute, RawTarget, TypedObjectRef
from nanlmind_nannet.rawroute_store import RawRouteDB
from nanlmind_nannet.bridge import RunnerRoute
PAIR_COUNT = 32640


def pair_index(a: int, b: int) -> int:
    if a > b:
        a, b = b, a
    if a == b:
        return -1
    return a * 255 - (a * (a - 1)) // 2 + (b - a - 1)


def matrix_for(path: Path) -> dict:
    counts = [0] * PAIR_COUNT
    raw = path.read_bytes()
    last = None
    for byte in raw:
        if last is not None and last != byte:
            idx = pair_index(last, byte)
            if idx >= 0:
                counts[idx] += 1
        last = byte
    payload = json.dumps(counts, separators=(",", ":")).encode()
    digest = hashlib.sha256(payload).hexdigest()
    return {
        "schema": "nanlm.nannet.corpus-matrix/1",
        "corpus": str(path.relative_to(ROOT)),
        "corpus_sha256": hashlib.sha256(raw).hexdigest(),
        "pair_count": PAIR_COUNT,
        "nonzero_pairs": sum(1 for x in counts if x),
        "matrix_sha256": digest,
        "matrix": counts,
    }


def build_route(name: str, corpus: Path, kind: str, id_hint: str) -> tuple[RawRoute, dict]:
    matrix = matrix_for(corpus)
    object_id = int(matrix["matrix_sha256"][:8], 16) or 1
    target = RawTarget(int(name[2:]), tuple(range(256)))
    obj = TypedObjectRef(kind, object_id)
    route = RawRoute(0, 0, 0, 0, 0, int(name[2:]), 0, target, obj)
    matrix["object"] = {"kind": kind, "id": object_id, "id_hint": id_hint}
    matrix["route"] = route.text()
    matrix["route_id"] = route.definition_id
    return route, matrix


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--routes", default="state/nannet_routes/bs0.sqlite3")
    args = ap.parse_args()
    specs = {
        "HW4": ("state/wordnet_corpus.txt", "hyperedge"),
        "HW5": ("state/gutenberg_corpus.txt", "memory"),
    }
    out_dir = ROOT / "spec" / "nannet_objects"
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": "nanlm.nannet.corpus-routes/1", "routes": {}}
    route_db = RawRouteDB(ROOT / args.routes, "BS0", physical_root=ROOT / "state")
    tick = 1
    for name, (rel, kind) in specs.items():
        route, matrix = build_route(name, ROOT / rel, kind, name.lower())
        obj_path = out_dir / f"{name.lower()}_{kind}_{matrix['object']['id']}.json"
        obj_path.write_text(json.dumps(matrix, sort_keys=True), encoding="utf-8")
        result = route_db.commit(route, 0, tick, transport_route=RunnerRoute(0,0,0,0,int(name[2:]),0))
        manifest["routes"][name] = {
            "route": route.text(),
            "route_id": route.definition_id,
            "object_kind": kind,
            "object_id": matrix["object"]["id"],
            "object_file": str(obj_path.relative_to(ROOT)),
            "matrix_sha256": matrix["matrix_sha256"],
            "corpus": rel,
            "registry": str(Path(args.routes)),
            "commit": result,
        }
        tick += 1
    (ROOT / "spec" / "nannet_corpus_objects.v1.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
