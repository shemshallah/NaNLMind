# Round 18T Control: plain dense RNN vs the 256-head transposition structure

Setup (experiments/r18t_rnn/, numpy BPTT, gradient-checked incl. variable hidden size): h' = tanh(W h + U[x] + b), logits = V h + c.
Corpus B (174 KB C++ source), batch 16x32, Adam 3e-3, 3200 iterations = 1.64M bytes, held-out bits/byte (uniform = 8, bigram = 3.54).
"plain" = ordinary unconstrained Elman RNN, no topology structure.

| Model | effective params | seed 0 | seed 1 |
|---|---|---|---|
| 256 heads, full W | 197K | 2.202 | 2.192 |
| 256 heads, symmetric W | 164K | 2.693 | 2.580 |
| 256 heads, antisymmetric W | 164K | 2.441 | 2.415 |
| plain RNN, 213 hidden (total params matched to sym/anti) | 155K | 2.211 | 2.213 |
| plain RNN, 181 hidden (W dof matched to sym/anti) | 126K | 2.252 | 2.184 |

## Reading
- A plain dense RNN with fewer parameters (126K) matches the 256-head full-W model (197K): 2.18-2.25 vs 2.19-2.20.
- It beats the symmetric and antisymmetric 256-head variants by 0.2-0.5 bits at equal or smaller size. Constraining W to one half of the transposition decomposition costs accuracy.
- So the earlier "asymmetry matters" finding stands only as: asymmetric > symmetric. It does not show the 256-head structure helps learning versus an ordinary RNN.
- Conclusion on the Round 18T question: the topology is a storage/addressing scheme (verified exactly) and a source of resonance/sequence-memory dynamics (verified), but gives no measured learning advantage over a plain RNN.

## Limits (be honest)
- Only corpus B, seeds 0 and 1 (10 of 30 planned runs). Corpus A and seed 2 were NOT run. Gaps below ~0.05 bits are not resolved.
- Single optimizer setting, no tuning per model, 3200 iterations only (curves still falling), no GRU/LSTM, no dropout.
- Plain RNN here means unconstrained dense Elman; it is not stored in topology cells (not needed for the comparison).

## To finish (opencode)
cd experiments/r18t_rnn && python3 control.py   # resumes: skips runs already in control_results.jsonl
Runs corpus B seed 2 then corpus A seeds 0-2 (~1 min per B run, ~30 s per A run, single CPU, numpy only).
