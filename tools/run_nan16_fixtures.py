#!/usr/bin/env python3
"""Assemble and execute the raw NaN16 adaptive-field fixtures.

The fixtures are the authority for the new mathematical path. This script only
invokes the canonical NaN0S assembler and guest runner; it performs no Boolean,
triad, field, or trig arithmetic itself.

Default NaN0S root: $NAN0S_ROOT or ~/nan0s. On a host without NaN0S the script
prints SKIP unless NAN16_REQUIRE=1 is set.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_NAN0S = Path(os.environ.get("NAN0S_ROOT", str(Path.home() / "nan0s")))
STEP_RE = re.compile(r"(\d+) steps")


@dataclass(frozen=True)
class Fixture:
    name: str
    path: str
    steps: int
    marker: str


FIXTURES = (
    Fixture("triad_vote", "mth/tests/mth_triad_vote_test.nas", 200_000,
            "MTH TRIAD VOTE PASS"),
    Fixture("field_vote", "mth/tests/mth_field_vote_test.nas", 200_000,
            "MTH FIELD VOTE PASS"),
    Fixture("q16_sin_cos", "mth/tests/mth_q16_sin_cos_test.nas", 200_000,
            "MTH Q16 SIN COS PASS"),
    Fixture("triad_remap", "mth/tests/mth_remap_test.nas", 200_000,
            "MTH TRIAD REMAP PASS"),
    Fixture("triad_remap_general", "mth/tests/mth_remap_general_test.nas", 200_000,
            "MTH GENERAL REMAP PASS"),
    Fixture("field_coherence", "mth/tests/mth_field_coherence_test.nas", 2_000_000,
            "MTH FIELD COHERENCE PASS"),
    Fixture("field_driver", "mth/tests/mth_field_driver_test.nas", 5_000_000,
            "MTH FIELD DRIVER PASS"),
    Fixture("cft_credit", "mth/tests/mth_cft_credit_test.nas", 200_000,
            "MTH CFT CREDIT PASS"),
    Fixture("q16_mul", "mth/tests/mth_q16_mul_test.nas", 200_000,
            "MTH Q16 MUL PASS"),
    Fixture("trail_credit", "mth/tests/mth_trail_credit_test.nas", 200_000,
            "MTH TRAIL CREDIT PASS"),
    Fixture("micro_block", "mth/tests/mth_micro_block_test.nas", 200_000,
            "MTH MICRO BLOCK PASS"),
    Fixture("field_commit", "mth/tests/mth_field_commit_test.nas", 200_000,
            "MTH FIELD COMMIT PASS"),
    Fixture("readout_train", "mth/tests/mth_readout_train_test.nas", 1_000_000,
            "MTH READOUT TRAIN PASS"),
    Fixture("credit_pipeline", "mth/tests/mth_credit_pipeline_test.nas", 200_000,
            "MTH CREDIT PIPELINE PASS"),
    Fixture("hot_trihead", "mth/tests/mth_hot_trihead_test.nas", 5_000_000,
            "MTH HOT TRIHEAD PASS"),
    Fixture("credit_suite", "mth/tests/mth_credit_suite_test.nas", 2_000_000,
            "MTH CREDIT SUITE PASS"),
    Fixture("context_class", "mth/tests/mth_context_class_test.nas", 500_000,
            "MTH CONTEXT CLASS PASS"),
    Fixture("micro_feature", "mth/tests/mth_micro_feature_test.nas", 200_000,
            "MTH MICRO FEATURE PASS"),
    Fixture("context24", "mth/tests/mth_context24_test.nas", 200_000,
            "MTH CONTEXT24 PASS"),
    Fixture("phase_encode", "mth/tests/mth_phase_encode_test.nas", 200_000,
            "MTH PHASE ENCODE PASS"),
    Fixture("phase_pq", "mth/tests/mth_phase_pq_test.nas", 200_000,
            "MTH PHASE PQ SPECTRAL PASS"),
    Fixture("vector_matrix", "mth/tests/mth_vector_matrix_test.nas", 8_000_000,
            "MTH VECTOR MATRIX PASS"),
    Fixture("triangle_contrast", "mth/tests/mth_triangle_contrast_test.nas",
            1_000_000, "MTH TRIANGLE CONTRAST PASS"),
    Fixture("global_hodge", "mth/tests/mth_global_hodge256_native_test.nas",
            3_000_000, "MTH GLOBAL HODGE256 PASS"),
    Fixture("geometric_trail_field", "mth/tests/mth_geometric_field_train_test.nas",
            7_000_000, "MTH GEOMETRIC FIELD TRAIN PASS"),
    Fixture("ht256_arena", "mth/tests/mth_hypertensor256_mirror_arena_native_test.nas",
            10_000_000, "MTH HYPERTENSOR256 MIRROR ARENA PASS"),
    Fixture("ht256_dual", "mth/tests/mth_hypertensor256_mirror_dual_native_test.nas",
            3_000_000, "MTH FULL 128M MIRROR DUAL BANK PASS"),
    Fixture("spectral_tensor_proposal", "mth/tests/mth_spectral_trihead_tensor_proposal_test.nas",
            12_000_000, "MTH SPECTRAL TRIHEAD TENSOR PROPOSAL PASS"),
    Fixture("spectral_tensor_opcode106", "mth/tests/mth_spectral_tensor_driver_opcode_test.nas",
            12_000_000, "MTH 48M SPECTRAL TENSOR OPCODE106 PASS"),
    Fixture("six_context_poincare", "mth/tests/mth_six_context_poincare_attention_test.nas",
            6_000_000, "MTH SIX CONTEXT POINCARE ATTENTION PASS"),
    Fixture("six_context_opcode107", "mth/tests/mth_context6_driver_opcode107_test.nas",
            12_000_000, "MTH 48M CONTEXT6 OPCODE107 PASS"),
    Fixture("poincare128_curl", "mth/tests/mth_hyperedge_poincare128_curl_test.nas",
            6_000_000, "MTH POINCARE128 HODGE CURL HYPEREDGE PASS"),
    Fixture("context6_stream", "mth/tests/mth_context6_window_stream_test.nas",
            3_000_000, "MTH CONTEXT6 STREAM TARGET ISOLATION PASS"),
    Fixture("future3_causal", "mth/tests/mth_future3_causal_window_test.nas",
            12_000_000, "MTH FUTURE3 NATIVE CAUSAL PREFIX PASS"),
    Fixture("context6_stream_opcode109", "mth/tests/mth_context6_stream_driver_opcode109_test.nas",
            12_000_000, "MTH 48M STREAM CONTEXT6 OPCODE109 PASS"),
    Fixture("leaf_hash", "mth/tests/mth_leaf_hash_test.nas", 200_000,
            "MTH LEAF HASH PASS"),
    Fixture("dual_gate", "mth/tests/mth_dual_gate_test.nas", 200_000,
            "MTH DUAL GATE PASS"),
    Fixture("pq_train", "mth/tests/mth_pq_train_test.nas", 1_000_000,
            "MTH PQ TRAIN PASS"),
    Fixture("tokenizer", "mth/tests/mth_tokenizer_test.nas", 1_000_000,
            "MTH TOKENIZER PASS"),
    Fixture("meta_trihead", "mth/tests/mth_meta_trihead_test.nas", 1_000_000,
            "MTH META TRIHEAD PASS"),
    Fixture("temporal_slots", "mth/tests/mth_temporal_slots_test.nas", 1_000_000,
            "MTH TEMPORAL SLOTS PASS"),
    Fixture("ngram_train", "mth/tests/mth_ngram_train_test.nas", 20_000_000,
            "MTH NGRAM TRAIN PASS"),
)


def run_one(fixture: Fixture, nan0s: Path, out_dir: Path) -> tuple[bool, str]:
    source = ROOT / fixture.path
    if not source.is_file():
        return False, f"missing source {fixture.path}"
    image = out_dir / f"{fixture.name}.nan"
    assemble = subprocess.run(
        ["awk", "-f", str(nan0s / "tools" / "nmk.awk"), "-v", "CMD=emit", str(source)],
        cwd=ROOT, text=True, capture_output=True,
    )
    if assemble.returncode != 0 or not assemble.stdout.strip():
        return False, "assemble failed: " + (assemble.stderr.strip()[-1200:] or "empty image")
    image.write_text(assemble.stdout, encoding="utf-8")
    execute = subprocess.run(
        [str(nan0s / "aarch64" / "android" / "nan_cli"),
         "--img", str(image), "--steps", str(fixture.steps), "--serial"],
        cwd=ROOT, text=True, capture_output=True,
    )
    output = execute.stdout + execute.stderr
    match = STEP_RE.search(output)
    steps = match.group(1) if match else "?"
    if fixture.marker not in output:
        return False, f"marker missing ({fixture.marker}); steps={steps}\n{output.strip()[-1200:]}"
    return True, f"steps={steps} marker={fixture.marker}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nan0s-root", type=Path, default=DEFAULT_NAN0S)
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)
    if args.list:
        for fixture in FIXTURES:
            print(f"{fixture.name}\t{fixture.path}")
        return 0
    missing = []
    if not (args.nan0s_root / "tools" / "nmk.awk").is_file():
        missing.append(str(args.nan0s_root / "tools" / "nmk.awk"))
    if not (args.nan0s_root / "aarch64" / "android" / "nan_cli").is_file():
        missing.append(str(args.nan0s_root / "aarch64" / "android" / "nan_cli"))
    if missing:
        message = "NaN0S toolchain missing: " + ", ".join(missing)
        if os.environ.get("NAN16_REQUIRE") == "1":
            print("FAIL " + message, file=sys.stderr)
            return 2
        print("SKIP " + message)
        return 0
    selected = set(args.only)
    fixtures = [f for f in FIXTURES if not selected or f.name in selected]
    unknown = selected - {f.name for f in fixtures}
    if unknown:
        print(f"unknown fixture(s): {sorted(unknown)}", file=sys.stderr)
        return 2
    failures = 0
    with tempfile.TemporaryDirectory(prefix="nan16-fixtures-") as temp:
        out_dir = Path(temp)
        for fixture in fixtures:
            ok, detail = run_one(fixture, args.nan0s_root, out_dir)
            print(f"[{'PASS' if ok else 'FAIL'}] {fixture.name}: {detail}")
            failures += 0 if ok else 1
    print(f"{len(fixtures) - failures}/{len(fixtures)} raw NaN16 fixtures passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
