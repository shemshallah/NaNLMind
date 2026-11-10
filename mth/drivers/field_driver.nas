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
.include "../nan16/mth_context_copy.nas"
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
  MOVI r3,30
  CMP r2,r3
  JMP[EQ] @field_driver_readout_context_joint
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

field_driver_readout_context_joint:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_context_hier_joint
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
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
