# Byte expert router

## 1. Two lower-level experts

```text
expert 0: Hopfield mesh
expert 1: order-1 byte counts
```

Overbootstrap observes each expert on a validation slice and chooses the one
with better evidence. It does not receive raw bytes in the decision.

## 2. Result

```text
validation: router saw 4,799 samples per expert
chosen:     bigram
test top-1: 29.22%
order-0:    16.18%
Hopfield only: 14.12%
```

The route is deterministic from validation counts. The bigram expert beat the
Hopfield expert on this corpus, so the router chose bigram.

This is a legitimate overbootstrap decision: the mind selects the better lower
level. It is not a claim that Hopfield learned the corpus.

## 3. Why this matters

The layered system can keep multiple mathematical experts and route between
them:

- Hopfield for sparse associative recall;
- bigram/count for local byte context;
- context-2/Kneser-Ney later;
- vector/word experts after that.

The router is the first cross-layer selector. It can be extended to per-context
routing, confidence, cost, and merge-time updates.

## 4. Test

```sh
make build/test_byte_expert_router
./build/test_byte_expert_router
```

It passes with the 18% threshold and reports the exact chosen expert.

## 5. Next

1. Add context-2/KN-2 as a third expert.
2. Route per previous byte, not globally.
3. Store route evidence in overbootstrap layer payloads.
4. Merge evidence through Koyeb.
5. Keep the byte challenge threshold fixed.
