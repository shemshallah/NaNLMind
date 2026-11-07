"""RSS sparse capability contract tests; no host-side graph math."""
import unittest

from runner.relational_spectral import Capability, RSSJob, capability_manifest, dispatchable


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

    def test_source_written_kernel_is_not_dispatchable(self):
        manifest = capability_manifest("R0", [Capability(
            "sparse_graph_laplacian_q16_16", "source_written",
            max_workspace_bytes=4096, operator_version=1,
            q_format="Q16.16/I32")])
        self.assertFalse(dispatchable(manifest, self.job))

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
