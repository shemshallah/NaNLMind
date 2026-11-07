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
CAPABILITIES = (
    "sparse_graph_apply",
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

    def __post_init__(self):
        if self.name not in CAPABILITIES:
            raise ValueError("unknown RSS capability")
        if self.status not in {"specified", "source_written", "native_verified"}:
            raise ValueError("invalid capability status")
        if self.max_workspace_bytes < 0:
            raise ValueError("negative workspace")
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
             "kernel_digest": c.kernel_digest}
            for c in sorted(capabilities, key=lambda x: x.name)
        ],
    }


def dispatchable(manifest: Mapping[str, Any], job: RSSJob) -> bool:
    """True only when a matching native-verified kernel and workspace exist."""
    if manifest.get("protocol") != PROTOCOL:
        return False
    for item in manifest.get("capabilities", []):
        if (item.get("name") == job.operator
                and item.get("status") == "native_verified"
                and item.get("max_workspace_bytes", -1) >= job.workspace_bytes
                and bool(item.get("kernel_digest"))):
            return True
    return False


def canonical_digest(obj: Mapping[str, Any]) -> str:
    raw = json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()
