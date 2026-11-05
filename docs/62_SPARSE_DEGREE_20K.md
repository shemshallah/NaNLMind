# Sparse degree-term learner on 20k samples

## 1. Setup

- 6 Boolean variables: bird, up to 3 exceptions, noise.
- 20,000 sampled assignments, 16k train / 4k test.
- Candidate literals/conjunctions up to degree D.
- 472 terms up to degree 4.
- Select the term with best training F1; evaluate held-out accuracy.

## 2. Result

| depth | D=1 | D=2 | D=3 | D=4 | exact at |
|---:|---:|---:|---:|---:|---:|
| 1 | .750 | **1.000** | 1.000 | 1.000 | D=2 |
| 2 | .625 | .875 | **1.000** | 1.000 | D=3 |
| 3 | .563 | .813 | .938 | **1.000** | D=4 |

The sparse learner recovers the exact conjunction at `degree = depth + 1`.
Lower degrees fail on held-out samples.

```text
PASS sparse degree-term learner on 20k samples
```

## 3. Why this matters

- The degree result survives random sampling and held-out evaluation.
- No full truth table is needed.
- The term miner is deterministic and integer-only.
- It is still a symbolic learner, not the byte/Hopfield path.

## 4. Next

1. Add noise/contradiction to the sample stream.
2. Add degree-3 terms to the hypergraph layer.
3. Compare term miner vs hypervector recall.
4. Feed selected terms into overbootstrap as route evidence.
