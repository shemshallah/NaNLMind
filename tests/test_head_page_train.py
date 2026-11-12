#!/usr/bin/env python3
"""Smoke-test the one-page final-W2 native training adapter."""
from __future__ import annotations
import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAGIC = 0x48315233


def page() -> bytearray:
    data = bytearray(1024 * 1024)
    data[0xFCC00:0xFCC04] = MAGIC.to_bytes(4, "little")
    for layer in range(3):
        base = layer * 0x50000
        for matrix, rows, cols in (
            (0x00000, 128, 128), (0x08000, 128, 128),
            (0x10000, 128, 128), (0x18000, 128, 128),
            (0x20000, 384, 128), (0x38000, 128, 384),
        ):
            for i in range(min(rows, cols)):
                bits = struct.unpack("<I", struct.pack("<f", 1.0))[0]
                off = base + matrix + (i * cols + i) * 2
                data[off:off + 2] = struct.pack("<H", bits >> 16)
    return data


def checkpoint(directory: Path, data: bytes, generation: int) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "head-001.page").write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    (directory / "manifest.txt").write_text(f"1 {generation} {digest}\n")


def main() -> int:
    binary = ROOT / "build" / "nanlm-head-page-train"
    worker = ROOT / "build" / "head_worker.nan"
    if not binary.is_file() or not worker.is_file():
        print("SKIP page train binary/image missing")
        return 0
    tmp = Path(tempfile.mkdtemp(prefix="nanlm-page-train-"))
    try:
        baseline = tmp / "baseline"
        candidate = tmp / "candidate"
        source_page = bytes(page())
        checkpoint(baseline, source_page, 0)
        context = [0.0] * 128
        context[0] = 1.0
        target = [0.0] * 128
        (tmp / "context.txt").write_text(" ".join(map(str, context)) + "\n")
        (tmp / "target.txt").write_text(" ".join(map(str, target)) + "\n")
        receipt = tmp / "train.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(tmp / "context.txt"),
             str(tmp / "target.txt"), "1", "0.1", "2", str(candidate),
             str(receipt)], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        report = json.loads(receipt.read_text())
        assert report["schema"] == "nanlm.head-page-train/1"
        assert report["head"] == 1
        assert report["source_generation"] == 0
        assert report["candidate_generation"] == 1
        assert report["host_math"] is False
        assert report["local_scope"] == "final_layer_W2_only"
        assert report["page_training"] is True
        assert report["tensor_promotion"] is False
        assert report["error_norm"] > 0.0
        assert len(report["source_page_sha256"]) == 64
        assert len(report["candidate_page_sha256"]) == 64
        updated = (candidate / "head-001.page").read_bytes()
        assert len(updated) == 1024 * 1024
        assert updated != source_page
        assert hashlib.sha256(updated).hexdigest() == report["candidate_page_sha256"]
        manifest = (candidate / "manifest.txt").read_text().strip().split()
        assert manifest[0] == "1"
        assert manifest[1] == "1"

        wo_candidate = tmp / "wo-candidate"
        wo_receipt = tmp / "wo.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(tmp / "context.txt"),
             str(tmp / "target.txt"), "1", "0.1", "1", str(wo_candidate),
             str(wo_receipt), "wo"], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        wo = json.loads(wo_receipt.read_text())
        assert wo["local_scope"] == "final_layer_Wo_only"
        assert wo["page_training"] is True
        assert wo["tensor_promotion"] is False
        wo_updated = (wo_candidate / "head-001.page").read_bytes()
        assert wo_updated != source_page

        w1_candidate = tmp / "w1-candidate"
        w1_receipt = tmp / "w1.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(tmp / "context.txt"),
             str(tmp / "target.txt"), "1", "0.1", "1", str(w1_candidate),
             str(w1_receipt), "w1"], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        w1 = json.loads(w1_receipt.read_text())
        assert w1["local_scope"] == "final_layer_W1_only"
        w1_updated = (w1_candidate / "head-001.page").read_bytes()
        assert w1_updated != source_page

        wv_candidate = tmp / "wv-candidate"
        wv_receipt = tmp / "wv.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(tmp / "context.txt"),
             str(tmp / "target.txt"), "1", "0.1", "1", str(wv_candidate),
             str(wv_receipt), "wv"], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        wv = json.loads(wv_receipt.read_text())
        assert wv["local_scope"] == "final_layer_Wv_only"
        wv_updated = (wv_candidate / "head-001.page").read_bytes()
        assert wv_updated != source_page

        context2 = context + [0.5] + [0.0] * 127
        (tmp / "context2.txt").write_text(" ".join(map(str, context2)) + "\n")
        qk_candidate = tmp / "qk-candidate"
        qk_receipt = tmp / "qk.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(tmp / "context2.txt"),
             str(tmp / "target.txt"), "1", "0.1", "1", str(qk_candidate),
             str(qk_receipt), "qk"], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        qk = json.loads(qk_receipt.read_text())
        assert qk["local_scope"] == "final_layer_Wq_Wk_only"
        qk_updated = (qk_candidate / "head-001.page").read_bytes()
        assert qk_updated != source_page

        l1_candidate = tmp / "l1-candidate"
        l1_receipt = tmp / "l1.json"
        run = subprocess.run(
            [str(binary), str(baseline), str(tmp / "context.txt"),
             str(tmp / "target.txt"), "1", "0.1", "1", str(l1_candidate),
             str(l1_receipt), "l1w2"], cwd=ROOT, text=True, capture_output=True)
        if run.returncode != 0:
            print(run.stdout)
            print(run.stderr)
            return 1
        l1 = json.loads(l1_receipt.read_text())
        assert l1["local_scope"] == "layer1_W2_local"
        l1_updated = (l1_candidate / "head-001.page").read_bytes()
        assert l1_updated != source_page
        print("PASS native final + layer1 W2/W1/Wv/QK page training adapter")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
