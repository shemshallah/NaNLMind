; NaN16 temporary triad remap decision (fixed A1 <-> B0 slot swap).
;
; ABI:
;   r1 = pointer to six masks: A0,A1,A2,B0,B1,B2 (32-bit words)
;   r2 = operand A, r3 = operand B, r4 = target
; Returns:
;   r1 = 1 when the swap improves the combined triad objective
;   r2 = before score, r3 = after score
;
; The mask table is restored exactly when the trial is rejected.
.include "mth_triad_score.nas"

mth_remap_decision:
  MOVI r12,@mth_remap_link
  ST r15,r12,0
  MOVI r12,@mth_remap_ptr
  ST r1,r12,0
  MOVI r12,@mth_remap_a
  ST r2,r12,0
  MOVI r12,@mth_remap_b
  ST r3,r12,0
  MOVI r12,@mth_remap_target
  ST r4,r12,0

  ; before A
  MOVI r12,@mth_remap_ptr
  LD r10,r12,0
  LD r1,r10,0
  LD r2,r10,4
  LD r3,r10,8
  MOVI r12,@mth_remap_a
  LD r6,r12,0
  MOVI r12,@mth_remap_b
  LD r7,r12,0
  MOVI r12,@mth_remap_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_remap_before_a
  ST r1,r12,0

  ; before B
  MOVI r12,@mth_remap_ptr
  LD r10,r12,0
  ADDI r10,r10,12
  LD r1,r10,0
  LD r2,r10,4
  LD r3,r10,8
  MOVI r12,@mth_remap_a
  LD r6,r12,0
  MOVI r12,@mth_remap_b
  LD r7,r12,0
  MOVI r12,@mth_remap_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_remap_before_b
  ST r1,r12,0

  ; swap A1 and B0
  MOVI r12,@mth_remap_ptr
  LD r10,r12,0
  LD r5,r10,4
  LD r6,r10,12
  ST r6,r10,4
  ST r5,r10,12

  ; after A
  MOVI r12,@mth_remap_ptr
  LD r10,r12,0
  LD r1,r10,0
  LD r2,r10,4
  LD r3,r10,8
  MOVI r12,@mth_remap_a
  LD r6,r12,0
  MOVI r12,@mth_remap_b
  LD r7,r12,0
  MOVI r12,@mth_remap_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_remap_after_a
  ST r1,r12,0

  ; after B
  MOVI r12,@mth_remap_ptr
  LD r10,r12,0
  ADDI r10,r10,12
  LD r1,r10,0
  LD r2,r10,4
  LD r3,r10,8
  MOVI r12,@mth_remap_a
  LD r6,r12,0
  MOVI r12,@mth_remap_b
  LD r7,r12,0
  MOVI r12,@mth_remap_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_remap_after_b
  ST r1,r12,0

  ; sums
  MOVI r12,@mth_remap_before_a
  LD r2,r12,0
  MOVI r12,@mth_remap_before_b
  LD r5,r12,0
  ADD r2,r2,r5
  MOVI r12,@mth_remap_after_a
  LD r3,r12,0
  MOVI r12,@mth_remap_after_b
  LD r5,r12,0
  ADD r3,r3,r5
  CMP r3,r2
  JMP[GT] @mth_remap_accept

  ; restore A1/B0
  MOVI r12,@mth_remap_ptr
  LD r10,r12,0
  LD r5,r10,4
  LD r6,r10,12
  ST r6,r10,4
  ST r5,r10,12
  MOVI r1,0
  JMP @mth_remap_out

mth_remap_accept:
  MOVI r1,1
mth_remap_out:
  MOVI r13,1
  MOVI r12,@mth_remap_link
  LD r15,r12,0
  RET

mth_remap_link:
  .word 0
mth_remap_ptr:
  .word 0
mth_remap_a:
  .word 0
mth_remap_b:
  .word 0
mth_remap_target:
  .word 0
mth_remap_before_a:
  .word 0
mth_remap_before_b:
  .word 0
mth_remap_after_a:
  .word 0
mth_remap_after_b:
  .word 0
