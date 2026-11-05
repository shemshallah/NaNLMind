# NaN16 PTC — Round 15: Continuity of State

```sh
make test          # 43 checks: SHA-256 KATs, matrix structure, ledger, tamper, migration, branches, specialization
make determinism   # same event stream under -O0/-O2/-O3/-O1: chain head must be bit-identical
make test_r14      # R14 regression
```
See `docs/ROUND15.md`.
