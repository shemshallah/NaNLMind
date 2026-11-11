#!/usr/bin/env python3
"""Repair N16TRI/1 split assignments without regenerating the corpus.

The original generator assigned every row derived from an anchor to the
anchor's split.  That is correct for the positive/inverse pair, but a hard,
random, or self negative for the same unordered pair could still land in a
different split.  This tool streams the existing tri/readable files, derives
each row's split from its own unordered endpoint pair, and rewrites the
manifest audit fields.

Use this for corpora produced before the generator learned pair-level
assignment.  New corpora are already pair-consistent.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Iterable, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_relation_triangle_corpus import (  # noqa: E402
    SCHEMA,
    split_for_pair,
)

TRIPLE_FIELDS = 9
READABLE_FIELDS = 11
POSITIVE_LABELS = {"positive", "inverse"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pair_key(a: str, b: str) -> str:
    lo, hi = sorted((a, b))
    return f"{lo}|{hi}"


def _check_header(line: str, expected: str, path: Path) -> None:
    if line.rstrip("\n") != expected:
        raise SystemExit(f"{path}: unexpected header {line!r}")


def _split_tsv(line: str, fields: int, path: Path, line_no: int) -> list[str]:
    parts = line.rstrip("\n").split("\t")
    if len(parts) != fields:
        raise SystemExit(
            f"{path}:{line_no}: expected {fields} fields, found {len(parts)}"
        )
    return parts


def _replace_atomic(path: Path, tmp_path: Path) -> None:
    os.replace(tmp_path, path)


def resplit_corpus(
    *,
    tri_path: Path,
    readable_path: Path,
    manifest_path: Path,
    dry_run: bool = False,
) -> dict[str, object]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    before_cross_pairs = int(manifest.get("cross_split_row_pairs", -1))

    split_counts: Counter[str] = Counter()
    split_relation: Counter[str] = Counter()
    split_label: Counter[str] = Counter()
    anchor_pair_split: dict[str, str] = {}
    row_pair_split: dict[str, str] = {}
    synset_split: dict[str, str] = {}
    cross_synsets: set[str] = set()
    cross_anchor_pairs = 0
    cross_row_pairs = 0

    tri_tmp = tri_path.with_name(tri_path.name + ".resplit.tmp")
    readable_tmp = readable_path.with_name(readable_path.name + ".resplit.tmp")
    tri_hash = hashlib.sha256()
    readable_hash = hashlib.sha256()
    tri_bytes = 0
    readable_bytes = 0

    tri_handle = tri_tmp.open("w", encoding="utf-8", newline="\n")
    readable_handle = readable_tmp.open("w", encoding="utf-8", newline="\n")
    try:
        with tri_path.open("r", encoding="utf-8", newline="") as tri, \
                readable_path.open("r", encoding="utf-8", newline="") as readable:
            tri_header = tri.readline()
            _check_header(tri_header, SCHEMA, tri_path)
            readable_header = readable.readline()
            _check_header(
                readable_header,
                "split\trelation\tlabel\tconfidence\tsubject\tpredicate\tobject\t"
                "subject_id\tobject_id\tsource_sha256\tprovenance",
                readable_path,
            )
            tri_handle.write(tri_header)
            tri_hash.update(tri_header.encode("utf-8"))
            tri_bytes += len(tri_header.encode("utf-8"))
            readable_handle.write(readable_header)
            readable_hash.update(readable_header.encode("utf-8"))
            readable_bytes += len(readable_header.encode("utf-8"))

            tri_line_no = 1
            readable_line_no = 1
            while True:
                tri_line = tri.readline()
                readable_line = readable.readline()
                if not tri_line and not readable_line:
                    break
                if not tri_line or not readable_line:
                    raise SystemExit(
                        f"{tri_path}:{tri_line_no} / {readable_path}:"
                        f"{readable_line_no}: row counts differ"
                    )
                tri_line_no += 1
                readable_line_no += 1
                tparts = _split_tsv(tri_line, TRIPLE_FIELDS, tri_path, tri_line_no)
                rparts = _split_tsv(
                    readable_line, READABLE_FIELDS, readable_path, readable_line_no
                )
                old_split, relation, label, confidence, subject, predicate, obj, \
                    subject_id, object_id, source_sha, provenance = rparts
                if tparts[0] != old_split:
                    raise SystemExit(
                        f"{tri_path}:{tri_line_no}: split {tparts[0]!r} does not "
                        f"match readable split {old_split!r}"
                    )
                if (
                    tparts[1] != relation
                    or tparts[2] != label
                    or tparts[3] != confidence
                    or tparts[4] != subject.encode("utf-8").hex()
                    or tparts[5] != predicate.encode("utf-8").hex()
                    or tparts[6] != obj.encode("utf-8").hex()
                    or tparts[7] != source_sha
                    or tparts[8] not in provenance
                ):
                    raise SystemExit(
                        f"{tri_path}:{tri_line_no}: tri/readable rows are not aligned"
                    )

                new_split = split_for_pair(subject_id, object_id)
                split_counts[new_split] += 1
                split_relation[f"{new_split}/{relation}"] += 1
                split_label[f"{new_split}/{label}"] += 1

                key = pair_key(subject_id, object_id)
                previous = row_pair_split.get(key)
                if previous is None:
                    row_pair_split[key] = new_split
                elif previous != new_split:
                    cross_row_pairs += 1
                if label in POSITIVE_LABELS:
                    previous_anchor = anchor_pair_split.get(key)
                    if previous_anchor is None:
                        anchor_pair_split[key] = new_split
                    elif previous_anchor != new_split:
                        cross_anchor_pairs += 1

                for sid in (subject_id, object_id):
                    previous_synset = synset_split.get(sid)
                    if previous_synset is None:
                        synset_split[sid] = new_split
                    elif previous_synset != new_split:
                        cross_synsets.add(sid)

                tparts[0] = new_split
                rparts[0] = new_split
                tline = "\t".join(tparts) + "\n"
                rline = "\t".join(rparts) + "\n"
                tri_handle.write(tline)
                readable_handle.write(rline)
                tri_hash.update(tline.encode("utf-8"))
                readable_hash.update(rline.encode("utf-8"))
                tri_bytes += len(tline.encode("utf-8"))
                readable_bytes += len(rline.encode("utf-8"))
    finally:
        tri_handle.close()
        readable_handle.close()

    if cross_row_pairs:
        raise SystemExit(
            f"internal error: pair-derived splits still have "
            f"{cross_row_pairs} cross-split row pairs"
        )

    row_stats = dict(manifest.get("row_stats", {}))
    for key in [key for key in row_stats if key.startswith("split:")]:
        del row_stats[key]
    for split, count in split_counts.items():
        row_stats[f"split:{split}"] = count

    manifest["splits"] = dict(sorted(split_counts.items()))
    manifest["split_relation"] = dict(sorted(split_relation.items()))
    if "split_label" in manifest:
        manifest["split_label"] = dict(sorted(split_label.items()))
    manifest["row_stats"] = row_stats
    manifest["anchor_pairs"] = len(anchor_pair_split)
    manifest["cross_split_anchor_pairs"] = cross_anchor_pairs
    manifest["row_pairs"] = len(row_pair_split)
    manifest["cross_split_row_pairs"] = cross_row_pairs
    manifest["cross_split_synsets"] = len(cross_synsets)
    manifest["tri_sha256"] = tri_hash.hexdigest()
    manifest["readable_sha256"] = readable_hash.hexdigest()
    manifest["tri_bytes"] = tri_bytes
    manifest["readable_bytes"] = readable_bytes
    manifest["split_note"] = (
        "pair split hashes the unordered synset pair; every row's split is "
        "derived from its own endpoints, so no unordered pair crosses splits. "
        "Negatives for an anchor can be in a different split than the anchor's "
        "positive/inverse rows. Use the generator's --split-by synset for a "
        "stricter synset-disjoint corpus."
    )
    manifest["resplit"] = {
        "tool": "tools/resplit_relation_triangle_corpus.py",
        "from": "anchor-derived splits",
        "to": "pair-derived splits",
        "cross_split_row_pairs_before": before_cross_pairs,
        "cross_split_row_pairs_after": cross_row_pairs,
    }
    if isinstance(manifest.get("options"), dict):
        manifest["options"]["resplit"] = True

    if dry_run:
        tri_tmp.unlink(missing_ok=True)
        readable_tmp.unlink(missing_ok=True)
        return {
            "dry_run": True,
            "rows": sum(split_counts.values()),
            "splits": dict(sorted(split_counts.items())),
            "cross_split_row_pairs_before": before_cross_pairs,
            "cross_split_row_pairs_after": cross_row_pairs,
            "cross_split_anchor_pairs": cross_anchor_pairs,
            "cross_split_synsets": len(cross_synsets),
        }

    _replace_atomic(readable_path, readable_tmp)
    _replace_atomic(tri_path, tri_tmp)
    manifest_tmp = manifest_path.with_name(manifest_path.name + ".resplit.tmp")
    manifest_tmp.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    _replace_atomic(manifest_path, manifest_tmp)
    return {
        "dry_run": False,
        "rows": sum(split_counts.values()),
        "splits": dict(sorted(split_counts.items())),
        "cross_split_row_pairs_before": before_cross_pairs,
        "cross_split_row_pairs_after": cross_row_pairs,
        "cross_split_anchor_pairs": cross_anchor_pairs,
        "cross_split_synsets": len(cross_synsets),
        "tri_sha256": manifest["tri_sha256"],
        "readable_sha256": manifest["readable_sha256"],
    }


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="n16tri-resplit-") as tmp:
        root = Path(tmp)
        tri = root / "tri.tsv"
        readable = root / "tri.readable.tsv"
        manifest = root / "manifest.json"
        tri.write_text(
            SCHEMA + "\n"
            "train\tISA\tpositive\t50000\t61\t495341\t62\tabc\tprov-a\n"
            "test\tISA\thard_negative\t40000\t61\t495341\t63\tabc\tprov-b\n",
            encoding="utf-8",
        )
        readable.write_text(
            "split\trelation\tlabel\tconfidence\tsubject\tpredicate\tobject\t"
            "subject_id\tobject_id\tsource_sha256\tprovenance\n"
            "train\tISA\tpositive\t50000\ta\tISA\tb\tn0001\tn0002\tabc\tprov-a\n"
            "test\tISA\thard_negative\t40000\ta\tISA\tc\tn0001\tn0003\tabc\tprov-b\n",
            encoding="utf-8",
        )
        manifest.write_text(
            json.dumps(
                {
                    "schema": "nanlm.relation-triangle-corpus/1",
                    "tri_schema": SCHEMA,
                    "rows": 2,
                    "splits": {"train": 1, "test": 1},
                    "cross_split_row_pairs": 1,
                    "row_stats": {"split:train": 1, "split:test": 1},
                    "options": {"split_by": "pair"},
                    "split_note": "old",
                }
            )
            + "\n",
            encoding="utf-8",
        )
        result = resplit_corpus(
            tri_path=tri,
            readable_path=readable,
            manifest_path=manifest,
        )
        assert result["cross_split_row_pairs_after"] == 0, result
        expected = {
            "n0001|n0002": split_for_pair("n0001", "n0002"),
            "n0001|n0003": split_for_pair("n0001", "n0003"),
        }
        tri_lines = tri.read_text(encoding="utf-8").splitlines()
        readable_lines = readable.read_text(encoding="utf-8").splitlines()
        assert tri_lines[0] == SCHEMA
        assert len(tri_lines) == 3
        assert len(readable_lines) == 3
        for index, key in enumerate(expected, start=1):
            assert tri_lines[index].split("\t")[0] == expected[key]
            assert readable_lines[index].split("\t")[0] == expected[key]
        updated = json.loads(manifest.read_text(encoding="utf-8"))
        assert updated["cross_split_row_pairs"] == 0
        assert updated["resplit"]["cross_split_row_pairs_before"] == 1
        assert sum(updated["splits"].values()) == 2
        assert updated["tri_sha256"] == sha256_file(tri)
        assert updated["readable_sha256"] == sha256_file(readable)
        assert updated["tri_bytes"] == tri.stat().st_size
        assert updated["readable_bytes"] == readable.stat().st_size
        # The rest of each row must be byte-for-byte unchanged.
        assert tri_lines[1].split("\t")[1:] == [
            "ISA", "positive", "50000", "61", "495341", "62", "abc", "prov-a"
        ]
        assert readable_lines[2].split("\t")[1:] == [
            "ISA", "hard_negative", "40000", "a", "ISA", "c",
            "n0001", "n0003", "abc", "prov-b"
        ]
    print("self-test PASS resplit pairs=2 cross_split_row_pairs=0")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tri", type=Path, help="N16TRI/1 file")
    parser.add_argument("--readable", type=Path, help="readable TSV file")
    parser.add_argument("--manifest", type=Path, help="manifest JSON file")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="audit and report without rewriting files",
    )
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not (args.tri and args.readable and args.manifest):
        parser.error("--tri, --readable, and --manifest are required")
    result = resplit_corpus(
        tri_path=args.tri,
        readable_path=args.readable,
        manifest_path=args.manifest,
        dry_run=args.dry_run,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
