; NaN16 credit combination: sum_i coefficient_i * credit_i.
; ABI: r1=credits pointer[7], r2=coefficients pointer[7].
; Returns r1=combined Q16.16 credit.
mth_credit_combine:
  MOVI r12,@mth_cc_link
  ST r15,r12,0
  ADD r10,r1,r0
  ADD r11,r2,r0
  MOVI r12,0
  MOVI r14,0
mth_cc_loop:
  MOVI r5,7
  CMP r12,r5
  JMP[GE] @mth_cc_done
  ADD r5,r10,r12
  LD r1,r5,0
  ADD r5,r11,r12
  LD r2,r5,0
  CALL @mth_q16_mul
  ADD r14,r14,r1
  ADDI r12,r12,1
  JMP @mth_cc_loop
mth_cc_done:
  ADD r1,r14,r0
  MOVI r13,1
  MOVI r12,@mth_cc_link
  LD r15,r12,0
  RET
mth_cc_link:
  .word 0
