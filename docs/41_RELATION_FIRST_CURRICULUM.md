# Relation-first curriculum

## 1. Why relations before bytes

A byte-level Hopfield mesh starts with no relational structure. The penguin
curriculum gives it a small, inspectable relation memory first:

```text
entity/relation key -> value token
penguin:isa         -> bird
eagle:isa           -> bird
emperor:isa         -> penguin
bird:can            -> fly
penguin:cannot      -> fly
penguin:can         -> swim
bird:has            -> wings
ostrich:cannot      -> fly
```

Keys are relation-qualified so one entity can carry several relations without
overwriting a single "penguin" slot.

## 2. Stage order

```text
Stage 0  relation-qualified Hopfield associations
Stage 1  word/logic layer: exceptions and transitive kind chains
Stage 2  bit and byte sequences
Stage 3  words/pairs over byte tokens
Stage 4  deeper puzzles and corpus
```

The logic layer resolves the penguin exception and the nested
`emperor -> penguin -> bird` chain. Hopfield stores direct relations; it does
not silently claim transitive inference.

## 3. Result

`tests/test_relation_curriculum.cpp`:

```text
relation associations: 8/8
overbootstrap traces:  80
penguin fly:           no
eagle fly:             yes
emperor fly:           no   (inherited penguin exception)
emperor swim:          yes  (inherited penguin ability)
bird fly:              yes
PASS relation-first penguin curriculum
```

The word/logic checks are structured retrieval, not emergent reasoning. The
point is that relation memory is stable before bytes/words are introduced.

## 4. Run the curriculum stages

```sh
make curriculum
```

This runs:

- relation-first penguin gate;
- word/logic memory;
- bit/byte two-rate gate.

The real Alice byte-stream challenge remains separate:

```sh
make byte-mesh   # expected to fail at the 18% threshold
```

## 5. Next

1. Add more logic puzzles as relation-qualified facts.
2. Let overbootstrap learn which relation keys are reliable.
3. Feed relation traces into the vector/word layer.
4. Only then add byte/word corpus scale.
