# Lift, hypervectors, and the scale stack

## 1. What is in a layer-2 vector?

The layer-2 payload can be:

- a head's 16-int16 score/vector output;
- a word-vector slot;
- a route cell.

For the lift decision, treat the **head/word payload** as the layer-2 vector.
The route cell is metadata, not the vector.

## 2. Four lift choices

| lift | use | cost |
|---|---|---|
| embed `ι_c(v)=e_c⊗v`, restrict `π_c` | stored truth | 256× sparse direct sum |
| random-sign/Hadamard sketch | parent summary | JL distortion |
| outer product `u⊗w` | relations; transpose inverse | matrix size |
| NTT/Walsh low-frequency | multi-resolution | optional, lossy |

**Decision:** use embed/restrict as stored truth, sketch for upward summaries,
outer product for relation charts. Treat frequency lift as optional. Keep every
cross-layer map linear and integer; nonlinear only at read/argmax/cleanup.

Adjoint check: `⟨ι_c v, P⟩ = ⟨v, π_c P⟩`; this credits parent scores to the
right child vector without a new rule.

## 3. Hypervector layer — top pick

```text
bind(a,b)    = XOR
bundle       = integer counters, threshold at read
permute      = transform phase
triple       = bind(subject, bind(relation, object))
query        = unbind + cleanup against item codes
```

- one-example learning;
- bit-flip tolerance;
- bundle counters merge by integer addition;
- no floats.

This is the first layer to build after the Boolean spectrum.

## 4. Semiring closure

Same 256×256 chart, different algebras:

```text
OR/AND     reachability
min/+      shortest path
max/×      best path
+/×        diffusion/counts
```

Inheritance is Boolean matrix power; forward uses `A`, backward `Aᵀ`. The two
meet in frame sync. Nonlinear threshold only at read.

## 5. Other useful layers

- **Inheritance structure:** kinds in router charts, entities in children,
  exceptions as sparse residuals. Low-rank kind model + sparse exception.
- **Reversible coupling:** `(x1, x2 + F(x1)) mod 2^16` with exact inverse; no
  stored activations.
- **Erasure:** Reed-Solomon over slots; use GF(256) or 9-bit symbols, never
  F257 with a parity symbol equal to 256.
- **Reservoir:** fixed sparse integer recurrence with trained readout; must beat
  a static matrix under a pre-registered test.

## 6. Scale stack

```text
hardware              one chart
subcluster            256-chart router / 2 GiB overbootstrap
cluster/macrocluster  65,536 charts
IoT supercluster      16.7M charts
global mesh           4.3B charts
```

Up: counters/Count-Min/random-sign Hadamard sketches; merge by addition.
Down: read-only consolidated priors with generation.
Sideways: route cells; symmetric part affinity, antisymmetric part clock offset.

Each overlay is the same 256×256 object, so transforms compose. Global routing
with 8-bit digits is Pastry-like: at most four hops to 4.3B. Bit-reversed wake
order is a low-discrepancy prefix schedule.

## 7. Teacher and gate

The symbolic reference and learned gates must meet:

```text
Hopfield       recalls candidate relations
HeadGate       applies the exception rule (A AND NOT B)
TripleStore    grades the result
```

Cassowary is the concrete test: `cassowary isa bird`, `bird can fly`,
`cassowary cannot fly` -> no. The word/logic layer now includes this exception.

## 8. Falsifiable experiments

1. Shuffle merge order; require identical digests.
2. Hypervector triple store vs the 20k symbolic baseline.
3. Remove 30% of slots; recover.
4. Reversible coupling vs stored activation memory.
5. NTT correlation vs naive scan.
6. Degree-2/3/4 term learner: accuracy should jump at nesting depth + 1.

## 9. Rejected for now

- floats/Adam inside the object;
- full direct-sum storage at every layer;
- dense macrocluster copies;
- F257 erasure with 256 symbols;
- treating transform phase as a sequence of different inverses (Klein-four is
  self-inverse);
- one global optimizer for all layers.
