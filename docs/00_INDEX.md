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
| 26 | [26_RATE_LIMITS.md](26_RATE_LIMITS.md) | How does the 24/7 ring stay inside GitHub API limits? |
| 27 | [27_ANDROID_BOOTSTRAP.md](27_ANDROID_BOOTSTRAP.md) | How does the bootstrap run on Android, and how large is Gutenberg? |
| 28 | [28_BEHAVIOR_GATES.md](28_BEHAVIOR_GATES.md) | What do the penguin/logic gates prove, and what is the fixed challenge? |
| 29 | [29_REPEATABILITY.md](29_REPEATABILITY.md) | Is the alternating clock nondeterminism or a designed period-2 orbit? |
| 30 | [30_VECTOR_BINS.md](30_VECTOR_BINS.md) | How do points address vector bins and macro associations? |
| 31 | [31_WORD_MEMORY.md](31_WORD_MEMORY.md) | What does the word layer over bins answer, and what does it prove? |
| 32 | [32_HARD_LOGIC_WARMUP.md](32_HARD_LOGIC_WARMUP.md) | What happens after ten bytewise passes on nested-exception relations? |
| 33 | [33_BOOTSTRAP_ROUTER.md](33_BOOTSTRAP_ROUTER.md) | How does the bootstrap router work with a bootstrap-only 2 GiB map and 8 MiB Android peers? |
| 34 | [34_HOPFIELD_LEARNING.md](34_HOPFIELD_LEARNING.md) | Can the sparse Hopfield layer learn and replay a token sequence? |
| 35 | [35_BOOTSTRAP_HEAD_STORE.md](35_BOOTSTRAP_HEAD_STORE.md) | How do trained head vectors reach the 2 GiB overbootstrap head arena? |
| 36 | [36_TRAINING_MERGE.md](36_TRAINING_MERGE.md) | How does Koyeb merge training deltas without holding the 2 GiB map? |
| 37 | [37_TWO_RATE_MESH.md](37_TWO_RATE_MESH.md) | How do bootstrap and overbootstrap learn together with different math? |
| 38 | [38_LAYERED_LEARNING.md](38_LAYERED_LEARNING.md) | How does every layer learn from the layer below, up to the global mesh? |
| 39 | [39_BIT_BYTE_GATE.md](39_BIT_BYTE_GATE.md) | What happens when the mesh learns bit and byte transitions? |
| 40 | [40_BYTE_STREAM_GATE.md](40_BYTE_STREAM_GATE.md) | Does the mesh beat order-0 on real Alice byte transitions? |
| 41 | [41_RELATION_FIRST_CURRICULUM.md](41_RELATION_FIRST_CURRICULUM.md) | Why relations and penguin logic come before scaled bytes/words |
| 42 | [42_BYTE_EXPERT_ROUTER.md](42_BYTE_EXPERT_ROUTER.md) | How does overbootstrap choose between Hopfield and bigram byte experts? |
| 43 | [43_BYTE_ROUTER_REPEATS.md](43_BYTE_ROUTER_REPEATS.md) | Does repeating the same byte corpus improve the routed result? |
| 44 | [44_WORD_STREAM_GATE.md](44_WORD_STREAM_GATE.md) | How strong is a simple word-level baseline on Alice? |
| 45 | [45_WORD_VECTOR_GATE.md](45_WORD_VECTOR_GATE.md) | Can the word-vector layer beat unigram or bigram? |
| 46 | [46_LOGIC_SCALE_BASELINE.md](46_LOGIC_SCALE_BASELINE.md) | How large is the symbolic logic baseline, and what does it prove? |
| 47 | [47_BOOLEAN_HEADS_CURRICULUM.md](47_BOOLEAN_HEADS_CURRICULUM.md) | Do all 256 heads learn their own Boolean mappings and bit manipulation? |
| 48 | [48_HEAD_GATES.md](48_HEAD_GATES.md) | Can learned Boolean heads evaluate relation masks and exceptions? |
| 49 | [49_BOOLEAN_SPECTRUM.md](49_BOOLEAN_SPECTRUM.md) | What are ANF, Walsh, symmetry classes and the four-NaN transforms? |
| 50 | [50_LIFT_AND_SCALE.md](50_LIFT_AND_SCALE.md) | Which lift, hypervector and scale-stack forms should we build? |
| 51 | [51_HYPERVECTOR_TRIPLES.md](51_HYPERVECTOR_TRIPLES.md) | Can XOR hypervectors store and recall merged triples? |
| 52 | [52_TEACHER_GATE.md](52_TEACHER_GATE.md) | Do Hopfield, Boolean gates, and the triple store agree on cassowary? |
| 53 | [53_DETERMINISTIC_LAYERS.md](53_DETERMINISTIC_LAYERS.md) | What do reversible coupling, semiring closure, and exact NTT add? |
| 54 | [54_HYPERVECTOR_SCALE.md](54_HYPERVECTOR_SCALE.md) | Does the hypervector store hold 20k facts, and when does it fail? |
| 55 | [55_SUPERPOSITION_TODO.md](55_SUPERPOSITION_TODO.md) | What is the deferred superposition/phase design, and why is it not implemented? |
| 56 | [56_DEGREE_EXCEPTIONS.md](56_DEGREE_EXCEPTIONS.md) | Why does each nested exception level add one polynomial degree? |

The short version:

1. The address algebra is solid and exhaustively verified.
2. The R2–R23 code is a rich behavior specification, but much of the
   "cognition" is host C++ operating on topology cells, not local cell rules.
3. The new core fixes the framing: one global topology, charts as coordinate
   regions, hyperedges across spaces, a temporally split state space, and one
   ledger.
4. The next decisive experiments are substrate-only: hyperedge completion,
   bidirectional sequence memory, resonance learning, and a local-rule VM.
