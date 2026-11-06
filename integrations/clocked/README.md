# Clocked experience adapter

This adapter makes Clocked a **supervisory observation source** for NaNLMind. It does not train Clocked, replace the 256-head universe, or write directly into the NaN16 guest.

## Security boundary

- Set `CLOCKED_API_KEY` only in the server/runner secret environment.
- Never put the key in source, GitHub variables, Android resources, CLI arguments, corpus files, JSONL events, logs, or screenshots.
- The Android app should call the authenticated NaNLMind intake service; it must never call Clocked with the privileged key.
- Events emitted here contain hashes, endpoint/status metadata, bounded labels and usage metadata—not source text or extracted field values.
- The adapter does not persist raw Clocked responses.

The key shared during setup should be rotated. Add the replacement to the actual server's secret store as `CLOCKED_API_KEY`. The GitHub integration used for this change cannot create repository Actions secrets.

## Install

Python 3.9+:

```sh
python -m pip install -r integrations/clocked/requirements.txt
```

## Run

```sh
export CLOCKED_API_KEY='(set in your secret manager; do not paste into shell history)'
python integrations/clocked/clocked_experience.py input.txt --output experiences.jsonl
```

The default pipeline performs PII detection, prompt-injection detection (which can stop later steps), task classification, and structured extraction. Review the endpoint results and the Clocked account's credit usage before processing large corpora.

## Event contract

Each JSONL event is a credential-free, content-minimized external observation:

- schema/version and deterministic event id
- input and response digests
- endpoint status/timing summaries
- bounded task label and verdict flags, when present
- credit/cost metadata when supplied by the SDK
- explicit `learning_state: awaiting_nanlmind_ingest`

It deliberately does **not** invent active heads, head deltas, correctness labels, or a committed NaNLMind generation. Those are produced only after the native learner evaluates the observation against its own baseline and a verified outcome.

## Idempotency and billing

The Clocked SDK sends an idempotency key and reuses it for retries. The adapter uses one pipeline request per input document. It does not silently retry a completed task as new billable work. Use small batches first.

## Current integration boundary

This is the external API adapter and event contract. Native ingestion into the C++ 256-head/Overbootstrap state, durable ledger commits, Android controls, and held-out learning benchmarks remain subsequent integration steps. No claim of end-to-end training is made by this adapter.
