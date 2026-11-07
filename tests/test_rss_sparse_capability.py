"""RSS sparse capability contract tests; no host-side graph math."""
import unittest
import sys
from pathlib import Path
import json
from contextlib import redirect_stdout
from io import StringIO
from types import SimpleNamespace

from runner.relational_spectral import (Capability, RSSJob, capability_manifest, dispatchable, sparse_graph_laplacian_q16_16_capability, sparse_weighted_graph_laplacian_q16_16_i64_v2_capability)
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "runner"))
from runner.nanlm_worker import op_rss_status


class SparseCapabilityContractTests(unittest.TestCase):
    def setUp(self):
        self.job = RSSJob.from_mapping({
            "protocol": "NAN-RSS-1",
            "job_id": "sparse-1",
            "universe_id": "u0",
            "topology_digest": "topology-sha256",
            "operator": "sparse_graph_laplacian_q16_16",
            "operator_version": 1,
            "input_ref": "page:graph:1",
            "output_ref": "page:result:1",
            "element_count": 256,
            "q_format": "Q16.16/I32",
            "workspace_bytes": 4096,
            "step_budget": 100000,
            "cancellation_epoch": 7,
            "parameters": {"layout": "symmetric-csr-u16-v1"},
        })


    def test_worker_status_advertises_only_verified_sparse_evidence(self):
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(op_rss_status(SimpleNamespace(slot_name="R0")), 0)
        manifest = json.loads(output.getvalue())
        sparse = next(c for c in manifest["capabilities"]
                      if c["name"] == "sparse_graph_laplacian_q16_16")
        self.assertEqual(sparse["status"], "native_verified")
        self.assertEqual(sparse["operator_version"], 1)
        self.assertEqual(sparse["q_format"], "Q16.16/I32")
        self.assertEqual(sparse["kernel_digest"],
                         "013048435c1026643554fb20e3434934cf059dd47cf2857577cac13ed5be6b8f")
        self.assertFalse(manifest["native_math_dispatch_enabled"])
        self.assertIn("sparse_graph_laplacian_q16_16", manifest["native_verified_operators"])
        self.assertEqual(manifest["dispatchable_operators"], [])
        self.assertTrue(manifest["preflight_gate_required"])
        self.assertEqual(manifest["preflight_gate_abi"], "NAN16-MTH-PREFLIGHT/1")


    def test_weighted_v2_worker_status_reports_exact_native_evidence(self):
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(op_rss_status(SimpleNamespace(slot_name="R0")), 0)
        manifest = json.loads(output.getvalue())
        weighted = next(c for c in manifest["capabilities"]
                        if c["name"] == "sparse_weighted_graph_laplacian_q16_16_i64_v2")
        self.assertEqual(weighted["status"], "native_verified")
        self.assertEqual(weighted["operator_version"], 2)
        self.assertEqual(weighted["q_format"], "Q16.16/I32->I64;U8W")
        self.assertEqual(weighted["kernel_digest"],
                         "8958bf432cd4052576d9b950d9e50c1853bc96d90bc3c50680bf9013ab36d613")
        self.assertFalse(manifest["native_math_dispatch_enabled"])
        self.assertIn("sparse_weighted_graph_laplacian_q16_16_i64_v2",
                      manifest["native_verified_operators"])
        self.assertEqual(manifest["dispatchable_operators"], [])
        self.assertTrue(manifest["preflight_gate_required"])

    def test_weighted_v2_capability_matches_its_own_job_abi(self):
        job = RSSJob.from_mapping({
            "protocol": "NAN-RSS-1",
            "job_id": "weighted-v2-1",
            "universe_id": "u0",
            "topology_digest": "weighted-topology-sha256",
            "operator": "sparse_weighted_graph_laplacian_q16_16_i64_v2",
            "operator_version": 2,
            "input_ref": "page:weighted-graph:1",
            "output_ref": "page:weighted-result:1",
            "element_count": 256,
            "q_format": "Q16.16/I32->I64;U8W",
            "workspace_bytes": 4096,
            "step_budget": 200000,
            "cancellation_epoch": 8,
            "parameters": {"layout": "symmetric-weighted-csr-u8-v2",
                           "weight_range": [1, 255]},
        })
        manifest = capability_manifest(
            "R0", [sparse_weighted_graph_laplacian_q16_16_i64_v2_capability()])
        self.assertTrue(dispatchable(manifest, job))

    def test_weighted_v2_wrong_version_or_format_is_rejected(self):
        good = sparse_weighted_graph_laplacian_q16_16_i64_v2_capability()
        for version, q_format in ((1, "Q16.16/I32->I64;U8W"),
                                  (2, "Q16.16/I32")):
            bad = Capability(good.name, "native_verified", good.max_workspace_bytes,
                             good.kernel_digest, operator_version=version,
                             q_format=q_format)
            manifest = capability_manifest("R0", [bad])
            job = RSSJob.from_mapping({
                "protocol": "NAN-RSS-1", "job_id": "bad-weighted",
                "universe_id": "u0", "topology_digest": "t",
                "operator": good.name, "operator_version": 2,
                "input_ref": "in", "output_ref": "out",
                "element_count": 256, "q_format": "Q16.16/I32->I64;U8W",
                "workspace_bytes": 64, "step_budget": 1000,
                "cancellation_epoch": 1, "parameters": {},
            })
            self.assertFalse(dispatchable(manifest, job))

    def test_source_written_kernel_is_not_dispatchable(self):
        manifest = capability_manifest("R0", [Capability(
            "sparse_graph_laplacian_q16_16", "source_written",
            max_workspace_bytes=4096, operator_version=1,
            q_format="Q16.16/I32")])
        self.assertFalse(dispatchable(manifest, self.job))

    def test_registered_native_verified_kernel_is_dispatchable(self):
        manifest = capability_manifest("R0", [sparse_graph_laplacian_q16_16_capability()])
        self.assertTrue(dispatchable(manifest, self.job))

    def test_native_verified_requires_digest_and_matching_abi(self):
        capability = Capability(
            "sparse_graph_laplacian_q16_16", "native_verified",
            max_workspace_bytes=8192, kernel_digest="a" * 64,
            operator_version=1, q_format="Q16.16/I32")
        manifest = capability_manifest("R0", [capability])
        self.assertTrue(dispatchable(manifest, self.job))

    def test_wrong_q_format_or_version_is_not_dispatchable(self):
        for version, q_format in ((2, "Q16.16/I32"), (1, "Q8.24/I32")):
            manifest = capability_manifest("R0", [Capability(
                "sparse_graph_laplacian_q16_16", "native_verified",
                max_workspace_bytes=8192, kernel_digest="b" * 64,
                operator_version=version, q_format=q_format)])
            self.assertFalse(dispatchable(manifest, self.job))

    def test_workspace_ceiling_is_enforced(self):
        manifest = capability_manifest("R0", [Capability(
            "sparse_graph_laplacian_q16_16", "native_verified",
            max_workspace_bytes=2048, kernel_digest="c" * 64,
            operator_version=1, q_format="Q16.16/I32")])
        self.assertFalse(dispatchable(manifest, self.job))


if __name__ == "__main__":
    unittest.main()
