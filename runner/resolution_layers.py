"""Canonical stored-evidence resolution layers for NaNLMind.

These L0-L9 resolutions describe the granularity at which evidence is stored.
They are not NANNET's M0-M9 processing transformations and are not the
router's address/head/bin mapping stages.
"""
from __future__ import annotations

RESOLUTION_SCHEMA = "nanlm.resolution-layer.v1"

RESOLUTION_LAYERS = (
    "bit",             # L0
    "nibble",          # L1
    "byte",            # L2
    "phonetic",        # L3
    "morpheme",        # L4
    "lexical",         # L5
    "word_completion", # L6
    "sentence",        # L7
    "paragraph",       # L8
    "narrative",       # L9
)

# Only stages whose output granularity is explicit are assigned here.
# Boolean and deep-logic stages remain unassigned: their semantic task type
# does not, by itself, establish a stored-evidence resolution.
STAGE_RESOLUTION = {
    "common_words": 5,
    "repetitive_words": 5,
    "word_choice": 6,
    "sentences": 7,
}


def resolution_metadata(stage: str) -> dict:
    index = STAGE_RESOLUTION.get(stage)
    if index is None:
        return {
            "resolution_schema": RESOLUTION_SCHEMA,
            "resolution": None,
            "resolution_name": None,
        }
    return {
        "resolution_schema": RESOLUTION_SCHEMA,
        "resolution": index,
        "resolution_name": RESOLUTION_LAYERS[index],
    }


def validate_resolution(index: int, name: str | None = None) -> bool:
    if isinstance(index, bool) or not isinstance(index, int):
        return False
    if not 0 <= index < len(RESOLUTION_LAYERS):
        return False
    return name is None or name == RESOLUTION_LAYERS[index]
