# Byte-stream gate

## 1. Setup

`tests/test_byte_stream_learning.cpp` trains the two-rate mesh on consecutive
bytes from `data/alice_excerpt.txt`:

```text
query: previous byte
target: next byte
train: first 80%
test:  last 20%
code:  splitmix 32-dimension token vector
top_k: 8
passes: 2
```

## 2. Result

```text
corpus bytes      30,000
train steps       47,998
test bytes         5,999
held-out top-1     14.12%
order-0 top-1      16.18%
hybrid top-1       14.12%  (no abstentions, so fallback never fired)
slots                77
overbootstrap traces 47,998
```

The mesh **does not beat order-0** on this task yet.

This is not a green gate. It is recorded as a challenge target:

```sh
make byte-mesh
```

The test intentionally keeps the 18% threshold and is not in `make test`.

## 3. What the failure means

- The 32-dimensional byte code activates nearby heads, but the pair slots carry
  too little context for natural byte streams.
- Hopfield slot voting is not a substitute for an order-1/2 count model.
- Overbootstrap evidence is being collected, but its bounded bias does not add
  enough context on this task.
- A most-frequent-byte fallback was tried; Hopfield never abstained, so the
  fallback never fired and the hybrid stayed at 14.12%.

## 4. Next honest fixes

1. Add a count/backoff fallback for abstained Hopfield predictions.
2. Compare Hopfield+backoff against order-0 on the same split.
3. Add pair/word context only after the byte gate is stable.
4. Store overbootstrap evidence in the 2 GiB layer payloads and merge through
   Koyeb.
5. Keep the challenge threshold fixed until a real change beats it.
