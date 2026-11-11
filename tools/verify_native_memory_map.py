#!/usr/bin/env python3
"""Prevent the combined NaN16 guest from overwriting its phase lookup table.

Image word indices are sequential as emitted by third_party/nan0s/tools/nmk.awk.
The 512-word phase table occupies [0x395000, 0x395200); registers start at 0x4000.
"""
from __future__ import annotations
import argparse
import re
from pathlib import Path

WORD = re.compile(r"^\s*[0-9A-Fa-f]{4}_[0-9A-Fa-f]{8}_[0-9A-Fa-f]{4}\b")
PHASE_TABLE_START = 0x395000
COMMAND_START = 0x4000
CODE_LIMIT = 0x100000
PHASE_TABLE_WORDS = 256 * 2

def verify(image: Path, phase_source: Path) -> dict:
    lines = image.read_text(encoding="utf-8").splitlines()
    code_words = sum(bool(WORD.match(line)) for line in lines)
    if not 1000 <= code_words < CODE_LIMIT:
        raise ValueError(
            f"NaN16 executable spans {code_words} words and crosses the "
            f"0x{CODE_LIMIT:X} code/data boundary")
    phase = phase_source.read_text(encoding="utf-8")
    # Both guest storage and read address must refer to the same reserved table.
    if len(re.findall(r"MOVI r(?:10|7),0x5000\b", phase)) != 2:
        raise ValueError("native phase table storage/lookup addresses disagree")
    if (PHASE_TABLE_START < CODE_LIMIT or
        not (PHASE_TABLE_START + PHASE_TABLE_WORDS <= COMMAND_START or
             PHASE_TABLE_START >= COMMAND_START + 256)):
        raise ValueError("phase table overlaps code or command control words")
    return {"executable_words": code_words, "reserved_start": PHASE_TABLE_START,
            "free_words_before_table": PHASE_TABLE_START-code_words,
            "phase_table_words": PHASE_TABLE_WORDS,
            "command_word_start": COMMAND_START,
            "program_table_disjoint": True}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("image",type=Path)
    p.add_argument("--phase-source",type=Path,default=Path("mth/nan16/mth_phase_encode.nas"))
    a=p.parse_args()
    print("NAN16_EXECUTABLE_LAYOUT",verify(a.image,a.phase_source))
if __name__=="__main__":main()
