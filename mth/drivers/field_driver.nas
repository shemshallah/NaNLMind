; Raw NaN16 field-command driver.
;
; Host writes one command block at guest word 0x4000:
;   [0] opcode: 1 proposal, 2 field vote, 3 coherence, 4 remap
; Proposal args at 0x4001: current, patch, m0, m1, m2, a, b, target
;   results at 0x4010: votes, accepted, candidate mask, candidate rule
; Context readout: target/lr/bucket/buckets at 0x4001..0x4004; greedy
;   command 25, joint head-pair routing command 30
;   results at 0x4010: correct, loss, predicted high, predicted low
; Field vote: 85 masks at 0x5000, count 85 fixed
;   results at 0x4010: accepted count, field accepted
; Coherence: 255 phases at 0x6000
;   result at 0x4010: average Q16.16 coherence
; Remap: six masks at 0x4001..0x4006, a/b/target at 0x4007..0x4009
;   results at 0x4010: decision, before, after
; Hot triheads: 255 credits at 0x7000, threshold at 0x4001
;   results at 0x4010: hot heads, hot triads, field flag, mapped
;   mapping at 0x8000: 85 triads x 3 heads
; Micro feature: x0 at 0x7000, x1 at 0x7100, output at 0x7200
;   result at 0x4010: feature count (8)
; Causal trunk: T at 0x4001, tokens at 0x7000, weights at 0x9000,
;   output feature at 0xA000, result count at 0x4010
; Wide causal trunk: T/D/H at 0x4001..0x4003, tokens 0x10000,
;   weights 0x60000, output 0x200000, result D at 0x4010
; Trunk local credit: target/best at 0x4001/0x4002, lr at 0x4003
;   result r1=1 at 0x4010
; QKV local credit: same target/best/lr, command 15, uses last forward
; CFT/TRAIL gated local credit: command 22/23
; Credit field: 255 credits at 0x7000, threshold 0x4001, votes 0x7100
; Credit combine: 7 credits at 0x7000, 7 coefficients at 0x7100, result 0x4010
; Credit bundle: state at 0x8000, credits at 0x7200; command 29
; Combined gated credit: target/best/base/threshold 0x4001..4, credits 0x7000, coeffs 0x7100
; Context copy/induction: target/lr/context key/B/E/C/weight at 0x4001..7
;   result at 0x4010: correct, memory CE, combined class
; Phase layers: command 58 rotate, 59 PQ, 60 wide trig encode,
;   61 spectral iteration, 62 sparse k-NN, 63 batched wide trig encode.
;   Encoder input bytes 0x7000, complex output 0x5200 (command 60) or
;   0x70000 (batch 63); PQ query 0x7000, codebook 0x10000, result 0x4010;
;   spectral A 0x7000, x 0x7040, out 0x7080; k-NN query 0x7000,
;   bank 0x10000, neighbor indices 0x7200 and scores 0x7240.
;
; The driver contains no host math. It is assembled by nmk.awk and executed
; by the canonical NaN0S VM. The guest starts at word 0.
JMP @field_driver_entry

.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_triad_vote.nas"
.include "../nan16/mth_field_vote.nas"
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_field_coherence.nas"
.include "../nan16/mth_triad_score.nas"
.include "../nan16/mth_remap_decision.nas"
.include "../nan16/mth_remap_general.nas"
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_cft_credit.nas"
.include "../nan16/mth_trail_credit.nas"
.include "../nan16/mth_field_commit.nas"
.include "../nan16/mth_hot_trihead.nas"
.include "../nan16/mth_micro_feature.nas"
.include "../nan16/mth_trunk_causal.nas"
.include "../nan16/mth_trunk_wide.nas"
.include "../nan16/mth_readout_train.nas"
.include "../nan16/mth_readout_only.nas"
.include "../nan16/mth_readout_sample.nas"
.include "../nan16/mth_readout_softmax.nas"
.include "../nan16/mth_softmax16.nas"
.include "../nan16/mth_softmax16_table.nas"
.include "../nan16/mth_context_hier.nas"
.include "../nan16/mth_phase_encode.nas"
.include "../nan16/mth_phase_pq.nas"
.include "../nan16/mth_sparse_knn.nas"
.include "../nan16/mth_vector_matrix.nas"
.include "../nan16/mth_pq_train.nas"
.include "../nan16/mth_pq_residual.nas"
.include "../nan16/mth_leaf_verify.nas"
.include "../nan16/mth_ckpt_hash.nas"
.include "../nan16/mth_tokenizer.nas"
.include "../nan16/mth_meta_trihead.nas"
.include "../nan16/mth_temporal_slots.nas"
.include "../nan16/mth_ngram_train.nas"
.include "../nan16/mth_geometry.nas"
.include "../nan16/mth_triangle_model.nas"
.include "../nan16/mth_global_hodge256_f32.nas"
.include "../nan16/mth_hypertensor256_mirror_arena_map.nas"
.include "../nan16/mth_hypertensor256_mirror_dual_map.nas"
.include "../nan16/mth_triangle_flow.nas"
.include "../nan16/mth_meta_attention16_f32.nas"
.include "../nan16/mth_global_hodge256_q16.nas"
.include "../nan16/mth_phase_geometry.nas"
.include "../nan16/mth_shape_field.nas"
.include "../nan16/mth_dual_gate.nas"
.include "../nan16/mth_context_backoff.nas"
.include "../nan16/mth_context_encode.nas"
.include "../nan16/mth_role_step.nas"
.include "../nan16/mth_sense_step.nas"
.include "../nan16/mth_semantic_query.nas"
.include "../nan16/mth_context_encode24.nas"
.include "../nan16/mth_role_step24.nas"
.include "../nan16/mth_role_step24k.nas"
.include "../nan16/mth_sense_step24.nas"
.include "../nan16/mth_context_hash.nas"
.include "../nan16/mth_context_batch.nas"
.include "../nan16/mth_context_copy.nas"
.include "../nan16/mth_context_class.nas"
.include "../nan16/mth_readout_hier.nas"
.include "../nan16/mth_trunk_credit.nas"
.include "../nan16/mth_qkv_credit.nas"
.include "../nan16/mth_qkv_credit_wide.nas"
.include "../nan16/mth_trunk_credit_wide.nas"
.include "../nan16/mth_credit_gate.nas"
.include "../nan16/mth_credit_field.nas"
.include "../nan16/mth_credit_combine.nas"
.include "../nan16/mth_holo_credit.nas"
.include "../nan16/mth_ring_credit.nas"
.include "../nan16/mth_leaf_credit.nas"
.include "../nan16/mth_tca_credit.nas"
.include "../nan16/mth_flux_credit.nas"
.include "../nan16/mth_credit_bundle.nas"
.include "../nan16/mth_geometric_trail_field.nas"
.include "../nan16/mth_spectral_trihead_tensor_proposal.nas"
.include "../nan16/mth_six_context_poincare_attention.nas"
.include "../nan16/mth_hyperedge_poincare128_curl.nas"
.include "../nan16/mth_context6_window_stream.nas"
.include "../nan16/mth_future3_causal_window.nas"
.include "../nan16/mth_head16_poincare_vector.nas"
.include "../nan16/mth_triad_hotcold_poincare128.nas"
.include "../nan16/mth_full_field_head_triad_measure.nas"

field_driver_entry:
  MOVI r13,1
  CALL @field_driver_main
  HALT

field_driver_main:
  MOVI r10,@field_driver_link
  ST r15,r10,0
  MOVI r10,0x4000
  LD r2,r10,0
  MOVI r3,1
  CMP r2,r3
  JMP[EQ] @field_driver_proposal
  MOVI r3,2
  CMP r2,r3
  JMP[EQ] @field_driver_field
  MOVI r3,3
  CMP r2,r3
  JMP[EQ] @field_driver_coherence
  MOVI r3,4
  CMP r2,r3
  JMP[EQ] @field_driver_remap
  MOVI r3,5
  CMP r2,r3
  JMP[EQ] @field_driver_remap_general
  MOVI r3,6
  CMP r2,r3
  JMP[EQ] @field_driver_cft
  MOVI r3,7
  CMP r2,r3
  JMP[EQ] @field_driver_trail
  MOVI r3,8
  CMP r2,r3
  JMP[EQ] @field_driver_hot_trihead
  MOVI r3,9
  CMP r2,r3
  JMP[EQ] @field_driver_micro_feature
  MOVI r3,10
  CMP r2,r3
  JMP[EQ] @field_driver_trunk
  MOVI r3,11
  CMP r2,r3
  JMP[EQ] @field_driver_field_commit
  MOVI r3,12
  CMP r2,r3
  JMP[EQ] @field_driver_readout_train
  MOVI r3,13
  CMP r2,r3
  JMP[EQ] @field_driver_trunk_wide
  MOVI r3,14
  CMP r2,r3
  JMP[EQ] @field_driver_trunk_credit
  MOVI r3,15
  CMP r2,r3
  JMP[EQ] @field_driver_qkv_credit
  MOVI r3,16
  CMP r2,r3
  JMP[EQ] @field_driver_readout_only
  MOVI r3,17
  CMP r2,r3
  JMP[EQ] @field_driver_readout_sample
  MOVI r3,18
  CMP r2,r3
  JMP[EQ] @field_driver_qkv_credit_wide
  MOVI r3,19
  CMP r2,r3
  JMP[EQ] @field_driver_readout_softmax
  MOVI r3,20
  CMP r2,r3
  JMP[EQ] @field_driver_trunk_credit_wide
  MOVI r3,21
  CMP r2,r3
  JMP[EQ] @field_driver_readout_hier
  MOVI r3,22
  CMP r2,r3
  JMP[EQ] @field_driver_cft_credit
  MOVI r3,23
  CMP r2,r3
  JMP[EQ] @field_driver_trail_credit
  MOVI r3,24
  CMP r2,r3
  JMP[EQ] @field_driver_credit_field
  MOVI r3,25
  CMP r2,r3
  JMP[EQ] @field_driver_readout_context
  MOVI r3,40
  CMP r2,r3
  JMP[EQ] @field_driver_context_backoff
  MOVI r3,27
  CMP r2,r3
  JMP[EQ] @field_driver_combined_all
  MOVI r3,28
  CMP r2,r3
  JMP[EQ] @field_driver_combined_wide
  MOVI r3,29
  CMP r2,r3
  JMP[EQ] @field_driver_credit_bundle
  MOVI r3,30
  CMP r2,r3
  JMP[EQ] @field_driver_context_class
  ; Legacy credit opcodes 25..28 conflicted with decoder readout.
  ; Credit math is now reserved 31..39, all routed to original .nas kernels.
  MOVI r3,31
  CMP r2,r3
  JMP[EQ] @field_driver_credit_combine
  MOVI r3,32
  CMP r2,r3
  JMP[EQ] @field_driver_combined_credit
  MOVI r3,33
  CMP r2,r3
  JMP[EQ] @field_driver_combined_all
  MOVI r3,34
  CMP r2,r3
  JMP[EQ] @field_driver_combined_wide
  MOVI r3,35
  CMP r2,r3
  JMP[EQ] @field_driver_holo
  MOVI r3,36
  CMP r2,r3
  JMP[EQ] @field_driver_ring
  MOVI r3,37
  CMP r2,r3
  JMP[EQ] @field_driver_leaf
  MOVI r3,38
  CMP r2,r3
  JMP[EQ] @field_driver_tca
  MOVI r3,39
  CMP r2,r3
  JMP[EQ] @field_driver_flux
  MOVI r3,41
  CMP r2,r3
  JMP[EQ] @field_driver_geometric_trail_field
  MOVI r3,50
  CMP r2,r3
  JMP[EQ] @field_driver_context_encode
  MOVI r3,51
  CMP r2,r3
  JMP[EQ] @field_driver_role_step
  MOVI r3,52
  CMP r2,r3
  JMP[EQ] @field_driver_sense_step
  MOVI r3,53
  CMP r2,r3
  JMP[EQ] @field_driver_semantic_query
  MOVI r3,54
  CMP r2,r3
  JMP[EQ] @field_driver_context_encode24
  MOVI r3,55
  CMP r2,r3
  JMP[EQ] @field_driver_role_step24
  MOVI r3,56
  CMP r2,r3
  JMP[EQ] @field_driver_sense_step24
  MOVI r3,57
  CMP r2,r3
  JMP[EQ] @field_driver_role_step24k
  MOVI r3,58
  CMP r2,r3
  JMP[EQ] @field_driver_phase_rotate
  MOVI r3,59
  CMP r2,r3
  JMP[EQ] @field_driver_pq_encode
  MOVI r3,60
  CMP r2,r3
  JMP[EQ] @field_driver_phase_encode
  MOVI r3,61
  CMP r2,r3
  JMP[EQ] @field_driver_spectral_iter
  MOVI r3,62
  CMP r2,r3
  JMP[EQ] @field_driver_sparse_knn
  MOVI r3,63
  CMP r2,r3
  JMP[EQ] @field_driver_phase_encode_batch
  MOVI r3,64
  CMP r2,r3
  JMP[EQ] @field_driver_phase_table_init
  MOVI r3,65
  CMP r2,r3
  JMP[EQ] @field_driver_vector_matrix_reset
  MOVI r3,66
  CMP r2,r3
  JMP[EQ] @field_driver_vector_matrix_accum
  MOVI r3,67
  CMP r2,r3
  JMP[EQ] @field_driver_vector_matrix_probe
  MOVI r3,68
  CMP r2,r3
  JMP[EQ] @field_driver_vector_matrix_credits
  MOVI r3,69
  CMP r2,r3
  JMP[EQ] @field_driver_pq_train
  MOVI r3,70
  CMP r2,r3
  JMP[EQ] @field_driver_pq_residual
  MOVI r3,71
  CMP r2,r3
  JMP[EQ] @field_driver_pq_update
  MOVI r3,72
  CMP r2,r3
  JMP[EQ] @field_driver_leaf_verify
  MOVI r3,73
  CMP r2,r3
  JMP[EQ] @field_driver_ckpt_hash
  MOVI r3,74
  CMP r2,r3
  JMP[EQ] @field_driver_tokenize
  MOVI r3,75
  CMP r2,r3
  JMP[EQ] @field_driver_meta_reset
  MOVI r3,76
  CMP r2,r3
  JMP[EQ] @field_driver_meta_observe
  MOVI r3,77
  CMP r2,r3
  JMP[EQ] @field_driver_temporal_reset
  MOVI r3,78
  CMP r2,r3
  JMP[EQ] @field_driver_temporal_observe
  MOVI r3,79
  CMP r2,r3
  JMP[EQ] @field_driver_temporal_project
  MOVI r3,80
  CMP r2,r3
  JMP[EQ] @field_driver_ngram_reset
  MOVI r3,81
  CMP r2,r3
  JMP[EQ] @field_driver_ngram_train
  MOVI r3,82
  CMP r2,r3
  JMP[EQ] @field_driver_ngram_topk
  MOVI r3,83
  CMP r2,r3
  JMP[EQ] @field_driver_hyperbolic
  MOVI r3,84
  CMP r2,r3
  JMP[EQ] @field_driver_geometry_path
  MOVI r3,85
  CMP r2,r3
  JMP[EQ] @field_driver_geometry_triangle
  MOVI r3,86
  CMP r2,r3
  JMP[EQ] @field_driver_geometry_field
  MOVI r3,87
  CMP r2,r3
  JMP[EQ] @field_driver_dual_gate
  MOVI r3,90
  CMP r2,r3
  JMP[EQ] @field_driver_triangle_model_reset
  MOVI r3,91
  CMP r2,r3
  JMP[EQ] @field_driver_triangle_model_observe
  MOVI r3,92
  CMP r2,r3
  JMP[EQ] @field_driver_triangle_model_score
  MOVI r3,93
  CMP r2,r3
  JMP[EQ] @field_driver_triangle_model_observe_negative
  MOVI r3,94
  CMP r2,r3
  JMP[EQ] @field_driver_triangle_model_score_contrastive
  MOVI r3,95
  CMP r2,r3
  JMP[EQ] @field_driver_phase_hyperbolic
  MOVI r3,96
  CMP r2,r3
  JMP[EQ] @field_driver_shape_field_reset
  MOVI r3,97
  CMP r2,r3
  JMP[EQ] @field_driver_shape_field_observe
  MOVI r3,98
  CMP r2,r3
  JMP[EQ] @field_driver_shape_field_gate
  MOVI r3,99
  CMP r2,r3
  JMP[EQ] @field_driver_global_hodge
  MOVI r3,100
  CMP r2,r3
  JMP[EQ] @field_driver_global_hodge_q16
  MOVI r3,101
  CMP r2,r3
  JMP[EQ] @field_driver_triangle_flow
  MOVI r3,102
  CMP r2,r3
  JMP[EQ] @field_driver_meta_attention
  MOVI r3,104
  CMP r2,r3
  JMP[EQ] @field_driver_hypertensor256_map
  MOVI r3,105
  CMP r2,r3
  JMP[EQ] @field_driver_hypertensor256_dual_map
  MOVI r3,106
  CMP r2,r3
  JMP[EQ] @field_driver_spectral_tensor_proposal
  MOVI r3,107
  CMP r2,r3
  JMP[EQ] @field_driver_six_context_poincare
  MOVI r3,108
  CMP r2,r3
  JMP[EQ] @field_driver_hyperedge_poincare128
  MOVI r3,109
  CMP r2,r3
  JMP[EQ] @field_driver_stream_context6
  MOVI r3,110
  CMP r2,r3
  JMP[EQ] @field_driver_head16_poincare
  MOVI r3,111
  CMP r2,r3
  JMP[EQ] @field_driver_triad_hotcold_poincare
  MOVI r3,112
  CMP r2,r3
  JMP[EQ] @field_driver_future3_causal
  MOVI r3,113
  CMP r2,r3
  JMP[EQ] @field_driver_full_field_255_85
  JMP @field_driver_return

field_driver_proposal:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  LD r7,r10,6
  LD r8,r10,7
  CALL @mth_triad_vote
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_field:
  MOVI r1,0x5000
  MOVI r2,85
  CALL @mth_field_vote
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_coherence:
  MOVI r1,0x6000
  CALL @mth_field_coherence
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_remap:
  MOVI r1,0x4001
  MOVI r10,0x4007
  LD r2,r10,0
  MOVI r10,0x4008
  LD r3,r10,0
  MOVI r10,0x4009
  LD r4,r10,0
  CALL @mth_remap_decision
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  JMP @field_driver_return

field_driver_remap_general:
  MOVI r1,0x4001
  MOVI r10,0x400A
  LD r2,r10,0
  MOVI r10,0x400B
  LD r3,r10,0
  MOVI r10,0x4007
  LD r4,r10,0
  MOVI r10,0x4008
  LD r5,r10,0
  MOVI r10,0x4009
  LD r6,r10,0
  CALL @mth_remap_general
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  JMP @field_driver_return

field_driver_cft:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  CALL @mth_cft_credit
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_trail:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  LD r7,r10,6
  LD r8,r10,7
  LD r9,r10,8
  LD r10,r10,9
  MOVI r11,0x4001
  LD r11,r11,10
  ; r10 already holds gamma; load lambda into r11 via the command word
  MOVI r12,0x400B
  LD r11,r12,0
  CALL @mth_trail_credit
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  JMP @field_driver_return

field_driver_hot_trihead:
  MOVI r1,0x7000
  MOVI r10,0x4001
  LD r2,r10,0
  CALL @mth_hot_trihead
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_micro_feature:
  MOVI r1,0x7000
  MOVI r2,0x7100
  MOVI r3,0x7200
  CALL @mth_micro_feature
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_trunk:
  MOVI r10,0x4001
  LD r1,r10,0
  CALL @mth_trunk_causal
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_readout_train:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_readout_train
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_readout_only:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  CALL @mth_readout_only
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_readout_sample:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_readout_sample
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_readout_softmax:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  CALL @mth_readout_softmax
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  JMP @field_driver_return

field_driver_readout_hier:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_readout_hier
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_readout_context:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_context_hier
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

; Multi-order context backoff, one command with setup and runtime modes.
;   0x4001 = mode: 1 build, 2 select, 3 step
;   mode 1: 0x4002 = packed k=4 key
;   mode 2: 0x4002 = buckets, 0x4003 = exact slot limit
;   mode 3: 0x4002 = target, 0x4003 = lr bits, 0x4004 = key,
;           0x4005 = buckets
field_driver_context_backoff:
  MOVI r10,0x4001
  LD r1,r10,0
  MOVI r3,1
  CMP r1,r3
  JMP[EQ] @field_driver_ctxb_build
  MOVI r3,2
  CMP r1,r3
  JMP[EQ] @field_driver_ctxb_select
  MOVI r3,3
  CMP r1,r3
  JMP[EQ] @field_driver_ctxb_step
  MOVI r3,4
  CMP r1,r3
  JMP[EQ] @field_driver_ctxb_build_batch
  MOVI r3,5
  CMP r1,r3
  JMP[EQ] @field_driver_ctxb_reset
  JMP @field_driver_return

field_driver_ctxb_build:
  MOVI r10,0x4002
  LD r1,r10,0
  CALL @mth_ctxb_build
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_ctxb_reset:
  MOVI r12,@mth_ctxb_build_count
  ST r0,r12,0
  MOVI r12,@mth_ctxb_full
  ST r0,r12,0
  JMP @field_driver_return

field_driver_ctxb_build_batch:
  MOVI r10,0x4002
  LD r1,r10,0
  MOVI r10,0x4003
  LD r2,r10,0
  CALL @mth_ctxb_build_batch
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_ctxb_select:
  MOVI r10,0x4002
  LD r1,r10,0
  MOVI r10,0x4003
  LD r2,r10,0
  CALL @mth_ctxb_select
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_ctxb_step:
  MOVI r10,0x4002
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_context_backoff
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  ST r5,r10,4
  ST r6,r10,5
  JMP @field_driver_return

field_driver_field_commit:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x7000
  MOVI r3,0x7100
  CALL @mth_field_commit
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_trunk_wide:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_trunk_wide
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_trunk_credit:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_trunk_credit
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_qkv_credit:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_qkv_credit
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_qkv_credit_wide:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_qkv_credit_wide
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_trunk_credit_wide:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_trunk_credit_wide
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_cft_credit:
  ; target,best,base_lr,threshold at 0x4001..0x4004; CFT args at 0x4005..0x4009
  MOVI r10,0x4005
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  CALL @mth_cft_credit
  ADD r6,r4,r0          ; CFT residual is the credit
  MOVI r10,0x4003
  LD r2,r10,0
  MOVI r10,0x4004
  LD r3,r10,0
  ADD r1,r6,r0
  CALL @mth_credit_gate
  CMP r1,r0
  JMP[EQ] @field_driver_credit_rejected
  CALL @mth_credit_rate_float
  ADD r6,r1,r0          ; gated learning rate
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  ADD r3,r6,r0
  CALL @mth_trunk_credit
  MOVI r10,0x4010
  MOVI r1,1
  ST r1,r10,0
  JMP @field_driver_return

field_driver_credit_rejected:
  MOVI r10,0x4010
  ST r0,r10,0
  JMP @field_driver_return

field_driver_trail_credit:
  ; target,best,base_lr,threshold at 0x4001..0x4004; TRAIL args at 0x4005..0x400F
  MOVI r10,0x4005
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  LD r7,r10,6
  LD r8,r10,7
  LD r9,r10,8
  LD r10,r10,9
  MOVI r11,0x400F
  LD r11,r11,0
  CALL @mth_trail_credit
  ADD r6,r3,r0          ; TRAIL credit
  MOVI r10,0x4003
  LD r2,r10,0
  MOVI r10,0x4004
  LD r3,r10,0
  ADD r1,r6,r0
  CALL @mth_credit_gate
  CMP r1,r0
  JMP[EQ] @field_driver_credit_rejected
  CALL @mth_credit_rate_float
  ADD r6,r1,r0
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  ADD r3,r6,r0
  CALL @mth_trunk_credit
  MOVI r10,0x4010
  MOVI r1,1
  ST r1,r10,0
  JMP @field_driver_return

field_driver_credit_field:
  MOVI r1,0x7000
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r3,0x7100
  CALL @mth_credit_field
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_geometric_trail_field:
  ; Kernel stages all 255 signed two-rail credits and gates 85 triads.
  ; Writes result words 0x4010..0x4013 itself; no host formula.
  CALL @mth_geometric_trail_field
  JMP @field_driver_return

field_driver_holo:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_holo_credit
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_ring:
  MOVI r1,0x6000
  MOVI r10,0x4001
  LD r2,r10,0
  CALL @mth_ring_credit
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_leaf:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_leaf_credit
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_tca:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_tca_credit
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_flux:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_flux_credit
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  JMP @field_driver_return

; Commit to both local readout and QKV only through the existing guest
; arithmetic; the caller must stage/snapshot/validate the root for rollback.
field_driver_credit_combine:
  MOVI r1,0x7000
  MOVI r2,0x7100
  CALL @mth_credit_combine
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_combined_credit:
  MOVI r1,0x7000
  MOVI r2,0x7100
  CALL @mth_credit_combine
  ADD r6,r1,r0
  MOVI r10,0x4003
  LD r2,r10,0
  MOVI r10,0x4004
  LD r3,r10,0
  ADD r1,r6,r0
  CALL @mth_credit_gate
  CMP r1,r0
  JMP[EQ] @field_driver_credit_rejected
  CALL @mth_credit_rate_float
  ADD r6,r1,r0
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  ADD r3,r6,r0
  CALL @mth_trunk_credit
  MOVI r10,0x4010
  MOVI r1,1
  ST r1,r10,0
  JMP @field_driver_return

field_driver_combined_all:
  MOVI r1,0x7000
  MOVI r2,0x7100
  CALL @mth_credit_combine
  ADD r6,r1,r0
  MOVI r10,0x4003
  LD r2,r10,0
  MOVI r10,0x4004
  LD r3,r10,0
  ADD r1,r6,r0
  CALL @mth_credit_gate
  CMP r1,r0
  JMP[EQ] @field_driver_credit_rejected
  CALL @mth_credit_rate_float
  ADD r6,r1,r0
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  ADD r3,r6,r0
  CALL @mth_qkv_credit
  MOVI r10,0x4010
  MOVI r1,1
  ST r1,r10,0
  JMP @field_driver_return

field_driver_combined_wide:
  MOVI r1,0x7000
  MOVI r2,0x7100
  CALL @mth_credit_combine
  ADD r6,r1,r0
  MOVI r10,0x4003
  LD r2,r10,0
  MOVI r10,0x4004
  LD r3,r10,0
  ADD r1,r6,r0
  CALL @mth_credit_gate
  CMP r1,r0
  JMP[EQ] @field_driver_credit_rejected
  CALL @mth_credit_rate_float
  ADD r6,r1,r0
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  ADD r3,r6,r0
  CALL @mth_qkv_credit_wide
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  ADD r3,r6,r0
  CALL @mth_trunk_credit_wide
  MOVI r10,0x4010
  MOVI r1,1
  ST r1,r10,0
  JMP @field_driver_return

field_driver_credit_bundle:
  CALL @mth_credit_bundle
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_context_class:
  ; high table / buckets / bucket / low table / mode / direct high/low
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  LD r7,r10,6
  CALL @mth_context_pick
  MOVI r10,0x4010
  ST r5,r10,0             ; high class
  ST r6,r10,1             ; low class
  ST r1,r10,2             ; class head
  ST r2,r10,3             ; triad
  ST r3,r10,4             ; member
  ST r4,r10,12            ; field-head flag
  MOVI r12,@mth_driver_ctx_head
  ST r1,r12,0

  MOVI r10,0x4008
  LD r6,r10,0             ; credit mode 0 none, 1 CFT, 2 TRAIL
  MOVI r12,@mth_driver_ctx_mode
  ST r6,r12,0
  CMP r6,r0
  JMP[EQ] @field_driver_ctx_no_credit
  MOVI r12,1
  CMP r6,r12
  JMP[EQ] @field_driver_ctx_cft
  MOVI r12,2
  CMP r6,r12
  JMP[EQ] @field_driver_ctx_trail
  JMP @field_driver_ctx_no_credit

field_driver_ctx_cft:
  MOVI r10,0x400A
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  CALL @mth_cft_credit
  ADD r11,r4,r0
  JMP @field_driver_ctx_credit_ready

field_driver_ctx_trail:
  MOVI r10,0x7300
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  LD r7,r10,6
  LD r8,r10,7
  LD r9,r10,8
  LD r10,r10,9
  MOVI r12,0x7300
  LD r11,r12,10
  CALL @mth_trail_credit
  ADD r11,r3,r0
  JMP @field_driver_ctx_credit_ready

field_driver_ctx_no_credit:
  MOVI r11,0

field_driver_ctx_credit_ready:
  MOVI r12,@mth_driver_ctx_delta
  ST r11,r12,0
  MOVI r1,0x7000
  MOVI r10,0x4009
  LD r2,r10,0
  MOVI r3,0x7100
  MOVI r12,@mth_driver_ctx_head
  LD r4,r12,0
  ADD r5,r11,r0
  CALL @mth_context_field
  MOVI r10,0x4010
  ST r1,r10,5             ; accepted triads
  ST r2,r10,6             ; field accepted
  ST r3,r10,7             ; selected triad vote
  ST r4,r10,8             ; selected head credit before
  ST r5,r10,9             ; selected head credit after
  MOVI r12,@mth_driver_ctx_mode
  LD r11,r12,0
  CMP r11,r0
  MOVI r11,0
  JMP[EQ] @field_driver_ctx_applied_done
  MOVI r11,1
field_driver_ctx_applied_done:
  ST r11,r10,10           ; credit mode applied
  MOVI r12,@mth_driver_ctx_delta
  LD r11,r12,0
  ST r11,r10,11           ; guest credit delta
  JMP @field_driver_return

; Native Q16.16 -> float32 bit-pattern conversion for trunk ABI.
mth_credit_rate_float:
  CVTIF r1,r1
  MOVI r2,0
  MOVHI r2,0x4780
  FDIV r1,r1,r2
  RET

field_driver_phase_encode:
  MOVI r10,0x4001
  LD r2,r10,0
  LD r3,r10,1
  MOVI r1,0x7000
  MOVI r4,0x5200
  CALL @mth_phase_encode_wide
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_phase_rotate:
  MOVI r1,0x7000
  MOVI r2,0x7200
  MOVI r10,0x4001
  LD r3,r10,0
  LD r4,r10,1
  CALL @mth_phase_rotate
  MOVI r10,0x4010
  ST r4,r10,0
  JMP @field_driver_return
field_driver_pq_encode:
  MOVI r1,0x7000
  MOVI r2,0x0000
  MOVHI r2,0x0001
  MOVI r10,0x4001
  LD r3,r10,0
  LD r4,r10,1
  MOVI r5,0x4010
  CALL @mth_pq_encode
  JMP @field_driver_return
field_driver_spectral_iter:
  MOVI r1,0x7000
  MOVI r2,0x7040
  MOVI r3,0x7080
  CALL @mth_spectral_iter
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_sparse_knn:
  MOVI r1,0x7000
  MOVI r2,0x0000
  MOVHI r2,0x0001
  MOVI r10,0x4001
  LD r3,r10,0
  LD r4,r10,1
  LD r5,r10,2
  MOVI r6,0x7200
  MOVI r7,0x7240
  CALL @mth_sparse_knn
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_phase_encode_batch:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r3,r10,1
  LD r4,r10,2
  MOVI r2,0x0000
  MOVHI r2,0x0006
  MOVI r5,0x0000
  MOVHI r5,0x0007
  CALL @mth_phase_encode_batch
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_phase_table_init:
  CALL @mth_phase_table_init
  JMP @field_driver_return

field_driver_vector_matrix_reset:
  CALL @mth_vm_reset
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_vector_matrix_accum:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_vm_accum
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return
field_driver_vector_matrix_probe:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  CALL @mth_vm_probe
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_vector_matrix_credits:
  MOVI r1,0x7000
  CALL @mth_vm_credits
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_pq_train:
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r10,0x4001
  LD r2,r10,0
  LD r3,r10,1
  LD r4,r10,2
  LD r5,r10,3
  MOVI r6,0x0000
  MOVHI r6,0x0005
  MOVI r7,0
  MOVI r8,0
  CALL @mth_pq_train
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_pq_update:
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r10,0x4001
  LD r2,r10,0
  LD r3,r10,1
  LD r4,r10,2
  LD r5,r10,3
  MOVI r6,0x0000
  MOVHI r6,0x0005
  MOVI r7,1
  MOVI r8,0
  LD r8,r10,4
  CALL @mth_pq_train
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_pq_residual:
  MOVI r10,0x4001
  LD r4,r10,0
  LD r5,r10,1
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r2,0x0000
  MOVHI r2,0x0005
  MOVI r3,0x0000
  MOVHI r3,0x0008
  MOVI r6,0x0000
  MOVHI r6,0x0009
  CALL @mth_pq_residual
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_leaf_verify:
  MOVI r1,0x7000
  MOVI r2,0x0000
  MOVHI r2,0x0001
  MOVI r3,0x0000
  MOVHI r3,0x0003
  MOVI r10,0x4001
  LD r4,r10,0
  LD r5,r10,1
  LD r6,r10,2
  CALL @mth_leaf_verify
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_ckpt_hash:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  CALL @mth_ckpt_hash
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_tokenize:
  MOVI r10,0x4001
  LD r2,r10,0
  LD r6,r10,1
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r3,0x0000
  MOVHI r3,0x0002
  MOVI r4,0x0000
  MOVHI r4,0x0003
  MOVI r5,0x0000
  MOVHI r5,0x0004
  CALL @mth_tokenize
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_meta_reset:
  CALL @mth_meta_trihead_reset
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_meta_observe:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0002
  CALL @mth_meta_trihead_observe_batch
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_temporal_reset:
  CALL @mth_temporal_reset
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_temporal_observe:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0002
  CALL @mth_temporal_observe_batch
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_temporal_project:
  CALL @mth_temporal_project
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_ngram_reset:
  CALL @mth_ngram_reset
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_ngram_train:
  MOVI r10,0x4001
  LD r2,r10,0
  LD r3,r10,1
  MOVI r1,0x0000
  MOVHI r1,0x0001
  CALL @mth_ngram_train
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_ngram_topk:
  CALL @mth_ngram_topk
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_hyperbolic:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0034
  CALL @mth_geom_hyperbolic
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_geometry_path:
  MOVI r10,0x4001
  LD r2,r10,0
  LD r3,r10,1
  MOVI r1,0x0000
  MOVHI r1,0x0034
  CALL @mth_geom_path
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_geometry_triangle:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0034
  CALL @mth_geom_triangle
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  ST r5,r10,4
  ST r6,r10,5
  JMP @field_driver_return

field_driver_geometry_field:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0034
  CALL @mth_geom_field_perturb
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_dual_gate:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  LD r7,r10,6
  CALL @mth_dual_gate
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  ST r5,r10,4
  JMP @field_driver_return

field_driver_triangle_model_reset:
  CALL @mth_tri_model_reset
  JMP @field_driver_return
field_driver_triangle_model_observe:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_tri_model_observe
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_triangle_model_score:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  CALL @mth_tri_model_score
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_triangle_model_observe_negative:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_tri_model_observe_negative
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_triangle_model_score_contrastive:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  CALL @mth_tri_model_score_contrast
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_phase_hyperbolic:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0034
  CALL @mth_phase_hyperbolic
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_shape_field_reset:
  CALL @mth_tri_field_reset
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_shape_field_observe:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_tri_field_observe
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_shape_field_gate:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_shape_field_gate
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  JMP @field_driver_return

field_driver_global_hodge:
  MOVI r1,0x0000
  MOVHI r1,0x0036
  MOVI r2,0x8000
  MOVHI r2,0x0036
  MOVI r10,0x4001
  LD r3,r10,0
  MOVI r4,0x9000
  MOVHI r4,0x0036
  MOVI r5,0x9400
  MOVHI r5,0x0036
  MOVI r6,0xA000
  MOVHI r6,0x0036
  MOVI r7,0xB000
  MOVHI r7,0x0036
  CALL @mth_global_hodge256_f32
  MOVI r10,0x4010
  ST r1,r10,0
  ST r9,r10,1
  JMP @field_driver_return

field_driver_global_hodge_q16:
  CALL @mth_global_hodge256_q16
  MOVI r10,0x4010
  ST r1,r10,0
  ST r9,r10,1
  JMP @field_driver_return

field_driver_triangle_flow:
  MOVI r10,0x4001
  LD r2,r10,0
  MOVI r1,0x8000
  MOVHI r1,0x0036
  MOVI r3,0x0000
  MOVHI r3,0x0036
  MOVI r4,0x0000
  MOVHI r4,0x3F80
  CALL @mth_triangle_flow_build
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_meta_attention:
  MOVI r10,0x4001
  LD r4,r10,0
  LD r5,r10,1
  MOVI r1,0x0000
  MOVHI r1,0x0034
  MOVI r2,0x0800
  MOVHI r2,0x0034
  MOVI r3,0x1800
  MOVHI r3,0x0034
  MOVI r6,0x2800
  MOVHI r6,0x0034
  MOVI r7,0x3000
  MOVHI r7,0x0034
  CALL @mth_meta_attention16_f32
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return

field_driver_hypertensor256_map:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_hypertensor256_mirror_arena_map
  MOVI r10,0x4010
  ST r1,r10,0
  ST r4,r10,1
  ST r5,r10,2
  ST r6,r10,3
  JMP @field_driver_return
field_driver_hypertensor256_dual_map:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r8,r10,3
  CALL @mth_hypertensor256_mirror_dual_map
  MOVI r10,0x4010
  ST r1,r10,0
  ST r4,r10,1
  ST r5,r10,2
  ST r6,r10,3
  JMP @field_driver_return

; Opcode 106: exact NaN16 spectral-to-tensor transaction proposal.
; All request buffers are disjoint 32-bit guest WORD spans in a dedicated
; private region (0x003D0000..0x003D200B):
; spectral_i64 at 3D0000 (512 words), trihead masks at 3D0400 (85),
; oriented pair coordinates at 3D0500 (510), candidate writer lease
; bits at 3D0800 (255), scratch records at 3D0A00 (1275), output
; records at 3D1000 (1275), request at 3D2000 (12).
; 0x4001/2: expected/current generation; 0x4003/4: global/meta approval.
; 0x4010..13: success, accepted triads, staged records, rejection reason.
; Every output offset is for the 64MiB CANDIDATE bank; no tensor write.
field_driver_spectral_tensor_proposal:
  MOVI r1,0x2000
  MOVHI r1,0x003D
  MOVI r10,0
  MOVHI r10,0x003D
  ST r10,r1,0
  MOVI r10,0x0400
  MOVHI r10,0x003D
  ST r10,r1,1
  MOVI r10,0x0500
  MOVHI r10,0x003D
  ST r10,r1,2
  MOVI r10,0x0800
  MOVHI r10,0x003D
  ST r10,r1,3
  MOVI r10,0x0A00
  MOVHI r10,0x003D
  ST r10,r1,4
  MOVI r10,0x1000
  MOVHI r10,0x003D
  ST r10,r1,5
  MOVI r10,0x4001
  LD r11,r10,0
  ST r11,r1,6
  LD r11,r10,1
  ST r11,r1,7
  LD r11,r10,2
  ST r11,r1,8
  LD r11,r10,3
  ST r11,r1,9
  ST r0,r1,10
  ST r0,r1,11
  CALL @mth_spectral_trihead_tensor_proposal
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

;
; Opcode107: unified six-word signed-temporal self-attention, NOW(255)
; and true 2D Poincare ball radial depth. Task 0 forbids all future
; slots, task1 requires caller to mask its infill target.
; Guest request at word 0x003E4000 U32[12], output 0x003E4100 [8].
; Driver result at 0x4010: accepted, valid_count, mode, rejection_code.
; Neither opcode nor kernel modifies the 48M checkpoint or active tensor.
field_driver_six_context_poincare:
  MOVI r1,0x4000
  MOVHI r1,0x003E
  MOVI r2,0x4100
  MOVHI r2,0x003E
  CALL @mth_six_context_poincare_attention
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

; Opcode108: 128D hyperbolic hyperedge abstraction depth with signed
; Hodge curl (native verification only: source provenance comes from caller).
; guest 0x3E5000 input vector[128], 0x3E5200 candidate vector[128],
; 0x3E5400 hyperedge record[8], 0x3E5500 output[5].
; Return at 0x4010: accepted/128/sign/rejection.
; The VOID NOW point is reference-only. No root or active tensor writes.
field_driver_hyperedge_poincare128:
  MOVI r1,0x5000
  MOVHI r1,0x003E
  MOVI r2,0x5200
  MOVHI r2,0x003E
  MOVI r3,0x5400
  MOVHI r3,0x003E
  MOVI r4,0x5500
  MOVHI r4,0x003E
  CALL @mth_hyperedge_poincare128_curl
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

; Opcode109: REAL CORPUS STREAM -> 3-past+3-future target-free window
; -> existing trig/MC0/Poincare attention. NO host attention or window math.
; Guest source IDs 0x3E6000[up to4096]. Inputs at 0x4001:
; [count,target_index,task,masked_query_anchor,expected_gen,current_gen].
; The builder rejects causal prediction with center!=count and NEVER reads
; a target token for infilling. It directly writes request 0x3E4000 for
; opcode107 and then runs exactly the SAME guest attention kernel.
; Result 0x4010..13 accepted, number of valid slots, task, error code.
; Full context/Poincare record remains at 0x3E4100[8].
field_driver_stream_context6:
  MOVI r1,0x6000
  MOVHI r1,0x003E
  MOVI r10,0x4001
  LD r2,r10,0
  LD r3,r10,1
  LD r4,r10,2
  LD r5,r10,3
  LD r6,r10,4
  LD r7,r10,5
  MOVI r8,0x4000
  MOVHI r8,0x003E
  CALL @mth_context6_window_stream
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @field_driver_stream_context6_result
  MOVI r1,0x4000
  MOVHI r1,0x003E
  MOVI r2,0x4100
  MOVHI r2,0x003E
  CALL @mth_six_context_poincare_attention
field_driver_stream_context6_result:
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

; Opcode112: frozen-48M future3 AUTOREGRESSIVE native measurement.
; Guest reads original observed source at 0x3E6000 (1..4096 words),
; only earlier DECODER-GENERATED words from 0x3E5000[0..count-1].
; Args 0x4001: observed_count, generated_count[0..2], expected_gen, current_gen.
; Output context request 0x3E4000[12], trig/MC0/Poincare 0x3E4100[8].
; 0x4010: success, valid past count, horizon[1..3], rejection reason.
; No future gold, no active tensor, no host contextual mathematics.
field_driver_future3_causal:
  MOVI r1,0x6000
  MOVHI r1,0x003E
  MOVI r3,0x5000
  MOVHI r3,0x003E
  MOVI r10,0x4001
  LD r2,r10,0
  LD r4,r10,1
  LD r5,r10,2
  LD r6,r10,3
  MOVI r7,0x4000
  MOVHI r7,0x003E
  CALL @mth_future3_causal_window
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @field_driver_future3_result
  MOVI r1,0x4000
  MOVHI r1,0x003E
  MOVI r2,0x4100
  MOVHI r2,0x003E
  CALL @mth_six_context_poincare_attention
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @field_driver_future3_result
  MOVI r10,0x4002
  LD r3,r10,0
  ADDI r3,r3,1
field_driver_future3_result:
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

; Opcode110: independent raw NaN16 16-Boolean head measurement,
; per-head 128D source scratch 0x3B0000+h*256, projected 0x3F0000+h*256.
; Host writes h to 0x4001. The source vector, actual Hodge curl, writer
; capability, truth mask and epoch reside entirely in that head's scratch.
; Result 0x4010: accepted,head,hotvote,reason. No tensor write here.
field_driver_head16_poincare:
  MOVI r10,0x4001
  LD r1,r10,0
  CALL @mth_head16_poincare_measure
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

; Opcode111: 85 trihead vector scratch arenas, sourced 128D head vectors,
; 2/3 HOT/COLD, 3/3 HOT and COLD unanimity, and signed native 7-credit
; x Hodge-curl eligibility proposals.
; Args 0x4001: t, curl F32, expected_gen, current_gen, credit Q16.
; Mapping 85x3 U32 at 0x3E7000. Native triad scratch is 0x3E8000..3EE900.
; Result 0x4010: accepted,hot_count,cold_count,reason.
; The source must have passed Hodge/provenance; no automatic tensor promotion.
field_driver_triad_hotcold_poincare:
  MOVI r10,0x4001
  LD r1,r10,0
  MOVI r2,0x7000
  MOVHI r2,0x003E
  LD r3,r10,1
  LD r4,r10,2
  LD r5,r10,3
  LD r6,r10,4
  CALL @mth_triad_hotcold_poincare128
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

; Opcode113: source-derived WHOLE-FIELD native NaN16 head->trihead
; measurement, no supplied/synthetic 85 vote masks.
; All 255 head SOURCE 128D F32 vectors, Boolean masks, epoch/lease,
; actual source Hodge curl and relation anchors must already be present
; in independent head slabs 0x3B0000+h*256 (caller-provenanced).
; 85 sourced Hodge curls F32 at 0x3EF600 and native seven-credit Q16 at
; 0x3EF700; mapping 85x3 at 0x3E7000, 255 unique heads.
; Native guest computes all 255 head Poincare vectors and 85 triad vectors,
; with native HOT/COLD gradients in separate triad scratch slabs.
; Command args 0x4001[0..1] expected and observed generation.
; Results: 0x4010[0..3] accepted,hot_quorum_count,head_count,reason.
; Votes 0x3EF000[85], report 0x3EF100[10]; only written if ALL
; head and trihead measurements succeed. Global/meta and tensor promotion
; are separate authenticated gates; no direct active bank writes.
field_driver_full_field_255_85:
  MOVI r1,0x7000
  MOVHI r1,0x003E
  MOVI r2,0xF600
  MOVHI r2,0x003E
  MOVI r3,0xF700
  MOVHI r3,0x003E
  MOVI r10,0x4001
  LD r4,r10,0
  LD r5,r10,1
  MOVI r6,0xF000
  MOVHI r6,0x003E
  MOVI r7,0xF100
  MOVHI r7,0x003E
  CALL @mth_full_field_head_triad_measure
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  JMP @field_driver_return

field_driver_context_encode:
  CALL @mth_context_encode
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_role_step:
  CALL @mth_role_step
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return
field_driver_sense_step:
  CALL @mth_sense_step
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return
field_driver_semantic_query:
  CALL @mth_semantic_query
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_context_encode24:
  CALL @mth_context_encode24
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @field_driver_return
field_driver_role_step24:
  CALL @mth_role_step24
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return
field_driver_sense_step24:
  CALL @mth_sense_step24
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return
field_driver_role_step24k:
  CALL @mth_role_step24k
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  JMP @field_driver_return

field_driver_return:
  MOVI r10,@field_driver_link
  LD r15,r10,0
  RET

field_driver_link:
  .word 0
mth_driver_ctx_head:
  .word 0
mth_driver_ctx_mode:
  .word 0
mth_driver_ctx_delta:
  .word 0
