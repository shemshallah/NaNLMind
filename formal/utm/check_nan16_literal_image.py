#!/usr/bin/env python3
"""Check the in-repo literal NaN16 image dumps for ISA-OBL-2.

The Coq file [MinskyNaN16LiteralImage.v] proves slice facts about
[LiteralImageData.literal_image].  This script anchors that Coq list to the
assembled text image and to the pinned assembler output.

Artifacts (all paths relative to the repository root):

  mth/tests/mth_minsky_test.nas
      pinned source, sha256
      173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e
  formal/utm/data/mth_minsky_test.nan
      exact assembler text output ("LC_ALL=C gawk -f nmk.awk -v CMD=emit"),
      4366 words, 141409 bytes, sha256
      f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77
  formal/utm/data/mth_minsky_test.words
      one lowercase 16-hex-digit word per line, 4366 lines, sha256
      43fbe83226221463b91d99862eba53cdb61a2fb7ba59d397abc755af4522a7d7
  formal/utm/LiteralImageData.v
      generated Coq [N] list; must equal the .words file.

The script does not run Coq.  Use [coqc] on the two Coq files for that.

Exit codes: 0 all checks pass, 1 a check failed, 2 usage/IO error.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

NAS = ROOT / "mth/tests/mth_minsky_test.nas"
NAN = ROOT / "formal/utm/data/mth_minsky_test.nan"
WORDS = ROOT / "formal/utm/data/mth_minsky_test.words"
COQ = ROOT / "formal/utm/LiteralImageData.v"

NAS_SHA256 = "173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e"
NAN_SHA256 = "f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77"
WORDS_SHA256 = "43fbe83226221463b91d99862eba53cdb61a2fb7ba59d397abc755af4522a7d7"
NAN_NMK_SHA256 = "587116bdffc7715d0dffd6846767dbda76a9d14b55085e9ed8ed08cbdfe1009b"
WORD_COUNT = 4366

LINE_RE = re.compile(
    r"^([0-9A-F]{4})_([0-9A-F]{8})_([0-9A-F]{4})\s+;\s+(\d+)\b"
)
COQ_WORD_RE = re.compile(r"^\s*0x([0-9A-Fa-f]{16})\s*;?\s*$")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def parse_nan(path: Path) -> list[str]:
    words: list[str] = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        match = LINE_RE.match(line)
        if not match:
            continue
        index = int(match.group(4))
        if index != len(words):
            raise ValueError(
                f"{path.name}:{lineno}: word index {index}, expected {len(words)}"
            )
        words.append((match.group(1) + match.group(2) + match.group(3)).lower())
    return words


def parse_words(path: Path) -> list[str]:
    words = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    bad = [w for w in words if not re.fullmatch(r"[0-9a-f]{16}", w)]
    if bad:
        raise ValueError(f"{path.name}: malformed word line {bad[0]!r}")
    return words


def parse_coq_words(path: Path) -> list[str]:
    words: list[str] = []
    inside = False
    for line in path.read_text().splitlines():
        if line.startswith("Definition literal_image : list N := ["):
            inside = True
            continue
        if not inside:
            continue
        if line.strip() == "].":
            break
        match = COQ_WORD_RE.match(line)
        if match:
            words.append(match.group(1).lower())
    return words


def coq_source(words: list[str]) -> str:
    """Regenerate LiteralImageData.v from the word dump."""
    out = [
        "(** * Literal assembled image of [mth/tests/mth_minsky_test.nas]",
        "",
        "",
        "    GENERATED FILE.  Do not hand-edit.  Regenerate with",
        "    [python3 formal/utm/check_nan16_literal_image.py --regenerate-coq].",
        "",
        "    Source text: [formal/utm/data/mth_minsky_test.nan], the exact",
        "    [LC_ALL=C gawk -f third_party/nan0s/tools/nmk.awk -v CMD=emit]",
        "    output for the pinned fixture source",
        "    (sha256 173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e,",
        "    assembler sha256 587116bdffc7715d0dffd6846767dbda76a9d14b55085e9ed8ed08cbdfe1009b).",
        "",
        "    Assembled image pin (over the exact .nan text bytes):",
        "      f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77",
        "",
        "    Word dump pin (over [mth_minsky_test.words], one 16-hex-digit",
        "    word per line, 4366 lines):",
        "      43fbe83226221463b91d99862eba53cdb61a2fb7ba59d397abc755af4522a7d7",
        "",
        "    The [literal_image] list below is this word dump in Coq [N]",
        "    syntax.  [check_nan16_literal_image.py] checks the three",
        "    representations against each other. *)",
        "",
        "From Coq Require Import List Arith NArith.",
        "Import ListNotations.",
        "Open Scope N_scope.",
        "",
        "Definition literal_image_sha256 : N :=",
        "  0xF78CCB99EB0843B849A2560E0D27A09606C787A94366562A6A90B2C606C0BF77.",
        "",
        "Definition literal_words_sha256 : N :=",
        "  0x43FBE83226221463B91D99862EBA53CDB61A2FB7BA59D397ABC755AF4522A7D7.",
        "",
        "Definition literal_image : list N := [",
    ]
    for i, word in enumerate(words):
        out.append(f"  0x{word.upper()}{';' if i + 1 < len(words) else ''}")
    out.extend(
        [
            "].",
            "",
            "Lemma literal_image_length : length literal_image = 4366%nat.",
            "Proof. vm_compute. reflexivity. Qed.",
            "",
        ]
    )
    return "\n".join(out) + "\n"


class Checker:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.passed = 0

    def check(self, name: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.passed += 1
            print(f"ok   {name}")
        else:
            self.failures.append(f"{name}: {detail}" if detail else name)
            print(f"FAIL {name}" + (f": {detail}" if detail else ""))

    def finish(self) -> int:
        print()
        if self.failures:
            print(f"{len(self.failures)} check(s) failed, {self.passed} passed")
            for failure in self.failures:
                print(f"  - {failure}")
            return 1
        print(f"all {self.passed} checks passed")
        return 0


def check_assembled(verbose: bool) -> int:
    """Re-run the pinned assembler from HEAD and compare the image."""
    checker = Checker()
    nas = NAS
    checker.check(
        "pinned .nas source hash",
        sha256_file(nas) == NAS_SHA256,
        f"got {sha256_file(nas)}",
    )
    try:
        assembler = subprocess.run(
            ["git", "show", "HEAD:third_party/nan0s/tools/nmk.awk"],
            cwd=ROOT,
            check=True,
            capture_output=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"cannot read pinned assembler from git: {exc}", file=sys.stderr)
        return 2
    checker.check(
        "pinned assembler hash",
        sha256_bytes(assembler) == NAN_NMK_SHA256,
        f"got {sha256_bytes(assembler)}",
    )
    with tempfile.TemporaryDirectory() as tmp:
        nmk = Path(tmp) / "nmk.awk"
        nmk.write_bytes(assembler)
        output = Path(tmp) / "minsky.nan"
        labels = Path(tmp) / "minsky.labels"
        result = subprocess.run(
            [
                "gawk",
                "-f",
                str(nmk),
                "-v",
                "CMD=emit",
                "-v",
                f"LABELS={labels}",
                str(nas),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            env={**os.environ, "LC_ALL": "C"},
        )
        if result.returncode != 0:
            print(result.stderr.decode(errors="replace"), file=sys.stderr)
        checker.check("assembler exit status", result.returncode == 0)
        if result.returncode == 0:
            output.write_bytes(result.stdout)
            text = output.read_bytes()
            checker.check(
                "assembled image hash",
                sha256_bytes(text) == NAN_SHA256,
                f"got {sha256_bytes(text)}",
            )
            checker.check(
                "assembled word count",
                len(parse_nan(output)) == WORD_COUNT,
                f"got {len(parse_nan(output))}",
            )
            checker.check(
                "byte-identical to in-repo .nan",
                text == NAN.read_bytes(),
            )
            if verbose and labels.exists():
                print("\nlabels:")
                print("\n".join(sorted(labels.read_text().splitlines(), key=lambda s: int(s.split()[1]))))
    return checker.finish()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--assemble",
        action="store_true",
        help="re-run the pinned assembler from git HEAD and compare the image",
    )
    parser.add_argument(
        "--regenerate-coq",
        action="store_true",
        help="rewrite LiteralImageData.v from the checked word dump",
    )
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if args.assemble:
        return check_assembled(args.verbose)

    checker = Checker()
    try:
        nas_hash = sha256_file(NAS)
        nan_hash = sha256_file(NAN)
        words_hash = sha256_file(WORDS)
        nan_words = parse_nan(NAN)
        word_words = parse_words(WORDS)
        coq_words = parse_coq_words(COQ)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    checker.check("pinned .nas source hash", nas_hash == NAS_SHA256, f"got {nas_hash}")
    checker.check("assembled image hash", nan_hash == NAN_SHA256, f"got {nan_hash}")
    checker.check("word dump hash", words_hash == WORDS_SHA256, f"got {words_hash}")
    checker.check(
        "assembled word count",
        len(nan_words) == WORD_COUNT,
        f"got {len(nan_words)}",
    )
    checker.check(
        "word dump length",
        len(word_words) == WORD_COUNT,
        f"got {len(word_words)}",
    )
    checker.check(
        "word dump equals parsed .nan",
        word_words == nan_words,
        "first mismatch at "
        + str(next((i for i, (a, b) in enumerate(zip(word_words, nan_words)) if a != b), "length")),
    )
    checker.check(
        "Coq dump length",
        len(coq_words) == WORD_COUNT,
        f"got {len(coq_words)}",
    )
    checker.check(
        "Coq dump equals word dump",
        coq_words == word_words,
        "first mismatch at "
        + str(next((i for i, (a, b) in enumerate(zip(coq_words, word_words)) if a != b), "length")),
    )
    if args.regenerate_coq:
        expected = coq_source(word_words)
        if COQ.read_text() == expected:
            print("LiteralImageData.v already up to date")
        else:
            COQ.write_text(expected)
            print("rewrote LiteralImageData.v from word dump")

    # Coq-side constants that the image file proves against.
    checker.check(
        "literal word 0",
        nan_words[0] == "fff801d00001f8ff",
        f"got {nan_words[0]}",
    )
    checker.check(
        "table base 104 is a data word",
        nan_words[104].endswith("f87f"),
        f"got {nan_words[104]}",
    )
    checker.check(
        "tape base cell 99 payload is 4096",
        int(nan_words[99][4:12], 16) == 4096,
        f"got {int(nan_words[99][4:12], 16)}",
    )
    return checker.finish()


if __name__ == "__main__":
    sys.exit(main())
