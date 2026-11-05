# How the heads train

## Short answer

Training is **integer score learning in the scratchpad**, not backpropagation in
the head. Each head keeps a table of 16 scores for the 16 Boolean functions.
Every observed `(a, b, target)` increments the score of functions that match and
decrements the others. The winner-take-all function becomes the head's `rule`;
the mask becomes `1 << rule`. Sequence order is stored in the temporal links;
resonance is integer diffusion; a teacher model is optional and only produces
counts or targets.

No float is required in the replayable path.

---

## 1. Boolean score learning

The scratchpad reserves `work()[16..47]` for 16 little-endian `int16` scores.

```text
for each observation (a, b, target):
    for op in 0..15:
        pred = (op >> (2a + b)) & 1
        score[op] += (pred == target) ? +1 : -1
    rule = argmax score
    mask = 1 << rule
```

`HeadView::train_boolean(a,b,target)` implements this. It is capability-gated
through `set_boolean_mask`, records a head-history event, and updates the address
descriptor checksum.

Properties:

- 16 candidates only, so learning is exhaustive and cheap;
- integer scores, saturating at ±32767;
- deterministic and replayable;
- mergeable: two score tables add;
- the full score table remains in scratch for inspection or ensembles.

The test `tests/test_training.cpp` learns XOR and AND from scratch, checks the
selected rule, and evaluates the learned rule on 32 lanes.

---

## 2. Sequence learning

A sequence is a chain of temporal links:

```text
A -> B -> C -> ...
```

Each link stores `(past, future, epoch, flags, weight)`. The pair cell's two
rails hold the forward and reverse directions. Forward replay follows `s+`;
backward replay follows `s-`. A branch is a second link from the same past; a
merge is a second link into the same future.

This is the substrate version of the R18T sequence-memory result: asymmetric
storage replays order; symmetric storage cannot. The current core exposes this
through `BidirectionalMemory` and the pair rails.

Training a sequence is counting:

```text
observe x_t, x_{t+1}:
    link(x_t, x_{t+1}, epoch=t, weight += 1)
```

The weight is an integer; adding shards is addition.

---

## 3. Resonance learning

Resonance is an integer heat equation over the 256 heads. Training can:

- increase coupling `c_ij` when `i` predicts `j`;
- add phase correction toward a target;
- decay unused edges;
- use hyperedges for multi-head relations.

Keep `c` symmetric when the relation is undirected; use a directed hyperedge
when it is not. Clamp and leak to keep the field bounded.

---

## 4. What the R18T archive established

The merged R15–R22 archive contains `experiments/r18t_rnn/`:

- 256 hidden units, `h' = tanh(W h + U[x] + b)`, `logits = V h + c`;
- W can be full, symmetric-only, or antisymmetric-only;
- corpus A: 27.8 KB prose; corpus B: 174 KB C++ source;
- 3200 iterations, 1.64M bytes seen, held-out bits/byte.

Headline results:

| corpus | bigram | full W | symmetric W | antisymmetric W |
|---|---:|---:|---:|---:|
| A prose | 3.97 | 3.64 best @800 (4.08 @3200) | 3.49 | 3.51 |
| B code | 3.54 | 2.20 | 2.69 | 2.44 |

The control is the important part:

| model | effective params | seed 0 | seed 1 |
|---|---:|---:|---:|
| 256 heads, full W | 197K | 2.202 | 2.192 |
| plain RNN, 213 hidden | 155K | 2.211 | 2.213 |
| plain RNN, 181 hidden | 126K | 2.252 | 2.184 |

A plain dense RNN with fewer parameters matches the 256-head full-W model. The
control document is explicit: the topology is a storage/addressing scheme and a
source of resonance/sequence dynamics, but it shows **no measured learning
advantage** over a plain RNN.

This is the honest baseline for head training. The topology must earn any claim
through a different axis: one-object distribution, bidirectional memory,
hyperedge completion, energy, or deterministic replay — not raw bits/byte.

---

## 5. Early language tests

The archive already has the right shape for early language tests:

- byte-level next-byte prediction;
- bits-per-byte and top-1;
- bigram baseline;
- held-out split;
- learning-speed curve (bytes seen to pass the baseline);
- sequence memory (forward/backward replay);
- a plain-RNN control.

The first head-ring language test should be deliberately small:

```text
corpus: 30–200 KB of text/code
context: 3–8 bytes
heads: 256
readout: 256 → 256 bytes
loss: bits/byte
baselines: bigram, count-based slot memory, plain RNN
```

Do not start with a 7B teacher or a token vocabulary. Start with bytes, a
held-out stream, and a confidence interval.

---

## 6. Logic tests from the archives

The R21–R23 suites are a behavior specification:

- Barbara syllogism, modus ponens/tollens, hypothetical syllogism;
- contradiction containment;
- 12-step proof chain;
- three-box puzzle;
- knights/knaves, Einstein subset, fork, grid CSP;
- Kripke K/T/4/B, epistemic `K_a`.

They are currently host symbolic code over topology storage. The integration
path is:

1. keep the C++ suite as a regression gate;
2. compile each rule into a head/local rule or a `RuleOpDispatch` opcode;
3. run the same puzzle with the host implementation removed;
4. compare the answer and the proof/provenance.

The legacy logic test should stay in CI so the behavior spec cannot silently
drift.

---

## 7. The 6-runner training loop

```text
epoch t (logical clock tick)
  runner r owns heads H_r
  preload: page + head cells + scratch + neighbour pair cells
  local updates:
      - Boolean score observations
      - temporal link counts
      - resonance coupling deltas
  emit: HeadPacket per head + ScratchJournal delta
  barrier: all runners prepared
  commit: one ledger event, manifest flip
  handoff: next runner preloads the new page version
```

A runner never owns a private history. The ledger event is the commit; the
packet is the handoff; the manifest is the derived pointer.

### Head map for six runners

```text
owner(head) = head mod 6
```

Counts: 43 heads for runners 0–3, 42 for runners 4–5. The map is deterministic;
any runner can reconstruct it. The wake slot is `reverse8(head)` for survivor
spacing; the handoff order is bit-reversed, not linear.

---

## 8. Community training

A volunteer trains a shard:

1. lease a head range / chart;
2. read the committed page;
3. run N local observations;
4. emit a `ScratchJournal` with base hash and score deltas;
5. hash it; release the lease.

Merge:

1. verify base hash;
2. replay the journal into a COW page;
3. add counters (commutative) or apply ordered deltas;
4. recompute the global digest;
5. publish a generation.

A stale shard is rejected; a duplicate is a no-op. This is the same
counting/CRDT discipline as NaNLM's additive shards.

---

## 9. Training gates

A generation is not better because it is larger. It must pass:

1. `make test` and the legacy logic suite;
2. global digest replay;
3. held-out bits/byte vs bigram;
4. sequence forward/backward recall vs symmetric storage;
5. hyperedge completion vs a pairwise baseline;
6. resonance recall vs a static matrix;
7. handoff epoch consistency and survivor gap;
8. one global ledger, no fork.

A claim without a baseline and a confidence interval is not a result.

---

## 10. What not to claim

- The 256-head topology does not beat a plain RNN on bits/byte in the R18T
  control.
- The host symbolic logic suites are not emergent cognition.
- Integer score learning is not backpropagation and is not a transformer.
- A larger atlas does not automatically improve a task.
- The oscillator is a logical metronome, not a wall clock.

The first honest win would be a substrate-only bidirectional sequence task that
beats symmetric storage, followed by hyperedge completion that beats a
pairwise-only model.
