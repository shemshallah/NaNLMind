# Canonical training universe and endpoint evidence

**Architecture correction:** NaNLMind's six-runner ring is the primary training universe. Clocked is one endpoint environment, not the training coordinator or owner of the model.

## 1. Canonical universe

NaNLMind owns one global topology and one canonical generation. The six runner slots (0 through 5) divide the 256 heads using the existing deterministic owner(head) = head mod 6 map. The ring's prepare/barrier/commit cycle verifies all 256 head packets and publishes one ledger event and next manifest generation.

This is the primary bootstrap and training loop. The ring trains the canonical 256-head state; it is not a fifth endpoint and is not replaced by an external service.

## 2. Four endpoint environments

| ID | Environment | Role | State ownership |
|---|---|---|---|
| bootstrap | NaNLMind six-runner ring | Primary training universe; canonical head updates and generation commits | Canonical global state |
| my_android | MY Android / Termux edge | Local edge experience and scoped endpoint observations | Local 8 MiB edge universe |
| hermes_demo | Hermes demo | Independent demo task/experience stream | Hermes demo endpoint |
| clocked_demo | Clocked demo | External task evaluation, classification, extraction and safety observations | Clocked gateway only |

The machine-readable registry is integrations/clocked/training_endpoints.json. The Clocked gateway tags each observation with source_endpoint: clocked_demo. Other endpoint clients must use the same versioned logical event contract and their own endpoint identity. Endpoint identity is server- or runner-bound; a participant must not be allowed to claim another endpoint by editing JSON.

## 3. Overbootstrap: aggregation above the ring

Overbootstrap is the cross-endpoint meta-learning layer. It aggregates verified, mergeable summaries from the four endpoint environments. It learns evidence about head and route reliability across task families; confidence calibration and disagreement; endpoint quality, coverage and cost; and which policies/curricula should be sent back to the canonical ring.

It does not become another 256-head universe, take ownership of endpoint-local state, or overwrite the canonical bootstrap's keys and slots. It sends bounded policy/evidence feedback to the runner ring. The canonical ring remains the place where accepted training updates are applied and committed.

## 4. Evidence lifecycle

```text
MY Android ───────┐
Hermes demo ──────┼─> endpoint-authenticated, versioned observations
Clocked demo ────┘                   │
                                    ▼
                        Overbootstrap evidence fold
                        provenance / dedup / verify
                                    │
                                    ▼
                         bounded policy + curriculum
                                    │
                                    ▼
NaNLMind six-runner ring: 256 heads -> train -> evaluate -> commit
                                    │
                                    └── canonical generation / trace summaries
```

The bootstrap ring also contributes its own traces to Overbootstrap. It is the primary learner, not just an input adapter. External endpoint observations do not directly mutate head cells. They first pass endpoint authentication, provenance, duplicate detection, generation compatibility, and outcome verification. Only a native learner/merge operation can create canonical head deltas and commit them.

A Clocked classification or extraction is an observation, not a correctness label. Until a target or independently verified outcome exists, the record is evidence-only and receives no correctness credit. The event's learning_state: awaiting_nanlmind_ingest is intentional.

## 5. Shared hardware-neutral contract

The transport is HTTP/JSON today, with a versioned schema. Its logical meaning is independent of CPU, OS, memory tier, and accelerator. Each endpoint adapter maps local work into the same event envelope. A later NaN16-native or binary transport can encode the same fields without changing event semantics.

The Clocked gateway holds the upstream Clocked key. Android, Hermes, runner workers and participants receive only their own scoped endpoint credentials. No endpoint receives the runner ring's privileged GitHub secret or canonical state-write authority.

## 6. Non-goals and invariants

- No independent competing 256-head models for each endpoint.
- No direct Clocked-to-head mutation.
- No raw endpoint corpus copied into Overbootstrap by default.
- No endpoint can overwrite another endpoint's local state.
- No stale or duplicate training delta can advance a generation.
- No correctness credit without an explicit target or verified outcome.
- One canonical ledger and generation history for the NaNLMind training universe; endpoint provenance remains attached to every imported summary.

## 7. Implementation sequence

1. Keep the six-runner ring as the canonical bootstrap learner.
2. Standardize endpoint identity and event envelopes for Android, Hermes and Clocked; preserve endpoint-specific authentication.
3. Add an Overbootstrap intake fold for trace summaries, provenance, idempotency, stale-generation checks and evidence counters.
4. Connect the fold to the existing bounded LayerPolicy / head reliability path.
5. Let the canonical runner ring consume accepted curriculum/policy and perform real head updates.
6. Evaluate ring-only vs ring + each endpoint vs all endpoints on held-out, endpoint-separated tasks.

The first milestone is the trace/merge boundary, not a claim of improved language performance. Every improvement must survive held-out evaluation and a replayable generation commit.
