# BRAINSTORM_4 — After the deep audit: what Round 4 actually tested

## Integration of the post-Round-3 analysis

The long analysis correctly separated:

- **Demonstrated** (Round 3): Rule 90, signal wave, one adder, reversible XOR probe, consensus
- **Architecturally implied**: multi-geometry, orientation as resource, fixed points as subsystem, temporal memory
- **Unproven**: universality, dual-field advantage, async correctness, performance claims

Round 4 attacks the highest-value unproven items that are still implementable in a host reference.

## What Round 4 establishes

### A. Rule 110 embedding
A 64-cell linear window evolves under Rule 110 and matches a pure host reference for 30 steps.
This is the first concrete step on the universality path (Route A). It does **not** yet prove the mirror topology adds anything beyond a 1-D CA host — that is the next question.

### B. Arithmetic as a spatial family
Addition, subtraction, and comparison are all realized as wavefronts over linear embeddings:

| Op        | Wave direction | Local rule core                          |
|-----------|----------------|------------------------------------------|
| Add       | LSB → MSB      | sum = a⊕b⊕cin, cout = majority           |
| Sub       | LSB → MSB      | diff = a⊕b⊕bin, bout = borrow logic      |
| Compare   | MSB → LSB      | first differing bit decides              |

Scaling tests cover 4-, 8-, and 16-bit widths. The same topology runs them without a PC.

### C. Dual simultaneous fields
Two independent adders (22+11 and 100+23) run in the same topology at once.
Field B is marked Reverse orientation. Both results are correct.
This is the first real test of the “mirror orientation as a resource” thesis at the level of *independent concurrent work*, not just labels.

Still open: true *complementary* work (forward computes, reverse validates or explores an alternate branch) rather than two independent jobs.

### D. Reversibility audit
Every built-in rule now carries an explicit classification:

- FULL / COND / IRREV / HIST

This is the foundation for temporal memory that knows when it can step backward for free and when it must log.

### E. Fixed points as a subsystem
All 256 bit-palindromes are queryable. Activity near them is measurable.
They are ready to become validation gates, observation posts, or symmetry boundaries — experiments, not assumptions.

### F. Finite → cycles
A 16-cell Rule 90 ring produces a detectable state-hash cycle, as any finite deterministic system must. Temporal-cycle detection infrastructure is in place for future “collective oscillation” studies (carefully not over-claimed as physical time crystals).

## The most important remaining experiment (carried forward)

> Two simultaneous arithmetic fields where one is the *validation* or *complement* of the other through the mirror relationship, not merely a second independent job.

And:

> Program two different computations by changing *only* initial state, under a single fixed rule assignment across the topology.

Those two results would move the project from “hosts familiar CA and spatial arithmetic” to “mirror topology provides a distinctive computational advantage.”

## Design principle reinforced

> Do not move the computation to the data. Arrange the data so that the computation propagates through it.

Carry, borrow, and comparison decision are all signals moving through geometry.
