; NaN16 FLUX temporal-link divergence credit.
; ABI: r1=phi_u, r2=phi_v, r3=link weight Q16.16, r4=source Q16.16.
; Returns r1=flow J, r2=divergence D, r3=credit J*D.
mth_flux_credit:
  MOVI r12,@mth_flux_link
  ST r15,r12,0
  ADD r10,r1,r0
  ADD r11,r2,r0
  ADD r12,r3,r0
  ADD r14,r4,r0
  SUB r5,r11,r10
  ADD r1,r12,r0
  ADD r2,r5,r0
  CALL @mth_q16_mul
  ADD r5,r1,r0          ; J
  SUB r6,r5,r14         ; D = J - source
  ADD r1,r5,r0
  ADD r2,r6,r0
  CALL @mth_q16_mul
  ADD r7,r1,r0          ; credit
  ADD r1,r5,r0
  ADD r2,r6,r0
  ADD r3,r7,r0
  MOVI r13,1
  MOVI r12,@mth_flux_link
  LD r15,r12,0
  RET
mth_flux_link:
  .word 0
