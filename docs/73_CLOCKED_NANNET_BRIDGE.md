# CLOCKED service to NANNET and NaNLMROUTER bridge

The upstream CLOCKED SDK, task orchestration, fixtures and client integration are owned by [NaNLMind_CLOCKED](https://github.com/shemshallah/NaNLMind_CLOCKED). The authenticated gateway is embedded in the existing NaNLMind Koyeb NANNET process at `integrations/nannet/server.py`; this is one service, one listener and one persistent volume, not a second Clocked or router deployment.

## Evidence path

Clocked observations are stored by NANNET as endpoint-bound evidence and by the embedded NaNLMROUTER source inbox as a minimized, durable work item. The router payload contains only the event ID, input/response SHA-256 digests, NANNET address, node point, base generation and deterministic head shard. Raw prompt text, raw provider responses and the upstream `CLOCKED_API_KEY` are never copied into the router payload.

- NANNET evidence queue: `GET /internal/observations`; ACK with `POST /internal/observations/ack` only after a durable evidence fold.
- NaNLMROUTER queue: `POST /v1/riddle/lease`, `POST /v1/riddle/ack`, and `POST /v1/riddle/retry`.
- Six-runner ring: `GET /v1/riddle/volumes` and `POST /v1/riddle/ring/heartbeat`; the six `nanlm-cpu-*` workflows point `NANLM_ROUTER_URL` at the same Koyeb origin as `BSR0_PORTAL_API`.
- Candidate-only policy feedback remains signed and cannot directly commit the live route map.

The runner-only observation consumer writes its evidence ledger before acknowledging NANNET. The router worker separately leases the minimized source envelope, executes a provenance-bound step, and acknowledges only after its own durable trace. These are evidence and work queues, not proof of model learning.

## Training boundary

An HTTP 202, successful poll, lease, or ACK is not a training result. Clocked evidence starts as `outcome_verified=false`; it cannot assert correctness or supply canonical head deltas. The six-runner NaNLMind ring remains the only canonical 256-head learner and the only path that may commit a generation through the canonical merge API. Raw NaN16/NaN0S corpus training remains a separate validated corpus path and must preserve its binary payload and provenance rather than being converted into Clocked prose.

## Parallel workstreams

1. Clocked adapter: execute typed endpoint tasks and emit content-minimized, idempotent observation envelopes.
2. NANNET intake: authenticate endpoint identity, persist evidence, deduplicate event IDs and retain lease provenance.
3. NaNLMROUTER intake: enqueue digest-only source records in the durable BS0:0 inbox, partitioned by node point and head shard.
4. Runner fold: lease bounded work, verify source/ACL digests, produce a trace, and ACK only after durable receipt.
5. Canonical trainer: consume only independently verified curriculum/policy deltas and perform generation-barrier commits.
6. Evaluation: compare ring-only, ring plus Clocked evidence, and ring plus all endpoints on endpoint-separated held-out tasks.

The bridge must never treat an HTTP 202, successful poll, or acknowledgement as proof of model learning.
