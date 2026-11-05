# Bit and byte learning gate

## 1. What is tested

`tests/test_bit_byte_learning.cpp` drives the two-rate mesh:

```text
bit cycle:  0 -> 1 -> 0                  (2 tokens)
byte cycle: 0 -> 1 -> ... -> 255 -> 0    (256 tokens)
```

Each token is encoded by `HopfieldRouter::token_code`, a deterministic
splitmix-based 32-dimension signed code. The code is now part of the learner
API, not test-local FNV.

## 2. Setup

- 32-dimensional head/query vectors;
- `top_k = 1`;
- 10 passes;
- 256-slot transition table;
- overbootstrap observes every trace and sends bounded ±8 head bias.

## 3. Results

```text
bit:  2/2
byte: 255/256
used byte slots: 256
overbootstrap traces: 20 for bits, 2560 for bytes
```

The one unresolved byte transition is a real next target, not hidden by a
threshold. The test requires at least 255/256 and reports the exact value.

## 4. Why this matters

This is the first gate where the fast learner sees actual byte tokens, not a
toy vocabulary, while the slower overbootstrap learns head evidence alongside
it. The two learners use different math:

- bootstrap: sparse Hopfield keys/strengths;
- overbootstrap: evidence counters and bounded bias.

## 5. Next

1. Replace the synthetic byte cycle with Alice/Moby byte streams.
2. Compare byte top-1/BPC against context-2, KN-2, and the bigram gate.
3. Resolve the remaining byte transition.
4. Store overbootstrap evidence in the 2 GiB layer payloads and merge it through
   Koyeb.
5. Add word/pair tokens only after the byte gate is stable.
