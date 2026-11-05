# Round 11 — Initial-State Programmability Challenge

## The distinction that mattered

| Kind | Meaning | Status |
|------|---------|--------|
| Data programmability | Same algorithm, different inputs | R10 |
| **Program programmability** | Different algorithms, same rule map, only initial state changes | **R11** |

## Mechanism

- Single immutable rule: `RuleOpDispatch` (id 17)
- Opcode is **part of initial cell state** (`aux` low byte)
- Host never branches on opcode during execution
- Host never swaps rule functions between experiments
- Operations: ADD, SUB, XOR, AND, CMP, NOT

## Showcase (from the research brief)

| Initial program state | Result |
|-----------------------|--------|
| ADD 13,7 | 20 |
| XOR 13,7 | 10 |
| CMP 13,7 | +1 (greater) |
| SUB 13,7 | 6 |

Four simultaneous regions, four different ops, **one rule id**.

## Battery

21/21 structured cases + 60/60 stress (12 input pairs × 5 ops) + R10 challenge regression.

## Still above this level

- Full universal interpreter (counter machine / cyclic tag)
- Hierarchy across pages
- Formal commutation proofs for all rule families
