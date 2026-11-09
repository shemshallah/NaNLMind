; Sparse Hopfield top-1 retrieval primitive, fixed 4 patterns x 8 Q16 dims.
;
; ABI:
;   r1 = pointer to q[8] Q16.16
;   r2 = pointer to P[4][8] Q16.16 (row-major)
; Returns:
;   r1 = index of the nearest pattern (0..3)
;   r2 = its dot product, Q16.16
;
; This is a sparse retrieval primitive, not a full trunk or a dense attention
; matrix. It performs exact integer Q16 dot products in raw NaN16.

mth_hopfield_top1:
  MOVI r12,@mth_hop_link
  ST r15,r12,0
  ADD r10,r1,r0
  ADD r11,r2,r0
  MOVI r9,0
  MOVHI r9,0x8000
  MOVI r8,0

  ; pattern 0
  MOVI r7,0
  LD r1,r10,0
  LD r2,r11,0
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,1
  LD r2,r11,1
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,2
  LD r2,r11,2
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,3
  LD r2,r11,3
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,4
  LD r2,r11,4
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,5
  LD r2,r11,5
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,6
  LD r2,r11,6
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,7
  LD r2,r11,7
  CALL @mth_q16_mul
  ADD r7,r7,r1
  CMPS r7,r9
  JMP[LE] @mth_hop_p1
  ADD r9,r7,r0
  MOVI r8,0
mth_hop_p1:
  ADDI r11,r11,8

  ; pattern 1
  MOVI r7,0
  LD r1,r10,0
  LD r2,r11,0
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,1
  LD r2,r11,1
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,2
  LD r2,r11,2
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,3
  LD r2,r11,3
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,4
  LD r2,r11,4
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,5
  LD r2,r11,5
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,6
  LD r2,r11,6
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,7
  LD r2,r11,7
  CALL @mth_q16_mul
  ADD r7,r7,r1
  CMPS r7,r9
  JMP[LE] @mth_hop_p2
  ADD r9,r7,r0
  MOVI r8,1
mth_hop_p2:
  ADDI r11,r11,8

  ; pattern 2
  MOVI r7,0
  LD r1,r10,0
  LD r2,r11,0
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,1
  LD r2,r11,1
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,2
  LD r2,r11,2
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,3
  LD r2,r11,3
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,4
  LD r2,r11,4
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,5
  LD r2,r11,5
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,6
  LD r2,r11,6
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,7
  LD r2,r11,7
  CALL @mth_q16_mul
  ADD r7,r7,r1
  CMPS r7,r9
  JMP[LE] @mth_hop_p3
  ADD r9,r7,r0
  MOVI r8,2
mth_hop_p3:
  ADDI r11,r11,8

  ; pattern 3
  MOVI r7,0
  LD r1,r10,0
  LD r2,r11,0
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,1
  LD r2,r11,1
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,2
  LD r2,r11,2
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,3
  LD r2,r11,3
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,4
  LD r2,r11,4
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,5
  LD r2,r11,5
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,6
  LD r2,r11,6
  CALL @mth_q16_mul
  ADD r7,r7,r1
  LD r1,r10,7
  LD r2,r11,7
  CALL @mth_q16_mul
  ADD r7,r7,r1
  CMPS r7,r9
  JMP[LE] @mth_hop_out
  ADD r9,r7,r0
  MOVI r8,3

mth_hop_out:
  ADD r1,r8,r0
  ADD r2,r9,r0
  MOVI r13,1
  MOVI r12,@mth_hop_link
  LD r15,r12,0
  RET

mth_hop_link:
  .word 0
