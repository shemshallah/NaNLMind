# Open questions

These are the questions the repository does not answer yet. Each one has a
test or a decision point attached, so it can become a result rather than a
permanent ambiguity.

---

## 1. Is the pure local mirror topology universal?

The archive shows:

- Rule 110 can be embedded in a linear window;
- a two-counter machine runs in a host interpreter whose memory is the
  topology;
- self-modifying code patches program cells;
- hierarchical pages work.

It does **not** show that the local cell rules, without a host `vm_step`, can
implement a universal machine. The next test is a local-rule two-counter
machine. If it cannot be built, the honest claim is "a universal machine hosted
on the topology," not "the topology is universal."

**Decision point:** M7.

---

## 2. Do hyperedges add capability over pairwise edges?

A hyperedge can connect many cells across many charts. That is expressive, but
is it useful? The decisive experiment is held-out hyperedge completion:

- train on a set of relations;
- hold out one relation;
- reconstruct it from the remaining hyperedges;
- compare with a pairwise-only model of the same size.

**Falsified if:** no margin over the pairwise baseline, or the margin vanishes
under a shuffled-label null.

---

## 3. Does the temporal split beat symmetric storage?

The R18 sequence-memory result suggests yes: asymmetric storage preserves
order; symmetric storage does not. The new `BidirectionalMemory` makes the
mechanism explicit. The next test is a substrate-only sequence task:

- store a sequence in the pair rails;
- replay forward and backward;
- compare with a symmetric matrix.

**Falsified if:** the symmetric baseline matches forward/backward recall.

---

## 4. Does resonance add capability over a static matrix?

R18 reports wave propagation, coherence, and recall. The new core uses integer
diffusion. The decisive test is a recall task with the same node count and
parameter budget:

- resonance field vs static matrix;
- pre-registered margin;
- shuffled null.

**Falsified if:** no gain.

---

## 5. Is one-object distribution achievable under partition?

The design says one ledger, one head, one digest, with leases and base hashes.
The failure modes are specified, but not all are implemented. The open question
is whether the protocol survives:

- a replica disappearing mid-commit;
- a stale writer after a long partition;
- a duplicate delivery after a heal;
- a page migration during a write;
- a clock tick gap.

The R15/R17 experiments are the specification. M4 is the integration.

---

## 6. What is the right self-modification policy?

The head can XOR its 16-bit Boolean mask and select the lowest enabled
function. That is a minimal mechanism. Open questions:

- Should the mask be sparse or dense?
- Should the selected rule be the lowest bit, a learned score, or a router?
- How often may a head rewrite itself?
- Does self-modification improve a task, or only add state?
- How do we prevent a runaway rewrite loop?
- Should a rewrite require a quorum, a lease, or a local capability only?

The scratchpad makes experiments cheap. The first test should be a small
Boolean learning task with a fixed-mask baseline.

---

## 7. How should the per-head scratchpad be structured?

Current split: 256 B local + 768 B work. Open questions:

- Is 1 KiB enough for a head's working set?
- Should the local area be a register file, a stack, or a ring?
- Should the work area be paged or fixed?
- Should scratchpad writes be ledgered individually, or batched into a delta?
- Can a head share its work area with a hyperedge?
- How does a head's scratchpad migrate with its page?

The scratchpad is part of the one `Universe`, so it inherits COW, dirty
tracking, and page migration. The open question is the layout, not the
ownership.

---

## 8. What does the logical clock actually synchronize?

The nanclock is a logical oscillator, not a wall clock. Open questions:

- Should the committed tick be advanced by the coordinator, a quorum, or the
  writer?
- How do leases handle a tick gap?
- Does the period-2 phase map cleanly onto two-phase commit?
- Can a replica reconstruct the clock from the ledger alone?
- What happens if two replicas claim the same tick with different phases?
- Is the period-2 orbit useful as a cadence, or only as a curiosity?

The current answer: the stamp is `(tick, phase)`, the ledger is the authority,
and a divergent oscillator is rejected. The integration with leases is M4.

---

## 9. How big can the object usefully get?

The dense table goes to 32 PiB at depth 4, but density is not usefulness. Open
questions:

- What is the active working set for a real task?
- How many charts are touched per query?
- What is the page-fault latency from reporam/repovram/S3?
- Does the hypergraph locality match the placement?
- At what depth does the global digest become too expensive?
- Can partial verification replace a full root recompute?

The scaling table is arithmetic. The useful scale is an empirical question.

---

## 10. What is the training signal?

Candidates:

- next-bit / next-byte prediction;
- sequence replay (forward/backward);
- hyperedge completion;
- resonance recall;
- Boolean-mask learning;
- formal logic / proof chains;
- teacher distillation counts.

The first three are the most substrate-native. The last three are the most
likely to produce a measurable capability. The project should not attempt
language-model scale before one of them beats a baseline.

---

## 11. How do we measure "one mind" without mysticism?

Operational candidates:

- one global digest across disruption;
- one ledger that replays from genesis;
- one head identity that survives relocation;
- one hypergraph that connects charts without a coordinator;
- one temporal memory that goes forward and backward;
- one clock stamp that orders events.

These are substrate properties. They do not settle consciousness, personhood,
or moral status. The project should use "mind" carefully and define it when it
does.

---

## 12. What would make us stop?

A good research project has stop conditions:

- the local-rule VM cannot be built after a bounded effort;
- hyperedges show no gain over pairwise edges;
- resonance shows no gain over a static matrix;
- the one-object protocol cannot survive a partition without a coordinator;
- the 8 MiB chart cannot fit the runner budget with the required history;
- the training signal cannot beat a simple baseline.

If one of these happens, the honest response is to narrow the claim, not to
add another layer of metaphor.

---

## 13. What is the next single experiment?

If only one experiment can be run next, run this:

> **A substrate-only bidirectional sequence memory on one chart, compared with
> a symmetric-storage baseline.**

Why:

- it uses the temporal split directly;
- it uses the pair rails and the 256 heads;
- it has a clear baseline and a clear failure mode;
- it fits one CPU and one 8 MiB chart;
- it can be merged from shards later.

If it passes, the next experiment is hyperedge completion across two charts. If
it fails, the temporal split is a taxonomy, not a memory, and the design should
be revised before scaling.
