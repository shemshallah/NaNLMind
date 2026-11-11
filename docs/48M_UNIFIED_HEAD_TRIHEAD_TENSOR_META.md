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

## Remaining implementation and repository cleanup
Wire actual native runner vector frames to guest trihead/Hodge/meta outputs, external candidate value writes, and emitted decoder log-weight proposals; independently test automatic meta feedback and transaction journaling. Obtain new disjoint Gutenberg data before enabling promotion.

Use main as the only active development/integration branch; do not spawn another decoder model or series of topical PR branches. The audit found 44 non-main branch refs and only one open PR (#43), still experimental and 97 main commits behind with 17 ahead. Do not blindly merge old divergent branches. Fully-behind branches are deletion candidates once their work is confirmed in main; divergent branches require file-by-file review and isolated cherry-picks. Existing GitHub connector actions do not expose branch deletion, so no old branch refs were deleted in this integration.
