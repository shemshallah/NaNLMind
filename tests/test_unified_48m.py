#!/usr/bin/env python3
"""Fixture tests for the unified 48M language entrypoint."""
from __future__ import annotations

import importlib.util
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
SPEC = importlib.util.spec_from_file_location(
    "unified_48m_runtime", TOOLS / "unified_48m_runtime.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class FrozenFixture:
    """Interface fixture only; never presented as the archived 48M model."""
    def __init__(self):
        self.calls = 0

    def score(self, context, word):
        self.calls += 1
        table = {"alpha": 0.5, "beta": 0.3, "gamma": 0.1}
        return {"probability": table[word]}


def test_zero_feedback_is_exact_frozen_parity():
    emitter = FrozenFixture()
    result = module.normalize_candidate_scores(
        emitter, "the river", {"alpha": 0.0, "beta": 0.0, "gamma": 0.0},
        ["alpha", "beta", "gamma"])
    assert abs(result["normalizer"] - 1.0) < 1e-12
    for row in result["rows"]:
        assert abs(row["baseline_probability"] -
                   row["candidate_probability"]) < 1e-12
    assert result["top_k"][0]["word"] == "alpha"


def test_finite_candidate_normalizer():
    emitter = FrozenFixture()
    weights = {"alpha": 0.5, "beta": -0.25, "gamma": 0.0}
    result = module.normalize_candidate_scores(
        emitter, "the river", weights, ["alpha", "beta", "gamma"])
    expected_z = 1.0 + 0.5 * math.expm1(0.5) + \
        0.3 * math.expm1(-0.25) + 0.1 * math.expm1(0.0)
    assert abs(result["normalizer"] - expected_z) < 1e-12
    rows = {row["word"]: row for row in result["rows"]}
    assert abs(rows["alpha"]["candidate_probability"] -
               0.5 * math.exp(0.5) / expected_z) < 1e-12
    assert rows["alpha"]["candidate_probability"] > \
        rows["alpha"]["baseline_probability"]
    assert result["full_vocabulary_argmax"] is False
    assert result["tensor_promotion"] is False


def test_native_batch_abi_fixture():
    with tempfile.TemporaryDirectory(prefix="nanlm-48m-test-") as tmp:
        tmp_path = Path(tmp)
        binary = tmp_path / "native-batch"
        # argv[3] is the textual 48M context; argv[4] is the wordlist.
        binary.write_text(
            "#!/usr/bin/env python3\n"
            "import json,sys\n"
            "ctx=sys.argv[3]\n"
            "out=sys.argv[5]\n"
            "words=[x for x in open(sys.argv[4]).read().splitlines() if x]\n"
            "json.dump({'context':ctx,'accepted':len(words),"
            "'candidate_count':len(words),"
            "'native_log_weights':{w:0.25 for w in words}},open(out,'w'))\n",
            encoding="utf-8")
        os.chmod(binary, 0o755)
        result = module.run_native_batch(binary, "the river",
                                         ["alpha", "beta"])
        assert result["native_accepted"] == 2
        assert result["native_log_weights"] == {"alpha": 0.25, "beta": 0.25}


def test_native_emit_bridge_abi_fixture():
    with tempfile.TemporaryDirectory(prefix="nanlm-48m-emit-test-") as tmp:
        tmp_path = Path(tmp)
        binary = tmp_path / "native-emit"
        binary.write_text(
            "#!/usr/bin/env python3\n"
            "import json,sys\n"
            "word=sys.argv[4]\n"
            "json.dump({'native_log_weights':{word:0.125},"
            "'native_evidence':{'meta_available':True,"
            "'candidate_staged':True,'automatic_promotion':False}},"
            "open(sys.argv[5],'w'))\n",
            encoding="utf-8")
        os.chmod(binary, 0o755)
        result = module.run_native_emit(binary, "the river",
                                        ["alpha", "beta"])
        assert result["native_log_weights"] == {"alpha": 0.125,
                                                "beta": 0.125}
        assert result["native_evidence"]["alpha"]["meta_available"] is True
        assert result["native_evidence"]["alpha"][
            "automatic_promotion"] is False


def test_missing_archive_fails_closed():
    with tempfile.TemporaryDirectory(prefix="nanlm-48m-missing-") as tmp:
        tmp_path = Path(tmp)
        candidates = tmp_path / "words.txt"
        candidates.write_text("alpha\n", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(TOOLS / "unified_48m_runtime.py"),
             "--archive-root", str(tmp_path / "absent"),
             "--context", "the river",
             "--candidate-file", str(candidates)],
            cwd=ROOT, text=True, capture_output=True)
        assert proc.returncode == 2
        assert "original frozen 48M archive is required" in proc.stderr
        assert "{" not in proc.stdout


def main():
    test_zero_feedback_is_exact_frozen_parity()
    test_finite_candidate_normalizer()
    test_native_batch_abi_fixture()
    test_native_emit_bridge_abi_fixture()
    test_missing_archive_fails_closed()
    print("PASS unified 48M language entrypoint")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
