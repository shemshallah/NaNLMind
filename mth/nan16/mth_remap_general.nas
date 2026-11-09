; General NaN16 triad remap trial.
;
; ABI:
;   r1 = pointer to six masks A0,A1,A2,B0,B1,B2 (word array)
;   r2 = slot A (0..2), r3 = slot B (0..2)
;   r4 = operand A, r5 = operand B, r6 = target
; Returns:
;   r1 = 1 when the swap improves the combined majority objective
;   r2 = before score, r3 = after score
;
; The guest restores the six-mask table before every return. The host decides
; whether to commit the corresponding chart mapping swap.

mth_remap_general:
  MOVI r12,@mth_rg_link
  ST r15,r12,0
  MOVI r12,@mth_rg_ptr
  ST r1,r12,0
  MOVI r12,@mth_rg_slot_a
  ST r2,r12,0
  MOVI r12,@mth_rg_slot_b
  ST r3,r12,0
  MOVI r12,@mth_rg_a
  ST r4,r12,0
  MOVI r12,@mth_rg_b
  ST r5,r12,0
  MOVI r12,@mth_rg_target
  ST r6,r12,0

  ; before A
  MOVI r12,@mth_rg_ptr
  LD r10,r12,0
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  MOVI r12,@mth_rg_a
  LD r6,r12,0
  MOVI r12,@mth_rg_b
  LD r7,r12,0
  MOVI r12,@mth_rg_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_rg_before_a
  ST r1,r12,0

  ; before B
  MOVI r12,@mth_rg_ptr
  LD r10,r12,0
  ADDI r10,r10,3
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  MOVI r12,@mth_rg_a
  LD r6,r12,0
  MOVI r12,@mth_rg_b
  LD r7,r12,0
  MOVI r12,@mth_rg_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_rg_before_b
  ST r1,r12,0

  ; swap A[slotA] and B[slotB] in the six-mask table
  MOVI r12,@mth_rg_ptr
  LD r10,r12,0
  MOVI r12,@mth_rg_slot_a
  LD r2,r12,0
  ADD r5,r10,r2
  LD r6,r5,0
  MOVI r12,@mth_rg_slot_b
  LD r3,r12,0
  ADD r7,r10,r3
  ADDI r7,r7,3
  LD r8,r7,0
  ST r8,r5,0
  ST r6,r7,0

  ; after A
  MOVI r12,@mth_rg_ptr
  LD r10,r12,0
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  MOVI r12,@mth_rg_a
  LD r6,r12,0
  MOVI r12,@mth_rg_b
  LD r7,r12,0
  MOVI r12,@mth_rg_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_rg_after_a
  ST r1,r12,0

  ; after B
  MOVI r12,@mth_rg_ptr
  LD r10,r12,0
  ADDI r10,r10,3
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  MOVI r12,@mth_rg_a
  LD r6,r12,0
  MOVI r12,@mth_rg_b
  LD r7,r12,0
  MOVI r12,@mth_rg_target
  LD r8,r12,0
  CALL @mth_triad_score
  MOVI r12,@mth_rg_after_b
  ST r1,r12,0

  ; sums
  MOVI r12,@mth_rg_before_a
  LD r2,r12,0
  MOVI r12,@mth_rg_before_b
  LD r5,r12,0
  ADD r2,r2,r5
  MOVI r12,@mth_rg_after_a
  LD r3,r12,0
  MOVI r12,@mth_rg_after_b
  LD r5,r12,0
  ADD r3,r3,r5
  MOVI r1,@mth_rg_before_out
  ST r2,r1,0
  MOVI r1,@mth_rg_after_out
  ST r3,r1,0
  CMP r3,r2
  JMP[GT] @mth_rg_accept

  ; restore the table without clobbering saved before/after words
  MOVI r12,@mth_rg_ptr
  LD r10,r12,0
  MOVI r12,@mth_rg_slot_a
  LD r9,r12,0
  ADD r5,r10,r9
  LD r6,r5,0
  MOVI r12,@mth_rg_slot_b
  LD r9,r12,0
  ADD r7,r10,r9
  ADDI r7,r7,3
  LD r8,r7,0
  ST r8,r5,0
  ST r6,r7,0
  MOVI r1,0
  JMP @mth_rg_out

mth_rg_accept:
  ; restore the caller's mask table; only the decision is returned
  MOVI r12,@mth_rg_ptr
  LD r10,r12,0
  MOVI r12,@mth_rg_slot_a
  LD r9,r12,0
  ADD r5,r10,r9
  LD r6,r5,0
  MOVI r12,@mth_rg_slot_b
  LD r9,r12,0
  ADD r7,r10,r9
  ADDI r7,r7,3
  LD r8,r7,0
  ST r8,r5,0
  ST r6,r7,0
  MOVI r1,1
mth_rg_out:
  MOVI r12,@mth_rg_before_out
  LD r2,r12,0
  MOVI r12,@mth_rg_after_out
  LD r3,r12,0
  MOVI r13,1
  MOVI r12,@mth_rg_link
  LD r15,r12,0
  RET

mth_rg_link:
  .word 0
mth_rg_ptr:
  .word 0
mth_rg_slot_a:
  .word 0
mth_rg_slot_b:
  .word 0
mth_rg_a:
  .word 0
mth_rg_b:
  .word 0
mth_rg_target:
  .word 0
mth_rg_before_a:
  .word 0
mth_rg_before_b:
  .word 0
mth_rg_after_a:
  .word 0
mth_rg_after_b:
  .word 0
mth_rg_before_out:
  .word 0
mth_rg_after_out:
  .word 0
