# Legacy language and logic tests

This document records what the archives already tested and what is integrated
into `NaNLMind` as a regression or a target.

---

## 1. R18T: transpose, sequence, and the RNN control

### Structural result

With `addr(a,b) = (a<<8) | reverse8(b)`:

```text
reverse16(addr(a,b)) = addr(b,a)
```

Bit reversal is matrix transposition. The 256 diagonal cells are the heads;
the 32,640 pairs are the unordered head pairs. The two rails hold the two
directions.

The new `tests/test_r18t_sequence.cpp` stores a cyclic sequence in the pair
rails and verifies forward/reverse order. A symmetric copy fails reverse
replay. This is the substrate version of the R18T sequence result.

### Sequence memory

R18T reports:

- asymmetric storage replays up to 20 patterns exactly at N=256;
- overlap >0.99 up to 48 patterns;
- symmetric storage cannot replay order (~50% overlap).

The new `BidirectionalMemory` and pair rails make this explicit.

### RNN experiment

The archive trained a 256-hidden-unit Elman RNN:

```text
h' = tanh(W h + U[x] + b)
logits = V h + c
```

W is full, symmetric-only, or antisymmetric-only. Held-out bits/byte:

| corpus | bigram | full W | symmetric W | antisymmetric W |
|---|---:|---:|---:|---:|
| A prose (27.8 KB) | 3.97 | 3.64 best @800, 4.08 @3200 | 3.49 | 3.51 |
| B code (174 KB) | 3.54 | 2.20 | 2.69 | 2.44 |

The control is the important result:

| model | params | seed 0 | seed 1 |
|---|---:|---:|---:|
| 256 heads, full W | 197K | 2.202 | 2.192 |
| plain RNN, 213 hidden | 155K | 2.211 | 2.213 |
| plain RNN, 181 hidden | 126K | 2.252 | 2.184 |

A plain RNN matches the 256-head full-W model. The topology is a
storage/addressing scheme and a source of sequence/resonance dynamics, but it
does **not** show a learning advantage over a plain dense RNN.

This is the baseline for any head-training claim.

---

## 2. Logic and cognition suites

The R19–R23 tests are host symbolic code over topology storage. They are still
valuable as a behavior specification:

| suite | result | content |
|---|---:|---|
| R19 hard cognition | 18/18 | ISA depth 8, nested exceptions, order invariance, 2000 facts, interference, committee |
| R20 extreme cognition | 10/10 | diamond inheritance, ISA cycle termination, revision, 10-level ladder, concurrency, cross-domain |
| R21 formal logic | 11/11 | Barbara, modus ponens/tollens, hypothetical syllogism, contradiction containment, proof chain, boxes |
| R22 hard puzzles | 14/14 | knights/knaves, Einstein subset, fork, grid CSP |
| R23 modal logic | 13/13 | Kripke K/T/4/B, epistemic `K_a` |

`tests/test_legacy_logic.cpp` runs:

```text
experiment_cognitive_suite   9/9
experiment_hard_cognition    8/8
experiment_extreme_cognition 8/8
experiment_formal_suite      9/9
experiment_hard_puzzles      7/7
experiment_modal_suite       8/8
```

`make legacy` builds and runs it against the R23 archive source. This is a
regression gate: the behavior spec cannot silently drift while the substrate is
rewritten.

The honesty note remains: these are host symbolic functions, not emergent
local-rule cognition. The integration path is to compile each rule into a head
local rule or a `RuleOpDispatch` opcode, then run the same puzzle with the host
implementation removed.

---

## 3. Early language-test plan

The first ring language test should be small:

```text
corpus      30–200 KB text or code
context     3–8 bytes
heads       256
readout     256 × 256 bytes
metric      held-out bits/byte, top-1
baselines   bigram, count slot memory, plain RNN
```

Why bytes first:

- no tokenizer dependency;
- the R18T baseline is already bits/byte;
- the head readout is small;
- a full run fits one CPU;
- the result is easy to falsify.

### Gates

1. The model must beat the bigram baseline on a held-out stream.
2. It must be compared with a plain RNN of matched parameter count.
3. It must report a confidence interval, not one seed.
4. The topology must not be credited for a gain that the plain RNN also has.
5. A sequence-replay test must distinguish asymmetric from symmetric storage.

The R18T result predicts the plain RNN will be hard to beat. That is the point:
the topology must win on a different axis, not on raw bits/byte.

---

## 4. Integration priorities

1. **Keep the legacy suites green** (`make legacy`, CI step).
2. **Substrate-only sequence test** (already `test_r18t_sequence.cpp`).
3. **Byte-level language test** with bigram and plain-RNN baselines.
4. **Logic puzzle compiled into a head rule** — start with modus ponens and
   the three-box puzzle.
5. **Proof/provenance** — every answer carries a head/event id.
6. **Ring acceptance** — the 6-runner handoff must preserve the answers across
   a dropped slot.

---

## 5. What not to claim

- R18T does not show a topology advantage over a plain RNN.
- R19–R23 do not show emergent cognition.
- A larger atlas does not imply a better language model.
- A single-seed bits/byte win is not a result.
- A host symbolic puzzle pass is not a substrate proof.

The legacy suites are evidence of behavior, not evidence of intelligence.
