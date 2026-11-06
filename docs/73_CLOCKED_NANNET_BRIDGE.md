# Clocked to NANNET evidence bridge

Clocked observations are stored by NANNET as endpoint-bound evidence. The runner-only observation queue is exposed at `GET /internal/observations`; acknowledgements use `POST /internal/observations/ack` only after a durable native fold receipt exists. Observations are not validated corpora and must not be sent through the text-corpus consumer. They remain unverified until an independent target or outcome exists. The canonical six-runner ring alone commits model generations.

## Parallel workstreams

1. Clocked adapter: evaluate task families and emit content-minimized, idempotent observation envelopes.
2. NANNET intake: authenticate endpoint identity, persist evidence, deduplicate event IDs, and retain provenance.
3. Runner fold: claim bounded batches, verify base generation and event schema, write a durable evidence receipt, and only then acknowledge.
4. Canonical trainer: consume only verified curriculum/policy deltas and perform generation-barrier commits.
5. Evaluation: compare ring-only, ring plus Clocked evidence, and ring plus all endpoints on endpoint-separated held-out tasks.

The bridge must never treat an HTTP 202, successful poll, or acknowledgement as proof of model learning.