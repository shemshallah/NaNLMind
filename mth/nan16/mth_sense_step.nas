; Raw NaN16 contextual sense step over the shared encoder.
; Candidate exact synset heads and biases are trained by softmax CE; the
; shared encoder is frozen in this first native slice.
;
; Memory:
;   candidate heads K x 8 at 0x7600, biases at 0x7700 (K<=8)
;   K 0x4003, target index 0x7523, learning rate 0x7522
;   command 42; returns r1=target probability, r2=loss
mth_sense_step:
  MOVI r12,@mth_ss_link
  ST r15,r12,0
  CALL @mth_context_encode

  MOVI r10,0x4003
  LD r3,r10,0
  MOVI r4,0
  MOVI r14,0
mth_ss_logits:
  CMP r4,r3
  JMP[GE] @mth_ss_softmax
  MOVI r10,8
  MUL r10,r4,r10
  MOVI r11,0x7600
  ADD r11,r11,r10
  MOVI r12,0
  MOVI r6,0
mth_ss_dot:
  MOVI r7,8
  CMP r6,r7
  JMP[GE] @mth_ss_store_logit
  ADD r7,r11,r6
  LD r7,r7,0
  MOVI r12,0x73A0
  ADD r12,r12,r6
  LD r12,r12,0
  FMUL r7,r7,r12
  FADD r14,r14,r7
  ADDI r6,r6,1
  JMP @mth_ss_dot
mth_ss_store_logit:
  MOVI r10,0x7700
  ADD r10,r10,r4
  LD r10,r10,0
  FADD r14,r14,r10
  MOVI r10,0x7800
  ADD r10,r10,r4
  ST r14,r10,0
  ADDI r4,r4,1
  JMP @mth_ss_logits

mth_ss_softmax:
  MOVI r4,0
  MOVI r5,0
mth_ss_exp:
  CMP r4,r3
  JMP[GE] @mth_ss_norm
  MOVI r10,0x7800
  ADD r10,r10,r4
  LD r1,r10,0
  FEXP r1,r1
  ST r1,r10,0
  FADD r5,r5,r1
  ADDI r4,r4,1
  JMP @mth_ss_exp
mth_ss_norm:
  MOVI r4,0
mth_ss_norm_loop:
  CMP r4,r3
  JMP[GE] @mth_ss_update
  MOVI r10,0x7800
  ADD r10,r10,r4
  LD r1,r10,0
  FDIV r1,r1,r5
  ST r1,r10,0
  ADDI r4,r4,1
  JMP @mth_ss_norm_loop

mth_ss_update:
  MOVI r10,0x7523
  LD r6,r10,0
  MOVI r4,0
mth_ss_update_k:
  CMP r4,r3
  JMP[GE] @mth_ss_out
  MOVI r10,0x7800
  ADD r10,r10,r4
  LD r7,r10,0
  MOVI r10,0x7523
  LD r6,r10,0
  CMP r4,r6
  JMP[NE] @mth_ss_no_target
  MOVI r10,0
  MOVHI r10,0x3F80
  FSUB r7,r7,r10
mth_ss_no_target:
  MOVI r10,8
  MUL r10,r4,r10
  MOVI r11,0x7600
  ADD r11,r11,r10
  MOVI r6,0
mth_ss_head_d:
  MOVI r8,8
  CMP r6,r8
  JMP[GE] @mth_ss_bias
  ADD r8,r11,r6
  LD r9,r8,0
  MOVI r12,0x73A0
  ADD r12,r12,r6
  LD r12,r12,0
  MOVI r10,0x7522
  LD r10,r10,0
  FMUL r12,r12,r10
  FMUL r12,r12,r7
  FSUB r9,r9,r12
  ST r9,r8,0
  ADDI r6,r6,1
  JMP @mth_ss_head_d
mth_ss_bias:
  MOVI r10,0x7700
  ADD r10,r10,r4
  LD r9,r10,0
  ; bias -= lr*(p-y)
  MOVI r12,0x7700
  ADD r12,r12,r4
  LD r9,r12,0
  MOVI r11,0x7522
  LD r11,r11,0
  FMUL r11,r11,r7
  FSUB r9,r9,r11
  ST r9,r12,0
  ADDI r4,r4,1
  JMP @mth_ss_update_k
mth_ss_out:
  MOVI r10,0x7800
  MOVI r11,0x7523
  LD r11,r11,0
  ADD r10,r10,r11
  LD r1,r10,0
  MOVI r2,0
  ; loss = -log(p_target): approximate via FLOG
  FLOG r2,r1
  SUB r2,r0,r2
  MOVI r13,1
  MOVI r12,@mth_ss_link
  LD r15,r12,0
  RET
mth_ss_link:
  .word 0
