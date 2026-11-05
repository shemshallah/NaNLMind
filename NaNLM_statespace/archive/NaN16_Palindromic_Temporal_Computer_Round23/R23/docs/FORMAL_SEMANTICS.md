# Formal execution semantics (Round 13)

## Configuration

M = (P, IP, R, F, O, H, C)

- P: program memory (words at base+16…)
- IP: instruction pointer
- R: {A, B}
- F: flags {Z, GT, LT}
- O: OUT
- H: HALT ∈ {0,1}
- C: cycle count

## Transition

If H=1, terminal.

Else fetch insn = P[IP], op = insn & 0xFF, execute effect, set IP' as specified, C ← C+1.

### Selected effects

| Op | Effect |
|----|--------|
| HALT | H ← 1 |
| LOAD_A imm | A ← imm; IP ← IP+2 |
| LOAD_B imm | B ← imm; IP ← IP+2 |
| ADD | A ← (A+B) mod 2^16 |
| SUB | A ← (A−B) mod 2^16 |
| XOR/AND | bitwise |
| CMP | F from A?B |
| JMP imm | IP ← imm |
| JZ/JNZ/JG/JL imm | conditional IP |
| INC_A/B | +1 |
| DEC_A/B | saturate 0; DEC_B sets Z |
| STORE_PROG | P[B] ← A |
| LOAD_PROG | A ← P[B] |
| OUT | O ← A |

## Schedule independence (tested)

For disjoint machines M_a, M_b, interleaving steps in different orders yields the same terminal (O_a, O_b) when programs do not share cells.

## Universality path

Two-counter-style programs (INC/DEC/JZ) implement addition, multiplication, and copy.
A 2CM with unbounded counters is universal; this instance is width-bounded (16-bit).
Expandable multi-cell counters + hierarchical pages are the route to unbounded simulation.
