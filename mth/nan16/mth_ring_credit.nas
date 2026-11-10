; NaN16 RING angular correlation over the 255-lane ring.
; ABI: r1=phase[255] pointer, r2=shift (0..254).
; Returns r1=average cos(phase[h]-phase[(h+shift)%255]) Q16.16.
mth_ring_credit:
  MOVI r12,@mth_ring_link
  ST r15,r12,0
  ADD r10,r1,r0
  ADD r11,r2,r0
  MOVI r12,0
  MOVI r14,0
mth_ring_loop:
  MOVI r5,255
  CMP r12,r5
  JMP[GE] @mth_ring_done
  ADD r5,r10,r12
  LD r1,r5,0
  ADD r6,r12,r11
  MOVI r5,255
  MODU r6,r6,r5
  ADD r5,r10,r6
  LD r2,r5,0
  SUB r1,r1,r2
  CALL @mth_q16_sin_cos
  ADD r14,r14,r1
  ADDI r12,r12,1
  JMP @mth_ring_loop
mth_ring_done:
  MOVI r5,255
  DIV r1,r14,r5
  MOVI r13,1
  MOVI r12,@mth_ring_link
  LD r15,r12,0
  RET
mth_ring_link:
  .word 0
