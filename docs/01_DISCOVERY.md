# Discovery audit: Round 2 to Round 23

This document reconstructs the flow of discovery from the archives in
`NaNLM_statespace/`. It is deliberately split into three columns:

- **demonstrated** — what the code and tests actually established;
- **host-driven** — results produced by C++ code outside the local cell rule,
  even when the output is stored in topology cells;
- **open** — what the archive claims or implies but did not prove.

The distinction matters. The archive is valuable precisely because it contains
many honest scope notes; the new repository keeps those notes rather than
smoothing them away.

---

## 0. Provenance and method

The source material is 27 ZIP archives:

- `NaN16_Palindromic_Temporal_Computer_Round2..Round23` (no Round 1 archive);
- `NaN16_Palindromic_Temporal_Computer_Round5-1` (duplicate of Round 5);
- `NaN16_Palindromic_Temporal_Computer_Round8-1` (duplicate of Round 8);
- `NaN16_PTC_merged_R15-R17` and `NaN16_PTC_merged_R15-R18`;
- `distributedmind.zip` (= Round 15 plus the R14 binary and the continuity
  header);
- `nanclock.zip` (the independent NaN Temporal Oscillator v2).

All archives were extracted under
`NaNLM_statespace/archive/<archive-stem>/`, one directory per archive, so
duplicate round names never overwrite each other. SHA-256 hashes are in
`NaNLM_statespace/ARCHIVE_SHA256.txt`. The original ZIPs are retained.

The earliest snapshot is **Round 2**, which contains `BRAINSTORM_1.md` and
`BRAINSTORM_2.md`. That is the true origin of the design.

---

## 1. The timeline at a glance

| round | title / artifact | strongest result | status |
|---:|---|---|---|
| 2 | PTME + pair-cell brainstorm, address orbits | exact 65,536 / 256 / 32,640 / 32,896 counts; 16,576 four-transform orbits | solid math |
| 3 | topology cells, no-PC experiments | Rule 90, signal decay, one adder, reversible XOR, consensus | prototype |
| 4 | Rule 110, arithmetic family, dual fields | 30-step Rule 110 match; 4/8/16-bit add/sub/cmp; dual adders; reversibility audit | prototype, host drivers |
| 5 | multiplication field | shift-add multiply; dual multiply fields | host driver |
| 6 | signal-carried ripple adder | Θ(bits) step adder; event-driven dirty queue; initial-state programs | mixed; host advances steps |
| 7 | dual-state mirror pairs | S+/S− isolation; complementary XOR; scale analysis | solid experiment |
| 8 | local dual rules | dual couple/cross; NAND chain; dual-rail add + shadow; order independence | mostly host-stepped |
| 9 | host-blind logic | XOR/AND gates; ripple-carry cell | local rule, host orchestrates |
| 10 | absolute checkpoint suite | NOT/CNOT/Toffoli/Fredkin; fixed rule map; schedule matrix; fault recovery | broad regression |
| 11 | initial-state programmability | one `RuleOpDispatch`; ADD/SUB/XOR/AND/CMP; four regions | host dispatches |
| 12 | program-in-state VM | program + IP + regs in cells; 14 programs; branches; dual VMs | host interpreter |
| 13 | 2CM + hierarchy + self-mod | 2-counter add/mul/copy; self-modifying code; pages; async dual VMs | host interpreter |
| 14 | cognitive architecture | bird/eagle/penguin; exceptions; counterfactual; feedback | host symbolic |
| 15 | heads, ledger, continuity | transpose theorem; 256 heads; hash chain; branches; migration; specialization MI 2.58 | strong systems + host learning |
| 16 | unity under differentiation | shared facts; contested claims; attribution; specialization stability/transfer/failure/relocation | host symbolic |
| 17 | continuity under disruption | interrupted commit; replay; duplicate delivery; reconstruction; migration; disappearing head | strong systems |
| 18 | resonance wave matrix | 256-node wave; 0→255 in ~148 steps; coherence; 500 facts; depth 4; recall | host numeric |
| 19 | harder cognition | ISA depth 8; nested exceptions; order invariance; 2000 facts; interference; committee | host symbolic/numeric |
| 20 | extreme cognition | diamond inheritance; cycle termination; revision; 10-level ladder; concurrency; cross-domain | host symbolic |
| 21 | formal logic | Barbara, modus ponens/tollens, hypothetical syllogism, contradiction containment, proof chain 12, boxes | host symbolic |
| 22 | hard puzzles | knights/knaves, Einstein subset, fork, grid CSP | host search |
| 23 | modal logic | Kripke K/T/4/B, epistemic K_a | host symbolic |
| merged | R15–R18 merge | transposition correspondence; asymmetric sequence memory | theorem + host matrix |

---

## 2. Phase A — address algebra and the pair-cell hypothesis (R2)

**What was demonstrated.**

`BRAINSTORM_1.md` defines the palindromic temporal memory engine:

- `R(a) = reverse16(a)`;
- canonical representative `C(a) = min(a, R(a))`;
- orientation `+1` if `a <= R(a)`, `-1` otherwise;
- 65,536 addresses, 256 fixed points, 32,640 mirrored pairs, 32,896 canonical
  classes;
- forward, reverse, and fixed-point roles; temporal RAM; sparse temporal
  pages; four transformations `{I, B, R, B∘R}` forming a Klein four-group.

`BRAINSTORM_2.md` shifts from "memory optimization" to "the pair is the
computer":

- shared-state dual-lane pair;
- independent mirrored cells;
- pair-as-cell state machine with two directional ports;
- exact capacity accounting;
- the warning that "32,640 pairs" is the bit-reversal count, not a made-up
  60,000;
- 16,576 combined four-transform orbits.

The C++ reference prototype exhaustively verifies the counts, the
involutions, the commuting byte-swap/bit-reversal transforms, the orbit
distribution, and a tiny shared-state temporal pair with before-image restore.

**What was not demonstrated.** No performance claim, no native NaN16 runtime,
no proof that mirror orientation is computationally useful beyond labeling.

**Why it matters now.** The exact language of R2 — synchronization coordinates,
fixed points as rendezvous, forward/reverse/fixed roles — is the correct
foundation for the temporally split state space. The new repository keeps that
language and drops the temptation to claim that canonicalization doubles RAM.

---

## 3. Phase B — topology as computer (R3–R6)

### R3: the cell becomes a state machine

R3 introduces a 24-byte host cell record with `canonical`, `mirror`, `orient`,
`rule_id`, `signal`, `flags`, `generation`, and `state`. The topology has
multiple neighbor geometries: mirror, byte-swap, orbit mate, Hamming-1,
linear ±1, temporal ±1. The experiments are deliberately small:

- Rule 90 produces a Sierpinski pattern;
- a signal propagates and decays;
- an adder field computes 22 + 11 = 33;
- reversible XOR is an involution under a frozen mask;
- majority consensus converges;
- the 256 fixed points are queryable.

There is still a host step loop. That is fine: R3 is a substrate prototype,
not a claim that the host disappears.

### R4: breadth, and the honesty note

R4 adds:

- a 64-cell Rule 110 window matching a host reference for 30 steps;
- 4/8/16-bit addition, subtraction, and MSB-first comparison as wavefronts;
- two independent adders in one topology (22+11=33 and 100+23=123);
- a reversibility audit table (`FULL`, `COND`, `IRREV`, `HIST`);
- fixed-point observation;
- a state-hash cycle probe;
- signal decay.

The R4 results document contains the key honesty note: the arithmetic drivers
use **linear geometric passes** over topology cells; the carry walks the
address line in software. The archive explicitly says this proves "arithmetic
as geometry," not yet "pure traveling-signal carry."

### R5: multiplication

Multiplication is a shift-add over an accumulator field. It is useful as a
behavioral specification, but `run_multiplier` is a host loop that calls the
host adder; it is not a local multiplier.

### R6: the signal-carried adder

R6 closes part of the R4 gap. `run_signal_adder` seeds bit cells with
`a_i`, `b_i`, and a signal on the LSB. A step loop collects the firing cells,
computes sum/carry, writes the carry into the next cell, and raises its signal.
The result is correct for 4/8/16-bit cases, and the step count is Θ(width).

Is the carry "only a signal"? The carry is carried in `state` bit 2 and the
next cell is scheduled by a host write to `tmps[i+1]`. The host still owns the
indexing and the commit. The archive's claim is narrower than "fully
asynchronous": it is a synchronous global-step simulation of a traveling
carry. That is a legitimate prototype, but it is not yet a pure local rule.

R6 also adds:

- an event-driven dirty queue;
- initial-state programmability (3+4=7 vs 10+5=15 under the same machinery);
- regression of the R4 dual adders.

---

## 4. Phase C — dual rails, local rules, checkpoints (R7–R10)

### R7: the two rails are real storage

R7 enables dual state on a canonical cell: `state = S+`, `aux = S-`. It shows:

- touching S+ leaves S− unchanged;
- touching S− leaves S+ unchanged;
- complementary XOR recovery works;
- a 1024-cell × 50-step bulk walk has zero isolation failures;
- the number of configurations is enormous (~10^9903 for 1 bit/cell shared,
  ~10^19728 dual 1-bit, ~10^157826 dual 8-bit).

The scale numbers are combinatorial, not a memory claim. The important result
is that the dual rail is a genuine independent payload, not a label.

### R8: local dual coupling, NAND, dual-rail add

R8 adds `RuleDualCouple` and `RuleDualCross`, a pair-to-pair NAND chain, a
dual-rail adder whose S− holds a shadow for validation, and an order
independence test over disjoint regions. The tests pass. The implementations
still call rules from a host loop with snapshots; "local" means the rule reads
only local neighbor views, not that a scheduler disappears.

### R9: host-blind gates and ripple cells

R9 is an important step because the host no longer computes the gate output.
It seeds inputs and steps the rule. XOR/AND gates and a full-adder ripple cell
work for 4/8/16-bit addition. The host still orchestrates the per-cell calls
and supplies neighbor snapshots.

### R10: the checkpoint suite

R10 is a broad regression suite:

- local XOR/AND and pure adder;
- mirror independence and cooperation;
- reversible gates NOT, CNOT, Toffoli, Fredkin;
- fixed rule map, programs = initial state;
- sync/reverse/scramble schedule matrix;
- injected faults detected by the shadow and recovered;
- topology scale;
- the "Mirror Machine Challenge" subset.

This is the strongest single-chart regression suite in the archive. It is also
where the phrase "mirror machine" becomes concrete: the two rails can carry
arithmetic and validation, not just two independent jobs.

---

## 5. Phase D — programmability, VM, two-counter machine (R11–R13)

### R11: one rule, many operations

R11 uses a single `RuleOpDispatch` rule. The host seeds an opcode and operands;
the rule interprets the opcode in `aux` and executes ADD/SUB/XOR/AND/CMP.
21 cases pass, including four simultaneous regions with four different ops.

This is a real reduction in host-side operation selection: the operation is in
the cell state. It is still a host-stepped rule.

### R12: program in the state

R12 stores the program, instruction pointer, registers, flags, and HALT in
topology cells. `RuleVmCycle` is stamped on all machine cells, but the actual
decode is `Topology::vm_step`, a C++ function that reads the cells, switches on
the opcode, and writes the cells back. `rule_vm_cycle` itself is a no-op
sentinel.

That is not a criticism of the result; it is a precise description. The VM is a
**host interpreter whose memory is the topology**, and the tests show:

- 14 programs, branches, loops, dual concurrent VMs;
- deterministic run vs step-loop;
- immutable rule map;
- program/registers/IP all in cells.

The claim "host does not decode" in the README is too strong. The host does
decode; it does not keep the program in host memory. The distinction is the
right one to preserve.

### R13: the universality path

R13 adds:

- two-counter machine programs for add, multiply, copy;
- self-modifying code (`STORE_PROG` patches program memory);
- hierarchical pages with a portal;
- async dual VMs with schedule independence;
- a resource comparison.

A two-counter machine with increment, decrement, and zero-test is a standard
Turing-complete model. The R13 implementation has saturating decrement and a
bounded 16-bit register; it is a *path* to universality, not a proof of
unbounded universality. Self-modifying code and pages are the right primitives.
The remaining work is to move the interpreter into local rules and to prove
that the mirror topology itself, not the host switch, is the computer.

---

## 6. Phase E — the cognitive layer (R14–R17)

### R14: the bird/eagle/penguin knowledge graph

R14 stores triples in `cog_kb_`, a `std::vector<Triple>`, and queries them with
C++ graph traversal. The tests cover:

- inheritance (`eagle IS A bird`, `bird HAS wings`);
- exceptions (`penguin CANNOT fly` overrides `bird CAN fly`);
- dual general/exception paths;
- counterfactual checkpoint/restore;
- continual learning from feedback;
- distributed pages with a portal.

This is a behavior specification for a cognitive layer. It is not emergent
from cell rules: the reasoning is host code, and the topology cells at
`0xD000` are mostly storage tags. That is fine as a specification, but it must
not be presented as "the topology reasons."

### R15: 256 heads, the transpose theorem, the ledger

R15 is the conceptual bridge to the new repository. It proves:

```text
addr(a, b) = (a << 8) | reverse8(b)
reverse16(addr(a, b)) = addr(b, a)
```

Therefore bit reversal is matrix transposition on a 256 × 256 grid:

- the 256 fixed points are exactly the diagonal;
- the 32,640 mirror pairs are exactly the unordered head pairs `C(256,2)`;
- an arbitrary asymmetric 256 × 256 matrix round-trips through 32,896
  canonical cells;
- the dual rails `S+ = W[a][b]`, `S- = W[b][a]` are the natural home for a
  directed weighted graph on 256 heads.

R15 also builds:

- a self-contained SHA-256 with known-answer tests;
- a hash-chained ledger with replay from genesis;
- checkpoint → new topology → same chain head;
- tamper localization;
- branches as transactions with abort/commit;
- stale workspace/writer rejection;
- 256 identical heads that specialize under lateral inhibition (MI 2.58 bits
  on a 6-class task, against a shuffled null of 0.27).

The specialization result is real but host-coded: the update rule is online
k-means with a conscience term, not a local cell rule. R15 says so.

### R16: unity under differentiation

R16 separates:

- head identity from physical location;
- head plurality from state plurality.

It adds:

- shared facts visible to a collective query;
- conflicting conclusions preserved as **contested**, not overwritten;
- cross-head attribution (origin head + event id);
- specialization stability across a distribution shift;
- transfer without erasing the old specialty;
- head failure (local reset, identity preserved, others intact);
- physical relocation;
- schedule consistency.

This is the "one mind, many specialists" design: the collective state is
shared, the heads are differentiated views, and identity survives relocation.

### R17: continuity under disruption

R17 is a distributed-systems suite:

- interrupted commit leaves no partial state;
- replay reconstructs the same collective hash;
- duplicate delivery is idempotent;
- delayed delivery retains provenance;
- head reconstruction from snapshot;
- page migration preserves hash and identity;
- collective recovery restores contested state;
- the "disappearing head" experiment: logical identities survive restart,
  claims survive, provenance survives, no duplicates, no partials, hash
  matches.

This is the strongest part of the archive for the one-global-topology design.
It is exactly the machinery needed so that five replicas cannot fork the mind.

---

## 7. Phase F — resonance and broad cognition (R18–R23)

### R18: the resonance wave matrix

R18 treats the 256 heads as a 16 × 16 lattice of free bits. It builds a
symmetric coupling matrix, propagates energy, measures phase coherence, and
tests:

- wave propagation 0 → 15 in 48 steps and 0 → 255 in 148 steps;
- coherence 0.992 → 0.959 after evolution;
- learning within a few exposures;
- 500 facts at 100% probe accuracy;
- multi-hop depth 4;
- resonant recall.

The R18 implementation is a host numeric simulation with `float`. It is a
model, not a cell-local field. The new core replaces it with integer Q16.16
diffusion so replay is deterministic.

### R19–R23: increasingly hard host symbolic batteries

R19 adds ISA depth 8, nested exceptions, assert-order invariance, conflict
under learning, 2000 facts, resonance interference, and a head committee.

R20 adds diamond inheritance, ISA cycle termination, knowledge revision, a
10-level exception ladder, concurrent consistency, cross-domain isolation,
specificity, and a 10-hop stress path.

R21 adds Barbara syllogism, modus ponens/tollens, hypothetical syllogism,
contradiction containment, a 12-step proof chain, disjunctive syllogism, the
three-box puzzle, and a social asymmetry test.

R22 adds knights/knaves, a 3-house Einstein subset, the fork puzzle, exactly-one
knight, grid inequalities, and nested speech.

R23 adds Kripke frames, duality, axiom K, T, 4, B, possibility/necessity, and
epistemic `K_a`.

All of these are useful as **behavioral acceptance tests** for a future
substrate. None of them is currently emergent from the local rules. They are
C++ graph search, constraint solving, or host modal evaluation over topology
storage.

### 7.1 Boolean self-modification lineage

The archives contain several distinct kinds of self-modification:

- **R11 `RuleOpDispatch`**: one fixed rule interprets an opcode stored in
  `aux`. The operation is selected by state, not by swapping the rule. This is
  the first "program is in the data" step.
- **R13 `VmStoreProg`**: a program writes a word into its own program region
  (`program[B] := A`); `experiment_self_modifying` patches a `NOP` into an
  `OUT` and reads 99. The host still decodes the VM, but the program memory is
  genuinely self-modified.
- **R23 `RuleVmCycle`**: a sentinel rule id stamped on machine cells; the
  actual decode is `Topology::vm_step`. This is a useful negative result: a
  rule id is not a rule unless the rule itself advances the state.
- **NaNLM `LAYERS.md` / `ALIEN.md`** (outside the PTC archives): `STW` writes
  the class nibble `n` of a `BOOL.n` slot, so the next instruction executes a
  different Boolean truth table. This is the cleanest Boolean self-modification
  primitive: 4 bits of function space, one write.

The new head layer uses the last form at a larger grain: a 16-bit `ops` mask
selects which of the 16 Boolean functions are enabled; a capability-gated XOR
patch changes the mask; the selected rule becomes the lowest enabled function.
The patch is recorded in the head history and the global ledger.

### 7.2 Companion archive: nanclock

`nanclock.zip` is an independent prototype, not a PTC round. It is a 64-cell
temporal memory with LE/PAST at address 0 and BE/FUTURE at address 63. The
future program executes, a NaN signal travels to the past, and the past
rewrites the future. The seed is HALT:

```text
HALT -> +qNaN -> LOOP -> -sNaN -> HALT -> ...
```

It carries exact NaN bits as integers, logs causal events, and detects cycles.
The new core integrates it as a **logical clock**, not a wall clock: a
`(tick, phase)` stamp for distributed ordering, lease ticks, head handoffs, and
catch-up by replay. See [14_TEMPORAL_CLOCK.md](14_TEMPORAL_CLOCK.md).

The prototype's own scope note is preserved: the `LOOP` branch is a primitive
future result; the archive does not claim to decide arbitrary nontermination.

---

## 8. The merge and the strongest theorem

The merged R15–R18 archive contains the clean statement:

> With `addr(a,b) = (a<<8) | rev8(b)`, bit reversal is matrix transposition.
> The 256 fixed points are the diagonal; the 32,640 mirror pairs are the
> unordered head pairs; `W[a][b]` is one rail of the shared dual cell.

The merge also adds `docs/ROUND18.md`:

- dense signed, sparse, and antisymmetric matrices round-trip;
- one-direction writes are isolated;
- symmetric storage gives a real dominant mode; antisymmetric storage gives a
  quarter-turn; mixed storage gives a generic angle;
- Hebbian cyclic sequence memory replays P ≤ 20 patterns exactly at N = 256
  (overlap > 0.99 up to P = 48); symmetric storage cannot replay order.

That last result is the mathematical seed of **bidirectional temporal memory**:
asymmetric storage preserves order; symmetric storage does not. The new
`BidirectionalMemory` makes the forward/backward relation explicit.

---

## 9. What the archive actually established

### Solid, exhaustively verified

1. The address algebra: 65,536 addresses, 256 fixed points, 32,640 pairs,
   32,896 canonical classes.
2. The four-transform orbit count (16,576) and the Klein-four action.
3. The transpose theorem and `C(256,2)` identity.
4. The dual-rail cell model (S+/S− independent payloads).
5. The 4 NaN types / 16 Boolean functions of the NaN16 word.
6. Hash-chained ledger, replay, branch commit/abort, migration, tamper
   localization.
7. The two-counter machine programs and self-modifying code as a behavior
   specification.

### Real but host-driven

1. Arithmetic wavefronts and the signal-carried adder.
2. The VM interpreter (`vm_step`).
3. The cognitive knowledge graph and all R19–R23 logic.
4. The 256-head specialization (online k-means with inhibition).
5. The resonance wave matrix (host numeric simulation).

### Not established

1. Universality of the **pure local mirror topology** (distinct from "hosts
   Rule 110" or "the host VM is Turing-complete").
2. A measurable advantage of mirror orientation over a baseline of the same
   size.
3. A substrate-only implementation of the cognitive tests.
4. Fault tolerance from mirrors under shared storage.
5. Performance or energy vs a CPU / plain CA.
6. Any claim of consciousness, personhood, or "a mind" in the strong sense.

---

## 10. The synthesis

The new repository makes five decisions that the archive was circling:

1. **One global topology.** Charts are coordinate regions, not separate
   minds. There is one atlas, one hypergraph, one temporal memory, one ledger.
2. **Every palindromic NaN is a head.** All 256 fixed points are used; none
   is reserved.
3. **The pair is the temporal edge.** `s+` is forward, `s-` is reverse; the
   32,640 pairs are the past/future relations of the 256 present anchors.
4. **Hyperedges are first-class.** A cell in one chart can relate to many
   cells in many other charts; the object is a palindromic temporal
   hypergraph, not only a graph.
5. **The 8 MiB chart is the register file.** 65,536 address registers (every
   address, both mirrors) + 32,896 shared pair/head registers + descriptors +
   adjacency + head table + bit/byte/KB metadata. The memory tiers are rebuilt
   around that page.

The rest of the documentation specifies this object and the experiments that
could falsify it.

---

## 11. Artifact map

| archive directory | canonical content |
|---|---|
| `archive/NaN16_Palindromic_Temporal_Computer_Round2/...` | Brainstorm 1/2, address orbits, temporal pair |
| `...Round3/...` | first topology, no-PC experiments |
| `...Round4/...` | Rule 110, arithmetic family, dual fields |
| `...Round5/...` and `Round5-1` | multiplication |
| `...Round6/...` | signal adder, event-driven |
| `...Round7/...` | dual rails, scale |
| `...Round8/...` and `Round8-1` | local dual rules, NAND, dual-rail add |
| `...Round9/...` | host-blind gates, ripple cell |
| `...Round10/...` | checkpoint suite, reversible gates |
| `...Round11/...` | `RuleOpDispatch` |
| `...Round12/...` | program-in-state VM |
| `...Round13/...` | 2CM, self-modifying code, hierarchy |
| `...Round14/...` | bird/eagle/penguin cognition |
| `...Round15/...` (also `distributedmind`) | heads, ledger, branches, specialization |
| `...Round16/...` | unity, conflict, attribution |
| `...Round17/...` | continuity, disappearing head |
| `...Round18/...` | resonance matrix, transpose correspondence |
| `...Round19/...` | hard cognition |
| `...Round20/...` | extreme cognition |
| `...Round21/...` | formal logic |
| `...Round22/...` | hard puzzles |
| `...Round23/...` | modal logic |
| `merged_R15-R17`, `merged_R15-R18` | merged continuity/transposition snapshots |

The exact hashes and duplicate notes are in
[12_PROVENANCE.md](12_PROVENANCE.md).
