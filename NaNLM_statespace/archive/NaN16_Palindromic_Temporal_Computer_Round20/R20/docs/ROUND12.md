# Round 12 — Program-in-State VM (NaN16 Computer)

## What changed

R11: initial state selects **one operation**.
R12: initial state holds a **program** (instruction sequence); the machine
fetches, decodes, executes, branches, and halts under one fixed transition rule.

## Machine image (all in topology cells)

| Offset | Register |
|--------|----------|
| 0 | A |
| 1 | B |
| 2 | IP |
| 3 | FLAGS (Z, GT, LT) |
| 4 | HALT |
| 5 | OUT |
| 6 | CYCLES |
| 16+ | Program words |

## ISA

HALT, LOAD_A/B, ADD, SUB, XOR, AND, CMP, JMP, JZ, JNZ, JG, JL,
MOV, NOT, ADD_IMM, NOP, OUT — 19 opcodes.

## Host contract

Host may: load memory image, call `vm_step` / `vm_run`, read OUT.
Host may not: interpret opcodes, advance IP, or branch on FLAGS.

## Results (13/13)

- Brief programs: (13^7)+4=14, ((13+7)-3)^2=19
- 14/14 suite programs (branches, loops, dual region)
- Count loops 1..10
- Determinism, immutable RuleVmCycle
- R11 regression

## Universality note

This is a **finite** stored-program interpreter. With unbounded memory it would be
Turing-powerful in the usual ISA sense; the 16-bit topology instance remains finite.
The architectural claim is: programs live in state, and one fixed rule interprets them.
