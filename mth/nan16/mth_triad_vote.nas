; NaN16 per-head self-modification and triad vote.
;
; ABI:
;   r1 = proposer current 16-bit function mask
;   r2 = XOR patch proposed by that head
;   r3 = member 0 mask, r4 = member 1 mask, r5 = member 2 mask
;   r6 = operand A, r7 = operand B, r8 = target (0/1)
; Returns:
;   r1 = 3-bit vote mask (bit 0 = member 0, ...)
;   r2 = 1 when at least two members approve and the candidate predicts target
;   r3 = candidate mask
;   r4 = candidate rule
;
; Each member votes from its own Boolean prediction on the same operands. The
; proposer's candidate must itself predict the target. Only the proposer's
; mask is changed by the caller; the triad is a gate, not a copy step.
.include "mth_bool_dynamic.nas"

mth_triad_vote:
  MOVI r10,@mth_triad_vote_link
  ST r15,r10,0
  ADD r11,r3,r0
  ADD r12,r4,r0
  ADD r13,r5,r0

  BOOL.6 r9,r1,r2          ; candidate mask = current XOR patch
  ADD r1,r9,r0
  CALL @mth_bool_lowbit
  ADD r10,r2,r0            ; candidate rule

  ADD r1,r10,r0
  CALL @mth_bool_eval      ; r5 = candidate prediction
  CMP r5,r8
  JMP[NE] @mth_triad_candidate_false

  MOVI r14,0
  ADD r1,r11,r0
  CALL @mth_bool_lowbit
  ADD r1,r2,r0
  CALL @mth_bool_eval
  CMP r5,r8
  JMP[NE] @mth_triad_m0_done
  MOVI r14,1
mth_triad_m0_done:

  ADD r1,r12,r0
  CALL @mth_bool_lowbit
  ADD r1,r2,r0
  CALL @mth_bool_eval
  CMP r5,r8
  JMP[NE] @mth_triad_m1_done
  ADDI r14,r14,2
mth_triad_m1_done:

  ADD r1,r13,r0
  CALL @mth_bool_lowbit
  ADD r1,r2,r0
  CALL @mth_bool_eval
  CMP r5,r8
  JMP[NE] @mth_triad_m2_done
  ADDI r14,r14,4
mth_triad_m2_done:

  ADD r1,r14,r0
  CALL @mth_bool_popcount3
  MOVI r3,2
  CMP r2,r3
  JMP[LT] @mth_triad_not_accepted

  ADD r1,r14,r0
  MOVI r2,1
  ADD r3,r9,r0
  ADD r4,r10,r0
  JMP @mth_triad_return

mth_triad_not_accepted:
  ADD r1,r14,r0
  MOVI r2,0
  ADD r3,r9,r0
  ADD r4,r10,r0
  JMP @mth_triad_return

mth_triad_candidate_false:
  MOVI r1,0
  MOVI r2,0
  ADD r3,r9,r0
  ADD r4,r10,r0
mth_triad_return:
  MOVI r13,1
  MOVI r10,@mth_triad_vote_link
  LD r15,r10,0
  RET

mth_triad_vote_link:
  .word 0
