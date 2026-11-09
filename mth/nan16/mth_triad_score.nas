; NaN16 triad objective for one Boolean probe.
;
; ABI:
;   r1,r2,r3 = three member masks
;   r6 = operand A, r7 = operand B, r8 = target bit
; Returns:
;   r1 = correct-member count + 2 when at least two members are correct
;
; The majority bonus is what makes remapping non-invariant: moving a correct
; head next to another correct head can improve the cluster objective.
.include "mth_bool_dynamic.nas"

mth_triad_score:
  MOVI r9,@mth_triad_score_link
  ST r15,r9,0
  ADD r11,r1,r0
  ADD r12,r2,r0
  ADD r14,r3,r0
  MOVI r9,0

  ADD r1,r11,r0
  CALL @mth_bool_lowbit
  ADD r1,r2,r0
  CALL @mth_bool_eval
  CMP r5,r8
  JMP[NE] @mth_ts_m0
  ADDI r9,r9,1
mth_ts_m0:

  ADD r1,r12,r0
  CALL @mth_bool_lowbit
  ADD r1,r2,r0
  CALL @mth_bool_eval
  CMP r5,r8
  JMP[NE] @mth_ts_m1
  ADDI r9,r9,1
mth_ts_m1:

  ADD r1,r14,r0
  CALL @mth_bool_lowbit
  ADD r1,r2,r0
  CALL @mth_bool_eval
  CMP r5,r8
  JMP[NE] @mth_ts_m2
  ADDI r9,r9,1
mth_ts_m2:

  MOVI r1,2
  CMP r9,r1
  JMP[LT] @mth_ts_no_bonus
  ADDI r9,r9,2
mth_ts_no_bonus:
  ADD r1,r9,r0
  MOVI r13,1
  MOVI r9,@mth_triad_score_link
  LD r15,r9,0
  RET

mth_triad_score_link:
  .word 0
