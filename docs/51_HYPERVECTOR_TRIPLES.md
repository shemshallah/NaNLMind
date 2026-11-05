# XOR hypervector triple store

## 1. Encoding

```text
item code      deterministic 4096-bit hypervector
bind(a,b)      XOR
bundle         signed integer counters, threshold at read
permute        cyclic bit permutation
triple         bind(subject, bind(relation, object))
```

No floats. Bind is self-inverse; code cleanup is nearest Hamming.

## 2. Test

`tests/test_hypervector.cpp` stores:

```text
penguin can swim
penguin cannot fly
eagle can fly
bird has wings
```

and merges a second store containing the same penguin/eagle facts plus more.
Queries unbind subject and relation, then clean up against the item codebook.

```text
PASS XOR hypervector triple store
```

Also tested:

- bind is XOR and self-inverse;
- merge is integer counter addition;
- permutation is invertible;
- stored triples survive a merge.

The test uses 4096 bits so six bundled triples clean up reliably; 256/1024-bit
versions were too noisy for this bundle size.

## 3. Why this layer matters

- learns from one example;
- tolerates bit flips;
- merge order is addition, so it commutes;
- gives the relation path a distributed representation alongside the exact
  triple store;
- can feed candidates into the learned Boolean exception gates.

## 4. Next

1. Hypervector triple store vs the 20k symbolic split.
2. Bundle capacity vs number of triples.
3. Bind relation inverses through permutation/transpose.
4. Teacher/gate: hypervector recall -> head exception -> triple-store grade.
