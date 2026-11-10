; Raw NaN16 contextual role step over the shared encoder.
; The shared contextual encoder is frozen in this first native slice; the
; relation head is trained by sigmoid cross-entropy in the guest.
;
; Memory:
;   encoder state per mth_context_encode
;   relation vector 0x7500[8], relation bias 0x7520
;   label 0x7521, learning rate 0x7522, command 41
; Returns r1=p, r2=delta.
mth_role_step:
  MOVI r12,@mth_rs_link
  ST r15,r12,0
  CALL @mth_context_encode

  MOVI r10,0x7520
  LD r14,r10,0
  MOVI r10,0
mth_rs_score:
  MOVI r11,8
  CMP r10,r11
  JMP[GE] @mth_rs_prob
  MOVI r11,0x7500
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r11,0x73A0
  ADD r11,r11,r10
  LD r13,r11,0
  FMUL r12,r12,r13
  FADD r14,r14,r12
  ADDI r10,r10,1
  JMP @mth_rs_score
mth_rs_prob:
  ADD r1,r14,r0
  MOVI r2,0
  FSUB r2,r2,r1
  FEXP r2,r2
  MOVI r3,0
  MOVHI r3,0x3F80
  FADD r2,r2,r3
  FDIV r1,r3,r2
  MOVI r12,@mth_rs_p
  ST r1,r12,0
  MOVI r10,0x7521
  LD r2,r10,0
  FSUB r3,r1,r2
  MOVI r12,@mth_rs_delta
  ST r3,r12,0

  ; rel[d] -= lr*delta*h[d]
  MOVI r10,0
mth_rs_rel:
  MOVI r11,8
  CMP r10,r11
  JMP[GE] @mth_rs_bias
  MOVI r11,0x7500
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r13,0x73A0
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,@mth_rs_delta
  LD r14,r14,0
  FMUL r13,r13,r14
  MOVI r14,0x7522
  LD r14,r14,0
  FMUL r13,r13,r14
  FSUB r12,r12,r13
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs_rel
mth_rs_bias:
  MOVI r10,0x7520
  LD r11,r10,0
  MOVI r12,@mth_rs_delta
  LD r12,r12,0
  MOVI r13,0x7522
  LD r13,r13,0
  FMUL r12,r12,r13
  FSUB r11,r11,r12
  ST r11,r10,0
  MOVI r12,@mth_rs_p
  LD r1,r12,0
  MOVI r12,@mth_rs_delta
  LD r2,r12,0
  MOVI r13,1
  MOVI r12,@mth_rs_link
  LD r15,r12,0
  RET
mth_rs_link:
  .word 0
mth_rs_p:
  .word 0
mth_rs_delta:
  .word 0
