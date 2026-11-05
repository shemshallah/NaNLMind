# Round 14 — Cognitive Architecture

## Knowledge graph (in topology-backed store + dual activation cells)

| Fact | Encoding |
|------|----------|
| Eagles are birds | (EAGLE, ISA, BIRD) |
| Penguins are birds | (PENGUIN, ISA, BIRD) |
| Birds have wings | (BIRD, HAS, WINGS) |
| Eagles can fly | (EAGLE, CAN, FLY) |
| Penguins cannot fly | (PENGUIN, CANNOT, FLY) |
| Birds can fly (default) | (BIRD, CAN, FLY) |

## Results (17/17)

| Module | Result |
|--------|--------|
| Associative memory | bird→wings; eagle inherits wings |
| Can penguins fly? | **NO** (exception overrides default) |
| Can eagles fly? | **YES** |
| Unknown ISA penguin → fly? | **NO** (exception inherits) |
| Dual inference | general=YES, dual=NO, disagreement resolved |
| Counterfactual | hyp flips answer; restore recovers |
| Continual learning | wrong CANNOT corrected by feedback |
| Distributed pages | portal carries exception |
| R13 regression | 2CM mul OK |

## Discipline notes

- Fixed dual-resolution rule: exceptions override general inheritance.
- Single-state control path ignores exceptions (for comparison).
- Counterfactual uses full KB snapshot/restore.
- Cognitive triples live in `cog_kb_` (canonical address pairing made raw cell packing unsafe).
