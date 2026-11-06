# Training modes and conversational learning — implementation contract

Status: implementation target, not a claim that these paths are already complete.

## Why the existing metrics are flat

The current HERMES adapter sends every curriculum preset to `math-train`. That command performs one task: predict a selected target bit of the next byte from two selected bits in the previous/current bytes. The `logic`, `words`, `sentences`, and `pipeline` labels change the corpus, not the native objective. A scalar byte-bit held-out score therefore cannot establish progress at lexical, sentence, paragraph, or narrative resolution.

The Boolean foundation is a calibration gate, not a learning curve. `LogicSessionTrainer::train_boolean_basis` resets each head, assigns a deterministic target function, trains on all four truth rows, and evaluates those same four rows. Its exact score is expected to be 1.0 after sufficient repetitions and is not expected to rise across runs.

The native `words_after_logic` stage creates a fresh `WordMemory` from a fixed miniature corpus and evaluates ten fixed queries. It is a symbolic-memory smoke test, not persistent learning by the 256 heads.

## Two independent interaction modes

### A. Structured training

A teacher proposes machine-readable examples. A deterministic validator checks them, then the selected native task trainer consumes them. Keep train, validation, and frozen test partitions separate.

Required task families:
- Boolean: truth-table identification, unseen row order, composed circuits, inverse/contradiction probes.
- Relation/logic: entity, relation, polarity, conditions, exceptions, inheritance, counterexamples.
- Phonetic and morphemic: explicitly sourced or uncertainty-marked grapheme/phoneme and stem/affix records.
- Lexical: word identity, sense distinction, morphology, semantic relations and contextual usage.
- Word completion: prefix/context with multiple plausible candidates and one justified target.
- Sentence: agreement, syntax, ordering, continuation and ambiguity.
- Paragraph: reference tracking, cohesion, transition and topic continuity.
- Narrative: event order, time, causality, character/entity continuity and counterfactual variants.

Every task has its own objective, decoder/probe, train/validation/test metrics, baseline and sample counts. Never label a byte-bit score as word or sentence accuracy.

### B. Free-form conversational learning

Normal back-and-forth chat remains open-ended. Each exchange is eligible to produce two separate artifacts:
1. exact observations (UTF-8 bit/nibble/byte counts, tokenization and boundaries);
2. a structured, provenance-bound reflection of concepts and relations, including uncertainty, polarity, temporal links, alternatives and counterexamples.

The structured reflection is not itself a native update. It must be validated and passed to a native `conversation-ingest` operation. That operation must update the shared universe:
- assign participants to heads and canonical mirror-pair cells deterministically from stable concept/relation identifiers;
- update both temporal rails of each pair consistently, retaining the mirror involution;
- append a typed n-ary hyperedge for each relation/event with provenance, evidence weight, polarity and epoch;
- connect conversation events across turns and sessions when entities/relations align;
- preserve contradictory evidence as separate events rather than overwrite;
- commit the universe and append an auditable delta/event record;
- return before/after digests, changed head/pair counts, edge/hyperedge counts and rejected-event reasons.

Do not create a parallel semantic database that is disconnected from the native universe. The event ledger may be an audit log, but the native mirror pairs and hypergraph are the learning substrate.

Free-form chat must not claim a weight update if only a symbolic reflection was stored. Its result must report each stage separately: response, extraction, validation, native mutation, persistence, and evaluation.

## Ten independent resolution measurements

Keep the ten coordinates distinct:

| Resolution | Required held-out probe |
|---|---|
| L0 bit | bit transition and Boolean operator prediction |
| L1 nibble | nibble identity/transition and compositional reconstruction |
| L2 byte | byte prediction and reconstruction |
| L3 phonetic | grapheme/phoneme or syllable correspondence |
| L4 morpheme | segmentation and productive affix/stem generalization |
| L5 lexical | word/sense identity and relation discrimination |
| L6 word completion | contextual candidate ranking/completion |
| L7 sentence | next-unit choice, syntax and agreement |
| L8 paragraph | reference/cohesion/continuity |
| L9 narrative | event/time/causal consistency and continuation |

Each report includes: baseline-before, trained score, baseline-after where applicable, loss/accuracy, sample counts, coverage, confusion/errors, unique items, corpus/test digests, state digest before/after, and changed heads/pairs/hyperedges. No metric may be omitted silently; unsupported probes are `not_implemented`, not 0.0 or a copied score.

## Persistence and learning invariants

- Every training run restores the same named universe state before updates; it must never silently start from genesis or a temporary per-run state.
- A second run on new data must preserve prior learned state and produce a state digest change when updates are accepted.
- Replaying the same event is idempotent; a new event is not discarded merely because its subject matches an old one.
- Mirror-pair writes must update canonical and mirror views consistently.
- Hyperedges must reference actual participating head/pair cells and retain source/event provenance.
- Reorganization may change projections, not erase source events or native learning state.
- Validation/test examples never update heads, pair cells or hyperedges.
- A run that changes no state reports `no_op` and cannot claim training success.

## Required regression experiments

1. Run Boolean foundation twice: the fixed calibration gate remains exact, while a separate held-out/curriculum metric is reported.
2. Train logic on curriculum A, then novel logic curriculum B; show state extension and report held-out generalization rather than the fixed gate alone.
3. Train words on corpus A, then corpus B with new vocabulary/relations; verify old knowledge remains queryable and new held-out lexical probes improve.
4. Repeat for word completion, sentence, paragraph and narrative.
5. Compare structured ingestion with free-form chat ingestion; both must update the same native universe, but structured mode has explicit labels while chat mode retains extraction uncertainty.
6. Replay a conversation event; prove idempotence. Add a contradictory follow-up; prove both events remain and the relation assessment changes.
7. Restart the process between runs; prove persisted state is restored and extended.
8. Assert per-resolution metrics are genuinely computed from distinct held-out probes and are not aliases of byte accuracy.

## Implementation order

1. Fix measurement truthfulness and state continuity in the native runner.
2. Add native structured relation ingestion that writes mirror pairs and hyperedges.
3. Add task-specific trainers/probes for all ten resolutions.
4. Wire Hermes structured training tools to the corresponding task trainers.
5. Wire normal free-form chat reflection to the same native ingest path.
6. Add regression tests and report actual measured deltas before claiming improvement.
