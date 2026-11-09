# Hypermatrix reconciliation: NaNLM v1 vs NaNLMind v2

Status: **implementation note and integration plan**. NaNLM (`nanlm-test`) is
the v1 reference harness. NaNLMind is v2 and is the only target for this work.
No v1 Python, PyTorch, floating-point tensor, or overlay file is imported by
NaNLMind.

## 0. Build ownership and the one topology

NaNLMind is the canonical native build and the only v2 target. NaNROUTER owns
transport, point-0 ingress, routing and the control plane; it does not
instantiate a second native universe. NaNLMind_HERMES is a read-only adapter
and candidate producer. The machine-readable build boundary is
`spec/unified-build.v1.json`, exposed by:

```sh
./build/nanlm-universal unification
make unified-check
```

The same 256 physical heads support distinct role views that must not be
conflated: the router control plane reserves head 0 as the NANNET root role
and `0,4,5,6,7,8` as BSR control roles (250 curriculum heads); 255 heads
`1..255` are MP-writer-eligible; the v2 triad field uses heads `0..254` as
members and head 255 as the field counter. These are overlays on one chart,
not additional charts, heads or permissions. A role overlay may not reassign
the native field head.

## 1. The two layouts

| concern | NaNLM v1 (`nanlm-test`) | NaNLMind v2 (`NaNLMind`) |
|---|---|---|
| primary object | one 8 MiB mapped root: 256 heads x 128 B + 32,640 pairs x 256 B | one 8 MiB chart: 32,896 NaN cells x 64 B, 65,536 address registers x 32 B, descriptors, 256 head records, 256 KiB head scratch, 64 KiB chart scratch, mapped hypermatrix extension |
| state type | float32 head vectors, pair lanes, wave/spectral state | NaN16 words, integer Q16.16, Boolean masks, integer evidence |
| heads | 255 cognitive + head 255 ingress | 256 palindromic heads; one topology |
| pair relation | 16 support/refute typed lanes per direction | 16 Boolean operators + NaN words + descriptor/address state |
| hyperedge store | host-side sparse overlay plus `.overlay` file; later indexed residual | first-class `Hypergraph` incidence object; mapped hypermatrix projection in the chart |
| third-order signal | exact triple search and CP-rank pair/head-vector product | mapped pair-row bitset contract + integer CP proxy from head registers; exact and two-of-three dense support |
| learning | float teacher/gain gradients, calibrated readout scales | integer Boolean score learning, per-head self-modification, triad/field votes and Q16.16 gains |
| temporal | forward/inverse standing wave, 16-step attention, spectral modes | temporal links, resonance lattice, integer clock; no claimed BPTT or transformer |
| persistence | root + overlay + SO(3) sidecar, not jointly atomic | chart serialize/from_bytes, one chart digest; hypermatrix included in the same serialization |

## 2. Why v1's hyperedge ablation could be neutral

The v1 contract had four separate restrictions:

1. hyperedges were emitted only after another training update succeeded, every
   eighth step, and only for three distinct byte addresses;
2. prediction searched for an exact ordered triple, so related triples shared
   no learned state;
3. hyperedges lived in an overlay, not in the mapped mirror register;
4. the heads had per-head gates but no 3-head or field-level consensus.

An ablation therefore removed a lookup that frequently had no exact match on
the held-out fixture. That is a coverage failure, not evidence that the
higher-order mathematics is useless.

v1 PR #8/#9 corrected this by factorizing the interaction through the physical
pair cells, adding CP-rank coupling to the learned head vectors, indexing
signed residuals, and adding local/triad/field gains. Its fixture result was
2.6718 nats/byte and the ablated readout was 2.847188 (+0.175340). That is a
controlled fixture result, not a general-language claim.

## 3. How NaNLMind v2 processes the same ideas

NaNLMind keeps its own NaN16 semantics but adopts the useful *shape* of the v1
correction:

```
H[pair(a,b)] = 256 candidate bits          (32,640 pair rows)
hyperedge (a,b,c) projects to:
    c in H[pair(a,b)]
    a in H[pair(b,c)]
    b in H[pair(c,a)]

score(a,b,c) =
    exact_support * 4 + dense_two_of_three + integer_CP
    scaled by local + triad + field Q16.16 gains
```

The hypermatrix row table is 32,640 x 32 B = **1,044,480 bytes**, inside the
8 MiB chart extension. It is serialized with the chart and included in
`Universe::digest()`. `Hypergraph` remains the authoritative incidence store;
the mapped rows are the fast higher-order readout.

### Layer reconciliation

v1's L0–L9 semantic stack is not copied as a second model. In v2 it maps onto
the existing coordinate/learning layers:

| v1 layer | v2 interpretation |
|---|---|
| L0 bit / L1 nibble | L0 reflex Boolean masks and NaN16 class bits |
| L2 byte / L3 phonetic | byte/KB pages, address registers and head phase/energy |
| L4 morpheme / L5 lexical | word/vector memory and relation heads |
| L6 completion / L7 sentence | relation curriculum resolutions and hyperedges |
| L8 paragraph / L9 narrative | chart-local temporal and global journal structure |

The hypermatrix is a **third-order readout across these layers**, not a
replacement layer and not a second language model. Resolution 0–9 on
`N16REL/1` records remains the curriculum coordinate.

### Three-level head consensus

Heads 0..254 form 85 triads. Votes live in the leader's 1 KiB head scratchpad;
the field counter lives in head 255. A patch or gain change is accepted only
after two of three triad members vote for it. The field records how many of the
85 triads accept. This is integer state and persists with the chart.

### Q16.16 hierarchical gains

- local gain: each head's scratchpad, bytes 16..19;
- group gain: the triad's third-head scratchpad, bytes 20..23;
- field gain: head 255 scratchpad, bytes 16..19.

The score divides the sum of local/group/field gains by nine, so all default
gains equal 1.0 and do not change the initial readout.

## 4. What worked, what needed upgrading

Keep from v1:

- factorized pair interaction instead of exact triple lookup;
- a CP/rank-three term tied to the existing head state;
- signed sparse residual index for exact evidence;
- local/triad/field gains and consensus;
- an ablation guard that fails when the higher-order term is neutral;
- persistence tests over the same mapped object.

Do not import from v1:

- float32 head vectors, wave state, or the `.overlay` file;
- PyTorch or any host model;
- recomputed spectral eigenvectors as a production dependency;
- 255 independent Transformer blocks or end-to-end BPTT into the integer core.

Those remain optional host-side research, not NaNLMind production state.

Adapt for v2:

- use `NanCell`, `Head`, `AddressReg`, and head scratch instead of float arrays;
- use pair index rows (32,640) rather than 65,536 directed rows, preserving the
  hypergraph's unordered incidence; ordered residual evidence stays in
  `Hypergraph`;
- use Boolean target votes and Q16.16 gain steps instead of gradient descent;
- keep the global ledger/chart digest as the commit boundary.

## 5. Implementation status in this branch

| item | status | evidence |
|---|---|---|
| mapped 32,640-row hypermatrix in the 8 MiB chart | done | `Universe::hypermatrix_row`, `hypermatrix_nonzero`, serialization/digest tests |
| hyperedge projection into three pair rows | done | `Hypermatrix::project`, `GlobalTopology::add_hyperedge` |
| exact + two-of-three dense + integer CP score | done | `tests/test_hypermatrix.cpp`; unstored triple gets dense score |
| 85 triads with 2/3 votes and field count | done | `TriadField`, `tests/test_hypermatrix.cpp` |
| local/group/field Q16.16 gains | done | `TriadField::set_*_gain`; 0.5 gain halves score test |
| loss/target-gated self-modification | partial | `TriadField::apply_patch` accepts only when 2/3 members improve a Boolean target; global loss calibration remains open |
| relation readout includes hypermatrix | done | `relation-eval` prints `hypermatrix_score`; `relation-audit` reports full vs ablated score |
| persistence and digest | done | hypermatrix is serialized/digested; reload tests pass |
| no v1 dependency | done | no NaNLM v1 code, PyTorch, overlay or float model imported |
| cross-repo build contract | done | `spec/unified-build.v1.json`, native `unification`, `make unified-check`, HERMES adapter |
| raw NaN16 per-head proposal + triad vote | done | `mth/nan16/mth_triad_vote.nas`, `mth/tests/mth_triad_vote_test.nas` |
| raw NaN16 field vote + Q16 trig/coherence | done | `mth_field_vote.nas`, `mth_q16_sin_cos.nas`, `mth_field_coherence.nas`; 5/5 fixtures |
| general adaptive remap | done | `mth_remap_general.nas` + `RawFieldVM::remap_chart`; mapping is serialized; autonomous remap scheduling remains open |
| raw guest ↔ chart bridge | partial | `RawFieldVM` runs `field_driver.nas` on vendored NaN0S and updates proposer/field state; training scheduler still explicit |
| symbiotic field plan | design | `SYMBIOTIC_FIELD_ARCHITECTURE.md` S0–S6 TODO; no micro-transformer/1 MiB bank claims |

Measured on the small native fixture in `tests/test_relation_train.cpp`:

```text
relation_audit rows=3 mean_hypermatrix=4.33333
mean_full_score=7 mean_ablated_score=2.66667
hyperedge_ablation_delta=4.33333 hypermatrix_bits=6
```

The Boolean classification accuracy tied on this constructed fixture; the
higher-order **score** is no longer neutral. This is instrumentation evidence,
not a language-quality claim.

## 6. nanlm-test tracks queued for v2

The v1 `nanlm-test` PRs #10–#14 are reference evidence only. They are not
imported as Python/PyTorch/float state, and their branch results are not the
combined v2 result.

| v1 track | v1 evidence | v2 port gate |
|---|---|---|
| PR #10 mirror-fabric integrity | rejected writes leave mapped state unchanged; reserved ingress head cannot learn | already aligned with v2 chart/ledger invariants; add explicit regression when porting |
| 48-byte temporal credit | 2.6475 vs 2.6561 nats/byte with the long-context term removed | P1/P2: integer feature gains in unused register space; no BPTT claim |
| adaptive three-head groups | 2.6557 nats/byte on its fixture; swaps roll back and survive restart | P4: reversible membership swaps under a full-predictor probability gate |
| source-disjoint transfer | 2.7754 weighted CE; integrated 2.7760 (effectively tied) | P5: run the same three-domain split with the native mapped readout and no-hyper ablation |
| free-generation diagnostics | generated byte text remains incoherent | add a v2 generation audit; do not treat byte-likeness as fluency |
| fourth-order experiment | 2.8267 vs 2.7760 (worse); retained, not merged | negative evidence; do not port as a performance claim |

## 7. Ordered integration plan

1. **P0 — mapped hypermatrix and triads** (this round): finish serialization
   tests, triad vote tests, relation-audit, and a source-disjoint fixture.
2. **P1 — calibrated hierarchical gains**: use a development split to fit local,
   triad and field gains; commit only if the held-out score improves and the
   no-hyper ablation remains worse.
2. **P1.5 — raw adaptive field**: keep the new per-head, triad, field and trig
   mathematics in `mth/nan16/` and expose only orchestration/storage in the
   host. The fixed-slot remap fixture is done; general remap membership and
   calibrated gains remain open.
3. **P2 — signed residual index**: add a constant-time `hyper_query` to the v2
   Hypergraph and make refutation/support explicit in the hypermatrix score.
4. **P3 — layer integration**: keep v2's L0 reflex, L1 resonance and later
   coordinate layers; treat the hypermatrix as the third-order readout rather
   than a second model. Add an explicit layer field to relation records.
5. **P4 — adaptive groups**: form triads from evidence correlation rather than
   fixed head order, while preserving one field and one ledger.
6. **P5 — source-disjoint benchmark**: run the mapped readout and no-hyper
   ablation on genuinely unseen prose/relations; report both, including ties.
7. **P6 — optional host reference**: if a differentiable QKV/BPTT reference is
   still wanted, keep it outside the native integer core and compare against
   the same mapped v2 state. Do not make BPTT a production claim.

## 8. Verification commands

```sh
make -j2 build/test_hypermatrix build/test_relation_train build/nanlm-universal
./build/test_hypermatrix
./build/test_relation_train
./build/nanlm-universal unification
make unified-check
./build/nanlm-universal relation-train RECORDS STATE
./build/nanlm-universal relation-audit TEST_RECORDS STATE
```

The final architecture claim is limited to what the native tests and audit
show. No v1 overlay, float model, or NaNLM runtime is part of the v2 path.
