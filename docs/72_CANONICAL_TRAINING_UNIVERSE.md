# BS0 / HW0 canonical training universe and endpoint evidence

**Topology correction:** There is one instantiated universe and one runner ring: `HW0::BS0`. BS0 owns six runner processes internally. HW4–HW8 are not runner addresses, do not need to exist, and must not be allocated or instantiated to represent runner processes.

## 1. Hierarchy and endpoint roles

- **HW0::BS0** is the single instantiated universe, runnerlink and six-runner ring. The six runner processes are internal BS0 ring members, not six HW nodes or separate universes.
- **HW1** is the phone endpoint.
- **HW2** is the HERMES demo endpoint.
- **HW3** is the Clocked demo endpoint.
- **HW4–HW8** are not required and must not be created to represent runner processes.
- **HW9–HW255** are available for other universes joining through NANNET, subject to identity, ACL and provenance checks.
- **MC0** is a downstream learner; it does not own BS0's six runners.

Internal runner process slots (0–5) are implementation-level ring slots only. They are not HW addresses. The six existing CPU runner processes remain members of BS0's one ring and continue to partition the shared 256-head workload under the existing runner ownership and generation-barrier protocol.

## 2. Existing training pipeline is canonical

The existing NaNLMind runner-training pipeline and HERMES pipeline remain the canonical implementations. Extend their source adapters and contracts in place; do not create a competing trainer, duplicate 256-head model, or separate canonical generation.

- `runner/nanlm_worker.py`: runner entry point, ring lifecycle, head ownership, heartbeat and orchestration.
- `runner/training_pipeline.py`: staged corpus/training pipeline and N16TXT handling.
- `runner/logic_curriculum.py`: graded logic curriculum and feedback loop.
- `runner/hermes_pipeline.py`: HERMES adapter, discovery records, memory-ledger integration and prompt-to-plan interface.
- Native HERMES head-cortex and relation train/evaluate commands: existing native 256-head learning and read-only inference contracts.
- Existing generation barrier: the only path that may promote accepted candidate head state into a canonical generation.

Clocked, HERMES, phone and NANNET inputs are adapters/evidence sources for these existing paths. They must not become a second trainer.

## 3. BS0 logic-training flow

```text
                  HW0::BS0
       one instantiated universe / runnerlink
       one BS0 ring containing six runner processes
       shared 256-head topology and existing trainers
                       |
          +------------+------------+
          |            |            |
        HW1          HW2          HW3
       phone        HERMES       Clocked
          |            |            |
          +------ evidence/source adapters ------+
                                                   |
                                  existing corpus + logic +
                                  HERMES training interfaces
                                                   |
                                  candidate updates + held-out eval
                                                   |
                                  existing six-runner generation barrier
                                                   |
                                         BS0 canonical state

       NANNET: HW9–HW255 external universes
       (separate identity/ACL; no BS0 runner ownership)
```

The six runner processes train the shared heads as one BS0 ring. They do not each create an independent model. Runner shards, evidence receipts and candidate updates remain provenance-bound to their runner process, source, epoch and base generation.

## 4. MC0 is a downstream training phase

MC0 is deliberately downstream of BS0. It is not the six-runner owner and must not be substituted for BS0 in runner routing, heartbeat identity, head ownership or current logic training.

The planned MC0 training inputs are:

1. Trained and versioned BS0 logic state/results.
2. The ten mathematical layers.
3. NANNET mathematical transformations.
4. BS0DB.
5. MC0DB.

MC0 training begins as a distinct downstream phase over those inputs. Until its own contracts, data lineage, evaluation and promotion gates are implemented, BS0 remains the active logic trainer and canonical runner ring. MC0 must not receive an automatic canonical update merely because BS0 or an endpoint emitted evidence.

## 5. Evidence and learning boundaries

Clocked classifications, HERMES observations, phone observations and external NANNET universe messages are evidence, not ground truth by default. A source receipt preserves source identity, payload/source digest, ACL/provenance and clock/generation context.

The Clocked router consumer is an evidence-ingestion adapter only. It does not train a head, mark an outcome correct, update a candidate, or advance a generation. Later training use must pass through the existing corpus/logic/HERMES interfaces and established evaluation and generation barriers.

The existing HERMES head-cortex read-only endpoint remains read-only. Native relation training remains a separate candidate-producing operation. Candidate evaluation is not promotion; only the existing six-runner generation barrier may publish accepted BS0 head state.

## 6. NANNET universe boundary

NANNET is the authenticated routing and mathematical-transformation boundary for external universes. HW9–HW255 are available to other universes joining through NANNET; those universes retain their own identity, ACL, source provenance and local state. Their evidence can be routed to BS0 under explicit policy, but they do not acquire BS0 runner ownership or canonical write authority.

No external universe may claim a BS0 runner process slot, overwrite BS0 state, or address MC0 as if it owned the runner ring.

## 7. Invariants

- There is one instantiated universe: `HW0::BS0`.
- BS0 owns exactly six internal runner processes; these do not map to HW4–HW8 or any other HW addresses.
- HW1, HW2 and HW3 retain phone, HERMES demo and Clocked demo roles.
- HW9–HW255 remain available for external NANNET universes.
- Existing runner, logic-curriculum, corpus and HERMES pipelines are extended in place, never replaced by a parallel trainer.
- Six internal runner slots partition the shared 256-head topology.
- Evidence is not correctness; candidate creation is not promotion.
- No endpoint or external universe directly mutates canonical BS0 head state.
- Only the existing generation barrier may commit accepted canonical head updates.
- MC0 remains a later downstream learner over BS0, ten mathematical layers, NANNET mathematical transformations, BS0DB and MC0DB.
