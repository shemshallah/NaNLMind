# Hopfield token-sequence learning

## 1. What was tested

`tests/test_hopfield_learning.cpp` trains the sparse Hopfield layer on a token
cycle:

```text
0 -> 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 0
```

The setup is deliberately small:

- 8 active token codes, one-hot in 16 dimensions;
- 1 active head per query;
- 8 transition slots;
- 10 training passes;
- no gradients, no Adam, no 2 GiB map.

## 2. Learning rule

Each token is a query vector `q`. The router selects the top head, scans the
pairs involving it, and votes with key/strength weights. A wrong or absent
answer writes the weakest matching query slot; a correct answer strengthens it
and moves the key toward `q`.

The critical fix was **key identity**:

```text
Do not decay a slot merely because an active head is shared.
Decay/evict only when dot(q, slot.key) > 0.
```

Without that check, query `0` and query `1` could damage each other's slots
because their pair cells shared a head. That produced only 4 learned slots.

## 3. Result

After 10 passes:

```text
learned transitions: 8/8
used slots:          8
replay 0..7 twice:   15/15
PASS Hopfield token-sequence learning
```

The sequence is held out in the sense that replay uses the learned transition
graph; it is not a language result. It proves the update/eviction loop can learn
and retain distinct associations without cross-query corruption.

## 4. What this is

- a real sparse associative learner;
- deterministic;
- small enough for Android;
- keyed by query, not by active-head overlap alone.

It is not yet a byte/word language model. The next tests replace the 8-token
cycle with byte/word sequences and measure BPC/top-1 against the existing
count/Kneser-Ney baselines.

## 5. Next

1. Run the Hopfield loop on Alice/Moby byte transitions.
2. Compare against the context-2 and KN-2 baselines.
3. Add a layer-policy switch so different layers use different learners.
4. Keep the 2 GiB bootstrap map out of the Android path.
