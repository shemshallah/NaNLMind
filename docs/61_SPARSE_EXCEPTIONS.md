# Sparse exception residuals

## 1. Structure

The kind layer stays dense and small:

```text
256×256 Boolean closure   8 KiB
```

Per-entity exceptions stay sparse:

```text
20,000-bit residual       2.5 KiB
2,858 exceptions
```

That is the low-rank kind model plus sparse residual idea.

## 2. Result

```text
entities    20,000
exceptions   2,858
closure bytes 8,192
residual bytes 2,504
queries      2,000
matches      2,000/2,000
time         1 ms
```

The closure is graded against the explicit kind-chain reference; the bitset
blocks ability0 for every seventh entity.

## 3. Why it matters

- No 20,000×256 entity matrix.
- Exceptions are explicit and sparse, not lost in count smoothing.
- The kind closure can be shared/merged; the residual is per-entity.
- Cassowary/penguin exceptions fit this representation.

## 4. Test

```sh
./build/test_sparse_exceptions
```

## 5. Next

1. Add multi-level exception residuals.
2. Merge residuals by OR/set union across peers.
3. Map residual rows to hyperedge labels.
4. Compare learned gate exception masks to this residual.
