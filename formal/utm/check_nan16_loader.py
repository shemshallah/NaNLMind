#!/usr/bin/env python3
"""Fail-closed gate for the literal ``.nan`` image loader path and byte order.

This gate connects three things that were previously only checked separately:

  * the exact assembler text image
    ``formal/utm/data/mth_minsky_test.nan``;
  * the raw-word dump
    ``formal/utm/data/mth_minsky_test.words``;
  * the Coq transcription ``LiteralImageData.literal_image``.

It models the actual external runner path, not a new parser:

    nan_cli.c:slurp(--img)
      -> nan_load_auto(data, len, &kind)
      -> nan_load_text(...)                      # for a text .nan image
      -> v->mem[idx++] = near << 48 | payload << 16 | far_swapped

The model is deliberately strict and fail-closed:

  * the image must not carry a ``NAN1`` state header or a 55 AA floppy header,
    and must pass the ``nan_load_auto`` text probe;
  * every non-comment line must be a whole ``NEAR_PAYLOAD_FAR`` word with the
    loader's exact 4/8/4 hex columns and a matching word-index comment;
  * every NEAR/FAR head must be one of the four canonical heads, and the FAR
    field must be stored byte-swapped, as the text loader and ``nan_mkword``
    assume;
  * the 32-bit payload must be the little-endian byte group 2 of the raw
    64-bit word, matching ``nan16.c``'s ``(w >> 16) & 0xFFFFFFFF`` projection
    and the Coq ``word_payload`` definition;
  * the reconstructed raw words must equal the pinned ``.words`` dump and the
    Coq ``literal_image`` list, word for word;
  * the external loader source files must match the pins recorded in
    ``NAN0S_ISA_SPEC.md`` section 1.6 / the pinned checkout.

The gate does not compile Coq or C.  A missing or changed loader file is a
failure, never a skip.  Missing/unreadable in-repo artifacts are failures too.

Exit codes: 0 all checks pass, 1 a contract check failed, 2 usage error.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

NAS = ROOT / "mth/tests/mth_minsky_test.nas"
NAN = ROOT / "formal/utm/data/mth_minsky_test.nan"
WORDS = ROOT / "formal/utm/data/mth_minsky_test.words"
COQ_DATA = ROOT / "formal/utm/LiteralImageData.v"
COQ_IMAGE = ROOT / "formal/utm/MinskyNaN16LiteralImage.v"

# ---------------------------------------------------------------------------
# Pins
# ---------------------------------------------------------------------------

NAS_SHA256 = "173666f7635ffa3c942a6a251eb9c4874e686a45df0ca68c97ad50e9195d112e"
NAN_SHA256 = "f78ccb99eb0843b849a2560e0d27a09606c787a94366562a6a90b2c606c0bf77"
WORDS_SHA256 = "43fbe83226221463b91d99862eba53cdb61a2fb7ba59d397abc755af4522a7d7"

# The generated Coq list is content-addressed by this gate.  Its two hash
# constants are checked separately below, so a list edit or a constant edit
# both fail.
COQ_DATA_SHA256 = "9057006e04a8f143a6fca176dba48cd320b6b799e21a7cc89951fb2a617b7194"

WORD_COUNT = 4366
NAN_BYTES = 141_409
WORDS_BYTES = 74_222

# NAN0S_ISA_SPEC.md section 1.6: the external fixture runner used for the
# oracle observation is a separate checkout at this commit.  The file hashes
# below are the ones that path was inspected at.  nan_cli.c and nan_load.c are
# the loader path proper; nan16.c/nan16.h/nan16_int.h are pinned at the same
# checkout because the text loader stores into that VM's raw-word memory and
# the payload/head accessors live there.
LOADER_COMMIT = "80bc81dbf892ca72719882ddd02691f23083785c"

LOADER_FILES = (
    ("aarch64/android/tools/nan_cli.c", "19a1406e4593281f91313075fa9c6ca5d84d5ec0daa68e55f90f296b80a749ae", 16_246),
    ("aarch64/android/core/nan_load.c", "9542130a226e117a7d98fafe1d248db12809588f6eadd24ae6a63d8252219566", 3_262),
    ("aarch64/android/core/nan16.c", "7ed977607efb8f57c7bed802f9dffdf349ad3dc1cecd7fe379b59f4839b23d41", 30_272),
    ("aarch64/android/core/nan16.h", "740ea2cb17fcc3e1903c2566cde815a533432f9bad3023c4a85c906dc742e414", 9_127),
    ("aarch64/android/core/nan16_int.h", "959f90b7b92a70bc34bbe3d943186dddda442cee1cbc0b5a5dacf527b863a022", 2_984),
)

CANONICAL_HEADS = (0x7FF1, 0xFFF1, 0x7FF8, 0xFFF8)
CANONICAL_FAR_STORED = tuple(((h >> 8) | ((h & 0xFF) << 8)) for h in CANONICAL_HEADS)

NAN_LINE_RE = re.compile(r"^([0-9A-F]{4})_([0-9A-F]{8})_([0-9A-F]{4})$")
NAN_COMMENT_INDEX_RE = re.compile(r"^\s*(\d+)\b")
WORDS_LINE_RE = re.compile(r"^[0-9a-f]{16}$")
COQ_WORD_RE = re.compile(r"^0x([0-9A-Fa-f]{16})(;?)$")

C_SPACE = frozenset(b" \t\n\v\f\r")


class GateError(RuntimeError):
    """A fail-closed loader/image contract error."""


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def swap16(x: int) -> int:
    return ((x >> 8) | ((x & 0xFF) << 8)) & 0xFFFF


def hvalid(h: int) -> bool:
    return (h & 0x7FF0) == 0x7FF0 and (h & 0xF) in (1, 8)


def hcls(h: int) -> int:
    return ((h >> 2) & 2) | (h >> 15)


def words_for_mb(mb: int) -> int:
    """nan_cli.c:words_for_mb, including its 2^28-word ceiling."""
    want = (mb * 1024 * 1024 + 3) // 4
    p = 0x10000
    while p < want and p < 0x10000000:
        p <<= 1
    return p


def first_false(flags: list[bool]) -> int | None:
    return next((i for i, ok in enumerate(flags) if not ok), None)


def first_difference(a: list[int], b: list[int]) -> int | None:
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    if len(a) != len(b):
        return min(len(a), len(b))
    return None


def read_file(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError as exc:
        raise GateError(f"cannot read {path}: {exc}") from exc


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="strict")
    except (OSError, UnicodeError) as exc:
        raise GateError(f"cannot read {path}: {exc}") from exc


def resolve_loader_root(cli_value: str | None) -> Path:
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    for env_name in ("NAN0S_WORK", "NAN0S_ROOT"):
        value = os.environ.get(env_name)
        if value:
            return Path(value).expanduser().resolve()
    candidates = (ROOT.parent / "nan0s_work", Path.home() / "nan0s_work")
    for candidate in candidates:
        if (candidate / "aarch64/android/tools/nan_cli.c").is_file():
            return candidate.resolve()
    return candidates[0].resolve()


# ---------------------------------------------------------------------------
# Loader-text and artifact models
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Word:
    index: int
    near: int
    payload: int
    far_stored: int

    @property
    def raw(self) -> int:
        return (self.near << 48) | (self.payload << 16) | self.far_stored

    @property
    def far(self) -> int:
        return swap16(self.far_stored)

    @property
    def n(self) -> int:
        return (hcls(self.near) << 2) | hcls(self.far)

    def describe(self) -> str:
        return (
            f"word {self.index}: raw={self.raw:016x} near={self.near:04x} "
            f"payload={self.payload:08x} far_stored={self.far_stored:04x} "
            f"far={self.far:04x}"
        )


@dataclass
class NanImage:
    words: list[Word]
    header: str
    comment_lines: int


def parse_nan_as_loader(data: bytes) -> NanImage:
    """Strict model of nan_load_text on the dense fixture image.

    The C loader strips at ``;``, skips blank/comment-only lines, supports
    ``.org``, and otherwise requires columns 4 and 13 to be underscores with
    4/8/4 hex fields.  The fixture is a dense image: ``.org`` would change the
    word/comment-index contract, so it is rejected here and must be re-pinned.
    """
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as exc:
        raise GateError(f".nan is not ASCII text: {exc}") from exc

    lines = text.split("\n")
    if not lines or not lines[0].startswith("; NaN16 guest program"):
        raise GateError("missing literal image header comment on line 1")

    words: list[Word] = []
    comments = 0
    for lineno, line in enumerate(lines, 1):
        if line.endswith("\r"):
            line = line[:-1]
        body, sep, comment = line.partition(";")
        if not sep:
            if body.strip():
                raise GateError(f"{NAN.name}:{lineno}: missing ';' comment/index")
            continue
        comments += 1
        body = body.strip()
        if not body:
            continue
        if body.startswith(".org"):
            raise GateError(
                f"{NAN.name}:{lineno}: unexpected .org in dense literal image"
            )
        if len(body) != 18:
            raise GateError(
                f"{NAN.name}:{lineno}: word text length {len(body)}, expected 18"
            )
        match = NAN_LINE_RE.match(body)
        if not match:
            raise GateError(
                f"{NAN.name}:{lineno}: not NEAR_PAYLOAD_FAR at 4/8/4 columns"
            )
        index_match = NAN_COMMENT_INDEX_RE.match(comment)
        if not index_match:
            raise GateError(f"{NAN.name}:{lineno}: missing numeric word index")
        index = int(index_match.group(1))
        if index != len(words):
            raise GateError(
                f"{NAN.name}:{lineno}: word index {index}, expected {len(words)}"
            )
        near = int(match.group(1), 16)
        payload = int(match.group(2), 16)
        far_stored = int(match.group(3), 16)
        words.append(Word(index, near, payload, far_stored))

    if not words:
        raise GateError(f"{NAN.name}: no word lines")
    return NanImage(words, lines[0], comments)


def parse_words(data: bytes) -> list[int]:
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as exc:
        raise GateError(f"{WORDS.name} is not ASCII: {exc}") from exc
    if not text.endswith("\n"):
        raise GateError(f"{WORDS.name}: missing trailing newline")
    lines = text.splitlines()
    words: list[int] = []
    for lineno, line in enumerate(lines, 1):
        if not WORDS_LINE_RE.fullmatch(line):
            raise GateError(
                f"{WORDS.name}:{lineno}: not 16 lowercase hex digits: {line!r}"
            )
        words.append(int(line, 16))
    return words


def parse_coq_literal_image(text: str) -> list[int]:
    """Parse the generated Coq list strictly, one hexadecimal word per line."""
    lines = text.splitlines()
    starts = [
        i
        for i, line in enumerate(lines)
        if line.strip() == "Definition literal_image : list N := ["
    ]
    if len(starts) != 1:
        raise GateError(
            f"{COQ_DATA.name}: expected one literal_image definition, found {len(starts)}"
        )
    start = starts[0]
    words: list[int] = []
    end = None
    for lineno in range(start + 1, len(lines)):
        stripped = lines[lineno].strip()
        if stripped == "].":
            end = lineno
            break
        match = COQ_WORD_RE.fullmatch(stripped)
        if not match:
            raise GateError(
                f"{COQ_DATA.name}:{lineno + 1}: malformed literal_image line {stripped!r}"
            )
        words.append(int(match.group(1), 16))
    if end is None:
        raise GateError(f"{COQ_DATA.name}: unterminated literal_image list")
    for offset, line in enumerate(lines[start + 1 : end]):
        stripped = line.strip()
        has_semicolon = stripped.endswith(";")
        if offset + 1 < len(words):
            if not has_semicolon:
                raise GateError(
                    f"{COQ_DATA.name}:{start + offset + 2}: missing list separator"
                )
        elif has_semicolon:
            raise GateError(
                f"{COQ_DATA.name}:{end + 1}: trailing list separator on last word"
            )
    return words


def parse_coq_hash_definitions(text: str) -> dict[str, int]:
    pattern = re.compile(
        r"Definition\s+(literal_image_sha256|literal_words_sha256)\s*:\s*N\s*:=\s*"
        r"0x([0-9A-Fa-f]{64})\s*\.",
        re.DOTALL,
    )
    found = {name: int(value, 16) for name, value in pattern.findall(text)}
    if len(found) != 2:
        raise GateError(
            f"{COQ_DATA.name}: expected both literal hash definitions, found "
            f"{sorted(found)}"
        )
    return found


def auto_kind(data: bytes) -> tuple[str, bool]:
    """Model nan_load_auto's header dispatch and return (kind, texty).

    The text kind is only assumed loadable after parse_nan_as_loader succeeds.
    """
    if len(data) >= 16 and data[:4] == b"NAN1":
        return "state", False
    if len(data) >= 0x2200 + 8 and data[510] == 0x55 and data[511] == 0xAA:
        return "floppy", False
    if len(data) == 1_474_560:
        return "floppy", False

    texty = len(data) > 0
    for byte in data[: min(len(data), 4096)]:
        if byte >= 0x80 or (byte < 32 and byte not in C_SPACE):
            texty = False
            break
    if texty:
        return "nan-text", True
    if len(data) % 8 == 0 and len(data) >= 8:
        word0 = int.from_bytes(data[:8], "little")
        if hvalid(word0 >> 48) and hvalid(swap16(word0 & 0xFFFF)):
            return "words", False
    return "", False


# ---------------------------------------------------------------------------
# Checker
# ---------------------------------------------------------------------------


class Checker:
    def __init__(self, verbose: bool = False) -> None:
        self.failures: list[str] = []
        self.passed = 0
        self.verbose = verbose

    def section(self, title: str) -> None:
        print(f"\n== {title} ==")

    def note(self, message: str) -> None:
        print(f"NOTE {message}")

    def check(self, name: str, condition: bool, detail: str = "") -> bool:
        if condition:
            self.passed += 1
            print(f"ok   {name}")
        else:
            message = f"{name}: {detail}" if detail else name
            self.failures.append(message)
            print(f"FAIL {name}" + (f": {detail}" if detail else ""))
        return condition

    def fail(self, name: str, detail: str) -> None:
        self.check(name, False, detail)

    def finish(self) -> int:
        print()
        if self.failures:
            print(f"{len(self.failures)} check(s) failed, {self.passed} passed")
            for failure in self.failures:
                print(f"  - {failure}")
            return 1
        print(f"all {self.passed} checks passed")
        return 0


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------


def check_artifacts(checker: Checker) -> tuple[bytes | None, bytes | None, str | None]:
    checker.section("pinned artifacts")

    nas_data = None
    nan_data = None
    words_data = None
    coq_data_text = None

    try:
        nas_data = read_file(NAS)
        checker.check(
            ".nas source size",
            len(nas_data) == 7_827,
            f"got {len(nas_data)} bytes",
        )
        checker.check(
            ".nas source hash",
            sha256_bytes(nas_data) == NAS_SHA256,
            f"got {sha256_bytes(nas_data)}",
        )
    except GateError as exc:
        checker.fail(".nas source readable", str(exc))

    try:
        nan_data = read_file(NAN)
        checker.check(
            ".nan image size",
            len(nan_data) == NAN_BYTES,
            f"got {len(nan_data)} bytes, expected {NAN_BYTES}",
        )
        nan_hash = sha256_bytes(nan_data)
        checker.check(
            ".nan image hash",
            nan_hash == NAN_SHA256,
            f"got {nan_hash}",
        )
    except GateError as exc:
        checker.fail(".nan image readable", str(exc))

    try:
        words_data = read_file(WORDS)
        checker.check(
            ".words dump size",
            len(words_data) == WORDS_BYTES,
            f"got {len(words_data)} bytes, expected {WORDS_BYTES}",
        )
        words_hash = sha256_bytes(words_data)
        checker.check(
            ".words dump hash",
            words_hash == WORDS_SHA256,
            f"got {words_hash}",
        )
    except GateError as exc:
        checker.fail(".words dump readable", str(exc))

    try:
        coq_data_text = read_text(COQ_DATA)
        coq_hash = sha256_bytes(coq_data_text.encode("utf-8"))
        checker.check(
            "LiteralImageData.v hash",
            coq_hash == COQ_DATA_SHA256,
            f"got {coq_hash}",
        )
    except GateError as exc:
        checker.fail("LiteralImageData.v readable", str(exc))

    try:
        coq_image_text = read_text(COQ_IMAGE)
        checker.check(
            "MinskyNaN16LiteralImage.v literal_image pin alias",
            "Definition literal_image_pin : N := literal_image_sha256." in coq_image_text,
        )
        checker.check(
            "MinskyNaN16LiteralImage.v literal_words pin alias",
            "Definition literal_words_pin : N := literal_words_sha256." in coq_image_text,
        )
        checker.check(
            "MinskyNaN16LiteralImage.v headline theorem",
            "Theorem literal_image_matches_fixture :" in coq_image_text,
        )
        checker.check(
            "MinskyNaN16LiteralImage.v assumption audit",
            "Print Assumptions literal_image_matches_fixture." in coq_image_text,
        )
        checker.check(
            "MinskyNaN16LiteralImage.v has no Admitted proof",
            re.search(r"\bAdmitted\.", coq_image_text) is None,
        )
    except GateError as exc:
        checker.fail("MinskyNaN16LiteralImage.v readable", str(exc))

    return (
        nan_data,
        words_data,
        coq_data_text,
    )


def check_loader_sources(checker: Checker, root: Path) -> dict[str, str]:
    checker.section("external loader source pins")
    print(f"loader root: {root}")

    texts: dict[str, str] = {}
    for rel, pin, size in LOADER_FILES:
        path = root / rel
        try:
            data = read_file(path)
        except GateError as exc:
            checker.fail(f"{rel} readable", str(exc))
            continue
        texts[rel] = data.decode("utf-8", errors="replace")
        checker.check(f"{rel} size", len(data) == size, f"got {len(data)} bytes")
        got = sha256_bytes(data)
        checker.check(f"{rel} hash", got == pin, f"got {got}, pinned {pin}")

    git_head = root / ".git"
    if git_head.exists():
        try:
            import subprocess

            result = subprocess.run(
                ["git", "-C", str(root), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            )
            head = result.stdout.strip()
            if head != LOADER_COMMIT:
                checker.note(
                    f"loader checkout HEAD is {head}; NAN0S_ISA_SPEC.md section "
                    f"1.6 pins {LOADER_COMMIT}. File hashes above are authoritative."
                )
        except (OSError, subprocess.CalledProcessError):
            checker.note("loader checkout HEAD could not be read")

    cli = texts.get("aarch64/android/tools/nan_cli.c", "")
    if cli:
        checker.check(
            "nan_cli slurp opens the image in binary mode",
            re.search(r'fopen\s*\(\s*p\s*,\s*"rb"\s*\)', cli) is not None,
        )
        checker.check(
            "nan_cli slurp passes the exact file length",
            re.search(
                r"b\s*\[\s*l\s*\]\s*=\s*0\s*;\s*\*n\s*=\s*\(size_t\)\s*l\s*;",
                cli,
            )
            is not None,
        )
        checker.check(
            "nan_cli calls nan_load_auto on slurped bytes",
            re.search(
                r"nan_load_auto\s*\(\s*v\s*,\s*data\s*,\s*len\s*,\s*&kind\s*\)",
                cli,
            )
            is not None,
        )
        checker.check(
            "nan_cli defaults to 128 MiB guest memory",
            re.search(r"if\s*\(\s*mem_mb\s*==\s*0\s*\)\s*mem_mb\s*=\s*128\s*;", cli)
            is not None,
        )
        checker.check(
            "nan_cli creates the VM with words_for_mb",
            re.search(
                r"nan_vm\s*\*\s*v\s*=\s*nan_create_words\s*\(\s*words_for_mb\s*\(\s*mem_mb\s*\)\s*\)",
                cli,
            )
            is not None,
        )
        create_at = cli.find("nan_create_words")
        load_at = cli.find("nan_load_auto")
        checker.check(
            "nan_cli creates the VM before loading",
            create_at >= 0 and load_at >= 0 and create_at < load_at,
            f"nan_create_words at {create_at}, nan_load_auto at {load_at}",
        )

    loader = texts.get("aarch64/android/core/nan_load.c", "")
    if loader:
        checker.check(
            "nan_load_text signature",
            re.search(
                r"int\s+nan_load_text\s*\(\s*nan_vm\s*\*\s*v\s*,\s*const\s+char\s*\*\s*t\s*,\s*size_t\s+len\s*\)",
                loader,
            )
            is not None,
        )
        checker.check(
            "nan_load_text stores NEAR|payload|FAR byte-swapped",
            re.search(
                r"v->mem\s*\[\s*idx\s*\+\+\s*\]\s*=\s*"
                r"\(\(uint64_t\)\s*f1\s*<<\s*48\)\s*\|\s*"
                r"\(\(uint64_t\)\s*f2\s*<<\s*16\)\s*\|\s*f3\s*;",
                loader,
            )
            is not None,
        )
        checker.check(
            "nan_load_text reads 4/8/4 hex columns",
            all(
                pattern in loader
                for pattern in (
                    "!hexn(s, 4, &f1)",
                    "s[4] != '_'",
                    "!hexn(s + 5, 8, &f2)",
                    "s[13] != '_'",
                    "!hexn(s + 14, 4, &f3)",
                )
            ),
        )
        checker.check(
            "nan_load_text bounds idx by mem_words",
            re.search(r"idx\s*>=\s*v->mem_words", loader) is not None,
        )
        checker.check(
            "nan_load_text enforces the 18-character line minimum",
            re.search(r"strlen\s*\(\s*s\s*\)\s*<\s*18", loader) is not None,
        )
        checker.check(
            "nan_load_text implements .org",
            re.search(r'strncmp\s*\(\s*s\s*,\s*"\.org"\s*,\s*4\s*\)', loader)
            is not None,
        )
        checker.check(
            "nan_load_auto runs the text probe over the first 4096 bytes",
            re.search(r"i\s*<\s*len\s*&&\s*i\s*<\s*4096", loader) is not None
            and re.search(r"d\s*\[\s*i\s*\]\s*>=\s*0x80", loader) is not None,
        )
        checker.check(
            "nan_load_auto dispatches text to nan_load_text",
            re.search(
                r"texty\s*&&\s*\(\s*rc\s*=\s*nan_load_text\s*\(\s*v\s*,\s*"
                r"\(const\s+char\s*\*\)\s*d\s*,\s*len\s*\)\s*\)\s*==\s*0",
                loader,
            )
            is not None,
        )
        checker.note(
            "nan_load_text does not validate head bytes or require a word count; "
            "this gate checks both on the pinned image."
        )

    int_header = texts.get("aarch64/android/core/nan16_int.h", "")
    nan_words = None
    if int_header:
        match = re.search(r"#define\s+NAN_WORDS\s+0x([0-9A-Fa-f]+)u", int_header)
        if match:
            nan_words = int(match.group(1), 16)
        checker.check(
            "nan16_int.h defines NAN_WORDS",
            nan_words is not None,
            "missing #define NAN_WORDS 0x...u",
        )
        checker.check(
            "nan16_int.h NAN_HEADS are the canonical four",
            re.search(
                r"static\s+const\s+uint16_t\s+NAN_HEADS\s*\[\s*4\s*\]\s*=\s*"
                r"\{\s*0x7FF1\s*,\s*0xFFF1\s*,\s*0x7FF8\s*,\s*0xFFF8\s*\}",
                int_header,
            )
            is not None,
        )
        checker.check(
            "nan16_int.h nan_far swaps the low 16 bits",
            re.search(
                r"static\s+inline\s+uint32_t\s+nan_far\s*\([^)]*\)\s*"
                r"\{[^}]*<<\s*8[^}]*>>\s*8[^}]*\}",
                int_header,
            )
            is not None,
        )
        checker.check(
            "nan16_int.h nan_near shifts 48",
            re.search(
                r"static\s+inline\s+uint32_t\s+nan_near\s*\([^)]*\)\s*"
                r"\{[^}]*>>\s*48[^}]*\}",
                int_header,
            )
            is not None,
        )
        if nan_words is not None:
            checker.check(
                "loader capacity covers the literal image",
                WORD_COUNT <= nan_words,
                f"{WORD_COUNT} words > NAN_WORDS {nan_words}",
            )

    core = texts.get("aarch64/android/core/nan16.c", "")
    if core:
        checker.check(
            "nan16.c nan_word masks by mem_mask",
            re.search(
                r"uint64_t\s+nan_word\s*\(\s*const\s+nan_vm\s*\*\s*v\s*,\s*"
                r"uint32_t\s+i\s*\)\s*\{\s*return\s+v->mem\s*\[\s*i\s*&\s*"
                r"v->mem_mask\s*\]\s*;\s*\}",
                core,
            )
            is not None,
        )
        checker.check(
            "nan16.c LD projects payload with >> 16",
            re.search(
                r"r\s*\[\s*d\s*\]\s*=\s*\(uint32_t\)\s*\(\s*mem\s*\[\s*ad\s*&\s*M\s*\]\s*>>\s*16\s*\)\s*;",
                core,
            )
            is not None,
        )
        checker.check(
            "nan16.c byte reads use little-endian payload lanes",
            re.search(
                r"out\s*\[\s*i\s*\]\s*=\s*\(uint8_t\)\s*\(\s*\(\(uint32_t\)\s*"
                r"\(\s*v->mem\s*\[\s*wi\s*\]\s*>>\s*16\)\s*>>\s*shift\s*\)\s*"
                r"&\s*0xFFu\s*\)",
                core,
            )
            is not None,
        )

    api = texts.get("aarch64/android/core/nan16.h", "")
    if api:
        checker.check(
            "nan16.h exposes nan_create_words",
            re.search(r"nan_vm\s*\*\s*nan_create_words\s*\(", api) is not None,
        )
        checker.check(
            "nan16.h exposes nan_load_auto",
            re.search(r"int\s+nan_load_auto\s*\(", api) is not None,
        )
        checker.check(
            "nan16.h exposes nan_run",
            re.search(r"int\s+nan_run\s*\(", api) is not None,
        )

    return texts


def check_image(
    checker: Checker,
    nan_data: bytes,
    words_data: bytes,
    coq_data_text: str,
) -> list[int] | None:
    checker.section("nan_load_auto header / dispatch")

    try:
        image = parse_nan_as_loader(nan_data)
    except GateError as exc:
        checker.fail(".nan follows the nan_load_text line contract", str(exc))
        return None

    checker.check(
        ".nan header comment is the pinned fixture header",
        image.header.startswith("; NaN16 guest program"),
        f"got {image.header!r}",
    )
    checker.check(
        ".nan has no NUL bytes",
        b"\x00" not in nan_data,
    )
    checker.check(
        ".nan has no NAN1 state header",
        not (len(nan_data) >= 4 and nan_data[:4] == b"NAN1"),
    )
    checker.check(
        ".nan has no 55 AA floppy header",
        not (
            len(nan_data) >= 512
            and nan_data[510] == 0x55
            and nan_data[511] == 0xAA
        ),
    )
    checker.check(
        ".nan is not a 1,474,560-byte floppy image",
        len(nan_data) != 1_474_560,
    )

    kind, texty = auto_kind(nan_data)
    checker.check(
        ".nan passes the nan_load_auto text probe",
        texty,
        "non-ASCII/control byte in the first 4096 bytes",
    )
    checker.check(
        "nan_load_auto selects nan-text",
        kind == "nan-text",
        f"selected {kind!r}",
    )
    checker.check(
        "nan_cli default VM size covers the image",
        words_for_mb(128) >= WORD_COUNT,
        f"words_for_mb(128)={words_for_mb(128)}",
    )
    checker.check(
        "host is little-endian",
        sys.byteorder == "little",
        f"host byte order is {sys.byteorder}",
    )

    words = image.words
    checker.section("loader word count and header fields")
    checker.check(
        ".nan loader word count",
        len(words) == WORD_COUNT,
        f"got {len(words)}, expected {WORD_COUNT}",
    )
    checker.check(
        ".nan all word indices are dense 0..N-1",
        all(word.index == i for i, word in enumerate(words)),
    )
    checker.check(
        ".nan every line has a comment/index",
        image.comment_lines >= WORD_COUNT,
        f"got {image.comment_lines} comment lines",
    )

    bad_head = first_false([hvalid(w.near) and hvalid(w.far) for w in words])
    checker.check(
        "all NEAR/FAR heads are canonical valid heads",
        bad_head is None,
        words[bad_head].describe() if bad_head is not None else "",
    )
    checker.check(
        "NEAR head field set is exactly the canonical four",
        {w.near for w in words} == set(CANONICAL_HEADS),
        f"got {sorted({w.near for w in words})}",
    )
    checker.check(
        "FAR stored field set is exactly the byte-swapped four",
        {w.far_stored for w in words} == set(CANONICAL_FAR_STORED),
        f"got {sorted({w.far_stored for w in words})}",
    )
    bad_swap = first_false([w.far_stored == swap16(w.far) for w in words])
    checker.check(
        "every FAR head is stored byte-swapped",
        bad_swap is None,
        words[bad_swap].describe() if bad_swap is not None else "",
    )
    checker.check(
        "every word decodes to a 4-bit predicate selector n",
        all(0 <= w.n <= 15 for w in words),
    )

    checker.section("32-bit payload orientation")
    bad_payload = first_false(
        [(w.raw >> 16) & 0xFFFFFFFF == w.payload for w in words]
    )
    checker.check(
        "raw >> 16 masks the 32-bit payload",
        bad_payload is None,
        words[bad_payload].describe() if bad_payload is not None else "",
    )
    bad_near = first_false([(w.raw >> 48) == w.near for w in words])
    checker.check(
        "raw >> 48 recovers the NEAR head",
        bad_near is None,
        words[bad_near].describe() if bad_near is not None else "",
    )
    bad_far = first_false([swap16(w.raw & 0xFFFF) == w.far for w in words])
    checker.check(
        "swap16(raw low 16) recovers the FAR head",
        bad_far is None,
        words[bad_far].describe() if bad_far is not None else "",
    )

    packed = [w.raw.to_bytes(8, "little") for w in words]
    bad_bytes = first_false(
        [
            p[0:2] == w.far.to_bytes(2, "big")
            and p[2:6] == w.payload.to_bytes(4, "little")
            and p[6:8] == w.near.to_bytes(2, "little")
            for p, w in zip(packed, words)
        ]
    )
    checker.check(
        "LE64 bytes are FAR(BE) | payload(LE32) | NEAR(LE16)",
        bad_bytes is None,
        words[bad_bytes].describe() if bad_bytes is not None else "",
    )
    bad_roundtrip = first_false(
        [
            int.from_bytes(p[2:6], "little") == w.payload
            for p, w in zip(packed, words)
        ]
    )
    checker.check(
        "payload bytes round-trip as little-endian 32-bit",
        bad_roundtrip is None,
        words[bad_roundtrip].describe() if bad_roundtrip is not None else "",
    )

    checker.section("image / word-dump / Coq agreement")
    nan_raws = [w.raw for w in words]
    try:
        word_raws = parse_words(words_data)
    except GateError as exc:
        checker.fail(".words follows the 16-hex-digit line contract", str(exc))
        return None

    checker.check(
        ".words line count",
        len(word_raws) == WORD_COUNT,
        f"got {len(word_raws)}",
    )
    diff = first_difference(nan_raws, word_raws)
    checker.check(
        "loader-reconstructed raw words equal .words",
        diff is None,
        (
            f"first difference at {diff}: .nan={nan_raws[diff]:016x} "
            f".words={word_raws[diff]:016x}"
        )
        if diff is not None
        else "",
    )

    try:
        coq_raws = parse_coq_literal_image(coq_data_text)
        coq_hashes = parse_coq_hash_definitions(coq_data_text)
    except GateError as exc:
        checker.fail("LiteralImageData.v follows the generated list contract", str(exc))
        return None

    checker.check(
        "Coq literal_image length",
        len(coq_raws) == WORD_COUNT,
        f"got {len(coq_raws)}",
    )
    diff_coq = first_difference(coq_raws, word_raws)
    checker.check(
        "Coq literal_image equals .words",
        diff_coq is None,
        (
            f"first difference at {diff_coq}: Coq={coq_raws[diff_coq]:016x} "
            f".words={word_raws[diff_coq]:016x}"
        )
        if diff_coq is not None
        else "",
    )
    checker.check(
        "Coq literal_image_sha256 equals the .nan pin",
        coq_hashes["literal_image_sha256"] == int(NAN_SHA256, 16),
        f"got {coq_hashes['literal_image_sha256']:064x}",
    )
    checker.check(
        "Coq literal_words_sha256 equals the .words pin",
        coq_hashes["literal_words_sha256"] == int(WORDS_SHA256, 16),
        f"got {coq_hashes['literal_words_sha256']:064x}",
    )
    checker.check(
        "Coq literal_image_length lemma pins 4366",
        re.search(
            r"Lemma\s+literal_image_length\s*:\s*length\s+literal_image\s*=\s*"
            r"4366%nat\s*\.",
            coq_data_text,
        )
        is not None,
    )

    # Coq-side pin values in the headline image module.
    try:
        coq_image_text = read_text(COQ_IMAGE)
    except GateError as exc:
        checker.fail("MinskyNaN16LiteralImage.v readable", str(exc))
        return nan_raws

    image_pin = re.search(
        r"Lemma\s+literal_image_pin_value\s*:\s*literal_image_pin\s*=\s*"
        r"0x([0-9A-Fa-f]{64})%N\s*\.",
        coq_image_text,
        re.DOTALL,
    )
    words_pin = re.search(
        r"Lemma\s+literal_words_pin_value\s*:\s*literal_words_pin\s*=\s*"
        r"0x([0-9A-Fa-f]{64})%N\s*\.",
        coq_image_text,
        re.DOTALL,
    )
    checker.check(
        "Coq literal_image_pin_value equals the .nan pin",
        image_pin is not None
        and int(image_pin.group(1), 16) == int(NAN_SHA256, 16),
        "lemma missing or value moved",
    )
    checker.check(
        "Coq literal_words_pin_value equals the .words pin",
        words_pin is not None
        and int(words_pin.group(1), 16) == int(WORDS_SHA256, 16),
        "lemma missing or value moved",
    )

    checker.section("pinned literal-word anchors")
    checker.check(
        "word 0 raw is FFF801D00001F8FF",
        nan_raws[0] == 0xFFF801D00001F8FF,
        f"got {nan_raws[0]:016x}",
    )
    checker.check(
        "word 0 payload decodes as MOVI r13, 1",
        words[0].payload == 0x01D00001,
        f"got {words[0].payload:08x}",
    )
    checker.check(
        "cell 99 payload is tape base 4096",
        words[99].payload == 4096,
        f"got {words[99].payload}",
    )
    checker.check(
        "cells 100..103 payloads are zero",
        all(words[i].payload == 0 for i in range(100, 104)),
        f"got {[words[i].payload for i in range(100, 104)]}",
    )
    checker.check(
        "table base 104 is a data word with canonical heads",
        words[104].near == 0x7FF8
        and words[104].far == 0x7FF8
        and words[104].payload == 0,
        words[104].describe(),
    )
    checker.check(
        ".org padding 1649..4095 has zero payloads",
        all(words[i].payload == 0 for i in range(1649, 4096)),
    )
    checker.check(
        "tape prefix 4096..4223 has payload 2",
        all(words[i].payload == 2 for i in range(4096, 4224)),
    )
    checker.check(
        "last word is 7FF800000000F87F",
        nan_raws[-1] == 0x7FF800000000F87F,
        f"got {nan_raws[-1]:016x}",
    )

    if checker.verbose:
        print()
        print(f"first word: {words[0].describe()}")
        print(f"last word:  {words[-1].describe()}")
        print(f"words_for_mb(128) = 0x{words_for_mb(128):X}")

    return nan_raws


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--loader-root",
        help="NaN0S checkout root containing aarch64/android (default: "
        "$NAN0S_WORK, then <repo-parent>/nan0s_work, then ~/nan0s_work)",
    )
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    checker = Checker(args.verbose)
    loader_root = resolve_loader_root(args.loader_root)

    nan_data, words_data, coq_data_text = check_artifacts(checker)
    check_loader_sources(checker, loader_root)
    if nan_data is not None and words_data is not None and coq_data_text is not None:
        check_image(checker, nan_data, words_data, coq_data_text)

    return checker.finish()


if __name__ == "__main__":
    sys.exit(main())
