# Reading order

This repository has three layers: provenance, mathematical core, and plan.

| order | document | question it answers |
|---:|---|---|
| 1 | [01_DISCOVERY.md](01_DISCOVERY.md) | What did Rounds 2–23 actually build, and what is still open? |
| 2 | [02_ARCHITECTURE.md](02_ARCHITECTURE.md) | What is the one global topology, and how is it organized? |
| 3 | [03_MATHEMATICAL_STRUCTURE.md](03_MATHEMATICAL_STRUCTURE.md) | What is the formal object `(A,C,E,H,T,P,L)`? |
| 4 | [04_REGISTER_FILE.md](04_REGISTER_FILE.md) | How is one 8 MiB full-address chart laid out, bit for bit? |
| 5 | [05_MEMORY_TIERS.md](05_MEMORY_TIERS.md) | How do we rebuild reporam/repovram for this object? |
| 6 | [06_HEADS_RESONANCE.md](06_HEADS_RESONANCE.md) | How do the 256 heads, resonance, and self-modification work? |
| 7 | [07_DISTRIBUTED.md](07_DISTRIBUTED.md) | How does one object run on six runners without fragmenting? |
| 8 | [08_TRAINING.md](08_TRAINING.md) | How does it learn, and how can a community train it? |
| 9 | [09_ROADMAP.md](09_ROADMAP.md) | What do we build next, in what order, with what gates? |
| 10 | [10_FALSIFICATION.md](10_FALSIFICATION.md) | What would prove this wrong? |
| 11 | [11_GLOSSARY.md](11_GLOSSARY.md) | Terms and exact counts. |
| 12 | [12_PROVENANCE.md](12_PROVENANCE.md) | Archive hashes, duplicates, and round map. |
| 13 | [13_OPEN_QUESTIONS.md](13_OPEN_QUESTIONS.md) | The genuinely unresolved questions. |
| 14 | [14_TEMPORAL_CLOCK.md](14_TEMPORAL_CLOCK.md) | How does the nanclock logical oscillator synchronize distributed spaces? |
| 15 | [15_PHASE_SCHEDULING.md](15_PHASE_SCHEDULING.md) | What are the transform-phase orbits and the bit-reversed wake schedule? |
| 16 | [16_GROWTH_CONSOLIDATION.md](16_GROWTH_CONSOLIDATION.md) | When does a head grow, and how does consolidation flip the manifest? |
| 17 | [17_TRAINING_HEADS.md](17_TRAINING_HEADS.md) | How do the heads train, and what do the language/logic baselines show? |
| 18 | [18_HEAD_RING.md](18_HEAD_RING.md) | How do six runners hand off 256 heads and map them back? |
| 19 | [19_LEGACY_TESTS.md](19_LEGACY_TESTS.md) | Which R18T language tests and R21–R23 logic tests are integrated? |
| 20 | [20_META_ROUTER.md](20_META_ROUTER.md) | How do universes become heads and routes become pair cells? |
| 21 | [21_FRAME_SYNC.md](21_FRAME_SYNC.md) | How do forward/rollback frames meet, and how do heads invert a frame? |
| 22 | [22_ATOMIC_CLOCK.md](22_ATOMIC_CLOCK.md) | How is wall time anchored without putting it into state order? |
| 23 | [23_NAN_TRANSLATION_FABRIC.md](23_NAN_TRANSLATION_FABRIC.md) | How do physical, universe, and semantic addresses translate? |
| 24 | [24_ONE_UNIVERSE_TRAINING.md](24_ONE_UNIVERSE_TRAINING.md) | How does one universe train and pass its gates? |
| 25 | [25_GLOBAL_META_BRAINSTORM.md](25_GLOBAL_META_BRAINSTORM.md) | What is the 256×256×256 global meta, and why not build it yet? |

The short version:

1. The address algebra is solid and exhaustively verified.
2. The R2–R23 code is a rich behavior specification, but much of the
   "cognition" is host C++ operating on topology cells, not local cell rules.
3. The new core fixes the framing: one global topology, charts as coordinate
   regions, hyperedges across spaces, a temporally split state space, and one
   ledger.
4. The next decisive experiments are substrate-only: hyperedge completion,
   bidirectional sequence memory, resonance learning, and a local-rule VM.
