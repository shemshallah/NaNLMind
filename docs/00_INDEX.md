# Reading order

This repository has three layers: provenance, mathematical core, and plan.

| order | document | question it answers |
|---:|---|---|
| 1 | [01_DISCOVERY.md](01_DISCOVERY.md) | What did Rounds 2–23 actually build, and what is still open? |
| 2 | [02_ARCHITECTURE.md](02_ARCHITECTURE.md) | What is the one global topology, and how is it organized? |
| 3 | [03_MATHEMATICAL_STRUCTURE.md](03_MATHEMATICAL_STRUCTURE.md) | What is the formal object `(A,C,E,H,T,P,L)`? |
| 4 | [04_REGISTER_FILE.md](04_REGISTER_FILE.md) | How is one 8 MiB full-address chart laid out, bit for bit? |
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
| 35 | [35_BOOTSTRAP_HEAD_STORE.md](35_BOOTSTRAP_HEAD_STORE.md) | How do trained head vectors reach the 2 GiB overbootstrap head arena? |
| 36 | [36_TRAINING_MERGE.md](36_TRAINING_MERGE.md) | How does Koyeb merge training deltas without holding the 2 GiB map? |
| 37 | [37_TWO_RATE_MESH.md](37_TWO_RATE_MESH.md) | How do bootstrap and overbootstrap learn together with different math? |
| 38 | [38_LAYERED_LEARNING.md](38_LAYERED_LEARNING.md) | How does every layer learn from the layer below, up to the global mesh? |
| — | [HYPERMATRIX_V1_V2_RECONCILIATION.md](HYPERMATRIX_V1_V2_RECONCILIATION.md) | How do the v1 NaNLM and v2 NaNLMind architectures compare, and how does the mapped hypermatrix/triad field integrate? |
| — | [GEOMETRIC_CREDIT_REPLACEMENTS.md](GEOMETRIC_CREDIT_REPLACEMENTS.md) | What replaces BPTT with local temporal-rail, cycle, holonomy, ring, leaf and triad credit? |
| — | [SYMBIOTIC_FIELD_ARCHITECTURE.md](SYMBIOTIC_FIELD_ARCHITECTURE.md) | How do micro-transformer triads, the 255-head wave, the hypermatrix/leaves and the global field fit in one memory budget, with CFT-based hybrid credit? |
| — | [UNIFIED_BUILD_CONTRACT.md](UNIFIED_BUILD_CONTRACT.md) | Which repository owns the native build/topology, and what may NaNROUTER and HERMES do? |
| — | [NAN16_ADAPTIVE_FIELD.md](NAN16_ADAPTIVE_FIELD.md) | What raw NaN16 kernels implement per-head self-modification, triad/field votes and Q16 coherence? |
| 39 | [39_BIT_BYTE_GATE.md](39_BIT_BYTE_GATE.md) | What happens when the mesh learns bit and byte transitions? |
| 40 | [40_BYTE_STREAM_GATE.md](40_BYTE_STREAM_GATE.md) | Does the mesh beat order-0 on real Alice byte transitions? |
| 41 | [41_RELATION_FIRST_CURRICULUM.md](41_RELATION_FIRST_CURRICULUM.md) | Why relations and penguin logic come before scaled bytes/words |
| 44 | [44_WORD_STREAM_GATE.md](44_WORD_STREAM_GATE.md) | How strong is a simple word-level baseline on Alice? |
| 45 | [45_WORD_VECTOR_GATE.md](45_WORD_VECTOR_GATE.md) | Can the word-vector layer beat unigram or bigram? |
| 46 | [46_LOGIC_SCALE_BASELINE.md](46_LOGIC_SCALE_BASELINE.md) | How large is the symbolic logic baseline, and what does it prove? |
| 47 | [47_BOOLEAN_HEADS_CURRICULUM.md](47_BOOLEAN_HEADS_CURRICULUM.md) | Do all 256 heads learn their own Boolean mappings and bit manipulation? |
| 48 | [48_HEAD_GATES.md](48_HEAD_GATES.md) | Can learned Boolean heads evaluate relation masks and exceptions? |
| 49 | [49_BOOLEAN_SPECTRUM.md](49_BOOLEAN_SPECTRUM.md) | What are ANF, Walsh, symmetry classes and the four-NaN transforms? |
| 50 | [50_LIFT_AND_SCALE.md](50_LIFT_AND_SCALE.md) | Which lift, hypervector and scale-stack forms should we build? |
| 51 | [51_HYPERVECTOR_TRIPLES.md](51_HYPERVECTOR_TRIPLES.md) | Can XOR hypervectors store and recall merged triples? |
| 52 | [52_TEACHER_GATE.md](52_TEACHER_GATE.md) | Do candidates, Boolean gates, and the triple store agree on cassowary? |
| 53 | [53_DETERMINISTIC_LAYERS.md](53_DETERMINISTIC_LAYERS.md) | What do reversible coupling, semiring closure, and exact NTT add? |
| 54 | [54_HYPERVECTOR_SCALE.md](54_HYPERVECTOR_SCALE.md) | Does the hypervector store hold 20k facts, and when does it fail? |
| 55 | [55_SUPERPOSITION_TODO.md](55_SUPERPOSITION_TODO.md) | What is the deferred superposition/phase design, and why is it not implemented? |
| 56 | [56_DEGREE_EXCEPTIONS.md](56_DEGREE_EXCEPTIONS.md) | Why does each nested exception level add one polynomial degree? |
| 57 | [57_SEMIRING_INHERITANCE.md](57_SEMIRING_INHERITANCE.md) | Can semiring closure handle 20k inheritance queries? |
| 58 | [58_NTT_AND_REVERSIBLE.md](58_NTT_AND_REVERSIBLE.md) | Do real-window NTT correlation and reversible coupling hold? |
| 59 | [59_SLOT_RECOVERY.md](59_SLOT_RECOVERY.md) | What happens when 30% of learned slots are deleted? |
| 60 | [60_UTM_ROADMAP.md](60_UTM_ROADMAP.md) | What is the honest 2CM/UTM path, and what must not be claimed? |
| 61 | [61_SPARSE_EXCEPTIONS.md](61_SPARSE_EXCEPTIONS.md) | How do sparse entity exceptions sit on top of dense kind closure? |
| 62 | [62_SPARSE_DEGREE_20K.md](62_SPARSE_DEGREE_20K.md) | Does the degree rule survive sparse sampling and held-out evaluation? |
| 63 | [63_TWO_COUNTER_U1.md](63_TWO_COUNTER_U1.md) | Can a bounded 2CM run entirely in chart registers? |
| 64 | [64_LIMB_ATLAS_ORBIT.md](64_LIMB_ATLAS_ORBIT.md) | Do multi-limb counters, atlas pages, and the 2CM orbit agree? |
| 65 | [65_TURING_MACHINE.md](65_TURING_MACHINE.md) | Is the Turing machine runtime real, and what is still missing for UTM? |
| 66 | [66_UNIVERSAL_TM_RUNTIME.md](66_UNIVERSAL_TM_RUNTIME.md) | Can one fixed step interpret multiple encoded TMs from chart tape? |
| 67 | [67_UTM_PROOF_HARNESS.md](67_UTM_PROOF_HARNESS.md) | What is checked so far toward a UTM proof? |
| 68 | [68_TAPE_LEDGER_LINK.md](68_TAPE_LEDGER_LINK.md) | How are tape pages checkpointed and committed? |
| 69 | [69_UTM_PROOF_OBLIGATIONS.md](69_UTM_PROOF_OBLIGATIONS.md) | What is still missing before a formal UTM proof? |
| 70 | [70_SMALL_UTM_TABLE.md](70_SMALL_UTM_TABLE.md) | What explicit small universal transition table fits the runtime? |
| 71 | [71_MINSKY_UTM.md](71_MINSKY_UTM.md) | Can a 23-state/8-symbol universal table be loaded and trace-checked? |
| 72 | [72_UTM_TRACE_INVARIANT.md](72_UTM_TRACE_INVARIANT.md) | What is the exact trace relation and what remains unproved? |
| 73 | [73_UTM_IMPLEMENTATION_STATUS.md](73_UTM_IMPLEMENTATION_STATUS.md) | What is complete, and what is the remaining proof limitation? |
| 74 | [74_TM_TO_BINARY_COMPILER.md](74_TM_TO_BINARY_COMPILER.md) | How does the 23×8 table compile to a 508-state binary TM? |
| 75 | [75_SELF_SIMULATION_PROBE.md](75_SELF_SIMULATION_PROBE.md) | What happens when the recursive self-run is executed? |
| 76 | [76_COMPACT_BINARY_RUNTIME.md](76_COMPACT_BINARY_RUNTIME.md) | How does the compiled binary machine run without the Minsky scan? |
| 77 | [77_UTM_PROOF_PACKAGE.md](77_UTM_PROOF_PACKAGE.md) | What is the UTM proof package and its remaining mechanization gap? |
| 78 | [78_LOGIC_CURRICULUM.md](78_LOGIC_CURRICULUM.md) | How are graded logic puzzles run through the runners? |
| 79 | [79_STAGED_LOGIC_TRAINER.md](79_STAGED_LOGIC_TRAINER.md) | What happens in the Boolean -> deep logic -> word session? |
| 80 | [80_TRAINING_CORPUS_PIPELINE.md](80_TRAINING_CORPUS_PIPELINE.md) | How do HERMES and Clocked drive the staged corpus? |
| 81 | [81_CONVERSATIONAL_TRAINING_LOOP.md](81_CONVERSATIONAL_TRAINING_LOOP.md) | How does the host model close the training conversation loop? |\n| — | [NaNLMind_CLOCKED](https://github.com/shemshallah/NaNLMind_CLOCKED) | Dedicated CLOCKED integration repository: HW3, NaN16, M0–M9, HERMES scratch and runner-ring design. |

The short version:

1. The address algebra is solid and exhaustively verified.
2. The R2–R23 code is a rich behavior specification, but much of the
   "cognition" is host C++ operating on topology cells, not local cell rules.
3. The new core fixes the framing: one global topology, charts as coordinate
   regions, hyperedges across spaces, a temporally split state space, and one
   ledger.
4. The next decisive experiments are substrate-only: hyperedge completion,
   bidirectional sequence memory, resonance learning, and a local-rule VM.

| 74 | [74_HERMES_HEAD_CORTEX.md](74_HERMES_HEAD_CORTEX.md) | How does HERMES submit typed evidence to read-only Boolean-head inference through NANNET? |
