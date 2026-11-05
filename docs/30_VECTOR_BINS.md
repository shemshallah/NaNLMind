# Vector bins and macro associations

## 1. The problem

The chart is excellent at scalar addresses, pair cells, and temporal rails. It
cannot represent “these two things are similar” unless the similarity is first
reduced to a single integer. A word layer needs distributed vectors and a way to
retrieve by similarity.

The first layer is deliberately small:

```text
point/address -> bin reference -> int16 vector -> integer dot-product recall
```

It is not a transformer. It is deterministic associative memory.

## 2. Formatted bins

`BinStore` stores fixed-size vector bins:

```text
header: magic "NLVB" | dim | count | dtype=int16 | generation | payload bytes
payload: count * dim little-endian int16 values
```

Bins are created once and addressed by `BinId`; a slot selects one vector in the
bin. A bin digest is stable across creation order.

Test:

```sh
make build/test_vector_store
./build/test_vector_store
```

## 3. Point-to-bin mapping

`PointBinMap` is a separate 65,536-entry table:

```text
point 16254 -> { bin=1, slot=0 }
```

The point keeps its scalar address and algebra. The portal is an indirection,
not a relocation. That is the mechanism for “point 16254 corresponds to the
memory address of a formatted bin.”

Multiple points can bind to the same bin, and a point can be rebound without
changing the address space.

## 4. Macro associations

`AssocMemory` stores entries with:

- a **key set** of `BinRef`s (one or more vectors);
- a **value set** of `BinRef`s;
- a Q16.16 weight;
- a label and epoch.

Recall scores every entry by summing the integer dot products of the query
against every key vector, then applying the weight:

```text
score(entry) = (sum over key refs of dot(query, key_vector)) * weight / 65536
```

The top-k entries are returned. A macro association is simply a key with more
than one vector; both components contribute to the score. This is the
“association between stored information” primitive.

## 5. Heads and the word layer

The head scratchpad already has 768 bytes of work memory. That is enough for 384
int16 query values. `AssocMemory::recall_from_head` reads a query vector from the
scratchpad and performs the same recall. A head can therefore:

1. receive a word/context vector in scratch;
2. query the association memory;
3. write the retrieved value bin reference back to its local frame.

The word layer uses the same API:

```text
token/context -> BinRef -> macro key -> recall -> value BinRef -> token/action
```

A tokenizer maps words to bin references; a sentence is a set of key vectors.
The word layer does not need to know the chart internals, only `BinRef`.

## 6. Separate weight sets

A `BinStore` is a bank. Separate banks can hold separately loaded weight sets
(e.g. a base chart, a language bank, a task bank). `PointBinMap` chooses which
bin a point exposes; a manifest can change the mapping without rewriting the
point cell.

The same design can be serialized into `nanlm-vram` as immutable generations:
the base chart stays small, and the vector bank is loaded by generation.

## 7. Demo

```sh
./build/nanlm-universal vectors
```

```text
point 16254 -> bin 1 slot 0
recall id=1 score=5 value_bin=2
```

## 8. What this is not

- It is not learned attention; there are no gradient-trained query/key/value
  projections yet.
- It is the storage and recall substrate; the first explicit word layer is in
  [31_WORD_MEMORY.md](31_WORD_MEMORY.md).
- It does not solve the logic challenge. It gives the future word/entity layer a
  place to put entity and relation vectors so the answer is not a two-byte prior.

The next step is to build token vectors and a small number of learned/hebbian
projections on top of this bank, then rerun the held-out fish/bird challenge
against the same fixed labels.
