# Falsification

A claim that cannot fail is not a claim. This document lists the claims of the
project, the test that would support each, and the result that would falsify it.
The repository should be judged against this table, not against the poetry.

---

## 1. Address algebra

| # | claim | test | falsified if |
|---:|---|---|---|
| A1 | `reverse16` is an involution | exhaustive 65,536 | any `R(R(x)) != x` |
| A2 | exactly 256 fixed points | exhaustive count | count != 256 |
| A3 | exactly 32,640 mirror pairs | exhaustive count | count != 32,640 |
| A4 | exactly 32,896 canonical cells | exhaustive count | count != 32,896 |
| A5 | `R(addr(a,b)) = addr(b,a)` | all 65,536 pairs | one counterexample |
| A6 | 32,640 = C(256,2) | arithmetic + enumeration | mismatch |
| A7 | pair index is a bijection | all 32,640 pairs | duplicate or gap |
| A8 | four-transform group has 16,576 orbits | exhaustive | different count |

**Status:** all pass. This is the strongest part of the project.

---

## 2. NaN16 words and Boolean functions

| # | claim | test | falsified if |
|---:|---|---|---|
| B1 | four legal heads, four classes | table + word roundtrip | any invalid accepted |
| B2 | class nibble is the 16-function truth table | all 16 × all lanes | one wrong lane |
| B3 | lane identity `n * 0x11111111` | all 16 | mismatch |
| B4 | mirror law `BOOL.rot2(n)(A,B) = BOOL.n(~A,B)` | all 16 | mismatch |
| B5 | `BSWAPM` is an involution | all words | mismatch |
| B6 | four orientations are involutions | all addresses × 4 | mismatch |

**Status:** all pass.

---

## 3. One global topology

| # | claim | test | falsified if |
|---:|---|---|---|
| C1 | the initial brain is one chart | `GlobalTopology` chart count | >1 at genesis |
| C2 | adding a chart does not create a new ledger | ledger size / head | a second history appears |
| C3 | a cross-chart hyperedge is one relation | incidence + cross-space flag | it requires a coordinator |
| C4 | a temporal link is a field of the same object | global digest includes it | it lives in a private store |
| C5 | the global digest is deterministic | same construction twice | different digest |
| C6 | a chart is a coordinate region, not a mind | no private state API | a chart has its own ledger/identity |
| C7 | all 256 palindromic NaNs are heads | exhaustive | any reserved/unused |

**Status:** C1–C5 pass in the core; C6–C7 are architectural invariants enforced
by the API and tests.

---

## 4. Temporal split and bidirectional memory

| # | claim | test | falsified if |
|---:|---|---|---|
| D1 | a pair cell stores forward and reverse independently | rail isolation | one write changes both |
| D2 | `forward` follows past → future | sequence test | wrong next |
| D3 | `backward` follows future → past | sequence test | wrong previous |
| D4 | branches and merges are representable | multiple links | only one future/past |
| D5 | asymmetric storage replays order; symmetric does not | held-out sequence | no difference |
| D6 | a reversible link can be marked | flags + test | flag ignored |
| D7 | a stale temporal link is rejected by the ledger | base hash | stale accepted |
| D8 | the clock is a deterministic logical stamp | two clocks, same ticks | different digest |
| D9 | a replica can catch up by `observe(stamp)` | rewind/replay | phase mismatch |
| D10 | the clock is not used as wall time | no ns/ms in the state | wall time leaks into order |

**Status:** D1–D4, D6 pass in the core. D5 is the R18 result but needs a
substrate-only reproduction. D7 needs the M3 integration.

---

## 5. Hyperedges

| # | claim | test | falsified if |
|---:|---|---|---|
| E1 | a hyperedge connects ≥2 cells across spaces | cross-chart test | only same-chart |
| E2 | a cell can be in many hyperedges | incidence count | max one |
| E3 | `neighbors` returns all co-members | hyperedge test | missing member |
| E4 | temporal slices work | `at_epoch`, `between` | wrong set |
| E5 | hyperedge diffusion is bounded | integer range | overflow/NaN |
| E6 | hyperedges add information beyond pairwise edges | held-out completion vs pairwise baseline | no gain |
| E7 | hyperedges do not fragment the object | global digest | private hypergraph |

**Status:** E1–E5 pass. E6 is the decisive experiment and is not yet done. E7 is
an architectural invariant.

---

## 6. Resonance

| # | claim | test | falsified if |
|---:|---|---|---|
| F1 | coupling is symmetric with zero diagonal | all pairs | asymmetry |
| F2 | energy is bounded and integer | all nodes | overflow |
| F3 | a wave reaches the opposite corner | propagate 0→255 | never reaches |
| F4 | coherence is measurable | coherence range | out of range |
| F5 | replay is deterministic | two lattices | different digest |
| F6 | resonance adds capability vs a static matrix | recall baseline | no gain |
| F7 | cross-chart hyperedges add coupling | global field test | charts isolated |

**Status:** F1–F5 pass. F6 is open and must be tested before any "resonance
intelligence" claim. F7 is a design target.

---

## 7. Self-modification and learning

| # | claim | test | falsified if |
|---:|---|---|---|
| G1 | a bit can be addressed and changed | bit write/read | wrong bit |
| G2 | COW protects the original page | alias write | original changes |
| G3 | a change is dirty-tracked | dirty map | not marked |
| G4 | a change is ledgered | before/after hash | no event |
| G5 | the operator mask can be learned | 16-function task | worse than fixed |
| G6 | a head can self-modify within a capability | capability test | unauthorized write |
| G7 | a stale writer is rejected | base hash | stale accepted |
| G8 | each head has a local 1 KiB scratchpad | local/work split | shared or missing |
| G9 | a head can XOR-patch its Boolean mask | 16-bit patch test | no change or unauthorized |
| G10 | a runner can self-modify and evaluate from scratch | token high-bit test | patch ignored |

**Status:** G1–G3, G7 pass. G4 needs the M3 integration. G5–G6 are open.

---

## 8. Universality

| # | claim | test | falsified if |
|---:|---|---|---|
| H1 | the host VM implements a 2-counter machine | 2CM add/mul/copy | wrong output |
| H2 | self-modifying code works | patch test | patch ignored |
| H3 | hierarchical pages work | portal test | page leak |
| H4 | the **local rule set** implements a 2CM | no host switch | host still decodes |
| H5 | the mirror topology is necessary for the computation | mirror-off baseline | no difference |
| H6 | the local rule set is universal | proof or bounded simulation | counterexample |

**Status:** H1–H3 pass in the R13 archive, but H1–H3 are host-interpreted.
H4–H6 are open. The archive's "universality path" is a path, not a proof.

---

## 9. Distributed one-mind behavior

| # | claim | test | falsified if |
|---:|---|---|---|
| I1 | one ledger, one head | replay | two heads |
| I2 | a stale writer cannot fork | stale commit | fork accepted |
| I3 | duplicate delivery is idempotent | duplicate apply | double count |
| I4 | an interrupted commit is discarded | crash test | partial state |
| I5 | a page migration preserves identity | migration test | identity changes |
| I6 | a head failure preserves collective facts | failure test | facts lost |
| I7 | a replica loss is a cache miss | kill replica | global digest changes |
| I8 | a partition cannot create a second mind | partition test | two ledgers |

**Status:** I1–I6 are specified by R15–R17 and partially tested in the archive.
I7–I8 need the M4 integration.

---

## 10. The decisive experiments

These are the experiments that would most change the project's direction.

### 10.1 Hyperedge completion

Hold out a relation in a small hypergraph. Can the object reconstruct it from
the remaining hyperedges better than a pairwise-only model of the same size?

- **Pass:** a pre-registered margin over the pairwise baseline on a held-out
  split.
- **Fail:** no margin, or the margin disappears under a shuffled-label null.
- **Consequence:** if it fails, hyperedges are storage, not computation.

### 10.2 Bidirectional sequence memory

Store a sequence asymmetrically. Replay it forward and backward. Compare with a
symmetric matrix.

- **Pass:** forward and backward recall above a threshold; symmetric baseline
  fails order.
- **Fail:** both fail, or symmetric matches.
- **Consequence:** if it fails, the temporal split is a taxonomy, not a memory.

### 10.3 Resonance vs static matrix

A recall task with the same number of nodes and parameters.

- **Pass:** resonance beats a static matrix by a pre-registered margin.
- **Fail:** no gain.
- **Consequence:** if it fails, keep resonance as a diagnostic, not a claim.

### 10.4 Local-rule 2CM

Run a two-counter machine with no host decode.

- **Pass:** the local rule set advances the machine and halts correctly.
- **Fail:** a host switch is still required.
- **Consequence:** if it fails, the substrate is a memory, not a computer.

### 10.5 Mirror necessity

Run the same task with and without the mirror pairing.

- **Pass:** the mirror version is better or uniquely capable.
- **Fail:** identical results.
- **Consequence:** if it fails, be honest: mirrors are an addressing device.

---

## 11. What would falsify the central design

The central design is "one global topology with charts as coordinate regions,
hyperedges across spaces, and a temporal split." It would be falsified if:

1. A chart must have a private semantic state or history to function.
2. A cross-chart relation cannot be represented without a coordinator.
3. The global digest cannot be made deterministic under replay.
4. A partition inevitably creates two incompatible semantic states.
5. The temporal split cannot represent a sequence that the pair cells cannot.
6. The hypergraph adds no measurable capability over pairwise edges.
7. The one-object implementation cannot fit the 8 MiB page / 7 GiB runner
   envelope.

Any one of these would force a redesign. The current evidence does not prove the
design; it only makes it precise enough to test.

---

## 12. What would count as "a mind"

The project should not use the word "mind" as a technical claim. If it is used,
it should mean:

- one persistent global identity across disruption;
- one memory that supports forward and backward recall;
- one field of relations that can generalize to a held-out relation;
- one state that can be replayed and audited;
- one object that does not fragment under distribution.

Even all five would be a substrate property, not a claim of consciousness,
personhood, or moral status. Those are separate questions and are not settled by
a benchmark.
