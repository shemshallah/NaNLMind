import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "runner"))
from relational_spectral import (
    PROTOCOL, Capability, RSSJob, RSSResult, capability_manifest,
    dispatchable, canonical_digest,
)


def job_payload(**changes):
    value = {
        "protocol": PROTOCOL, "job_id": "job-1", "universe_id": "u0",
        "topology_digest": "topology-sha", "operator": "sparse_graph_apply",
        "operator_version": 1, "input_ref": "page:in", "output_ref": "page:out",
        "element_count": 256, "q_format": "Q16.16",
        "workspace_bytes": 4096, "step_budget": 1000,
        "cancellation_epoch": 7, "parameters": {"normalization": "symmetric"},
    }
    value.update(changes)
    return value


class RelationalSpectralContractTests(unittest.TestCase):
    def test_valid_job_round_trips(self):
        job = RSSJob.from_mapping(job_payload())
        self.assertEqual(job.element_count, 256)
        self.assertEqual(job.operator, "sparse_graph_apply")

    def test_rejects_wrong_protocol_missing_fields_and_aliasing(self):
        with self.assertRaises(ValueError):
            RSSJob.from_mapping(job_payload(protocol="RSS-0"))
        with self.assertRaises(ValueError):
            RSSJob.from_mapping({"protocol": PROTOCOL})
        with self.assertRaises(ValueError):
            RSSJob.from_mapping(job_payload(output_ref="page:in"))

    def test_rejects_negative_and_boolean_integer_fields(self):
        with self.assertRaises(ValueError):
            RSSJob.from_mapping(job_payload(workspace_bytes=-1))
        with self.assertRaises(ValueError):
            RSSJob.from_mapping(job_payload(step_budget=True))

    def test_only_native_verified_kernel_is_dispatchable(self):
        job = RSSJob.from_mapping(job_payload())
        source_only = capability_manifest("cpu-1", [
            Capability("sparse_graph_apply", "source_written", 8192)
        ])
        self.assertFalse(dispatchable(source_only, job))
        verified = capability_manifest("cpu-1", [
            Capability("sparse_graph_apply", "native_verified", 8192, "kernel-sha")
        ])
        self.assertTrue(dispatchable(verified, job))

    def test_k256_source_written_is_not_dispatchable(self):
        job = RSSJob.from_mapping(job_payload(operator="k256_laplacian_u16"))
        manifest = capability_manifest("cpu-1", [
            Capability("k256_laplacian_u16", "source_written", 0, "")
        ])
        self.assertFalse(dispatchable(manifest, job))

    def test_k256_native_verified_manifest_is_dispatchable(self):
        job = RSSJob.from_mapping(job_payload(
            operator="k256_laplacian_u16", workspace_bytes=4096,
        ))
        manifest = capability_manifest("cpu-1", [
            Capability(
                "k256_laplacian_u16", "native_verified", 4096,
                "7288547abb4ef7e7d9c259ce991d9dccbdd4a0575ce1233bab80968f1278291f",
            )
        ])
        self.assertTrue(dispatchable(manifest, job))
        too_large = RSSJob.from_mapping(job_payload(
            operator="k256_laplacian_u16", workspace_bytes=4097,
        ))
        self.assertFalse(dispatchable(manifest, too_large))

    def test_workspace_and_digest_are_mandatory(self):
        job = RSSJob.from_mapping(job_payload(workspace_bytes=9000))
        small = capability_manifest("cpu-1", [
            Capability("sparse_graph_apply", "native_verified", 8192, "kernel-sha")
        ])
        self.assertFalse(dispatchable(small, job))
        with self.assertRaises(ValueError):
            Capability("sparse_graph_apply", "native_verified", 8192)
        self.assertEqual(canonical_digest({"b": 2, "a": 1}),
                         canonical_digest({"a": 1, "b": 2}))

    def test_result_envelope(self):
        payload = {
            "protocol": PROTOCOL, "job_id": "job-1", "status": "complete",
            "topology_digest": "topology-sha", "operator_digest": "op-sha",
            "output_digest": "out-sha", "residual_bound": "0",
            "saturation_count": 0, "iterations": 12,
            "runner_id": "cpu-1", "kernel_digest": "kernel-sha",
        }
        self.assertEqual(RSSResult.from_mapping(payload).status, "complete")
        with self.assertRaises(ValueError):
            RSSResult.from_mapping({**payload, "iterations": -1})


if __name__ == "__main__":
    unittest.main()
