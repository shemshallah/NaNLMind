# Round 9 — Host-blind local-rule logic machine

## Contract

Host may:
- Initialize cell state (operands, signals, rule IDs)
- Schedule steps (line-local two-phase or synchronous)
- Inspect results

Host may **not**:
- Compute sum/cout in the driver
- Inject carry by writing next cells after a host-side formula

All arithmetic bits are produced inside `rule_ripple_cell`.

## Results

| Test | Outcome |
|------|---------|
| Local XOR/AND for all input pairs | 4/4 |
| Pure local adder 4/8/16-bit | 7/7, steps = width |
| Two independent pure adders | 22+11=33 and 100+27=127 |
| Dual complementary regression | OK |

## Position on the hierarchy

1. Address topology — established
2. Paired state — R7
3. Complementary transitions — R7
4. **Local pair-to-pair computation — R8/R9** (this is the turning point, still narrow)
5. Composed programmable machine — open

R9 is evidence for level 4 on a small library (XOR, AND, ripple full-adder cells). It is not yet a general composed machine programmable only by initial state under one fixed rule map.
