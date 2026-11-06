#!/usr/bin/env python3
"""Clocked -> credential-free NaNLMind external-observation JSONL adapter."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

SCHEMA = "nanlm.clocked-experience"
VERSION = 1


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def digest(value: Any) -> str:
    payload = value if isinstance(value, bytes) else canonical_json(value)
    return hashlib.sha256(payload).hexdigest()


def bounded_label(value: Any, limit: int = 96) -> Optional[str]:
    if isinstance(value, (str, int, float, bool)):
        return str(value)[:limit]
    return None


def summarize_step(step: Dict[str, Any]) -> Dict[str, Any]:
    """Keep metadata and verdicts; never copy extracted values or source text."""
    result = step.get("result")
    if not isinstance(result, dict):
        result = {}
    summary: Dict[str, Any] = {
        "endpoint": bounded_label(step.get("endpoint"), 32),
        "name": bounded_label(step.get("name"), 48),
        "status": step.get("status"),
        "model_ms": step.get("ms"),
        "skipped": bounded_label(step.get("skipped"), 64),
    }
    for key in ("verdict", "injection", "answers_question", "stopped"):
        if key in result:
            summary[key] = bounded_label(result[key], 96)
    # Only retain field names, not field values.
    fields = result.get("fields")
    if isinstance(fields, dict):
        summary["extracted_field_names"] = sorted(str(k)[:64] for k in fields.keys())[:64]
    answers = result.get("answers")
    if isinstance(answers, dict):
        summary["decision_labels"] = sorted(str(k)[:64] for k in answers.keys())[:64]
        # Keep only primitive decision values; no free-form response text.
        decisions = {}
        for key, value in list(answers.items())[:32]:
            label = bounded_label(value)
            if label is not None:
                decisions[str(key)[:64]] = label
        if decisions:
            summary["decisions"] = decisions
    if "error" in step:
        summary["error_class"] = "clocked_step_error"
        summary["error_digest"] = digest(str(step.get("error", "")))
    return {k: v for k, v in summary.items() if v is not None}


def build_pipeline(text: str) -> list[dict]:
    """Conservative starter curriculum; pipeline steps share the original text."""
    return [
        {
            "pii": {
                "entities": ["person", "email", "phone", "address", "username"],
                "anonymize": "replace",
            },
            "name": "privacy_scan",
        },
        {
            "injection": {"source": "user", "evidence": True},
            "stop": True,
            "name": "injection_guard",
        },
        {
            "decide": {
                "questions": {
                    "task_family": {
                        "type": "choice",
                        "instructions": "Classify the primary kind of material or task.",
                        "options": [
                            "technical_document",
                            "code_or_script",
                            "support_request",
                            "general_prose",
                            "structured_record",
                            "unknown",
                        ],
                    },
                    "contains_claims": {
                        "type": "noul",
                        "instructions": "Does the text make factual or technical claims that could be checked?",
                    },
                }
            },
            "name": "task_classification",
        },
        {
            "extract": {
                "fields": {
                    "dates": "Dates explicitly stated in the source",
                    "quantities": "Measurements, counts, amounts, or numeric values explicitly stated",
                    "named_entities": "Names of products, organizations, systems, or technical components",
                    "claims": "Short factual or technical claims stated in the source",
                }
            },
            "name": "evidence_extraction",
        },
    ]


def make_event(source_text: str, response: Dict[str, Any], result_meta: Any) -> Dict[str, Any]:
    steps = response.get("steps", [])
    if not isinstance(steps, list):
        steps = []
    summaries = [summarize_step(s) for s in steps if isinstance(s, dict)]
    decision_labels = {}
    for item in summaries:
        decision_labels.update(item.get("decisions", {}))
    now = datetime.now(timezone.utc).isoformat()
    event_id = digest({"input": digest(source_text.encode("utf-8")), "response": digest(response)})
    event = {
        "schema": SCHEMA,
        "version": VERSION,
        "event_id": event_id,
        "observed_at": now,
        "input_sha256": digest(source_text.encode("utf-8")),
        "response_sha256": digest(response),
        "pipeline": summaries,
        "task_labels": decision_labels,
        "stopped": response.get("stopped"),
        "timing": response.get("timing"),
        "credits": getattr(result_meta, "credits", None),
        "cost_usd": getattr(result_meta, "cost_usd", None),
        "cost_basis": getattr(result_meta, "cost_basis", None),
        "learning_state": "awaiting_nanlmind_ingest",
        "raw_text_persisted": False,
        "raw_response_persisted": False,
    }
    return event


def process_file(path: Path, output, client) -> Dict[str, Any]:
    source_text = path.read_text(encoding="utf-8")
    if not source_text.strip():
        raise ValueError(f"{path}: input is empty")
    response = client.pipeline(text=source_text, steps=build_pipeline(source_text), on_error="continue")
    event = make_event(source_text, dict(response), response)
    output.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
    output.flush()
    return event


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="UTF-8 text file to process")
    parser.add_argument("--output", type=Path, default=Path("-"), help="JSONL output (default: stdout)")
    args = parser.parse_args(argv)

    if not os.environ.get("CLOCKED_API_KEY"):
        parser.error("CLOCKED_API_KEY must be provided by the server secret environment")

    try:
        from clocked_sdk import Clocked
    except ImportError:
        print("Missing dependency: install integrations/clocked/requirements.txt", file=sys.stderr)
        return 2

    output = sys.stdout if str(args.output) == "-" else args.output.open("a", encoding="utf-8")
    try:
        with Clocked() as client:
            event = process_file(args.input, output, client)
        print(json.dumps({"event_id": event["event_id"], "learning_state": event["learning_state"]}), file=sys.stderr)
        return 0
    except Exception as exc:
        # Do not print request bodies, response bodies, headers, or credentials.
        print(f"Clocked adapter failed ({type(exc).__name__}); inspect server-side diagnostics.", file=sys.stderr)
        return 1
    finally:
        if output is not sys.stdout:
            output.close()


if __name__ == "__main__":
    raise SystemExit(main())
