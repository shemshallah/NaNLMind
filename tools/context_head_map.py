#!/usr/bin/env python3
"""Emit the canonical mapping from context-memory classes to the 256 heads.

The context memory has 16 high-nibble groups and 16 low-nibble classes. This
tool maps those classes onto the existing 255 triad-member heads plus field
head 255, and maps the 16 high groups onto the 85 triads (five triads per
high group; the last five triads are reserved for field/control use).

This is a mapping/validation artifact. It does not change model arithmetic.
The same map is implemented in the raw guest by
mth/nan16/mth_context_class.nas (driver command 30).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", type=Path, default=Path("spec/unified-build.v1.json"))
    ap.add_argument("--out", type=Path, default=Path("state/context_head_map.json"))
    args = ap.parse_args()
    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    topology = spec["topology"]
    physical = int(topology["heads"])
    field_head = int(topology["field_head"])
    triad_count = int(topology["triads"])
    classes = []
    for cls in range(255):
        classes.append({
            "class": cls,
            "head": cls,
            "high_nibble": cls >> 4,
            "low_nibble": cls & 15,
            "triad": cls // 3,
            "triad_member": cls % 3,
        })
    groups = []
    for group in range(16):
        first = group * 5
        groups.append({
            "high_nibble": group,
            "class_heads": list(range(group * 16, group * 16 + 16)),
            "triads": list(range(first, min(first + 5, triad_count))),
        })
    result = {
        "schema": "nanlm.context-head-map/1",
        "physical_heads": physical,
        "triad_member_heads": physical - 1,
        "field_head": field_head,
        "triads": triad_count,
        "field_threshold": {"accepted": 43, "total": 85},
        "high_groups": groups,
        "classes": classes,
        "note": ("high nibble selects a field group; low nibble selects one "
                 "of sixteen class heads; head 255 is the field head"),
    }
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8")
    print(f"wrote {args.out} classes={len(classes)} groups={len(groups)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
