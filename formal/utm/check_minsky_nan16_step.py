#!/usr/bin/env python3
"""Transcription gate for the literal NaN16 ``step``/``run100`` routine.

This is a source-text gate, not a refinement proof.  It compares the literal
instruction sequence in ``mth/tests/mth_minsky_test.nas`` with the Coq
mnemonic split used by the Layer 2 VM scaffold:

    prelude_block   (MinskyNaN16Prelude.v)
    scan_block      (MinskyNaN16VM.v)
    action_block    (MinskyNaN16Action.v)
    no_trans_block  (MinskyNaN16StepNone.v)

The Coq blocks are not contiguous slices of the .nas text: they renumber
block-relative branches, replace fallthroughs by explicit jumps, and use HALT
sentinels for the scan exits.  The gate therefore applies a small, explicit
normalization (documented in the output) before comparing instruction tuples.
Anything outside that normalization fails closed.

The gate also checks the literal ``run100`` driver shape and the presence of
the exact Coq declarations in the checked step/run100 chain.  It does NOT
compile Coq, prove the ISA, check the assembler/encoding, or promote Layer 2
to a certificate.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / "mth/tests/mth_minsky_test.nas"
DEFAULT_COQ_DIR = ROOT / "formal/utm"

# Memory operands are compared symbolically.  The Coq address constants are
# abstract stand-ins for cells, not the assembled addresses of the .nas labels.
SOURCE_MEMORY = {
    "head": "head",
    "state": "state",
    "halt": "halt",
    "tbase": "tbase",
    "table": "table",
}
COQ_MEMORY = {
    "action_head_addr": "head",
    "action_state_addr": "state",
    "action_halt_addr": "halt",
    "tape_base_addr": "tbase",
    "table_base": "table",
}

PREDICATES = {"EQ", "NE", "LT", "GE", "GT", "LE", "ALWAYS", "NEVER"}

BLOCK_FILES = (
    ("prelude_block", "MinskyNaN16Prelude.v"),
    ("scan_block", "MinskyNaN16VM.v"),
    ("action_block", "MinskyNaN16Action.v"),
    ("no_trans_block", "MinskyNaN16StepNone.v"),
)

# Exact declarations in the checked VM chain.  The gate only checks that the
# named declaration is present in the named file; the Coq workflow checks the
# proofs.  See the certificate README for which modules are coqchk-checked.
THEOREM_FILES = (
    ("prelude_ready", "MinskyNaN16PreludeReady.v"),
    ("prelude_halted", "MinskyNaN16PreludeReady.v"),
    ("action_refines", "MinskyNaN16ActionRefines.v"),
    ("action_run_frame", "MinskyNaN16ActionRun.v"),
    ("scan_loop", "MinskyNaN16ScanLoop.v"),
    ("scan_phase", "MinskyNaN16ScanPhase.v"),
    ("step_hit_phase", "MinskyNaN16StepHit.v"),
    ("no_trans_run", "MinskyNaN16StepNone.v"),
    ("step_none_phase", "MinskyNaN16StepNone.v"),
    ("native_step_refines", "MinskyNaN16Step.v"),
    ("native_step_spec_active", "MinskyNaN16StepSpec.v"),
    ("step_entry_spec", "MinskyNaN16StepEntrySpec.v"),
    ("vm_run_refines", "MinskyNaN16Run.v"),
)

CHAIN_DEFINITIONS = (
    ("step_entry", "MinskyNaN16StepEntrySpec.v"),
    ("vm_run", "MinskyNaN16Run.v"),
)


class GateError(RuntimeError):
    """A fail-closed transcription error."""


# ---------------------------------------------------------------------------
# Coq text parsing
# ---------------------------------------------------------------------------


def strip_coq_comments(text: str) -> str:
    """Remove nested Coq comments while preserving line structure."""
    out: list[str] = []
    depth = 0
    index = 0
    while index < len(text):
        if text.startswith("(*", index):
            depth += 1
            index += 2
        elif text.startswith("*)", index):
            if depth == 0:
                raise GateError("unmatched Coq comment terminator")
            depth -= 1
            index += 2
        elif depth:
            if text[index] == "\n":
                out.append("\n")
            index += 1
        else:
            out.append(text[index])
            index += 1
    if depth:
        raise GateError("unterminated Coq comment")
    return "".join(out)


def coq_nat_constant(text: str, name: str, path: Path) -> int:
    pattern = re.compile(
        r"\bDefinition\s+" + re.escape(name) + r"\b[^.]*?:=\s*(\d+)\s*\.",
        re.DOTALL,
    )
    match = pattern.search(text)
    if match is None:
        raise GateError(f"{path.name}: missing nat definition {name!r}")
    return int(match.group(1))


def coq_list_definition(text: str, name: str, path: Path) -> str:
    pattern = re.compile(
        r"\bDefinition\s+" + re.escape(name) + r"\b.*?:=\s*\[(.*?)\]\s*\.",
        re.DOTALL,
    )
    match = pattern.search(text)
    if match is None:
        raise GateError(f"{path.name}: missing list definition {name!r}")
    return match.group(1)


@dataclass(frozen=True)
class Insn:
    """A normalized instruction tuple.

    ``line`` and ``text`` are provenance only and do not participate in
    equality.  Memory operands use ``("mem", name)``; jump/call targets are
    integers; registers and immediates are integers.
    """

    op: str
    pred: str | None
    args: tuple[object, ...]
    line: int | None = field(default=None, compare=False)
    text: str = field(default="", compare=False)

    def shown(self) -> str:
        mnemonic = "i" + self.op
        if self.pred is not None:
            if self.op in ("JMP", "RET"):
                mnemonic += f"[{self.pred}]"
            else:
                mnemonic += f" {self.pred}"
        operands = " ".join(show_arg(arg) for arg in self.args)
        return (mnemonic + (" " + operands if operands else "")).strip()


def show_arg(arg: object) -> str:
    if isinstance(arg, tuple) and len(arg) == 2 and arg[0] == "mem":
        return str(arg[1])
    return str(arg)


def normalize_pred(pred: str | None) -> str | None:
    if pred is None:
        return None
    upper = pred.upper()
    if upper.startswith("P"):
        upper = upper[1:]
    if upper not in PREDICATES:
        raise GateError(f"unknown predicate {pred!r}")
    return upper


def coq_memory(arg: str) -> object:
    if arg.isdigit():
        return int(arg)
    if arg in COQ_MEMORY:
        return ("mem", COQ_MEMORY[arg])
    raise GateError(f"unknown Coq memory operand {arg!r}")


def parse_coq_block(text: str, name: str, path: Path) -> list[Insn]:
    body = coq_list_definition(text, name, path)
    tokens = [token.strip() for token in body.split(";") if token.strip()]
    instructions: list[Insn] = []
    for token in tokens:
        parts = token.split()
        if not parts or not parts[0].startswith("i"):
            raise GateError(f"{path.name}:{name}: bad instruction {token!r}")
        op = parts[0][1:]
        operands = parts[1:]
        try:
            if op == "JMP":
                if len(operands) != 2:
                    raise GateError("JMP arity")
                pred = normalize_pred(operands[0])
                args: tuple[object, ...] = (int(operands[1]),)
            elif op in ("CALL", "RET", "HALT"):
                if op == "RET":
                    pred = normalize_pred(operands[0]) if operands else None
                    args = ()
                elif op == "HALT":
                    pred = None
                    args = ()
                else:
                    pred = None
                    args = (int(operands[0]),)
            elif op in ("LD", "ST"):
                if len(operands) != 3:
                    raise GateError(f"{op} arity")
                pred = None
                args = (int(operands[0]), int(operands[1]), coq_memory(operands[2]))
            elif op == "MOVI":
                if len(operands) != 2:
                    raise GateError("MOVI arity")
                pred = None
                args = (int(operands[0]), coq_memory(operands[1]))
            elif op == "CMP":
                if len(operands) != 2:
                    raise GateError("CMP arity")
                pred = None
                args = (int(operands[0]), int(operands[1]))
            elif op in ("ADD", "SUB", "SHL"):
                if len(operands) != 3:
                    raise GateError(f"{op} arity")
                pred = None
                args = (int(operands[0]), int(operands[1]), int(operands[2]))
            else:
                raise GateError(f"unsupported Coq mnemonic i{op}")
        except (ValueError, IndexError) as exc:
            raise GateError(
                f"{path.name}:{name}: cannot parse instruction {token!r}"
            ) from exc
        instructions.append(Insn(op, pred, args, text=token))
    return instructions


# ---------------------------------------------------------------------------
# .nas text parsing
# ---------------------------------------------------------------------------


LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")
INSTR_RE = re.compile(
    r"^([A-Za-z][A-Za-z0-9_.]*)(?:\[([A-Za-z]+)\])?\s*(.*)$"
)
REG_RE = re.compile(r"^r(\d+)$")


@dataclass(frozen=True)
class SourceInsn:
    op: str
    pred: str | None
    raw_args: tuple[str, ...]
    line: int
    text: str


def parse_source(path: Path) -> tuple[list[SourceInsn], dict[str, int]]:
    instructions: list[SourceInsn] = []
    labels: dict[str, int] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split(";", 1)[0].strip()
        if not line:
            continue
        label_match = LABEL_RE.match(line)
        if label_match:
            label = label_match.group(1)
            if label in labels:
                raise GateError(f"{path.name}:{number}: duplicate label {label!r}")
            labels[label] = len(instructions)
            line = label_match.group(2).strip()
            if not line:
                continue
        if line.startswith("."):
            continue
        match = INSTR_RE.fullmatch(line)
        if match is None:
            raise GateError(f"{path.name}:{number}: cannot parse line {raw!r}")
        op, pred, rest = match.groups()
        raw_args = tuple(part.strip() for part in rest.split(",") if part.strip())
        instructions.append(SourceInsn(op, pred, raw_args, number, line))
    return instructions, labels


def source_reg(arg: str) -> int:
    match = REG_RE.fullmatch(arg)
    if match is None:
        raise GateError(f"expected register, found {arg!r}")
    return int(match.group(1))


def source_reg_or_int(arg: str) -> int:
    if arg.isdigit():
        return int(arg)
    return source_reg(arg)


def source_memory(arg: str) -> object:
    if arg.isdigit():
        return int(arg)
    if arg.startswith("@"):
        name = arg[1:]
        if name in SOURCE_MEMORY:
            return ("mem", SOURCE_MEMORY[name])
    raise GateError(f"unknown source memory operand {arg!r}")


def normalize_source(
    insn: SourceInsn, target_map: dict[str, int]
) -> Insn:
    op = insn.op
    args = insn.raw_args
    pred = normalize_pred(insn.pred)
    try:
        if op in ("LD", "ST"):
            if len(args) != 3:
                raise GateError(f"{op} arity")
            norm_args: tuple[object, ...] = (
                source_reg(args[0]),
                source_reg(args[1]),
                source_memory(args[2]),
            )
        elif op == "MOVI":
            if len(args) != 2:
                raise GateError("MOVI arity")
            norm_args = (source_reg(args[0]), source_memory(args[1]))
        elif op == "CMP":
            if len(args) != 2:
                raise GateError("CMP arity")
            norm_args = (source_reg_or_int(args[0]), source_reg_or_int(args[1]))
        elif op in ("ADD", "SUB", "SHL"):
            if len(args) != 3:
                raise GateError(f"{op} arity")
            norm_args = (
                source_reg_or_int(args[0]),
                source_reg_or_int(args[1]),
                source_reg_or_int(args[2]),
            )
        elif op == "JMP":
            if len(args) != 1:
                raise GateError("JMP arity")
            target = args[0]
            key = target[1:] if target.startswith("@") else target
            if key in target_map:
                norm_args = (target_map[key],)
            elif target.isdigit():
                norm_args = (int(target),)
            else:
                raise GateError(f"no block-relative target for {target!r}")
            if pred is None:
                pred = "ALWAYS"
        elif op == "CALL":
            if len(args) != 1:
                raise GateError("CALL arity")
            target = args[0]
            key = target[1:] if target.startswith("@") else target
            if key not in target_map:
                raise GateError(f"no block-relative target for {target!r}")
            norm_args = (target_map[key],)
        elif op in ("RET", "HALT"):
            norm_args = ()
        else:
            raise GateError(f"unsupported source mnemonic {op!r}")
    except (ValueError, IndexError) as exc:
        raise GateError(
            f"line {insn.line}: cannot normalize {insn.text!r}"
        ) from exc
    return Insn(op, pred, norm_args, line=insn.line, text=insn.text)


def synthetic(op: str, pred: str | None, args: tuple[object, ...], why: str) -> Insn:
    return Insn(op, pred, args, line=None, text=f"<synthesized {why}>")


def source_slice(
    instructions: list[SourceInsn],
    labels: dict[str, int],
    start: str,
    end: str | None = None,
) -> list[SourceInsn]:
    if start not in labels:
        raise GateError(f"missing .nas label {start!r}")
    begin = labels[start]
    if end is None:
        finish = len(instructions)
    else:
        if end not in labels:
            raise GateError(f"missing .nas label {end!r}")
        finish = labels[end]
    if not 0 <= begin < finish <= len(instructions):
        raise GateError(f"bad source slice {start!r}..{end!r}")
    return instructions[begin:finish]


# ---------------------------------------------------------------------------
# Gate checks
# ---------------------------------------------------------------------------


def compare_blocks(name: str, source: list[Insn], coq: list[Insn]) -> None:
    if len(source) != len(coq):
        raise GateError(
            f"{name}: instruction count mismatch: source={len(source)}, "
            f"Coq={len(coq)}"
        )
    for index, (source_insn, coq_insn) in enumerate(zip(source, coq)):
        if source_insn != coq_insn:
            origin = (
                f"line {source_insn.line}"
                if source_insn.line is not None
                else "normalization"
            )
            raise GateError(
                f"{name}: instruction {index} mismatch\n"
                f"  source ({origin}): {source_insn.shown()}\n"
                f"         {source_insn.text}\n"
                f"  Coq:              {coq_insn.shown()}\n"
                f"         {coq_insn.text}"
            )


def check_declarations(
    texts: dict[str, str], declarations: tuple[tuple[str, str], ...], kinds: str
) -> list[tuple[str, str]]:
    missing = []
    for name, filename in declarations:
        text = texts[filename]
        pattern = re.compile(
            r"(?m)^\s*(?:" + kinds + r")\s+" + re.escape(name) + r"\b"
        )
        if pattern.search(text) is None:
            missing.append((name, filename))
    if missing:
        detail = ", ".join(f"{name} ({file})" for name, file in missing)
        raise GateError(f"missing Coq declaration(s): {detail}")
    return list(declarations)


def check_no_admitted(texts: dict[str, str]) -> None:
    for filename, text in texts.items():
        if re.search(r"(?m)^\s*Admitted\s*\.", text):
            raise GateError(f"{filename}: contains Admitted")


def check_theorem_contains(
    texts: dict[str, str], filename: str, name: str, needles: tuple[str, ...]
) -> None:
    text = texts[filename]
    match = re.search(
        r"\bTheorem\s+"
        + re.escape(name)
        + r"\b(.*?)\.\s*Proof\.",
        text,
        re.DOTALL,
    )
    if match is None:
        raise GateError(f"{filename}: missing theorem statement {name!r}")
    statement = re.sub(r"\s+", " ", match.group(1))
    for needle in needles:
        if re.sub(r"\s+", " ", needle) not in statement:
            raise GateError(
                f"{filename}:{name}: statement no longer contains {needle!r}"
            )


def check_definition_contains(
    texts: dict[str, str], filename: str, name: str, needles: tuple[str, ...]
) -> None:
    text = texts[filename]
    match = re.search(
        r"\b(?:Definition|Fixpoint)\s+"
        + re.escape(name)
        + r"\b.*?:=\s*(.*?)(?=\n\s*(?:Definition|Fixpoint|Lemma|Theorem|"
        r"Inductive|Record)\b|\Z)",
        text,
        re.DOTALL,
    )
    if match is None:
        raise GateError(f"{filename}: missing definition {name!r}")
    body = re.sub(r"\s+", " ", match.group(1))
    for needle in needles:
        if re.sub(r"\s+", " ", needle) not in body:
            raise GateError(
                f"{filename}:{name}: definition no longer contains {needle!r}"
            )


def check_run100_driver(
    instructions: list[SourceInsn], labels: dict[str, int]
) -> list[Insn]:
    driver = source_slice(instructions, labels, "run100", "step")
    if len(driver) != 7:
        raise GateError(
            f"run100: expected 7 instructions, found {len(driver)}"
        )
    expected_ops = ["ST", "MOVI", "CALL", "SUB", "JMP", "LD", "RET"]
    actual_ops = [insn.op for insn in driver]
    if actual_ops != expected_ops:
        raise GateError(
            f"run100: instruction sequence changed: {actual_ops} != {expected_ops}"
        )
    if driver[0].raw_args != ("r15", "r0", "@rlink"):
        raise GateError("run100: link save changed")
    if driver[1].raw_args != ("r11", "100"):
        raise GateError("run100: loop count is not literal 100")
    if driver[2].raw_args != ("@step",):
        raise GateError("run100: loop does not call @step")
    if driver[3].raw_args != ("r11", "r11", "r13"):
        raise GateError("run100: loop decrement changed")
    if driver[4].pred != "NE" or driver[4].raw_args != ("@rloop",):
        raise GateError("run100: loop branch changed")
    if driver[5].raw_args != ("r15", "r0", "@rlink"):
        raise GateError("run100: link restore changed")
    if driver[6].op != "RET":
        raise GateError("run100: does not return")

    if "rloop" not in labels:
        raise GateError("run100: missing rloop label")
    if labels["rloop"] != labels["run100"] + 2:
        raise GateError("run100: rloop label is not at the CALL instruction")

    main = source_slice(instructions, labels, "main", "run100")
    calls = [
        index
        for index, insn in enumerate(main)
        if insn.op == "CALL" and insn.raw_args == ("@run100",)
    ]
    if len(calls) != 1:
        raise GateError("main: expected exactly one CALL @run100")
    before = main[: calls[0]]
    if not any(
        insn.op == "MOVI" and insn.raw_args == ("r13", "1") for insn in before
    ):
        raise GateError("main: r13 is not set to 1 before CALL @run100")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--coq-dir", type=Path, default=DEFAULT_COQ_DIR)
    args = parser.parse_args()

    try:
        source_path: Path = args.source
        coq_dir: Path = args.coq_dir
        for path in (source_path, coq_dir):
            if not path.exists():
                raise GateError(f"missing path: {path}")

        source_instructions, labels = parse_source(source_path)
        step = source_slice(source_instructions, labels, "step", "puts")

        required_labels = (
            "scan",
            "mleft",
            "mright",
            "mdone",
            "step_ret",
            "next",
            "no_trans",
        )
        missing = [name for name in required_labels if name not in labels]
        if missing:
            raise GateError(f"{source_path.name}: missing label(s) {missing}")

        rel = {
            name: labels[name] - labels["step"] for name in required_labels
        }
        if not (0 < rel["scan"] < len(step)):
            raise GateError("step: scan label is not inside the step body")
        if not (
            rel["scan"]
            < rel["mleft"]
            < rel["mright"]
            < rel["mdone"]
            <= rel["step_ret"]
            < rel["next"]
            < rel["no_trans"]
            < len(step)
        ):
            raise GateError("step: block labels are not in the expected order")

        action_start_candidates = [
            index
            for index in range(rel["scan"], rel["mleft"])
            if step[index].op == "LD"
            and step[index].raw_args == ("r9", "r7", "2")
        ]
        if len(action_start_candidates) != 1:
            raise GateError(
                "step: cannot identify the action start (LD r9,r7,2) uniquely"
            )
        action_start = action_start_candidates[0]
        if action_start >= rel["mleft"]:
            raise GateError("step: action start is not before mleft")

        prelude_src = step[: rel["scan"]]
        scan_src = step[rel["scan"] : action_start]
        action_src = step[action_start : rel["step_ret"] + 1]
        next_src = step[rel["next"] : rel["no_trans"]]
        no_trans_src = step[rel["no_trans"] :]

        expected_lengths = {
            "prelude": (prelude_src, 11),
            "scan": (scan_src, 10),
            "action": (action_src, 22),
            "next": (next_src, 2),
            "no_trans": (no_trans_src, 3),
        }
        for name, (items, expected) in expected_lengths.items():
            if len(items) != expected:
                raise GateError(
                    f"step: {name} block has {len(items)} instructions, "
                    f"expected {expected}"
                )
        if no_trans_src[-1].op != "RET":
            raise GateError("step: no_trans block does not end in RET")
        if step[rel["step_ret"]].op != "RET":
            raise GateError("step: step_ret label does not point to RET")

        # ------------------------------------------------------------------
        # Coq side
        # ------------------------------------------------------------------
        texts = {
            filename: strip_coq_comments((coq_dir / filename).read_text(encoding="utf-8"))
            for _, filename in (*BLOCK_FILES, *THEOREM_FILES, *CHAIN_DEFINITIONS)
        }
        coq_blocks = {
            name: parse_coq_block(texts[filename], name, coq_dir / filename)
            for name, filename in BLOCK_FILES
        }

        scan_match_pc = coq_nat_constant(
            texts["MinskyNaN16VM.v"], "scan_match_pc", coq_dir / "MinskyNaN16VM.v"
        )
        scan_none_pc = coq_nat_constant(
            texts["MinskyNaN16VM.v"], "scan_none_pc", coq_dir / "MinskyNaN16VM.v"
        )

        # Prelude: the standalone block exits at its own end (pc 11).  The
        # literal @step_ret return address is therefore compared to the
        # block-relative exit sentinel, not to the assembled return address.
        prelude_targets = {"step_ret": len(prelude_src)}
        prelude_norm = [
            normalize_source(insn, prelude_targets) for insn in prelude_src
        ]

        # Scan: first ten literal instructions, then the match fallthrough as
        # an explicit jump to the match sentinel, then the literal next: loop,
        # then the two model HALT exits.
        next_entry = len(scan_src) + 1
        scan_targets = {"no_trans": scan_none_pc, "next": next_entry}
        scan_norm = [
            normalize_source(insn, scan_targets) for insn in scan_src
        ]
        scan_norm.append(
            synthetic(
                "JMP",
                "ALWAYS",
                (scan_match_pc,),
                "scan match fallthrough -> match sentinel",
            )
        )
        next_targets = {"scan": 0}
        scan_norm.extend(normalize_source(insn, next_targets) for insn in next_src)
        scan_norm.append(synthetic("HALT", None, (), "scan match exit sentinel"))
        scan_norm.append(synthetic("HALT", None, (), "scan no-match exit sentinel"))

        # Action: the literal right branch falls through into mdone; Coq makes
        # that fallthrough an explicit jump.  Insert exactly one synthetic
        # jump before the literal mdone label.
        action_rel = {
            name: rel[name] - action_start
            for name in ("mleft", "mright", "mdone", "step_ret")
        }
        insert_index = action_rel["mdone"]

        def action_pc(index: int) -> int:
            return index + (1 if index >= insert_index else 0)

        action_targets = {
            "mleft": action_pc(action_rel["mleft"]),
            "mright": action_pc(action_rel["mright"]),
            "mdone": action_pc(action_rel["mdone"]),
            "step_ret": action_pc(action_rel["step_ret"]),
        }
        action_norm: list[Insn] = []
        for index, insn in enumerate(action_src):
            if index == insert_index:
                if action_src[index].op != "ST":
                    raise GateError(
                        "action: mdone does not begin with the head store"
                    )
                if action_src[index - 1].op != "ADD":
                    raise GateError(
                        "action: right-branch fallthrough is no longer an ADD"
                    )
                action_norm.append(
                    synthetic(
                        "JMP",
                        "ALWAYS",
                        (action_pc(action_rel["mdone"]),),
                        "action right-branch fallthrough",
                    )
                )
            action_norm.append(normalize_source(insn, action_targets))

        # no_trans: the literal block is already the Coq block.
        no_trans_norm = [
            normalize_source(insn, {}) for insn in no_trans_src
        ]

        compare_blocks("prelude_block", prelude_norm, coq_blocks["prelude_block"])
        compare_blocks("scan_block", scan_norm, coq_blocks["scan_block"])
        compare_blocks("action_block", action_norm, coq_blocks["action_block"])
        compare_blocks("no_trans_block", no_trans_norm, coq_blocks["no_trans_block"])

        # The literal driver and the generic Coq run recursion must still line
        # up structurally.  The number 100 and main's final assertions are
        # source-level facts, not Coq theorems.
        check_run100_driver(source_instructions, labels)
        check_definition_contains(
            texts,
            "MinskyNaN16StepEntrySpec.v",
            "step_entry",
            ("prelude_block table_base", "native_step"),
        )
        check_definition_contains(
            texts,
            "MinskyNaN16Run.v",
            "vm_run",
            ("step_entry vm table table_base",),
        )
        check_declarations(texts, CHAIN_DEFINITIONS, "Definition|Fixpoint")
        check_no_admitted(texts)
        check_theorem_contains(
            texts,
            "MinskyNaN16Run.v",
            "vm_run_refines",
            (
                "step_ok vm table table_base tbase",
                "vm_run n",
                "nrun n",
            ),
        )
        checked_theorems = check_declarations(
            texts, THEOREM_FILES, "Theorem|Lemma"
        )

        try:
            shown_source = source_path.relative_to(ROOT)
        except ValueError:
            shown_source = source_path
        print(
            f"PASS {shown_source}: "
            f"literal step prelude/scan/action/no_trans order"
        )
        for name, filename in BLOCK_FILES:
            print(
                f"PASS {name} <-> {filename}: "
                f"{len(coq_blocks[name])}/{len(coq_blocks[name])} instructions"
            )
        print(
            "PASS run100: literal 100-iteration CALL @step driver "
            "(main sets r13=1 and calls @run100 once)"
        )
        print(
            "PASS Coq step_entry/vm_run structure: "
            "prelude_block -> native_step, vm_run -> step_entry"
        )
        print(
            "PASS vm_run_refines remains conditional on step_ok "
            "(no admitted proof in the checked files)"
        )
        for name, filename in checked_theorems:
            print(f"PASS theorem {name} ({filename})")
        print(
            "NAN16 STEP/RUN100 TRANSCRIPTION PASS "
            "(source-text gate only; not a VM refinement certificate)"
        )
        return 0

    except (GateError, OSError) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
