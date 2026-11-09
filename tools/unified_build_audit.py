#!/usr/bin/env python3
"""Validate the canonical NaNLMind unified-build contract.

This is a build/contract audit, not a claim of mathematical correctness or a
live deployment. It checks the checked-in contract, the built native CLI's
`unification` line, and, when present, the sibling transport/adapter
repositories for contradictory topology claims.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "spec" / "unified-build.v1.json"
CLI = ROOT / "build" / "nanlm-universal"
SIBLING_ROUTER = ROOT.parent / "NaNROUTER"
SIBLING_HERMES = ROOT.parent / "NaNLMind_HERMES"


def fail(message: str) -> None:
    print(f"FAIL {message}")
    raise SystemExit(1)


def parse_unification(text: str) -> dict[str, str]:
    for line in text.splitlines():
        if line.startswith("unified_build "):
            return dict(part.split("=", 1) for part in line.split()[1:] if "=" in part)
    fail("native CLI did not emit a unified_build line")
    raise AssertionError


def main() -> int:
    document = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if document.get("schema") != "nanlm.unified-build/1":
        fail("unexpected contract schema")
    if document.get("canonical_repository") != "NaNLMind":
        fail("NaNLMind is not canonical")
    topology = document["topology"]
    expected = {
        "heads": 256,
        "triad_member_heads": 255,
        "field_head": 255,
        "triads": 85,
        "mirror_pairs": 32640,
        "canonical_cells": 32896,
        "chart_bytes": 8388608,
        "hypermatrix_rows": 32640,
        "hypermatrix_row_bits": 256,
        "resolution_layers": 10,
        "transform_passes": 10,
        "runner_slots": 6,
        "active_runner_slots": 1,
    }
    for key, value in expected.items():
        if topology.get(key) != value:
            fail(f"contract {key}={topology.get(key)!r}, expected {value}")
    roles = document.get("role_views", {})
    role_expected = {
        "physical_heads": 256,
        "mp_writer_eligible_heads": 255,
        "boolean_curriculum_heads": 250,
        "nannet_root_control_head": 0,
        "triad_member_heads": 255,
        "triad_field_head": 255,
    }
    for key, value in role_expected.items():
        if roles.get(key) != value:
            fail(f"role view {key}={roles.get(key)!r}, expected {value}")
    if roles.get("nannet_port_is_native_head"):
        fail("the NANNET port must not be represented as a native head")
    if roles.get("role_overlay_may_reassign_native_heads"):
        fail("the router role overlay must not reassign native heads")
    if document["authority"]["hermes_may_commit_canonical_state"]:
        fail("HERMES must not commit canonical state")
    if document["authority"]["nanrouter_may_copy_or_fork_native_universe"]:
        fail("NaNROUTER must not fork the native universe")
    if not CLI.is_file():
        fail(f"canonical binary missing: {CLI}")
    result = subprocess.run([str(CLI), "unification"], text=True, capture_output=True)
    if result.returncode != 0:
        fail(f"unification command failed: {result.stderr.strip()}")
    native = parse_unification(result.stdout)
    for key, value in expected.items():
        if native.get(key) != str(value):
            fail(f"native {key}={native.get(key)!r}, expected {value}")
    if native.get("canonical_repository") != "NaNLMind":
        fail("native CLI does not name NaNLMind as canonical")
    for key in ("mp_writer_eligible_heads", "boolean_curriculum_heads",
                "nannet_root_control_head", "bsr_control_heads"):
        if native.get(key) != str({
            "mp_writer_eligible_heads": 255,
            "boolean_curriculum_heads": 250,
            "nannet_root_control_head": 0,
            "bsr_control_heads": 6,
        }[key]):
            fail(f"native role view {key}={native.get(key)!r} is inconsistent")
    if SIBLING_HERMES.is_dir():
        topology_doc = SIBLING_HERMES / "docs" / "UNIFIED_TOPOLOGY_AND_LAYERS.md"
        if topology_doc.is_file():
            text = topology_doc.read_text(encoding="utf-8")
            if "ONE canonical NaNLMind universe" not in text:
                fail("HERMES topology document does not name the one canonical NaNLMind universe")
    if SIBLING_ROUTER.is_dir():
        role = SIBLING_ROUTER / "docs" / "HEAD_ROLE_NAMESPACE_CONTRACT.md"
        if role.is_file():
            text = role.read_text(encoding="utf-8")
            if "NaNLMind" not in text:
                # Report only; the router document is allowed to stay transport-focused.
                print("note: NaNROUTER head-role contract does not mention NaNLMind")
    print("unified_build status=green canonical=NaNLMind heads=256 triads=85 pairs=32640 chart_bytes=8388608")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
