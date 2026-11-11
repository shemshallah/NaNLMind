# Unified 48M Decoder -> Heads -> Triheads -> Hypertensor -> Global -> Meta

Status: C++ 128 MiB arena backing and original 48M decoder candidate adapter are implemented and locally exercised. Live native streams, fresh-data improvement and journaled promotion are NOT yet verified. This design retains one trained language model and one NaN16 global state space.

## Original checkpoint (unchanged)
- R20 43,000,000-event base: run_v20_new_prose/state.npz. SHA-256: 299a91daf65c8e66fe3489940371d262afef18dd2ef6fef61947ac14c62bb717.
- R22 5,000,000-event contextual overlay: run_v22_direct_context_char/state_overlay.npz. SHA-256: 62bf1e5defbb8224d795db16a8e6959cc9aa3d7fed8a63346c4cee205a1bea04.
- Same 205,073-node Round 24 trie, 69,974 known lexical forms, and frozen Round 25 pair-context weight rho=0.1. One 48M hybrid: neither state file is a replacement model.
- Source: Library archive palindromic_language_R27_48M_INDEPENDENT_GUTENBERG_FULL.zip. R27's 7,200 sampled positions from four qualifying Gutenberg books are audit-only and cannot be reused to tune this feedback gate.

## Execution path
Stream -> native phase/PQ/spectral/temporal measurements -> 255 candidate-capable head coordinates -> 85 triheads -> 256x256x256 external tensor (64MiB active + 64MiB candidate) -> Hodge global field and triad consensus -> masked MC0 meta over up to 16 committed context slots -> feedback to all authorized heads. The decoder accepts native-proposed full-word score deltas only as a normalized CANDIDATE. The trained 48M state and 8MiB root chart are not overwritten.

There are 256 real palindrome points; 255 is the VOID/global head, so the trainable-coordinate range is 0..254. Index 0 is also a protected NANNET control role. Being physically present does not authorize a write. The HW5:0 NANNET corpus hardware point is not local head 5.

## Mathematics

1. Head phase observation. For byte b at position p:
   lane = (b+p) mod 8, theta = 2*pi*((257*b+8192*p) mod 65536)/65536,
   z[lane] <- z[lane] + cos(theta) + i*sin(theta).
   Existing NaN16 phase, quantizer, sparse and spectral kernels compute geometry. The host transports observations and does not invent semantic vectors.

2. Trihead rule. Every three-head group emits a 3-bit member vote mask m_t; A_t = 1[popcount(m_t & 7) >= 2]. Across 85 groups accept only if sum_t A_t >=43. Shape, orientation, area, time and positive/negative evidence remain the original native guest calculations. All explicitly authorized heads may propose writes to the CANDIDATE tensor, never directly to ACTIVE.

3. Full mirror tensor. 256^3 = 16,777,216 float32 coordinates, 67,108,864 bytes per bank and 134,217,728 bytes for the two full banks. Each independent orientation of canonical pair {a,b} shares its physical cell: T[h,a,b] is NOT required to equal or negate T[h,b,a]. For a=b, index = 65536*h+a. For a!=b, low=min(a,b), high=max(a,b), pair=low*(511-low)/2 + high-low-1; index=65536*h+256+2*pair+(a>b?1:0). Candidate byte offset=67,108,864+4*index, consistent with mth_hypertensor256_mirror_dual_map.nas. Slots with 255 are real physical capacity but semantically forbidden for training. The external arena is not folded into the 8MiB authoritative root.

4. Global Hodge field. On admitted oriented triangles and measured directed pair cochain f, divergence = B1*f; curl = B2^T*f. The oriented triangle curl is f(a,b)+f(b,c)+f(c,a). An oriented FLOW is not a tensor weight: its antisymmetry must not collapse mirror tensor directions. Native mth_global_hodge256_f32 and Q16 compute the values and reject nonzero VOID255 flow.

5. Meta attention. For 16 or fewer committed prior slots, alpha_j = softmax(q dot k_j / sqrt(D)) restricted to valid mask bits; m = sum_j alpha_j*v_j. Uncommitted/future slots cannot contribute. All-invalid masks reject. The MC0 meta and trihead/global kernels own model mathematics.

6. Exact frozen whole-word candidate normalization. For finite native-proposed word set S in context c and original 48M distribution P0:
   Z(c) = 1 + sum_{w in S} P0(w|c)*(exp(d(w,c))-1).
   Pcand(w|c) = P0(w|c)*exp(d(w,c) if w in S else 0)/Z(c).
   Thus ALL other known words and infinitely many OOV spellings are normalized correctly without rebuilding the trie or changing the token head. With all deltas zero, Z=1 and Pcandidate=P0. Guest deltas must be finite in [-8,8]. The bridge loads the original archived hybrid_v25_emit.Emitter and SHA-checks both checkpoint files.

7. Meta promotion. Development exact-word NLL L(P) = -(1/N)*sum log P(w_i|c_i). A full tensor bank swaps only if the 48M hash pair matches, at least one native candidate write exists, at least 43 triheads pass, global and meta native gates both pass and L(candidate) < L(baseline) on a NEW disjoint development panel. Rejection leaves the active tensor and frozen decoder unchanged. Claim language gains only after an independent new precommitted held-out panel.

## Files and tests
- include/nanlm/dual_tensor_arena.hpp: two full physical banks, mirror offsets, explicit per-head candidate write authority, global/meta and NLL gate, rollback, generation.
- tests/test_dual_tensor_arena.cpp: compile with g++ -std=c++20 -O2 -Iinclude tests/test_dual_tensor_arena.cpp -o /tmp/test_dual_tensor_arena && /tmp/test_dual_tensor_arena.
- tools/decoder48m_candidate.py: loads original archived 48M R25 decoder and normalizes finite candidate weights without touching checkpoints.
- tests/test_decoder48m_candidate.py: exact known/OOV normalization and zero-feedback parity.
- mth/nan16/mth_meta_attention16_f32.nas: MC0 masked-score write corrected; all-invalid masks rejected.

Local work tested the original frozen R25 emitter with known word government and OOV neurogenomics. Unmodified candidate probability matched the original exactly; a nonzero finite test candidate normalized correctly. This is a readout test, not evidence of a trained tensor improving loss.

## Verified native feedback path (continuation)

The live guest execution interface now has `include/nanlm/native48m_feedback.hpp` and `tools/nanlm48m_native_emit.cpp`. The latter consumes two separately supplied source text windows, calls the real NaN16 tokenizer, invokes raw phase/trihead/Hodge/MC0 operations, and emits a candidate-only JSON receipt for the original 48M decoder. The first window is committed into the attention history before the second is evaluated. The 20D MC0 query/key/value feature contract is strictly: 16 phase channels, native field signal, native trihead credit of the authorized proposer, native Hodge divergence at the target head, and native Hodge curl of the first admitted face. These are guest-produced measurements packaged by the host, not independently trained host embeddings. Existing `mth_meta_attention16_f32.nas` computes the attention and `mth_hypertensor256_mirror_dual_map.nas` validates addresses before any candidate write.

The native trihead credit loop was repaired: it now writes **exactly 3 selected head credits**, not 85. The guest fixture explicitly scans all 255 head-credit positions for unintended writes. The C++ `RawFieldVM::meta_attention` bridge now reports guest rejection for all-invalid masks rather than accepting stale output.

Example *candidate-only local smoke* (not live NANNET training):

```sh
make -j2 build/nanlm48m-native-emit
printf 'the bright river reflects the light and gentle sky' > /tmp/past.txt
printf 'a quiet bird moves above the river as clouds drift' > /tmp/current.txt
./build/nanlm48m-native-emit /tmp/past.txt /tmp/current.txt 'the bright river' bird /tmp/candidate.json
python3 tools/decoder48m_candidate.py --archive-root /path/to/R27/experiment_archive --candidate /tmp/candidate.json --output /tmp/decoder-score.json
```

`tools/decoder48m_candidate.py` verifies both SHA-256 checkpoint anchors and receipt constraints; the scored word distribution is exactly normalized over the original 48M model's known and unseen spellings. Optional `--dev-panel /path/panel.json` computes baseline/candidate exact-word NLL diagnostics, but cannot promote the active tensor. Native origin claims in JSON are **not cryptographic attestation**; the runtime must enforce actual writer capabilities, generation leases, source disjointness and atomic journaling outside this local test program. The CLI deliberately uses an explicitly authorized local test head 3 and supplies no external pair-flow faces, so the resulting candidate has **no admissible global Hodge evidence** and must not be promoted.

CI executes `build/test_native48m_feedback`, the native receipt CLI, the guest fixtures and the Python exact-word normalization tests; CI does not have the private Library archive and therefore cannot claim full archived-weight validation from its own workflow. An independent local execution did reopen the complete original R27 archive, verified both SHA-256 anchors and successfully scored known/unseen words with the real frozen R25 emitter.

## Remaining implementation and repository cleanup
Wire actual native runner vector frames to guest trihead/Hodge/meta outputs, external candidate value writes, and emitted decoder log-weight proposals; independently test automatic meta feedback and transaction journaling. Obtain new disjoint Gutenberg data before enabling promotion.

Use main as the only active development/integration branch; do not spawn another decoder model or series of topical PR branches. The audit found 44 non-main branch refs and only one open PR (#43), still experimental and 97 main commits behind with 17 ahead. Do not blindly merge old divergent branches. Fully-behind branches are deletion candidates once their work is confirmed in main; divergent branches require file-by-file review and isolated cherry-picks. Existing GitHub connector actions do not expose branch deletion, so no old branch refs were deleted in this integration.

## Seven-credit, all-head and native memory reconciliation (2026-11-11)

The single-mainline guest driver now disambiguates decoder and mathematical commands: decoder context readout opcode **25**, context-class mapping **30**, seven-credit combination **31–34**, HOLO **35**, RING **36**, LEAF **37**, TCA **38**, FLUX **39**, context-backoff **40**, and two-rail 255-head geometric-TRAIL batch **41**. The latter retains the original 2/3 sign-vote, 43/85 field quorum and stale-generation rollback checks from the branch. Opcode 13 remains the wide trunk; the divergent branch's colliding opcode 13 was not copied.

The native seven-credit bundle has the stable Q16.16 channel order **CFT, TRAIL, HOLO, RING, LEAF, TCA, FLUX**. Each remains in its original `.nas` mathematical kernel; `RawFieldVM::credit_bundle` and `RawFieldVM::combine_credits` only stage typed input/output words. The `Native48MFeedbackBridge::stage_seven_credit_feedback` adapter injects the **original 48M exact-word** candidate/baseline log probabilities into the native TCA channel, gathers the full seven guest-computed credits, combines them in the guest and stages a reversible tensor proposal. The guest does not independently learn a replacement 8D decoder. Source and tests for every channel are recorded in `spec/unified_48m_math_manifest.v1.json`.

**All 255 trainable heads** can be granted explicit, revocable candidate-writer authority via `DualTensor256Arena::set_all_candidate_writer_permissions`. The bridge validates that any runtime trihead mapping is an exact permutation of heads 0..254 across 85 groups, then stages *nonzero guest-measured* head credits in **one oriented mirror lane per head**, leaving the reverse orientation independent and preserving existing active weights. Invalid or duplicate mappings are rejected before writing. Physical head 255 (VOID/global) cannot propose writes. The root/head 0 does not receive implicit authority; it must be explicitly granted.

**Native program memory repair:** Guest instruction growth crossed the old 512-word phase-table position at 0x3000 and corrupted later tests. The lookup table was relocated to `[0x3E00,0x4000)`, with a new emitted-image word-count guard that rejects overlapping future program growth. The full CI build returned green after that repair.

**Current verification distinction:** GitHub CI has exercised real native phase, cumulative trihead, Hodge, masked MC0, tensor candidate storage, normalized decoder receipt, all seven native credit channels and rollback without promoting the frozen 48M decoder. A sample `bird` score changed under one candidate, but that is not source-disjoint language-model improvement. The 33 historical divergent branches are inventoried file-by-file in four manifests, with their unique commits retained until reviewed. End-to-end automated Hodge evidence ingestion, canonical chart journaling, disjoint development and held-out evaluation, and production promotion remain open and must not be claimed completed.


## Native closed-loop layering — six-word stream, hottriheads, Poincare128 and signed curl (2026-11-11)

The same **48M decoder and one 128MiB dual tensor** now have an extended,
direct-`main` native mathematical path. No new neural decoder, checkpoint,
model instance or hothead state authority was created.

### Stage-by-stage executable interface

1. **Stream intake/temporal NOW.** Native `mth_context6_window_stream.nas`
   selects exactly three preceding and three following word positions. Task 0
   is strictly causal next-token prediction: `target_index==observed_count`,
   only past words exist, and all future mask bits/payloads are zero. Task 1
   is masked infilling: `target_index<observed_count`, the center word is
   NEVER read by the guest, and the query anchor is an explicit mask symbol.
   The physical `255` point is a VOID/NOW reference; it cannot own candidate
   tensor writes or be registered as a separate learner. Opcode **109**
   fuses this native window builder with native trig/attention/geometry.
2. **Trigonometric attended vector.** Existing NaN16 16-iteration CORDIC
   (`mth_q16_sin_cos.nas`) computes content+position phasors, and the
   existing masked MC0 `mth_meta_attention16_f32.nas` computes real
   content-dependent softmax over six slots with `D=2`. New
   `mth_six_context_poincare_attention.nas` projects the resulting vector
   into a genuine open 2D Poincare disk and measures
   `d(0,p)=ln((1+||p||)/(1-||p||))`. Direct opcode **107** accepts an
   already-selected 6-slot request; **109** accepts the original word
   stream. Neither path can see future words during task0.
3. **Hothead -> hottrihead.** Existing native `mth_hot_trihead.nas`
   scans the SAME 255 trainable head credits and returns a permutation of all
   255 heads grouped into 85 dynamically hot-first triheads. The 48M
   `Native48MFeedbackBridge::measure_and_stage` now records this genuine
   guest measurement as `native_hot`, alongside original trihead votes.
   Optional `stage_native_hottrihead_feedback` requires native hot
   `>=43` triads, actual Hodge evidence and committed-history MC0
   readout; it stages only authorized CANDIDATE writes. It does NOT silently
   remap the committed root chart or grant write authority to all heads.
4. **Global Hodge/curl and MC0.** The existing signed oriented face
   `curl=B2^T f` and head divergence remain native. They enter the
   existing 20D MC0 committed-history context (`curl[0]` in component19,
   divergence for the current head in component18). The new temporal
   `NativeContext6Receipt` is carried through the same C++ VM wrapper,
   which does no trigonometry or attention mathematics.
5. **True 128D hyperbolic hyperedge.** New
   `mth_hyperedge_poincare128_curl.nas` maps a sourced 128D vector
   `v` to `p=v/(1+||v||_2)`, measures exact radial Poincare
   distance `d(0,p)=ln((1+r)/(1-r))`, and produces
   signed oriented `curl*r` feedback for a distinct valid ordered
   hyperedge (h,a,b). Opcode **108** exposes this through the SAME
   field driver. Hodge-curl reversal flips signed feedback without altering
   radial depth, and rotations of a fixed-norm source preserve depth.
   This is real hyperbolic geometry, not proof that trained semantic
   abstractions already correspond to geometric depth.
6. **Mirrored candidate feedback.** The bridge stages temporal
   `(x,y)` in independent directed lanes
   `T[h,a,b]`/`T[h,b,a]`. The native 128D hyperedge places
   `curl*r` and radial depth in the *different* mirror pair
   `T[h,a,h]`/`T[h,h,a]`, so temporal and hyperedge evidence do
   not erase one another. All four are CANDIDATE-bank values; the
   original 48M decoder and 64MiB active bank are untouched.
   Actual tensor-bank promotion still requires writer lease, generation,
   >=43 accepted triheads, global+meta approval, matching checkpoint
   digests, and a strict disjoint real whole-word development NLL reduction.
   Before that promotion, this is a **measured reversible proposal loop**,
   not enduring neural learning.

### Verified code and test responsibilities

- Native source: `mth/nan16/mth_context6_window_stream.nas`,
  `mth/nan16/mth_six_context_poincare_attention.nas`,
  `mth/nan16/mth_hyperedge_poincare128_curl.nas`.
- Native driver: opcodes **107** (selected window), **108** (128D ball/curl)
  and **109** (source stream to masked attention); original 106 weighted
  spectral candidate proposal remains available.
- C++ ABI-only adapter: `include/nanlm/raw_field.hpp`,
  `src/raw_field.cpp`, `include/nanlm/native48m_feedback.hpp`.
- Native fixtures: `mth_six_context_poincare_attention_test.nas`,
  `mth_context6_driver_opcode107_test.nas`,
  `mth_hyperedge_poincare128_curl_test.nas`,
  `mth_context6_window_stream_test.nas`,
  `mth_context6_stream_driver_opcode109_test.nas`; all included in
  `tools/run_nan16_fixtures.py` for the canonical NaN0S preflight.
- Actual source-target mutation must NOT change the mask/infill geometry.
  Signed curl reversal changes its own directional feedback but not norm
  or Poincare depth. Stale generations, nonfinite vectors and VOID writers
  reject before side effects. C++ parity test confirms independent mirror
  pairs and unchanged active tensor.

Dedicated verified cross-platform workflow evidence:
- https://github.com/shemshallah/NaNLMind/actions/runs/43067112924
  (six-context trig and 2D disk, Linux x86-64 and ARM64).
- https://github.com/shemshallah/NaNLMind/actions/runs/43068489130
  (128D hyperedge/curl, Linux x86-64 and ARM64).
- https://github.com/shemshallah/NaNLMind/actions/runs/43070091534
  (strict source-window target isolation, Linux x86-64 and ARM64).

Important remaining work: the production NANNET HW5:0 Gutenberg stream,
authenticated versioned evidence into all 255 heads, source-trained
128D hyperedge vectors, a genuinely novel whole-word development/held-out
quality gain, durable atomic multi-node promotion, and final merge/difference
closure of all historical branches. CI regression fixtures are not training
outcome evidence. Keep development on `main` only.
