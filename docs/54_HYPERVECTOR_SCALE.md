# Hypervector scale: 20k split

## 1. Setup

Generated logic:

```text
entities        20,000
kinds              256
exceptions       2,858
facts            ~23k
shards            1,024
hypervector bits  4,096
```

Two arrangements:

- one global bundle containing every fact;
- 1,024 subject-hash shards, each with its own bundle and a shared item codebook.

## 2. Result

```text
global bundle top-1: 0.0000
sharded top-1:       1.0000
```

The global bundle does not clean up at this capacity. Sharding by subject makes
the direct `entity isa kind` queries exact.

## 3. Bugs found and fixed

1. **Positive-count threshold.** `threshold()` originally set any bit with a
   positive counter. With many triples that saturates toward all ones. It now
   uses a majority: `2 * count[bit] > items`.
2. **Missing object codes.** A shard cleanup codebook did not contain the kind
   codes it needed. The test now registers the relevant object codes in each
   shard.
3. **Shard cleanup scope.** A 256-code shard was too noisy for some settings;
   registering only the kinds used in that shard keeps the codebook small.

## 4. Interpretation

- Hypervectors are not a single global store at 20k facts.
- They work when the cleanup codebook and bundle are localized.
- That is exactly the lift/shard pattern: linear bundles merge, but cleanup must
  be bounded.

## 5. Test

```sh
make hyper-scale
```

## 6. Next

1. Add exception facts to the sharded hypervector store.
2. Compare sharded hypervector vs symbolic 20k split per relation.
3. Add degree-2/3 exception terms.
4. Measure shard count vs recall and memory.
