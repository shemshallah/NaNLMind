# Training a single state space

## 1. What "training" means here

The core is not a floating-point transformer. It is an integer state space with:

- 16 Boolean functions per cell;
- two temporal rails per pair;
- 256 resonance heads per chart;
- hyperedges with integer weights;
- a temporal link graph;
- a global ledger.

Training therefore means changing **discrete or fixed-point parameters** under
a rule that can be replayed and merged:

| target | representation | learner |
|---|---|---|
| Boolean operator | 16-bit `ops` mask + `rule` | count wins, exhaust, evolve |
| rail values | 64-bit NaN words | Hebbian / delta / counting |
| pair weight | `s+`, `s-` words | integer Hebbian, decay |
| hyperedge weight | Q16.16 | integer delta, count |
| resonance phase/energy | Q16.16 | diffusion + local update |
| temporal link | (past, future, epoch) | sequence counting |
| head routing | activation/load | competitive inhibition |
| chart growth | child chart | load threshold |

No gradients are required. If a gradient is used in a host trainer, it is a
teacher, not part of the replayable object.

---

## 2. The training loop

```text
for each shard:
  1. lease a page range / chart range
  2. read the current committed pages
  3. run a bounded number of local updates
  4. emit integer deltas + counters
  5. hash the delta
  6. release the lease
merge:
  1. verify every delta against its base hash
  2. fold commutative counters (add)
  3. fold ordered deltas (replay in ledger order)
  4. recompute the global digest
  5. publish a generation
  6. evaluate against baselines
```

The merge is a fold:

- **commutative** for counters and weights (addition, saturating);
- **associative** for shard sets;
- **deterministic** for ordered deltas;
- **idempotent** for duplicate delivery;
- **rejectable** for a stale base or a bad hash.

This is the same "train by counting, merge by adding" principle as NaNLM, lifted
to the state space.

---

## 3. Local learning rules

### 3.1 Boolean mask learning

For a cell with a target bit `y` and inputs `a,b`:

```text
for n in 0..15:
    score[n] += (BOOL.n(a,b) == y) ? +1 : -1
ops = { n : score[n] > threshold }
rule = argmax_n score[n]
```

Only 16 candidates. Exhaustive search is cheap. Evolution is cheap. The mask is
16 bits, so a mutation is a single bit flip and a ledger event.

### 3.2 Hebbian pair learning

For a pair cell `(a,b)`:

```text
if active(a) and active(b):
    s+(a,b) += η · (1 - s+(a,b))   // saturating
    s-(b,a) += η · (1 - s-(b,a))
if only one active:
    decay
```

In integer arithmetic, replace `η` with a shift and clamp. The two rails are
updated independently, preserving order.

### 3.3 Sequence learning

For a sequence `x0, x1, ..., xk`:

```text
link(x_t, x_{t+1}, epoch=t, weight += 1)
```

Forward replay follows `s+`; backward replay follows `s-`. A branch is a
second link from the same past. A merge is a second link into the same future.
The temporal module already exposes these operations.

### 3.4 Resonance learning

For a target head `j` activated by a source `i`:

```text
c_ij += δ
e_j += γ · e_i
phase_j += small correction toward phase_i
```

Keep `c` symmetric when the relation is undirected; use hyperedges when the
relation is multi-way. Clamp and leak to keep the field bounded.

### 3.5 Competitive head specialization

The R15 result used online k-means with a conscience term. A substrate version:

```text
activate heads by similarity
apply lateral inhibition through the s- rail
increase the winner's special_score
decrease the losers' scores
```

The inhibition must be a local rule over the head's pair list, not a host loop.
That is an explicit milestone.

---

## 4. Teacher distillation

A teacher language model can produce targets, but the student stores counts, not
gradients:

1. run the teacher on a corpus shard;
2. emit `(context, target, weight)` counts;
3. merge counts by addition;
4. compile counts into pair weights, operator masks, or temporal links;
5. evaluate the student on a held-out shard.

This is how a small open teacher can improve the substrate without a GPU farm.
The teacher is a data source; the object remains integer and replayable.

The NaNLM/Qwen7B work already provides the pattern: teacher cards, token
shards, additive merges, and honest BPC/top-1 baselines. The new object can use
the same shard format, but the target is a chart delta, not a dense matrix.

---

## 5. GPU use

GPUs are useful for:

- simulating many charts in parallel;
- evolving operator masks / hyperedge weights;
- running a teacher for distillation;
- evaluating resonance fields at scale;
- searching for local rules that pass a gate.

GPUs are **not** required for the core. The object is integer and page-based;
a CPU runner can host a chart. A free GPU can accelerate training, but the
artifact must still replay on CPU.

The five 7 GiB runners are the baseline. A GPU farm is an optional accelerator,
not a dependency.

---

## 6. Community training

A volunteer can:

- lease a chart range;
- run a local update on a corpus slice;
- upload a delta + counters;
- never see the whole object;
- never need a trusted coordinator.

The merge job verifies:

- the delta base hash;
- the page hash;
- the ledger link;
- the global digest;
- the evaluation card.

A volunteer cannot fork the object because a delta is against a committed base
and the ledger is one chain. A volunteer can contribute a new chart, a new
hyperedge, or a new temporal link; the merge decides whether it is consistent.

---

## 7. Evaluation gates

A generation is not "better" because it is larger. It must pass:

### 7.1 Substrate gates

1. `make test` passes.
2. Global digest recomputes.
3. Ledger verifies from genesis.
4. Page hashes match.
5. A stale delta is rejected.
6. A duplicate is a no-op.
7. A head survives relocation.

### 7.2 Capability gates

1. **Sequence memory**: replay a held-out sequence forward and backward;
   compare with a symmetric-storage baseline.
2. **Hyperedge completion**: hold out a relation; can the object infer it from
   the remaining hyperedges? Compare with a pairwise-only baseline.
3. **Resonance recall**: a target head is reached from a cue; compare with a
   static matrix of the same size.
4. **Boolean learning**: a cell learns the correct function from feedback;
   compare with a fixed mask.
5. **Formal logic**: the R21/R23 behavior suite compiled into substrate rules;
   compare with the host implementation.
6. **Language modeling**: next-byte/token prediction on a held-out stream;
   compare with an n-gram and a count-based slot memory.

### 7.3 Honesty gates

- Report the baseline, the sample size, and the confidence interval.
- Report the null, including a shuffled-label null.
- Do not claim a win from a cherry-picked seed.
- Do not call a host symbolic result "emergent."
- Do not call a combinatorial state count "intelligence."

---

## 8. What to train first

The first trainable target should be small and measurable:

> **A single chart that learns a short sequence and replays it both ways.**

Why:

- it uses the temporal split directly;
- it has a clear baseline (symmetric storage cannot replay order);
- it is small enough for a CPU;
- it exercises the pair rails, the fixed points, and the ledger;
- it can be merged from shards.

The second target:

> **A hyperedge completion task across two charts.**

Why:

- it uses the one-object cross-space relation;
- it has a pairwise-only baseline;
- it tests whether hyperedges add information beyond edges.

The third target:

> **A resonance recall task with a static-matrix baseline.**

Why:

- it tests whether the wave dynamics add anything;
- it is the R18 claim, made falsifiable.

Only after these should the project attempt language-model-scale training.

---

## 9. Invariants for training

1. Training is integer or fixed-point in the replayable path.
2. Every durable update is a delta with a base hash.
3. Every delta is idempotent by key.
4. Merge is commutative for counters and associative for shards.
5. A stale base is rejected.
6. A teacher is a data source, not a runtime dependency.
7. A GPU is an accelerator, not a requirement.
8. A generation is evaluated against a baseline and a null.
9. A claim without a confidence interval is not a result.
10. The object stays one object after every merge.
