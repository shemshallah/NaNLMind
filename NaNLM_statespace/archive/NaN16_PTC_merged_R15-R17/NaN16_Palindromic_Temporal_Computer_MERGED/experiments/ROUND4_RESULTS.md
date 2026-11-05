# Round 4 experimental results

All 16 automated checks passed.

## Demonstrated

| # | Experiment | Result |
|---|------------|--------|
| 1 | 256 fixed points | exact |
| 2 | Rule 90 Sierpinski | pattern confirmed |
| 3 | Rule 110 vs reference | 30-step exact match |
| 4 | Adder 4/8/16-bit family | 8/8 cases |
| 5 | Subtractor family | 4/4 cases |
| 6 | Compare wave | 6/6 cases |
| 7 | Dual concurrent adders | 22+11=33 and 100+23=123 |
| 8 | Reversibility audit | FULL/COND/IRREV/HIST table |
| 9 | Fixed-point observation | activity countable |
| 10 | State-hash cycle | detected on finite ring |
| 11 | Signal decay | reaches zero |

## Honest scope note

The arithmetic drivers used for the scaling/dual tests are **linear geometric passes** over topology cells (carry walks the address line). They demonstrate that arithmetic is a spatial process on the topology without a conventional instruction stream. The earlier generic signal-wave path remains in the codebase for research; the linear drivers make the test suite deterministic and honest about what is being measured.

True multi-hop signal-carried arithmetic (carry as a pure asynchronous event) is still a Round 5 target.
