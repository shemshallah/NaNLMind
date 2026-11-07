# Mathematical transformation catalog and layer-unification contract

Status: architecture contract and implementation inventory. This document does not claim that every operation below is already implemented. Each operation must be marked `implemented`, `tested`, `verified`, `experimental`, or `planned` in the eventual machine-readable registry; names in this inventory are not proof of implementation.

## 1. Ownership and non-negotiable topology

- There is one instantiated universe: `HW0::BS0`.
- BS0 owns the existing six internal runner processes `R0–R5`. They partition one shared 256-head topology; they are not six HW endpoints or six independent models.
- `MC0Link` is downstream of BS0. MC0 consumes versioned BS0 outputs and mathematical results; it does not own the runner ring.
- `HW4–HW8` are not runner addresses and must not be instantiated to represent workers.
- NANNET remains the authenticated network, identity, route, capability and transformation boundary. It does not become a second canonical learner.
- The existing runner-training, corpus, logic-curriculum, native head-cortex and HERMES pipelines remain canonical. Extend their adapters and contracts in place. No parallel trainer, duplicate 256-head model, or alternate promotion path is introduced.

The earlier architecture records in `docs/49_BOOLEAN_SPECTRUM.md`, `docs/50_LIFT_AND_SCALE.md`, `docs/53_DETERMINISTIC_LAYERS.md`, `docs/72_CANONICAL_TRAINING_UNIVERSE.md`, and `docs/78_LOGIC_CURRICULUM.md` through `docs/81_CONVERSATIONAL_TRAINING_LOOP.md` remain the mathematical and training foundations.

## 2. Two coupled systems, not one collapsed stack

There are multiple existing layer namespaces. They must remain distinct:

- **Language/evidence resolution L0–L9** is defined in `runner/resolution_layers.py`: bit, nibble, byte, phonetic, morpheme, lexical, word completion, sentence, paragraph and narrative. These describe the granularity at which evidence is stored.
- **NANNET M0–M9** is the separate transformation namespace requested for the network/math path. The current repository audit did not locate a canonical M0–M9 registry or stage contract, so this remains an integration target, not a claim of implemented stages. The ten router mapping stages below are not silently renamed M0–M9.
- **Router mapping layers** are the ten existing `MAPPING_LAYERS` in `runner/nannet_router/macro.py`: bit-to-head, address-to-head, head-to-bin, vector-to-bin, hyperedge, temporal-link, logic-rule, route, merge-provenance and meta-policy.
- **Mathematical catalog families** are typed operation families (Boolean, arithmetic, linear algebra, geometry, relations, discrete transforms, symbolic reasoning, composition and meta-learning). They crosscut the other layer systems and must not be relabeled as L0–L9 or M0–M9.

The mathematical layer decomposition requested for the ten mathematical layers remains an explicit audit item until the NANNET M0–M9 contract is located/defined and the ten router mapping stages have been reconciled. Repository code search did not locate declarations for `vector13`, `vector42`, `matha`, `mathb`, or a `NaNLayer` type. Their bit layouts and semantics remain unknown; do not fabricate them. The existing `NaN16` word model, Boolean spectrum, transform chain, reversible operations, semiring and NTT modules are concrete math primitives to catalog and reuse. Do not invent a third ten-stage numbering scheme. Exchange occurs through typed, provenance-bearing packets with explicit source namespace, destination namespace, packet schema, direction and validation rule. A result may be projected into several layers without merging their state or semantics.

## 3. Mathematical catalog: scope and families

A complete catalog is necessarily open-ended: user-defined functions, parameterized operators, dimensions and algebraic structures cannot be exhaustively enumerated as a finite list. Completeness therefore means a complete **catalog contract**, exhaustive finite families where possible, and explicit coverage accounting for parameterized or open-ended families.

Every catalog entry must define:

1. stable identifier, canonical name, aliases, version and family;
2. input arity, operand roles, scalar/domain types, shapes and dimension constraints;
3. output type and shape;
4. preconditions, postconditions, domain exclusions and exceptional cases;
5. exactness class: exact integer/rational/finite-field, exact symbolic, bounded approximation, heuristic, or learned proposal;
6. identity, inverse, involution, composition and algebraic laws, when applicable;
7. preservation claims: bijection, order, norm, rank, symmetry, sparsity, reversibility, etc.;
8. reference semantics and deterministic test vectors;
9. proof/evidence references and falsifying counterexamples;
10. resource estimate: operations, memory/scratch, communication, precision and expected complexity;
11. permitted execution contexts, capability requirements and side-effect class;
12. provenance, source digest, authoring source, catalog version and status.

A function without known preconditions or output semantics is not executable. A learned candidate is not promoted into the verified catalog until it passes independent reference tests and required proof obligations. Never label an approximation or heuristic as exact.

### 3.1 Boolean and finite logic

Exhaustive finite families:

- all 16 two-input Boolean functions, using the established four-NaN class nibble and truth-table bit order `k = 2a + b`;
- all 256 three-input Boolean functions;
- all 65,536 four-input Boolean functions;
- all Boolean functions for a declared finite arity, generated/represented by truth table or canonical form subject to explicit size limits;
- multi-output Boolean maps for declared input/output widths;
- permutations and reversible Boolean maps, including inverse tables;
- composition, substitution, cofactors, restriction, quantification, normal forms and equivalence checking.

Catalog Boolean primitives include constants, identity/projections, negation, AND, OR, XOR, XNOR, NAND, NOR, implication, converse implication, non-implication, converse non-implication, and all remaining truth tables. The 16-entry truth-table enumeration is authoritative; names are aliases only.

Required analyses: algebraic normal form (ANF), Walsh spectrum, symmetry classes, influence/sensitivity, balance, degree, nonlinearity, monotonicity, self-duality, affine classification, essential-variable count and equivalence under declared input/output transformations.

### 3.2 Arithmetic and number systems

- integer add/subtract/multiply/divide, quotient/remainder, gcd/lcm, extended gcd, comparisons, min/max, absolute value, sign, shifts and bit operations;
- arbitrary precision and fixed-width modular arithmetic with explicit overflow semantics;
- rational arithmetic and normalization;
- finite fields and polynomial arithmetic, including the existing F257 NTT domain;
- modular exponentiation, inverses where defined, roots and discrete transforms;
- interval arithmetic and directed bounds for approximate real operations.

Division by zero, overflow, invalid inverses, modulus requirements and signedness must be explicit. No implicit host-language overflow semantics.

### 3.3 Linear algebra, vectors and tensors

- vector construction, indexing, slicing, concatenation, permutation, reshape, broadcast and reduction;
- dot/inner products, norms, distances, normalization and projections;
- matrix transpose, symmetric/antisymmetric decomposition, multiplication, determinant, trace, rank, inverse/pseudoinverse and decompositions;
- tensor products, contractions, outer products, permutations, reshaping and reductions;
- basis change, embeddings, restrictions, projections, direct sums and dimensional lifts;
- sparse, packed-bit and block-sparse variants.

Shape compatibility, scalar field, accumulation width, singularity, rank assumptions and precision are preconditions, not comments.

### 3.4 Geometry and transformations

- identity, composition and inverse;
- translation, reflection, rotation, scaling, shear, affine and projective maps;
- orthogonal/unitary transforms and basis changes;
- permutations, bit reversal, byte reversal, transpose and the existing four-NaN Klein-four transform orbit `I, B, BR, R`;
- embeddings, restrictions, quotient maps, projections and lifts;
- metric, norm, distance and topology-aware maps, with the metric and invariants named;
- reversible coupling and exact forward/rollback maps.

For each transform record whether it is bijective, its inverse (or why none exists), fixed points, order, orbit structure, preserved quantities and whether information is discarded.

### 3.5 Relations, graphs and algebraic structures

- relation composition, converse, closure, reflexive/transitive/symmetric closure and equivalence classes;
- graph adjacency, path composition, reachability, shortest paths and connectivity;
- semiring operations and matrix products over OR/AND, min/+, max/× and +/× where their laws hold;
- group, monoid, ring, field, lattice and order operations, with axioms declared rather than assumed;
- hypergraph incidence, hyperedge composition, binding, bundling and cleanup;
- inheritance, exceptions and sparse residuals.

The operator must declare its algebra. The same matrix multiplication syntax under different semirings is not the same function.

### 3.6 Signal, sequence and discrete transforms

- Walsh-Hadamard, NTT/FFT (with exactness and modulus/roots requirements), convolution and correlation;
- prefix/suffix scans, differences, cumulative reductions, windows and sequence alignment;
- reversible sequence transforms, coding and erasure recovery;
- sketches and low-rank summaries with explicit distortion/error bounds.

### 3.7 Symbolic and abstract operations

- substitution, unification, normalization, rewrite steps and term composition;
- quantifier/logic operations, satisfiability and equivalence queries;
- type construction, refinement, coercion and shape inference;
- abstraction, concretization, quotienting, lifting and interpretation;
- proof-rule application, proof checking, counterexample generation and invariant checking.

These operations must carry a logic/theory identifier and must not silently mix incompatible theories.

## 4. Special trigger and vector interface

The names `vector13`, `vector42`, `matha` and `mathb` are preserved as named interface symbols. Their exact numeric or semantic meanings must be read from the existing implementation/configuration before assigning new meanings; this contract does not invent their definitions.

The trigger path is:

```text
input/event
  -> typed trigger decode (matha / mathb)
  -> operand and vector binding (vector13 / vector42)
  -> catalog lookup by stable function ID + version
  -> precondition/type/shape/capability checks
  -> deterministic execution or explicit rejection
  -> postcondition/invariant checks
  -> result packet + trace + digest
  -> scratch write / layer deposits / authorized DB projection
```

A trigger is a request, not authority. It cannot bypass type checks, ACLs, quotas, generation barriers or promotion rules. Unknown, ambiguous, malformed, stale-version or unsupported triggers are rejected with structured diagnostics. Trigger aliases resolve to one canonical function ID and cannot shadow it.

## 5. Scratch memory and the 8 MiB chart

Keep the existing 8 MiB 256-palindromic-point / 32,640-mirror-pair chart and its address semantics intact. Add a separately described scratch arena, not a reinterpretation or destructive expansion of the chart.

Scratch tiers:

- **S0 — runner-local registers:** small bounded working state for R0–R5; short-lived, generation-scoped, deterministic and attributable to a runner.
- **S1 — shared BS0 mathematical scratch:** bounded shared scratch for vector operands, transform intermediates, Boolean truth tables, matrix tiles and packet staging. Access is leased/versioned; no unsynchronized writes.
- **S2 — optional RAM arena:** only when measured working-set size, spill frequency or transform throughput demonstrates that the bounded scratch cannot handle the job. RAM is a capacity/performance tier, not a new universe or authority.
- **S3 — durable Koyeb storage:** long-lived mathematical packets, catalog versions, proofs, experiment traces, checkpoints, indexes and larger structured scratch snapshots. Durable storage is not treated as low-latency runner registers.

Scratch descriptors must include owner, scope, shape, element type, byte length, alignment, lifetime, generation, lease, content digest, read/write permissions and spill policy. Allocation must be bounded and checked; no unbounded scratch growth. A scratch overflow may request a larger tier but cannot silently mutate the 8 MiB chart layout.

## 6. Runner execution and optional NANNET workers

First attempt mathematical jobs on the existing BS0 runners R0–R5 using bounded, separately budgeted mathematical scratch. Keep language/HERMES training schedules and generation barriers intact.

Only add isolated `nannet-runner-0` through `nannet-runner-5` workers if measurements show contention, memory isolation requirements, or network transformation throughput that the existing ring cannot satisfy. If created, they are worker processes/services, not HW addresses, not universes, not a second head ring, and not independent trainers.

Their permitted responsibilities are:
- authenticate and validate NANNET transformation requests;
- decode/encode mathematical packets;
- run catalog-approved transforms in bounded scratch;
- produce deterministic result packets, traces and digests;
- submit candidate/evidence packets to the existing authorized BS0/HERMES interfaces.

They must not write canonical heads, bypass BS0 generation barriers, own BS0DB, or promote learned functions. A worker's output is evidence/candidate material until the existing training and evaluation path accepts it.

## 7. Databases and packet lineage

- **BS0DB:** canonical BS0-side records and references for accepted state, runner execution and validated mathematical results. Writes follow the existing commit/generation protocol.
- **MC0DB:** downstream learner's derived records, indexes, training examples and analysis. It consumes versioned BS0DB exports and approved mathematical packets; it cannot become the source of truth for BS0.
- **Koyeb long-term memory:** durable storage for larger structured scratch snapshots, catalog revisions, mathematical packet archives, proofs, indexes, experiment results and replay checkpoints. It is not an unbounded hot-memory substitute.

Every mathematical packet must include schema/version, packet ID, source identity, source digest, function ID/version, input type/shape/digest, output type/shape/digest, exactness/status, pre/postcondition results, trace ID, logical clock stamp, base generation, ACL/scope, scratch allocation reference and retention class.

The same packet may be projected into multiple layers or databases by explicit adapters. Those are derived views linked by the same packet ID and digest, not independent copies with divergent semantics. MC0Link receives only the authorized downstream projection.

## 8. Mathematical catalog and the existing layer namespaces

The mathematical catalog is not a competing set of ten numbered layers. It supplies typed operations and their contracts to the existing layer systems:

| Namespace | Canonical meaning | Existing implementation |
|---|---|---|
| Language L0–L9 | evidence resolution from bit to narrative | `runner/resolution_layers.py` |
| NANNET M0–M9 | requested network/math transformation namespace | canonical registry not yet located in this repository audit |
| Router mapping 0–9 | bit/head/address/bin/hyperedge/temporal/rule/route/provenance/meta-policy | `runner/nannet_router/macro.py` |
| Math catalog | operation families, signatures, laws and proofs | `include/nanlm/math_catalog.hpp` plus native mathematical modules |

The catalog is usable from any stage only through a typed operation request and a packet adapter. The adapter must declare source namespace, source stage, destination namespace/stage, function ID/version, operand types/shapes, ACL, base generation and validation status. No numeric layer equality implies semantic equivalence. No stage may reinterpret another stage's scratch or persisted evidence directly.

## 9. Self-modification and learning policy

Heads may propose:
- a new composition of existing catalog functions;
- a new parameterization or optimized implementation;
- a new candidate function with a formal signature;
- a new invariant, test or counterexample;
- a scratch layout or execution schedule improvement.

They may not directly rewrite the trusted catalog, router, ACL, trainer, generation barrier or their own execution authority.

Promotion sequence:

1. candidate emitted with source head, generation, function lineage and reproducible input;
2. isolated validation against reference semantics and adversarial/property tests;
3. proof obligations checked where claimed;
4. resource and determinism comparison against current implementation;
5. held-out evaluation by the existing pipeline;
6. accepted version staged as candidate;
7. canonical publication only through the existing BS0 generation barrier;
8. rollback retained with parent version, digest and reason.

A learned composition may be used experimentally before promotion only when explicitly sandboxed and labelled unverified.

## 10. Required validation matrix

Minimum catalog conformance tests:

- exhaustive all 16 two-input Boolean truth tables;
- exhaustive all 256 three-input truth tables and all 65,536 four-input truth tables;
- randomized/property tests for larger arities with reproducible seeds;
- composition identity and inverse round trips;
- domain/shape/precondition rejection tests;
- overflow, divide-by-zero, singularity and invalid-modulus cases;
- exact NTT/F257 and Walsh reference comparisons;
- matrix transpose involution and symmetric/antisymmetric reconstruction;
- semiring law tests only for declared valid structures;
- transform orbit and fixed-point tests;
- scratch bounds, lease expiry, spill/reload digest and concurrent access tests;
- packet schema, provenance, replay, idempotence and stale-generation tests;
- NANNET ACL, malformed trigger, unknown function, quota and unauthorized write tests;
- no change to existing HERMES, runner training, corpus, logic, or generation-barrier behavior.

A catalog-wide test report must state coverage by family and status. “Catalog complete” is not allowed while a family has undocumented operations, missing preconditions, missing reference semantics or untested claims.

## 11. Implementation order

1. Audit the live `include/nanlm`, `src`, `runner`, `integrations/nannet` and HERMES interfaces; map current mathematical primitives and exact meanings of vector13/vector42/matha/mathb.
2. Add the catalog descriptor and validation contract around existing functions; do not duplicate their implementations.
3. Wire catalog lookup and typed trigger validation through the existing NANNET adapter.
4. Add bounded scratch descriptors and packet serialization, keeping the 8 MiB chart unchanged.
5. Add mathematical job scheduling to the existing BS0 runner ring with isolated budgets.
6. Add optional NANNET worker processes only after contention and resource measurements.
7. Add BS0DB/MC0DB/Koyeb packet projections and replay/lineage checks.
8. Feed catalog examples and proof/counterexample tasks into the existing logic/HERMES training interfaces.
9. Enable sandboxed head-proposed compositions; gate all trusted promotion through existing evaluation and generation barriers.

## 12. Open audit questions (must be resolved from code, not guessed)

- Which source files currently own NaNLayer and NaNRouter responsibilities?
- Where are `vector13`, `vector42`, `matha` and `mathb` declared and what exact bit-level trigger semantics do they have?
- Which of the ten mathematical layers already have runtime implementations versus documentation only?
- What are the actual BS0DB and MC0DB schemas and commit boundaries?
- What Koyeb service/database and retention APIs already exist for durable mathematical packets?
- What is the current maximum scratch allocation and can it be extended without changing the 8 MiB chart?
- Can existing R0–R5 meet math throughput targets under concurrent HERMES training, measured under load?

Do not resolve these questions by inventing new names, tables, routes or semantics. Record the source path, symbol, tests and evidence for each answer.


## 14. Native NaN16 preflight integration

The mathematical catalog in this repository remains the semantic inventory and evidence index; it must not become a second numerical execution engine. Native MTH kernels and the typed-object applicability gate live in NaNROUTER under `mth/nan16/`. The canonical NaN16 assembler/runtime remains NaN0S. NaNLMind owns the mind-side selection, learning, and provenance policy.

The shared gate is `NaNROUTER/mth/nan16/mth_preflight.nas`. The existing NaN0S `math_registry.nas` now stores immutable 10-word typed applicability contracts alongside its existing operator records; `nmr_resolve` returns the registered contract pointer in r6. The preflight guest consumes that exact pointer plus two typed leaf descriptors, checks kinds, ranks, domains, shape rules, payload capacities, capability bits, and declared preconditions, and commits output metadata only after successful validation. It does not register functions or execute the selected kernel.

The integration CI in `.github/workflows/ci.yml` checks out the shared NaNROUTER source and canonical NaN0S toolchain, assembles the actual `.nas` fixture, and executes it in the NaN16 guest. This is a cross-repository native execution gate, not a Python/C++ mathematical reimplementation.

Evidence status: source and fixture are committed on the integration branch; native verification is pending the GitHub Actions run. The gate currently supports rank-0 through rank-2 shape contracts and five shape rules. Higher-rank tensor contracts, durable MC0DB rule persistence, and end-to-end RSS job dispatch remain separate work.


The native integration now includes a second fixture that parses a literal `nan://...::op:77::nan://...` expression through the existing NaN0S route resolver and expression linker. The linker returns its canonical typed contract pointer in r10; the exact pointer is passed to NaNROUTER's NaN16 preflight guest. This tests the real route/operator/contract/preflight handoff rather than a hardcoded contract record.
