# TRANSFER BRIEF — NaN16 Palindromic Temporal Computer
## Rounds 4, 5 & 6 for independent GPT / researcher review

**Purpose:** Self-contained technical brief. No prior chat required. Separates demonstrated facts, limitations, and recommended next work.

**One-liner:** A 16-bit address space is a computational topology of ~32,896 bit-reversal-canonical cells. Local transition rules evolve state; there is no per-cell instruction pointer.

---

## 1. Core model

- Canonical cell: `C(a)=min(a, reverse16(a))` → 256 fixed points + 32,640 pairs = **32,896 cells**.
- Cell fields: orientation, generation, state, aux, signal, rule_id, flags.
- Neighborhoods: mirror, byte-swap, orbit, Hamming-1, linear ±1, temporal ±1.
- Execution: full-grid sync, wavefront, linear CA steppers, **signal-carried arithmetic**, **event-driven sparse step**.

---

## 2. Round 4 results (16/16 tests)

| Demo | Outcome |
|------|---------|
| Rule 90 Sierpinski | local law → fractal |
| Rule 110 vs reference | 30-step exact match (universality path) |
| Add/sub/compare 4–16 bit | all cases via linear geometric drivers |
| Dual concurrent adders | 22+11=33 and 100+23=123 together; B Reverse-marked |
| Reversibility audit | FULL / COND / IRREV / HIST per rule |
| Fixed points | 256 queryable |
| Signal decay | reaches zero |

**Honesty (R4):** Arithmetic correctness used host linear passes (carry walks address index in software). Proved “arithmetic as geometry,” not yet pure traveling-signal carry.

---

## 3. Round 5 results (4/4 tests)

| Demo | Outcome |
|------|---------|
| Shift-add multiply | 8 cases including 100×200=20000 |
| Dual multiply fields | 6×7=42 and 9×9=81 |
| Regressions | dual add + Rule 110 OK |

Multiply = repeated spatial add into an accumulator field. Same honesty note as R4 drivers.

---

## 4. Round 6 results (13/13 tests) — closes the P0 honesty gap

| Demo | Outcome |
|------|---------|
| **Signal-carried adder** | 8/8 cases (4/8/16-bit). Carry moves only via `signal` + linear next. Steps ≈ bit-width (Θ(n) ripple). |
| Event-driven sparse step | dirty queue; signal quiets; work > 0 |
| Initial-state programmability | same machinery, different seeds → 3+4=7 vs 10+5=15 |
| Dual geometric regression | still green |

**This is the important R6 claim:**  
Ripple-carry addition can complete as a **traveling signal** on the topology. Host only advances global steps until the field is quiet; it does not iterate bit indices to inject carry.

---

## 5. What is still NOT established

- Universality *of the mirror topology* (only: can host Rule 110)
- Performance or energy vs CPU / plain CA
- 2× useful work from mirror pairs (dual fields are independent jobs)
- Schedule-independence of all rules under true async
- IEEE-754 NaN hardware semantics (state is integer payloads)
- Fault tolerance from mirrors under shared storage
- Complementary dual-rail validation at fixed-point gates

---

## 6. Strongest defensible claims

1. Address space → defined 32,896-cell computational substrate with mirror symmetry.
2. Local rules yield CA, universal-CA embedding, multi-width arithmetic, consensus, signals **without a per-cell PC**.
3. Multiple independent fields coexist.
4. **Carry can be a pure traveling signal** (R6); step count tracks bit-width.
5. Different results from **initial state alone** under the same signal-adder mechanism.
6. Rules classified by reversibility for future temporal memory policy.

---

## 7. Priority agenda for the next planner

1. Complementary mirror validation (A computes, B validates at fixed-point gate).
2. Longer Rule 110 / TM sketch (separate “hosts 110” from “mirrors are essential”).
3. Order-independence matrix for event-driven rules.
4. Sparse temporal pages + branch/checkpoint API.
5. Metrics: cells/s, ops/s, active fraction, Termux ARM64.
6. Dynamic rule propagation via signals.

---

## 8. Questions for GPT

1. Is “signal-carried ripple add with host global step” enough to claim spatial ALU, or is a fully async message-passing model required?
2. Design a falsification test for “mirror orientation is computationally useful beyond labeling.”
3. Minimal local rule set: reversible-friendly + NAND-complete + programmable by initial state only?
4. Fair baseline for benchmarks (1-D CA array vs soft CPU vs graph CA)?
5. Sparse temporal page format for FULL vs HIST vs IRREV transitions?

---

## 9. Abstract

NaN16 PTC R4–R6 implement an address-derived spatial computer over 32,896 cells. Tests show Rule 90/110, multi-width add/sub/compare/multiply, dual fields, reversibility taxonomy, event-driven sparse update, and **signal-carried ripple addition with Θ(width) steps**. Mirror-as-complementary-resource, competitive performance, and schedule-independent async remain open. Highest-value next work: fixed-point validation gates and initial-state-only general programs under a fixed rule map.
