# Geometric credit replacements for BPTT

Status: **design record, not an implementation claim**. NaNLMind v2 is the
target. NaNLM is v1 and is not imported. The canonical VM is NaN0S; N16I is a
guest interpreter running on it, not a second VM.

The user rejected a global BPTT tape as the primary learning path. The
alternatives below use the state that already exists in one 8 MiB chart:

- `s+`/`s-` forward and inverse rails;
- `q+`/`q-` validation/error shadows;
- 65,536 address records, with mirror orientations sharing one canonical cell;
- 32,640 mapped hypermatrix rows (256 candidate bits each);
- 85 three-head triads and one field vote (43/85);
- address/sub-definition leaves: bit, byte, word, cell, page.

None requires a new opcode; Q16.16 multiply is `MULH/MUL`, trig uses the raw
CORDIC kernels, and `FEXP/FTANH/FLOG` cover softmax/activation.

## Shared rule

A leaf is exact: `(cell, word 0..3, bit 0..63)` or a byte/word/cell/page
sub-definition. A proposal is staged in scratch, voted by its 3-head triad
(2/3), aggregated by the field (43/85), then committed with a ledger event and
rollback record. Rejected proposals leave `s+`/`s-`, checksums and generation
untouched.

## Candidate mechanisms

### 1. TRAIL — two-rail TD eligibility (recommended first slice)

Forward and inverse eligibility traces live in `s+`/`s-`; local TD errors are
`δ+` and `δ-`. Credit is `δ+ e+ - δ- e-`, with no activation tape. Update a
weight leaf only from its own two traces and the local value readout. Triad
2/3 and field 43/85 gate the step.

Falsify against forward-only trace, static bigram, `s-` ablation and shuffled
temporal links. Requires no new op.

### 2. CFT — triangle cycle-flux credit

Credit a coefficient by the circulation around a triangle. Three edge updates
change the loop by exactly the proposed delta; mirror antisymmetry is
preserved. This is the local geometric control and already has native mirror
kernels. A dense 8×8 delta-rule control must be run; existing evidence says a
dense control can tie or win.

### 3. HOLO — holonomy/gauge defect

Use cycle phase `θ`; `h_C = wrap(sum θ)`, defect `1-cos(h_C)`, distribute
credit by the edge share. Gauge shifts change raw phases but not the defect or
votes. Use the existing Q16 CORDIC, not `FSIN`.

### 4. RING — angular correlation on the 255-lane ring

Correlate the forward rail of head `h` with the inverse rail of `h+r`; the
best shift is local rotation credit. Triads vote on their modal shift; the
field accepts a circular-mean rotation only above a resultant-length threshold
and 43/85. Head 255 remains the fixed field head.

### 5. LEAF — hypermatrix leaf support

`R_ab[c]` says candidate head `c` is eligible for pair `(a,b)`. Each head owns
a 32-byte leaf mask `L_c`; a leaf is an exact bit/byte/word sub-definition.
Support is `R_ab[c]&L_c[l_c] + R_bc[a]&L_a[l_a] + R_ca[b]&L_b[l_b]`. A signed
per-leaf counter (64 KiB chart scratch) is updated by local error; promotion
sets/clears leaf bits after triad/field votes.

### 6. TCA — triad counterfactual advantage

Each head compares its local log-loss with the leave-one-out consensus of its
two triad peers: `A_i = log p_i(y) - log p_{-i}(y)`. Negative advantage
downweights the head. If all three are equal, credit is zero. This is a local
peer-relative credit, not a global gradient.

### 7. FLUX — temporal-link divergence

Treat temporal links as a flow network. `J = w(φ_v-φ_u)`, `D = div J - I`,
`c = J D`. Heads update incident links locally; cycles with nonzero
circulation are retained rather than forced to close. A 24-byte link record
fits the free extension (32,640 links).

## Implementation status

Raw NaN16 CFT and TRAIL credit primitives, a signed Q16 multiply, a field
command driver, and a deterministic auto-remap scheduler now exist in
`mth/nan16/` and `include/nanlm/raw_field.hpp`. The trunk also has diagnostic
local error-corrective updates and a host autograd reference; neither is the
production learning policy. CFT/TRAIL are still not fully wired into every
trunk weight, and no quality claim follows from the primitives.

## Recommendation

Implement **TRAIL** first, restricted to one 8-token block and an 8×8 bank per
triad. It is the closest replacement for the missing temporal credit path.
TRAIL supplies:

```text
δ+_t = r_t + γ V-(s_{t+1}) - V+(s_t)
δ-_t = r_t + γ V+(s_{t-1}) - V-(s_t)
e+  = λγ e+ + ∂V+/∂θ
e-  = λγ e- + ∂V-/∂θ
c   = Σ (δ+ e+ - δ- e-)
```

Use Q16.16 constants and saturating integer arithmetic. Store traces in the
two rails, local value/error in `q+`/`q-`, active triplets in the hypermatrix,
and leaf promotions in the head leaf masks.

## Falsification gates

1. Sign parity with finite differences on a reversible affine block.
2. Forward/inverse recall and exact rollback on a 3-step sequence.
3. 2/3 triad and 43/85 field threshold tests, including stale generation.
4. Source-disjoint next-byte task against no-hypermatrix, forward-only, and
   no-triad-vote ablations, plus order-0/bigram controls.
5. Crash/replay determinism; a rejected proposal must leave the digest
   unchanged.

## P1/P2 relation

P1 (full d=8 QKV/MLP block) can proceed in parallel because the block only
needs the existing op set. P2 is replaced by TRAIL/CFT/HOLO/RING/LEAF credit,
not a global BPTT tape. No mechanism is claimed to be equivalent to BPTT; the
matched controls decide.
