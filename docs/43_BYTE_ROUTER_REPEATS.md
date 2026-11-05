# Ten-pass byte router measurement

Same Alice excerpt split as the byte expert router; incremental training passes;
validation evidence refreshed each pass.

| pass | Hopfield | bigram | routed | chosen |
|---:|---:|---:|---:|---|
| 1 | 0.1700 | 0.2922 | 0.2922 | bigram |
| 2 | 0.1657 | 0.2922 | 0.2922 | bigram |
| 3 | 0.1614 | 0.2922 | 0.2922 | bigram |
| 5 | 0.1614 | 0.2922 | 0.2922 | bigram |
| 10 | 0.1602 | 0.2922 | 0.2922 | bigram |

## What it means

- Repetition over the same corpus does **not** improve byte top-1.
- Hopfield drifts slightly worse after the first pass.
- The bigram expert is stable at 29.22%.
- Overbootstrap correctly keeps routing to bigram.

The next lever is new data or a richer context, not more passes.

Run (takes ~50s; not in CI):

```sh
make byte-router-repeats
```
