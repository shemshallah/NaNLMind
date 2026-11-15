#!/usr/bin/env python3
"""Cross-check the Coq p=9 trace against the native NaN16 fixture image."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
NAS = ROOT / "mth/tests/mth_minsky_compiler_general_test.nas"
COQ = ROOT / "formal/utm/MinskyWideFixture.v"


def nat_list(text: str, name: str) -> list[int]:
    m = re.search(rf"Definition {name} : list nat :=\s*\[(.*?)\]\.", text, re.S)
    if not m:
        raise SystemExit(f"missing {name} in {COQ}")
    return [int(x) for x in re.findall(r"\d+", m.group(1))]


def main() -> int:
    nas = NAS.read_text()
    m = re.search(r"expected:\n\s*\.word ([^\n]+)", nas)
    if not m:
        raise SystemExit("missing native expected array")
    native_expected = [int(x) for x in m.group(1).split(",") if x.strip()]

    coq = COQ.read_text()
    coq_final = nat_list(coq, "wide_fixture_final_cells")
    coq_initial = nat_list(coq, "wide_fixture_initial_cells")

    if native_expected != coq_final:
        for i, (a, b) in enumerate(zip(native_expected, coq_final)):
            if a != b:
                raise SystemExit(f"final image differs at cell {i}: native={a} coq={b}")
        raise SystemExit("final image lengths differ")

    # The native guest writes a 94-cell image beginning at working cell 24.
    if len(coq_initial) != 94 or len(coq_final) != 94:
        raise SystemExit("unexpected p=9 image length")
    print("PASS native/Coq p=9 compiler image and final tape agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
