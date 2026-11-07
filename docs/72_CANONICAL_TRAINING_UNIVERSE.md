# BS0 / HW0 canonical training universe and endpoint evidence

**Architecture correction:** BS0 owns the six-runner ring. MC0 does not own the runners and is not the current logic trainer. The existing NaNLMind runner-training pipeline and HERMES pipeline remain the canonical implementations; integrations must extend their inputs and handoff contracts, not replace them.

## 1. Hierarchy and ownership

- **BS0** is the runner-ring owner and primary logic-training system.
- **HW0** is the instantiated universe/subunit inside BS0 and the runnerlink interface through which BS0 coordinates its work.
- **HW1** is the phone endpoint.
- **HW2** is the HERMES demo endpoint.
- **HW3** is the Clocked demo endpoint.
- **HW4–HW8** are the five runner HW addresses explicitly enumerated in the current topology description.
- **HW9–HW255** are reserved for other universes joining through NANNET. They must not be consumed as an unannounced sixth runner address.

There are six runner processes/repositories: `nanlm-cpu-1` through `nanlm-cpu-6`. Their existing internal ring slots remain 0–5 and continue to partition the 256 heads with the established `owner(head) = head mod 6` rule. Internal runner slot numbers are not automatically HW addresses. The stated HW4–HW8 range contains five addresses, so the sixth runner's HW address must be resolved explicitly before assigning or changing HW routing; no address is inferred here.

## 2. Existing training pipeline is canonical

The following existing paths are retained and must not be replaced by a parallel trainer:

- `runner/nanlm_worker.py`: runner entry point, ring lifecycle, head ownership, heartbeat and orchestration.
- `runner/training_pipeline.py`: existing staged corpus/training pipeline and N16TXT corpus handling.
- `runner/logic_curriculum.py`: existing graded logic curriculum and feedback loop.
- `runner/hermes_pipeline.py`: existing HERMES adapter, discovery records, memory-ledger integration and prompt-to-plan interface.
- Native HERMES head-cortex and relation train/evaluate commands: existing native 256-head learning and read-only inference contracts.
- Existing generation barrier: the only path that may promote accepted candidate head state into a canonical generation.

Router, Clocked, phone, HERMES and future NANNET sources are adapters/evidence inputs to this system. They must not create a second training pipeline, a competing 256-head model, or a separate canonical generation.

## 3. BS0 logic-training flow

```text
BS0
 └── HW0 instantiated universe / runnerlink
      ├── HW1 phone observations
      ├── HW2 HERMES demo observations
      ├── HW3 Clocked demo observations
      ├── six existing NaNLMind runner processes
      │    └── shared 256-head topology / existing logic + corpus trainers
      └── NANNET authenticated intake and universe routing
           └── HW9–HW255: other universes, isolated by identity and ACL

existing trainers -> candidate updates -> held-out evaluation
                  -> six-runner generation barrier -> BS0 canonical state
```

The six runners train the shared heads as one BS0 ring. They do not each create an independent model. Runner shards, evidence receipts and candidate updates remain provenance-bound to their runner, source, epoch and base generation.

## 4. MC0 is a downstream training phase

MC0 is deliberately downstream of BS0. It is not the six-runner owner and must not be substituted for BS0 in runner routing, heartbeat identity, head ownership or current logic training.

The planned MC0 training inputs are:

1. The trained and versioned BS0 logic state/results.
2. The ten mathematical layers.
3. NANNET mathematical transformations.
4. BS0DB.
5. MC0DB.

MC0 training begins as a distinct downstream phase over those inputs. Until its own contracts, data lineage, evaluation and promotion gates are implemented, BS0 remains the active logic trainer and canonical runner ring. MC0 must not receive an automatic canonical update merely because BS0 or an endpoint emitted evidence.

## 5. Evidence and learning boundaries

Clocked classifications, HERMES observations, phone observations and external NANNET universe messages are evidence, not ground truth by default. A source receipt must preserve source identity, payload/source digest, ACL/provenance and clock/generation context.

The Clocked router consumer is an evidence-ingestion adapter only. It does not train a head, mark an outcome correct, update a candidate, or advance a generation. Any later training use must pass through the existing corpus/logic/HERMES training interfaces and the established evaluation and generation barriers.

The existing HERMES head-cortex read-only endpoint remains read-only. Native relation training remains a separate candidate-producing operation. Candidate evaluation is not promotion; only the existing six-runner generation barrier may publish an accepted BS0 head generation.

## 6. NANNET universe boundary

NANNET is the authenticated routing and mathematical-transformation boundary for external universes. HW9–HW255 are available to other universes joining through NANNET; those universes retain their own identity, ACL, source provenance and local state. Their evidence can be routed to BS0 under explicit policy, but they do not acquire BS0 runner ownership or canonical write authority.

No external universe may claim a BS0 runner slot, overwrite BS0 state, or address MC0 as if it owned the runner ring.

## 7. Invariants

- BS0 owns exactly six runner processes; MC0 owns none of them.
- HW0 is BS0's instantiated universe and runnerlink.
- HW1, HW2 and HW3 retain phone, HERMES demo and Clocked demo roles.
- HW9–HW255 remain available for external NANNET universes.
- Existing runner, logic-curriculum, corpus and HERMES pipelines are extended in place, never replaced by a parallel trainer.
- Six internal runner slots continue to partition the shared 256-head topology.
- Evidence is not correctness; candidate creation is not promotion.
- No endpoint or external universe directly mutates canonical BS0 head state.
- Only the existing generation barrier may commit accepted canonical head updates.
- MC0 remains a later downstream learner over BS0, ten mathematical layers, NANNET mathematical transformations, BS0DB and MC0DB.
