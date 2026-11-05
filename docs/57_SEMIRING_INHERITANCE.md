# Semiring inheritance on the 20k split

## 1. Model

- 256 kinds in a parent chain: `kindK -> kindK+1`.
- 20,000 entities assigned to kinds.
- Ability0 inherited by all kinds.
- Ability1 inherited only through a kind with `K mod 10 == 0`.
- Exceptions: every seventh entity blocks ability0.

The semiring layer is the Boolean reflexive-transitive closure of the kind
matrix. Queries use `bool_reachable(kind, parent)`.

## 2. Result

```text
entities   20,000
kinds         256
queries     2,000
matches     2,000/2,000
true cases  1,761
time        1 ms
```

The closure matches the explicit chain reference on every query.

## 3. Bug fixed

`bool_closure` was transitive but not reflexive. Inheritance needs `k -> k`, so
the diagonal is now set before Warshall. Existing closure tests still pass.

## 4. Meaning

- Inheritance can live in the semiring layer, not only in host code.
- The 256-kind chart is enough for this split; entity exceptions remain sparse
  residuals.
- This is still a symbolic engine; the learned gates/hypervectors must be
  compared against it, not substituted for it.

## 5. Test

```sh
./build/test_semiring_inheritance
```

## 6. Next

1. Add sparse entity exceptions into the matrix as residual rows.
2. Compare semiring closure with WordMemory on nested exceptions.
3. Run the same closure over 65,536 charts as a supercluster summary.
4. Keep the byte/sparse learners separate.
