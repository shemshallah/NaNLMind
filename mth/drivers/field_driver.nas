; Raw NaN16 field-command driver.
;
; Host writes one command block at guest word 0x4000:
;   [0] opcode: 1 proposal, 2 field vote, 3 coherence, 4 remap
; Proposal args at 0x4001: current, patch, m0, m1, m2, a, b, target
;   results at 0x4010: votes, accepted, candidate mask, candidate rule
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
; Geometric credit: command 13, 255 x 9 TRAIL rows at 0xD000;
;   dual-rail eligibility at 0xE600/0xE700, Q16 weights at 0xE800,
;   85 triad votes at 0xF000, 43/85 generation-checked field gate.
; Causal trunk: T at 0x4001, tokens at 0x7000, weights at 0x9000,
;   output feature at 0xA000, result count at 0x4010
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
.include "../nan16/mth_geometric_trail_field.nas"
.include "../nan16/mth_field_commit.nas"
.include "../nan16/mth_hot_trihead.nas"
.include "../nan16/mth_micro_feature.nas"
.include "../nan16/mth_trunk_causal.nas"
.include "../nan16/mth_readout_train.nas"

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
  JMP[EQ] @field_driver_geometric_credit
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

field_driver_geometric_credit:
  CALL @mth_geometric_trail_field
  JMP @field_driver_return

field_driver_return:
  MOVI r10,@field_driver_link
  LD r15,r10,0
  RET

field_driver_link:
  .word 0
