"""Strict parser and canonical identity for hierarchical NaN rawroutes.

This is a name/address layer above the existing N16B/1 transport route. It
intentionally does not alter RunnerRoute or the six-byte wire representation.
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from typing import Optional

_COORD = r"(?:0|[1-9][0-9]{0,2})"
_HEADS = r"(?:0|[1-9][0-9]{0,2})(?:,(?:0|[1-9][0-9]{0,2}))*"
_OBJECT_KINDS = {"vector", "hyperedge", "memory", "transform"}
_RAWROUTE = re.compile(
    rf"nan://GM({_COORD}):SC({_COORD}):MC({_COORD}):"
    rf"BS({_COORD}):({_COORD}):HW({_COORD}):({_COORD})"
    rf"::HW({_COORD}):({_HEADS})"
    rf"(?:::([a-z][a-z0-9_-]*)(0|[1-9][0-9]{0,9}))?"
)


def _byte(value: str, label: str) -> int:
    number = int(value)
    if not 0 <= number <= 255:
        raise ValueError(f"{label} coordinate must be 0..255")
    return number


@dataclass(frozen=True)
class TypedObjectRef:
    kind: str
    object_id: int

    def __post_init__(self) -> None:
        if self.kind not in _OBJECT_KINDS:
            raise ValueError("unsupported rawroute object kind")
        if isinstance(self.object_id, bool) or not isinstance(self.object_id, int):
            raise ValueError("object id must be an integer")
        if not 0 <= self.object_id <= 0xFFFFFFFF:
            raise ValueError("object id must be uint32")

    def text(self) -> str:
        return f"{self.kind}{self.object_id}"


@dataclass(frozen=True)
class RawTarget:
    hardware_kind: int
    heads: tuple[int, ...]

    def __post_init__(self) -> None:
        if isinstance(self.hardware_kind, bool) or not isinstance(self.hardware_kind, int) or not 0 <= self.hardware_kind <= 255:
            raise ValueError("target hardware kind must be 0..255")
        if not self.heads or len(self.heads) > 256:
            raise ValueError("rawroute requires 1..256 target heads")
        if any(isinstance(h, bool) or not isinstance(h, int) or not 0 <= h <= 255
               for h in self.heads):
            raise ValueError("head indices must be 0..255")
        if tuple(sorted(set(self.heads))) != self.heads:
            raise ValueError("head indices must be strictly increasing and unique")

    def text(self) -> str:
        return f"HW{self.hardware_kind}:" + ",".join(str(h) for h in self.heads)


@dataclass(frozen=True)
class RawRoute:
    gm: int
    sc: int
    mc: int
    bs: int
    bs_node: int
    hw: int
    hw_node: int
    target: RawTarget
    object_ref: Optional[TypedObjectRef] = None

    def __post_init__(self) -> None:
        coordinates = (self.gm, self.sc, self.mc, self.bs, self.bs_node,
                       self.hw, self.hw_node)
        if any(isinstance(v, bool) or not isinstance(v, int) or not 0 <= v <= 255
               for v in coordinates):
            raise ValueError("rawroute hierarchy coordinates must be bytes")
        if not isinstance(self.target, RawTarget):
            raise ValueError("rawroute target must be a RawTarget")
        if self.target.hardware_kind != self.hw:
            raise ValueError("local target hardware kind must match network HW")
        if self.object_ref is not None and not isinstance(self.object_ref, TypedObjectRef):
            raise ValueError("object_ref must be a TypedObjectRef")

    def text(self) -> str:
        value = (f"nan://GM{self.gm}:SC{self.sc}:MC{self.mc}:"
                 f"BS{self.bs}:{self.bs_node}:HW{self.hw}:{self.hw_node}"
                 f"::{self.target.text()}")
        if self.object_ref is not None:
            value += "::" + self.object_ref.text()
        return value

    @property
    def definition_id(self) -> str:
        """Stable ID for this exact canonical route definition."""
        return hashlib.sha256(self.text().encode("ascii")).hexdigest()

    @classmethod
    def parse(cls, value: str) -> "RawRoute":
        if not isinstance(value, str):
            raise ValueError("rawroute must be text")
        match = _RAWROUTE.fullmatch(value)
        if match is None:
            raise ValueError("rawroute syntax or canonical decimal form rejected")
        (gm, sc, mc, bs, bs_node, hw, ring,
         target_hw, heads, object_kind, object_id) = match.groups()

        gm_i = _byte(gm, "GM")
        sc_i = _byte(sc, "SC")
        mc_i = _byte(mc, "MC")
        bs_i = _byte(bs, "BS")
        bs_node_i = _byte(bs_node, "BS node")
        hw_i = _byte(hw, "HW")
        hw_node_i = _byte(ring, "HW network node")
        target_hw_i = _byte(target_hw, "target HW")
        if target_hw_i != hw_i:
            raise ValueError("local target hardware kind must match network HW")

        head_values = tuple(_byte(part, "head") for part in heads.split(","))
        target = RawTarget(target_hw_i, head_values)

        object_ref = None
        if object_kind is not None:
            if object_kind not in _OBJECT_KINDS:
                raise ValueError("unsupported rawroute object kind")
            object_number = int(object_id)
            if object_number > 0xFFFFFFFF:
                raise ValueError("object id must be uint32")
            object_ref = TypedObjectRef(object_kind, object_number)

        route = cls(gm_i, sc_i, mc_i, bs_i, bs_node_i, hw_i, hw_node_i,
                    target, object_ref)
        if route.text() != value:
            raise ValueError("rawroute is not in canonical form")
        return route


def parse_rawroute(value: str) -> RawRoute:
    """Public convenience entry point."""
    return RawRoute.parse(value)
