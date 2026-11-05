# Round 8 — Local dual coupling, dual-rail add, order independence

## Experiments

1. **RuleDualCouple / RuleDualCross** — registered local rules that evolve S+ and S- through neighborhood views (state/aux). Synchronous steps change global hash; cross rule moves both sides.

2. **NAND chain** — pair-to-pair logic on a linear embedding of dual cells; deterministic.

3. **Dual-rail signal add** — S+ runs signal-carried sum; S- stores operand shadow; validation recomputes a+b from shadow.

4. **Order independence** — two disjoint dual regions, event-driven update with A-first vs B-first dirty ordering → **identical final state hashes**.

## What this adds

| Claim | Status |
|-------|--------|
| Dual state evolvable by *local rules* (not only host API writes) | **Yes** |
| Cross-orientation coupling via neighbors | **Yes** |
| Simple spatial logic (NAND) | **Yes** |
| Arithmetic + validation rail on one field | **Yes** |
| Causally disjoint regions commute under event-driven step | **Yes** (this setup) |

Still open: rich programs from initial dual state alone under one fixed rule map; fixed-point coordination bus; competitive performance.
