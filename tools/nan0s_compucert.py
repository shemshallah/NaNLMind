#!/usr/bin/env python3
"""Offline integrity verifier for the archived NaN16 universality certificate.

This is the minimal ``compucert`` / ``verify-cert`` backend.  It checks the
certificate manifest, the recorded statement/assumptions text, the recorded
``coqchk`` transcript, and every SHA-256 anchor available in the tree.  It does
not rebuild Coq, does not run ``coqchk`` unless ``--coqchk`` is passed, and does
not promote the certificate's scope: the manifest explicitly says the theorem
is about the Coq VM model and is not a refinement of
``third_party/nan0s/core/nan16.c``.

Exit codes:
  0  all requested checks passed
  1  verification failed
  2  usage or filesystem error
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CERT_DIR = ROOT / "formal/utm/certificates/nan16-vm"
DEFAULT_CERT = (
    DEFAULT_CERT_DIR / "nan16_run_halting_equivalence_canonical.certificate.json"
)

SCHEMA = "nanlm.coq-nan16-vm-certificate/1"
THEOREM = "NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical"
COQ_MODULE = "NaNLM.MinskyNaN16Universality"
COQCHK_OK = "Modules were successfully checked"
CLOSED = "Closed under the global context"
CERT_STEM = "nan16_run_halting_equivalence_canonical"

SUPPORTING_THEOREMS = (
    "nan16_source_halt_to_vm",
    "nan16_vm_halt_to_source",
    "nan16_run_halting_equivalence",
)

REQUIRED_FIELDS = (
    "schema",
    "theorem",
    "coq_module",
    "coq_source",
    "coq_vo",
    "statement_file",
    "assumptions_file",
    "proof_term_file",
    "coqchk_summary_file",
    "coqchk_log_file",
    "assumptions",
    "assumptions_text",
    "coqchk_status",
    "coq_version",
    "source_sha256",
    "vo_sha256",
    "hashes",
    "project_dependencies",
    "scope",
    "not_proved",
    "window_note",
)

REQUIRED_HASH_ANCHORS = (
    "MinskyNaN16Universality.v",
    "MinskyNaN16Universality.vo",
    "mth_minsky_test.nas",
    "minsky_table.inc",
    f"{CERT_STEM}.statement.txt",
    f"{CERT_STEM}.assumptions.txt",
    f"{CERT_STEM}.proofterm.txt",
    f"{CERT_STEM}.coqchk.summary.txt",
    f"{CERT_STEM}.coqchk.txt.gz",
)

HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")

SCOPE_NOTE = (
    "This verifier checks archived artifact integrity and the recorded "
    "closed-assumption/kernel-success text. It does not rebuild Coq, does not "
    "refine third_party/nan0s/core/nan16.c or the assembled .nas image, and "
    "does not promote the certificate's stated scope."
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


@dataclass
class Failure:
    check: str
    detail: str


class Checker:
    def __init__(self, root: Path, cert_path: Path, args: argparse.Namespace) -> None:
        self.root = root.resolve()
        self.cert_path = cert_path.resolve()
        self.default_cert_fallback = self.root == ROOT.resolve()
        self.args = args
        self.data: dict[str, Any] = {}
        self.passed = 0
        self.checks: list[dict[str, Any]] = []
        self.failures: list[Failure] = []
        self.warnings: list[str] = []
        self.missing_vo_warned: set[str] = set()

    # -- reporting ---------------------------------------------------------
    def check(self, name: str, ok: bool, detail: str = "") -> bool:
        self.checks.append({"name": name, "ok": bool(ok), "detail": detail})
        if ok:
            self.passed += 1
        else:
            self.failures.append(Failure(name, detail))
        return ok

    def fail(self, name: str, detail: str) -> None:
        self.check(name, False, detail)

    def warn(self, message: str) -> None:
        if message not in self.warnings:
            self.warnings.append(message)

    # -- path/hash helpers -------------------------------------------------
    def _allowed_roots(self) -> tuple[Path, ...]:
        roots = [self.root]
        if self.default_cert_fallback:
            roots.append(DEFAULT_CERT_DIR.resolve())
        if self.cert_path.parent not in roots:
            roots.append(self.cert_path.parent.resolve())
        return tuple(roots)

    def locate(self, raw: str) -> Path | None:
        """Find the first existing candidate for a manifest-relative path."""
        candidate = Path(raw)
        paths: list[Path] = []
        if candidate.is_absolute():
            paths.append(candidate)
        else:
            paths.append(self.root / candidate)
            paths.append(self.cert_path.parent / candidate)
            if self.default_cert_fallback:
                paths.append(DEFAULT_CERT_DIR / candidate)
            paths.append(self.root / "formal/utm" / candidate)
            if len(candidate.parts) == 1:
                paths.append(self.root / "mth/tests" / candidate)
                paths.append(self.root / "tests" / candidate)
        allowed = self._allowed_roots()
        for path in paths:
            try:
                resolved = path.resolve()
            except OSError:
                continue
            if not any(resolved.is_relative_to(root) for root in allowed):
                continue
            if resolved.is_file():
                return resolved
        return None

    def require_file(self, raw: Any, label: str) -> Path | None:
        if not isinstance(raw, str) or not raw:
            self.fail(label, f"expected a non-empty path, got {raw!r}")
            return None
        path = self.locate(raw)
        if path is None:
            self.fail(label, f"missing file: {raw}")
            return None
        self.check(label, True, str(path))
        return path

    def check_hash(self, label: str, raw: str, expected: Any) -> None:
        if not isinstance(expected, str) or not HEX64.match(expected):
            self.fail(label, f"bad expected sha256: {expected!r}")
            return
        path = self.locate(raw)
        if path is None:
            if self.args.allow_missing_vo and raw.endswith(".vo"):
                if raw not in self.missing_vo_warned:
                    self.missing_vo_warned.add(raw)
                    self.warn(
                        f"{raw} is absent; its .vo hash was not checked "
                        "(--allow-missing-vo)"
                    )
                return
            self.fail(label, f"missing file: {raw}")
            return
        actual = sha256_file(path)
        self.check(
            label,
            actual == expected.lower(),
            f"{path}: actual={actual} expected={expected.lower()}",
        )

    # -- verification ------------------------------------------------------
    def load_manifest(self) -> bool:
        if not self.cert_path.is_file():
            self.fail("certificate manifest", f"missing file: {self.cert_path}")
            return False
        if self.args.expect_cert_sha256:
            actual = sha256_file(self.cert_path)
            self.check(
                "certificate manifest sha256 anchor",
                actual == self.args.expect_cert_sha256.lower(),
                f"{self.cert_path}: actual={actual} "
                f"expected={self.args.expect_cert_sha256.lower()}",
            )
        try:
            loaded = json.loads(self.cert_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            self.fail("certificate JSON", f"{self.cert_path}: {exc}")
            return False
        if not isinstance(loaded, dict):
            self.fail("certificate JSON", "top-level value is not an object")
            return False
        self.data = loaded
        self.check("certificate JSON object", True, str(self.cert_path))
        return True

    def check_manifest(self) -> None:
        data = self.data
        missing = [field for field in REQUIRED_FIELDS if field not in data]
        self.check(
            "required manifest fields",
            not missing,
            "missing: " + ", ".join(missing) if missing else "all present",
        )
        self.check(
            "schema",
            data.get("schema") == SCHEMA,
            f"{data.get('schema')!r} != {SCHEMA!r}",
        )
        self.check(
            "theorem",
            data.get("theorem") == THEOREM,
            f"{data.get('theorem')!r} != {THEOREM!r}",
        )
        self.check(
            "coq_module",
            data.get("coq_module") == COQ_MODULE,
            f"{data.get('coq_module')!r} != {COQ_MODULE!r}",
        )
        self.check(
            "assumptions list empty",
            data.get("assumptions") == [],
            f"assumptions={data.get('assumptions')!r}",
        )
        assumptions_text = data.get("assumptions_text")
        self.check(
            "assumptions text closed",
            isinstance(assumptions_text, str) and assumptions_text.strip() == CLOSED,
            f"assumptions_text={assumptions_text!r}",
        )
        self.check(
            "coqchk status recorded",
            data.get("coqchk_status") == COQCHK_OK,
            f"coqchk_status={data.get('coqchk_status')!r}",
        )
        supporting = data.get("supporting_theorems")
        supporting_ok = (
            isinstance(supporting, list)
            and len(supporting) >= 3
            and all(
                isinstance(item, str) and item.startswith(COQ_MODULE + ".")
                for item in supporting
            )
        )
        self.check(
            "supporting theorems recorded",
            supporting_ok,
            f"supporting_theorems={supporting!r}",
        )
        scope = data.get("scope")
        self.check(
            "scope recorded",
            isinstance(scope, str) and bool(scope.strip()),
            f"scope={scope!r}",
        )
        not_proved = data.get("not_proved")
        self.check(
            "not_proved recorded",
            isinstance(not_proved, list) and len(not_proved) > 0,
            f"not_proved={not_proved!r}",
        )
        window_note = data.get("window_note")
        self.check(
            "window_note recorded",
            isinstance(window_note, str) and bool(window_note.strip()),
            f"window_note={window_note!r}",
        )
        coq_version = data.get("coq_version")
        self.check(
            "coq_version recorded",
            isinstance(coq_version, str) and bool(coq_version.strip()),
            f"coq_version={coq_version!r}",
        )

    def check_text_artifacts(self) -> None:
        data = self.data
        statement = self.require_file(data.get("statement_file"), "statement file")
        assumptions = self.require_file(
            data.get("assumptions_file"), "assumptions file"
        )
        proof_term = self.require_file(
            data.get("proof_term_file"), "proof term file"
        )
        summary = self.require_file(
            data.get("coqchk_summary_file"), "coqchk summary file"
        )
        log = self.require_file(data.get("coqchk_log_file"), "coqchk log file")

        short_name = THEOREM.rsplit(".", 1)[-1]
        if statement is not None:
            text = statement.read_text(encoding="utf-8", errors="replace")
            self.check(
                "statement names theorem",
                short_name in text,
                f"{statement}: missing {short_name}",
            )
            self.check(
                "statement has forall/iff shape",
                "forall" in text and "iff" in text,
                f"{statement}: expected forall and iff",
            )
        if assumptions is not None:
            text = assumptions.read_text(encoding="utf-8", errors="replace").strip()
            self.check(
                "assumptions file is closed",
                text == CLOSED,
                f"{assumptions}: {text!r}",
            )
        if proof_term is not None:
            text = proof_term.read_text(encoding="utf-8", errors="replace")
            self.check(
                "proof term nonempty",
                bool(text.strip()),
                f"{proof_term}: empty",
            )
            self.check(
                "proof term names theorem",
                short_name in text,
                f"{proof_term}: missing {short_name}",
            )
        if summary is not None:
            text = summary.read_text(encoding="utf-8", errors="replace")
            self.check(
                "coqchk summary status",
                COQCHK_OK in text,
                f"{summary}: missing {COQCHK_OK!r}",
            )
            self.check(
                "coqchk summary names theorem",
                f"checking cst:{THEOREM}" in text,
                f"{summary}: missing checking cst:{THEOREM}",
            )
        if log is not None:
            try:
                with gzip.open(log, "rt", encoding="utf-8", errors="replace") as handle:
                    text = handle.read(8 << 20)
            except (OSError, EOFError) as exc:
                self.fail("coqchk log gzip", f"{log}: {exc}")
            else:
                self.check(
                    "coqchk log status",
                    COQCHK_OK in text,
                    f"{log}: missing {COQCHK_OK!r}",
                )
                self.check(
                    "coqchk log names theorem",
                    f"checking cst:{THEOREM}" in text,
                    f"{log}: missing checking cst:{THEOREM}",
                )

        for name in SUPPORTING_THEOREMS:
            filename = f"{name}.assumptions.txt"
            candidates = [self.cert_path.parent / filename]
            if self.default_cert_fallback:
                candidates.append(DEFAULT_CERT_DIR / filename)
            path = next((candidate for candidate in candidates if candidate.is_file()), None)
            if path is None:
                self.fail(
                    f"supporting assumptions {name}",
                    f"missing {filename} in {self.cert_path.parent}",
                )
                continue
            text = path.read_text(encoding="utf-8", errors="replace").strip()
            self.check(
                f"supporting assumptions {name}",
                text == CLOSED,
                f"{path}: {text!r}",
            )

    def check_hashes(self) -> None:
        data = self.data
        source = data.get("coq_source")
        if isinstance(source, str):
            self.check_hash("coq_source sha256", source, data.get("source_sha256"))
        vo = data.get("coq_vo")
        if isinstance(vo, str):
            self.check_hash("coq_vo sha256", vo, data.get("vo_sha256"))

        hashes = data.get("hashes")
        if not isinstance(hashes, dict) or not hashes:
            self.fail("hashes map", f"expected non-empty object, got {hashes!r}")
        else:
            missing = [name for name in REQUIRED_HASH_ANCHORS if name not in hashes]
            self.check(
                "required hash anchors",
                not missing,
                "missing: " + ", ".join(missing) if missing else "all present",
            )
            for name, expected in hashes.items():
                self.check_hash(f"hash {name}", name, expected)

        dependencies = data.get("project_dependencies")
        if not isinstance(dependencies, list) or not dependencies:
            self.fail(
                "project dependencies",
                f"expected non-empty list, got {dependencies!r}",
            )
            return
        for index, dep in enumerate(dependencies):
            if not isinstance(dep, dict):
                self.fail("project dependency entry", f"#{index}: {dep!r}")
                continue
            module = dep.get("module", f"#{index}")
            source = dep.get("source")
            vo_expected = dep.get("vo_sha256")
            if not isinstance(source, str) or not source.endswith(".v"):
                self.fail(f"dependency {module} source", f"bad source: {source!r}")
                continue
            self.check_hash(
                f"dependency {module} source", source, dep.get("source_sha256")
            )
            self.check_hash(
                f"dependency {module} vo",
                str(Path(source).with_suffix(".vo")),
                vo_expected,
            )

    def run_coqchk(self) -> None:
        exe = shutil.which("coqchk")
        if exe is None:
            message = "coqchk not found on PATH"
            if self.args.require_coqchk:
                self.fail("coqchk available", message)
            else:
                self.warn(message + "; offline checks only")
            return

        version_text = ""
        try:
            version_proc = subprocess.run(
                [exe, "--version"],
                text=True,
                capture_output=True,
                timeout=60,
            )
            version_text = (version_proc.stdout + version_proc.stderr).strip()
        except (OSError, subprocess.SubprocessError) as exc:
            self.warn(f"could not read coqchk version: {exc}")

        recorded_version = self.data.get("coq_version")
        if (
            isinstance(recorded_version, str)
            and recorded_version
            and version_text
            and recorded_version not in version_text
        ):
            detail = (
                f"certificate={recorded_version!r} "
                f"coqchk={version_text.splitlines()[0] if version_text else ''!r}"
            )
            if self.args.strict_version:
                self.fail("coqchk version", detail)
            else:
                self.warn("coqchk version differs from certificate: " + detail)

        coq_dir = self.root / "formal/utm"
        if not coq_dir.is_dir():
            self.fail("coqchk workdir", f"missing {coq_dir}")
            return
        cmd = [exe, "-o", "-Q", ".", "NaNLM", "MinskyNaN16Universality.vo"]
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(coq_dir),
                text=True,
                capture_output=True,
                timeout=self.args.timeout,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            self.fail("coqchk execution", f"{' '.join(cmd)}: {exc}")
            return
        output = (proc.stdout or "") + (proc.stderr or "")
        self.check(
            "coqchk exit status",
            proc.returncode == 0,
            f"rc={proc.returncode}",
        )
        self.check(
            "coqchk modules checked",
            COQCHK_OK in output,
            f"missing {COQCHK_OK!r}",
        )
        self.check(
            "coqchk names theorem",
            f"checking cst:{THEOREM}" in output,
            f"missing checking cst:{THEOREM}",
        )
        if self.args.coqchk_log:
            try:
                Path(self.args.coqchk_log).write_text(output, encoding="utf-8")
            except OSError as exc:
                self.fail("coqchk log output", str(exc))

    def run(self) -> int:
        if not self.load_manifest():
            return 1
        self.check_manifest()
        self.check_text_artifacts()
        self.check_hashes()
        if self.args.coqchk or self.args.require_coqchk:
            self.run_coqchk()
        return 0 if not self.failures else 1

    # -- output ------------------------------------------------------------
    def report(self) -> dict[str, Any]:
        data = self.data
        return {
            "schema": "nanlm.nan0s-compucert-report/1",
            "ok": not self.failures,
            "mode": (
                "offline+coqchk"
                if (self.args.coqchk or self.args.require_coqchk)
                else "offline"
            ),
            "certificate": str(self.cert_path),
            "theorem": THEOREM,
            "recorded_coq_version": data.get("coq_version"),
            "passed": self.passed,
            "failed": len(self.failures),
            "warnings": self.warnings,
            "failures": [
                {"check": failure.check, "detail": failure.detail}
                for failure in self.failures
            ],
            "checks": self.checks,
            "scope_note": SCOPE_NOTE,
        }

    def print_human(self) -> None:
        data = self.data
        mode = (
            "offline + coqchk"
            if (self.args.coqchk or self.args.require_coqchk)
            else "offline (precomputed hashes only)"
        )
        print("NAN0S COMPUCERT — NaN16 universality certificate verifier")
        print(f"mode:        {mode}")
        print(f"certificate: {self.cert_path}")
        print(f"theorem:     {THEOREM}")
        if data:
            print(f"schema:      {data.get('schema')}")
            print(f"coq_version: {data.get('coq_version')}")
            print(f"assumptions: {str(data.get('assumptions_text', '')).strip()}")
            print(f"coqchk:      {data.get('coqchk_status')}")
        print(
            f"checks:      {self.passed} passed, "
            f"{len(self.failures)} failed, {len(self.warnings)} warnings"
        )
        if self.args.verbose:
            for item in self.checks:
                marker = "ok  " if item["ok"] else "FAIL"
                print(f"  [{marker}] {item['name']}: {item['detail']}")
        for failure in self.failures:
            print(f"FAIL {failure.check}: {failure.detail}")
        for warning in self.warnings:
            print(f"WARN {warning}")
        print()
        print("COMPUCERT: " + ("PASS" if not self.failures else "FAIL"))
        print("scope: " + SCOPE_NOTE)
        if isinstance(data.get("not_proved"), list) and data["not_proved"]:
            print("not_proved[0]: " + str(data["not_proved"][0]))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify the archived NaN16 universality certificate. By default "
            "this is an offline manifest/hash check; pass --coqchk to also "
            "re-run the Coq kernel checker."
        )
    )
    parser.add_argument(
        "--cert",
        type=Path,
        default=DEFAULT_CERT,
        help=f"certificate JSON (default: {DEFAULT_CERT})",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help=f"repository root used to resolve manifest paths (default: {ROOT})",
    )
    parser.add_argument(
        "--expect-cert-sha256",
        default="",
        metavar="HEX64",
        help="fail unless the certificate JSON itself has this SHA-256",
    )
    parser.add_argument(
        "--allow-missing-vo",
        action="store_true",
        help="warn instead of failing when an untracked .vo artifact is absent",
    )
    parser.add_argument(
        "--coqchk",
        action="store_true",
        help="run coqchk on MinskyNaN16Universality.vo if it is on PATH",
    )
    parser.add_argument(
        "--require-coqchk",
        action="store_true",
        help="fail unless coqchk is available and the kernel check passes",
    )
    parser.add_argument(
        "--strict-version",
        action="store_true",
        help="require coqchk's version text to match the manifest coq_version",
    )
    parser.add_argument(
        "--coqchk-log",
        type=Path,
        default=None,
        help="write the coqchk transcript to this path",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=900,
        help="coqchk timeout in seconds (default: 900)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print a machine-readable report",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="print every individual check",
    )
    args = parser.parse_args(argv)
    if args.expect_cert_sha256 and not HEX64.match(args.expect_cert_sha256):
        parser.error("--expect-cert-sha256 must be a 64-character hex digest")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    checker = Checker(args.root, args.cert, args)
    code = checker.run()
    if args.json:
        print(json.dumps(checker.report(), indent=2, sort_keys=True))
    else:
        checker.print_human()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
