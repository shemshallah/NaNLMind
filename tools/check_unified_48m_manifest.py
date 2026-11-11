#!/usr/bin/env python3
"""Validate that the 48M decoder/math source manifest loses no native method.

Static existence checks are NOT proof of mathematical correctness, which is
separately exercised by native guest fixtures and model evaluation.
"""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MANIFEST=ROOT/"spec/unified_48m_math_manifest.v1.json"
CREDIT_ORDER=["CFT","TRAIL","HOLO","RING","LEAF","TCA","FLUX"]
KNOWN_BRANCHES=33

def main()->None:
    m=json.loads(MANIFEST.read_text())
    assert m["schema"]=="nanlm.unified-48m-math/1"
    assert m["canonical_branch"]=="main"
    assert m["no_separate_models"] is True
    assert m["credit_order"]==CREDIT_ORDER
    channels=m["credit_channels"]
    assert len(channels)==len(CREDIT_ORDER)
    assert [x["id"] for x in channels]==CREDIT_ORDER
    paths=set()
    for entry in channels:
        assert entry["kernel"].startswith("mth/nan16/")
        paths.add(entry["kernel"])
        assert "tests" in entry and entry["tests"]
        paths.update(entry["tests"])
    stages=m["stages"]
    assert len(stages)>=9
    for stage in stages:
        assert stage["main_sources"] and stage["tests"]
        paths.update(stage["main_sources"])
        paths.update(stage["tests"])
    manifest_paths=m["branch_reconciliation_files"]
    assert len(manifest_paths)==4
    paths.update(manifest_paths)
    paths.update(["mth/drivers/field_driver.nas",
                  "mth/nan16/mth_geometric_trail_field.nas",
                  "tools/verify_native_memory_map.py"])
    missing=sorted(p for p in paths if not (ROOT/p).is_file())
    if missing:
        raise AssertionError("manifest references missing source/test files: "+", ".join(missing))
    branches=[]
    for path in manifest_paths:
        report=json.loads((ROOT/path).read_text())
        assert report["schema"]=="nanlm.branch-reconciliation/1"
        assert report["canonical_target"]=="main"
        for branch in report["branches"]:
            assert branch["status"] in (
                "review_required","partially_ported_remaining_diff_review_required",
                "comparison_unavailable")
            assert branch["branch"]!="main"
            branches.append(branch["branch"])
    if len(branches)!=KNOWN_BRANCHES or len(set(branches))!=KNOWN_BRANCHES:
        raise AssertionError(f"expected {KNOWN_BRANCHES} unique historical branches, got {len(branches)} total / {len(set(branches))} distinct")
    src=(ROOT/"mth/drivers/field_driver.nas").read_text()
    for command,label in ((31,"field_driver_credit_combine"),
        (32,"field_driver_combined_credit"),(33,"field_driver_combined_all"),
        (34,"field_driver_combined_wide"),(35,"field_driver_holo"),
        (36,"field_driver_ring"),(37,"field_driver_leaf"),
        (38,"field_driver_tca"),(39,"field_driver_flux"),
        (40,"field_driver_context_backoff"),
        (41,"field_driver_geometric_trail_field")):
        dispatch=re.compile(
            rf"\bMOVI r3,{command}\s+CMP r2,r3\s+JMP\[EQ\] @{label}\b")
        if not dispatch.search(src) or f"{label}:" not in src:
            raise AssertionError(f"guest command {command} -> {label} missing")
    op=(ROOT/"src/raw_field.cpp").read_text()
    if "kContextBackoffCommand = 40;" not in op:
        raise AssertionError("context backoff dispatch is not isolated from opcode 30")
    assert "0x395000" in (ROOT/"mth/nan16/mth_phase_encode.nas").read_text()
    print("PASS unified 48M math manifest:",len(stages),"stages,",
          len(channels),"native credit methods,",KNOWN_BRANCHES,
          "divergent branches,","all source and test paths present")
if __name__=="__main__":main()
