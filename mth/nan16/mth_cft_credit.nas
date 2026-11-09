; NaN16 cycle-flux credit for one triangle.
;
; ABI:
;   r1 = E(a,b), r2 = E(b,c), r3 = E(c,a) in Q16.16
;   r4 = local error in Q16.16 (non-negative in this first slice)
;   r5 = rate in Q16.16 (non-negative in this first slice)
; Returns:
;   r1,r2,r3 = updated edge energies
;   r4 = signed residual E(a,b)+E(b,c)+E(c,a)
;
; The three edge updates change the triangle circulation by the proposed
; delta: +delta, +delta, -delta. This is local credit, not a BPTT tape.
mth_cft_credit:
  MOVI r9,@mth_cft_link
  ST r15,r9,0
  ADD r10,r1,r0
  ADD r11,r2,r0
  ADD r12,r3,r0
  ADD r13,r4,r0
  ADD r14,r5,r0
  ADD r1,r13,r0
  ADD r2,r14,r0
  CALL @mth_q16_mul
  MOVI r7,3
  DIV r6,r1,r7
  ADD r10,r10,r6
  ADD r11,r11,r6
  SUB r12,r12,r6
  ADD r4,r10,r11
  ADD r4,r4,r12
  ADD r1,r10,r0
  ADD r2,r11,r0
  ADD r3,r12,r0
  MOVI r13,1
  MOVI r9,@mth_cft_link
  LD r15,r9,0
  RET

mth_cft_link:
  .word 0
