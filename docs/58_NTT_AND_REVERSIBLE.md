# NTT correlation and reversible memory

## 1. NTT correlation on real windows

`tests/test_ntt_sequence.cpp` takes eight 256-byte windows from
`data/alice_excerpt.txt`, builds two overlapping/offset vectors, and compares:

```text
cyclic_correlation_ntt   (F257)
cyclic_correlation_naive (direct scan)
```

Every entry matches.

```text
PASS NTT cyclic correlation on Alice windows
```

This is exact integer correlation, not a speed claim. On a CPU, the direct scan
can be faster for 256 points; the value is deterministic/replayable math and
composability with the transform stack.

## 2. Reversible coupling vs stored activations

`tests/test_reversible_vs_stored.cpp` runs 256 reversible layers:

```text
stored:     save every intermediate (x1,x2)
reversible: keep only the final pair, then invert
```

Both restore `(0x1234, 0xABCD)` exactly. The stored path uses
`257 * sizeof(pair)` bytes; the reversible path uses one pair.

```text
PASS reversible coupling vs stored activations
```

No activation storage is needed for the inverse.

## 3. Interpretation

- NTT gives exact correlation and a basis for frequency sketches.
- Reversible coupling gives a train/rollback path with constant state.
- Neither is a speed claim by itself.
- Both are deterministic and can be replayed.

## 4. Next

1. Remove 30% of slots and recover.
2. Sparse exception residual rows.
3. NTT/Walsh sparse-spectrum learner.
4. Full replay digest test for any seeded collapse (separate superposition TODO).
