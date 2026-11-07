"""Relational-Spectral runner contracts.

This module validates job/result envelopes and capability declarations only.
It deliberately contains no graph, spectral, wave, or numerical implementation:
those kernels belong in native NaN16 MTH.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping
import hashlib
import json

PROTOCOL = "NAN-RSS-1"
SPARSE_GRAPH_LAPLACIAN_Q16_16_SHA256 = "013048435c1026643554fb20e3434934cf059dd47cf2857577cac13ed5be6b8f"
SPARSE_WEIGHTED_GRAPH_LAPLACIAN_Q16_16_I64_V2_SHA256 = "8958bf432cd4052576d9b950d9e50c1853bc96d90bc3c50680bf9013ab36d613"
CAPABILITIES = (
    "k256_laplacian_u16",
    "sparse_graph_apply",
    "sparse_graph_laplacian_q16_16",
    "sparse_weighted_graph_laplacian_q16_16_i64_v2",
    "pair_space_apply",
    "fixed_point_vector",
    "polynomial_filter",
    "lanczos_symmetric",
    "wave_stepper",
    "fold_verified_symmetry",
)


@dataclass(frozen=True)
class Capability:
    name: str
    status: str
    max_workspace_bytes: int = 0
    kernel_digest: str = ""
    operator_version: int = 1
    q_format: str = ""

    def __post_init__(self):
        if self.name not in CAPABILITIES:
            raise ValueError("unknown RSS capability")
        if self.status not in {"specified", "source_written", "native_verified"}:
            raise ValueError("invalid capability status")
        if self.max_workspace_bytes < 0:
            raise ValueError("negative workspace")
        if type(self.operator_version) is not int or self.operator_version < 1:
            raise ValueError("invalid capability operator version")
        if self.q_format and not isinstance(self.q_format, str):
            raise ValueError("invalid capability Q format")
        if self.status == "native_verified" and not self.kernel_digest:
            raise ValueError("verified capability requires a kernel digest")


@dataclass(frozen=True)
class RSSJob:
    job_id: str
    universe_id: str
    topology_digest: str
    operator: str
    operator_version: int
    input_ref: str
    output_ref: str
    element_count: int
    q_format: str
    workspace_bytes: int
    step_budget: int
    cancellation_epoch: int
    parameters: Mapping[str, Any]

    @classmethod
    def from_mapping(cls, obj: Mapping[str, Any]) -> "RSSJob":
        if obj.get("protocol") != PROTOCOL:
            raise ValueError("unsupported RSS protocol")
        required = (
            "job_id", "universe_id", "topology_digest", "operator",
            "operator_version", "input_ref", "output_ref", "element_count",
            "q_format", "workspace_bytes", "step_budget",
            "cancellation_epoch", "parameters",
        )
        if any(k not in obj for k in required):
            raise ValueError("missing RSS job field")
        for key in ("job_id", "universe_id", "topology_digest", "operator",
                    "input_ref", "output_ref", "q_format"):
            if not isinstance(obj[key], str) or not obj[key]:
                raise ValueError("invalid RSS string field: " + key)
        for key in ("operator_version", "element_count", "workspace_bytes",
                    "step_budget", "cancellation_epoch"):
            if type(obj[key]) is not int or obj[key] < 0:
                raise ValueError("invalid RSS integer field: " + key)
        if obj["operator_version"] == 0:
            raise ValueError("operator version must be positive")
        if obj["input_ref"] == obj["output_ref"]:
            raise ValueError("input and output page refs must differ")
        if not isinstance(obj["parameters"], Mapping):
            raise ValueError("parameters must be an object")
        return cls(**{k: obj[k] for k in required})


@dataclass(frozen=True)
class RSSResult:
    job_id: str
    status: str
    topology_digest: str
    operator_digest: str
    output_digest: str
    residual_bound: str
    saturation_count: int
    iterations: int
    runner_id: str
    kernel_digest: str

    @classmethod
    def from_mapping(cls, obj: Mapping[str, Any]) -> "RSSResult":
        fields = tuple(cls.__dataclass_fields__)
        if obj.get("protocol") != PROTOCOL or any(k not in obj for k in fields):
            raise ValueError("invalid RSS result envelope")
        if obj["status"] not in {"complete", "rejected", "cancelled", "failed"}:
            raise ValueError("invalid RSS result status")
        for key in fields:
            if key in {"saturation_count", "iterations"}:
                if type(obj[key]) is not int or obj[key] < 0:
                    raise ValueError("invalid RSS result counter")
            elif not isinstance(obj[key], str):
                raise ValueError("invalid RSS result string")
        return cls(**{k: obj[k] for k in fields})


def capability_manifest(runner_id: str, capabilities: list[Capability]) -> dict[str, Any]:
    if not runner_id:
        raise ValueError("runner id is required")
    names = [c.name for c in capabilities]
    if len(names) != len(set(names)):
        raise ValueError("duplicate RSS capability")
    return {
        "protocol": PROTOCOL,
        "runner_id": runner_id,
        "capabilities": [
            {"name": c.name, "status": c.status,
             "max_workspace_bytes": c.max_workspace_bytes,
             "kernel_digest": c.kernel_digest,
             "operator_version": c.operator_version,
             "q_format": c.q_format}
            for c in sorted(capabilities, key=lambda x: x.name)
        ],
    }



def sparse_graph_laplacian_q16_16_capability() -> Capability:
    """Evidence record for the canonical NaN16 sparse CSR kernel.

    Callers should include this only for runners whose execution path is
    backed by the canonical NaN16 runtime. The source digest is exact; this
    is not a host-language implementation of the operator.
    """
    return Capability(
        name="sparse_graph_laplacian_q16_16",
        status="native_verified",
        max_workspace_bytes=4096,
        kernel_digest=SPARSE_GRAPH_LAPLACIAN_Q16_16_SHA256,
        operator_version=1,
        q_format="Q16.16/I32",
    )



def sparse_weighted_graph_laplacian_q16_16_i64_v2_capability() -> Capability:
    """Evidence for the canonical NaN16 weighted CSR v2 kernel."""
    return Capability(
        name="sparse_weighted_graph_laplacian_q16_16_i64_v2",
        status="native_verified",
        max_workspace_bytes=4096,
        kernel_digest=SPARSE_WEIGHTED_GRAPH_LAPLACIAN_Q16_16_I64_V2_SHA256,
        operator_version=2,
        q_format="Q16.16/I32->I64;U8W",
    )


def dispatchable(manifest: Mapping[str, Any], job: RSSJob) -> bool:
    """True only when a matching native-verified kernel and workspace exist."""
    if manifest.get("protocol") != PROTOCOL:
        return False
    for item in manifest.get("capabilities", []):
        if (item.get("name") == job.operator
                and item.get("status") == "native_verified"
                and item.get("max_workspace_bytes", -1) >= job.workspace_bytes
                and bool(item.get("kernel_digest"))
                and item.get("operator_version", 1) == job.operator_version
                and (not item.get("q_format") or item.get("q_format") == job.q_format)):
            return True
    return False


def canonical_digest(obj: Mapping[str, Any]) -> str:
    raw = json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()
