# Word memory over vector bins

## 1. What this layer does

`WordMemory` is the first word-level layer. It tokenizes a small corpus, maps
each token to a one-hot vector in a `BinStore`, and stores facts as macro
associations:

```text
sparrow is a bird   -> key {sparrow, is, a}  -> value {bird}
bird can fly        -> key {bird, can}       -> value {fly}
ostrich cannot fly  -> key {ostrich, cannot} -> value {fly}
```

A query traverses:

```text
entity -> kind -> can/ability -> exception check -> yes/no
```

The vector bins and `AssocMemory` are the same storage/recall layer documented
in [30_VECTOR_BINS.md](30_VECTOR_BINS.md).

## 2. Result on the fixed challenge

The fixed bird/fish challenge has eight held-out cases. The word layer answers
all eight:

```text
sparrow can fly?    yes
magpie can fly?     yes
trout can swim?     yes
cod can swim?       yes
ostrich can fly?    no
kiwi can fly?       no
emu can fly?        no
cassowary can fly?  no
```

The CLI reports:

```text
words vocab=22 associations=21 token_bin=1
  sparrow can fly? yes
  ostrich can fly? no
  trout can swim? yes
  cod can swim? yes
```

## 3. What is honest about it

This is **structured retrieval**, not a transformer suddenly learning logic.
The relation patterns (`is a`, `can`, `cannot`) are explicit host extraction
rules. The layer proves three useful things:

1. A point/bin bank can hold word-level vectors.
2. Macro associations can retrieve kind/ability values.
3. A held-out entity can be answered from stored facts plus the rule, instead
   of from a two-byte answer prior.

It does **not** prove that the byte model learned the rules. The byte model still
gets 4/8 on the same fixed labels. The word layer gives that work a target and a
storage API.

## 4. Heads and bins

A head has 768 bytes of work scratch, enough for 384 int16 query components.
The path is:

```text
head scratch -> query vector -> AssocMemory -> value BinRef -> token/action
```

A separate `PointBinMap` can expose a token/weight bank at a specific point
(for example `16254`) without moving the scalar point. The word layer does not
need to own the chart.

## 5. Next extensions

- Replace one-hot tokens with co-occurrence/hebbian vectors in the same bins.
- Learn the relation extractor from byte text instead of explicit patterns.
- Use multi-token macro keys for clauses and sentences.
- Add a training/update path for association weights instead of fixed Q16.16.
- Keep the fixed challenge labels unchanged and compare:
  - byte model,
  - word-memory baseline,
  - learned vector layer.

The fixed challenge is useful precisely because it can fail. The word layer is
a baseline that passes it; the byte model is still the thing being improved.
