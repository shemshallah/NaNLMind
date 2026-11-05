# Round 15 — Continuity of State

## What was built (all in `include/continuity.hpp`; R14 sources untouched except one 1-line setter, `restore_tick`)

| Piece | What it does |
|---|---|
| `Sha256` | Self-contained, KAT-verified. |
| `full_digest()` | Digest of every mutable field of every canonical cell **plus the cognitive KB**. |
| Matrix view | Mirror pairing is matrix transposition on a 256x256 grid (see below). |
| `Machine` | Topology + integer-only competitive head pool (no floats: replay-deterministic). |
| `Ledger` | One totally ordered hash chain: `chain_t = H(chain_{t-1} ‖ event ‖ delta ‖ checkpoint?)`. Replay-verifiable from genesis. |
| Branches | `fork()` → private workspace → `commit()` or `abort()`; both are single history entries. Stale workspaces and stale writers are rejected. |

Identity := genesis (which hashes the transition-function parameters) + chain head.

## Findings about R14 (each is a test)

1. **`state_hash()` is blind to rail swaps**: it XORs `state ^ aux`, so S+/S- swapped states collide.
2. **`state_hash()` ignores `cog_kb_`**: two knowledge bases that give different answers to "can penguins fly?" have identical hashes.
3. **Mirror pairing == transposition.** `reverse16(addr(a,b)) == addr(b,a)` with `addr(a,b) = a<<8 | rev8(b)`.
   The 256 bit-palindromic fixed points are exactly the diagonal; the 32,640 mirror pairs are exactly the
   unordered head pairs (C(256,2), an identity). A mirror-paired cell's S+/S- rails can hold the two *directed*
   weights W[a][b], W[b][a]. An arbitrary asymmetric 256x256 matrix round-trips through the 32,896 canonical cells.
   This is the natural, non-forced home for a 256-head system.

## Results

| Property | Result |
|---|---|
| Replay from genesis reproduces every delta, checkpoint, link | PASS (3000 transitions) |
| Edit to event / delta / link localized to the exact index | PASS (1234 / 777 / 2000) |
| Fully recomputed forgery is self-consistent but caught by pinned head | PASS |
| Checkpoint → brand-new Topology → continue → same chain head & state | PASS |
| Chain head bit-identical under -O0/-O1/-O2/-O3 (g++) | PASS |
| Branch abort leaves state unchanged; log records the discarded counterfactual's digest; replay re-verifies it | PASS |
| Stale workspace / stale writer cannot fork history | PASS |
| R14 knowledge assertions replay deterministically on the same chain | PASS |
| Cost | ~255 µs/transition incl. SHA-256 chain and checkpoints |

### Specialization (256 identical zero-initialized heads, 6 task types, max 2.58 bits)

| Condition | MI easy | MI hard (overlap 0.5) | shuffled null | heads used |
|---|---|---|---|---|
| WTA, no inhibition | 1.73 | 0.00 | 0.01 | 5 / 1 |
| **Lateral inhibition** | **2.58** | **2.58** | 0.27 | ~99 |
| Frozen (no learning) | 0.72 | 0.75 | 0.71 | 256 |
| Random routing (learns) | 0.71 | 0.72 | 0.71 | 255 |

## What this does and does NOT show

* Specialization appears **only** when the symmetry-breaking mechanism includes load-based inhibition. Identical
  heads under WTA collapse onto a handful of heads. The mechanism is the hypothesis.
* **Tie-break source.** Exact ties are broken by a priority derived from the previous chain head. The symmetry
  breaker is therefore the system's own causal history: deterministic, replayable, history-dependent. It is still
  a symmetry-breaker and must be reported as one.
* The rule is competitive learning (online k-means with a conscience term). It is textbook. The result shows the
  *harness* detects specialization and the *substrate* can host it deterministically. It does not show the topology
  computes anything special.
* The update rule is **host code** writing to cells. The cells are the physical store (and the transpose structure is
  real), but no cell rule executes the competition. Making a native `RuleFn` do it is the next step.
* Plug-in MI is biased upward when few events land per head; the null is 0.27 with ~99 heads used but 0.71 with 256.
  Always compare against the per-condition shuffled null.
* Determinism was checked across g++ optimization levels only (no clang in the build environment).
* Task labels are evaluation metadata and never enter the ledger.
* Not claimed: cognition, consciousness, analogical generalization, superiority over MoE/k-means.

## Next

1. Held-out relation test: withhold one relation type; does head coordination beat a no-heads baseline?
2. Native cell rule for the inhibition update (S- rail = directed inhibition edge a→b).
3. Replace the hardcoded "exceptions win" resolution with a rule learned from feedback.
4. Clang / MSVC / ARM determinism runs.
