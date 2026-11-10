; Raw NaN16 contextual sense step over the shared encoder.
; Candidate exact synset heads/biases and the shared encoder are trained by
; softmax CE and its local encoder gradient.
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
  ; dh[d] = (1-h^2) * sum_k (p_k-y_k) * head[k][d]
  MOVI r4,0
mth_ss_dh_zero:
  MOVI r5,8
  CMP r4,r5
  JMP[GE] @mth_ss_dh_k
  MOVI r10,0x7540
  ADD r10,r10,r4
  ST r0,r10,0
  ADDI r4,r4,1
  JMP @mth_ss_dh_zero
mth_ss_dh_k:
  MOVI r4,0
mth_ss_dh_k_loop:
  MOVI r5,0x4003
  LD r5,r5,0
  CMP r4,r5
  JMP[GE] @mth_ss_dh_tanh
  MOVI r10,0x7800
  ADD r10,r10,r4
  LD r7,r10,0
  MOVI r10,0x7523
  LD r6,r10,0
  CMP r4,r6
  JMP[NE] @mth_ss_dh_diff
  MOVI r10,0
  MOVHI r10,0x3F80
  FSUB r7,r7,r10
mth_ss_dh_diff:
  MOVI r10,8
  MUL r10,r4,r10
  MOVI r11,0x7600
  ADD r11,r11,r10
  MOVI r6,0
mth_ss_dh_d:
  MOVI r5,8
  CMP r6,r5
  JMP[GE] @mth_ss_dh_next_k
  ADD r8,r11,r6
  LD r8,r8,0
  FMUL r8,r8,r7
  MOVI r10,0x7540
  ADD r10,r10,r6
  LD r9,r10,0
  FADD r9,r9,r8
  ST r9,r10,0
  ADDI r6,r6,1
  JMP @mth_ss_dh_d
mth_ss_dh_next_k:
  ADDI r4,r4,1
  JMP @mth_ss_dh_k_loop
mth_ss_dh_tanh:
  MOVI r4,0
mth_ss_dh_tanh_loop:
  MOVI r5,8
  CMP r4,r5
  JMP[GE] @mth_ss_update_heads
  MOVI r10,0x73A0
  ADD r10,r10,r4
  LD r5,r10,0
  FMUL r5,r5,r5
  MOVI r6,0
  MOVHI r6,0x3F80
  FSUB r5,r6,r5
  MOVI r10,0x7540
  ADD r10,r10,r4
  LD r6,r10,0
  FMUL r6,r6,r5
  ST r6,r10,0
  ADDI r4,r4,1
  JMP @mth_ss_dh_tanh_loop
mth_ss_update_heads:
  MOVI r10,0x7523
  LD r6,r10,0
  MOVI r4,0
mth_ss_update_k:
  CMP r4,r3
  JMP[GE] @mth_ss_encoder
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
mth_ss_encoder:
  MOVI r10,@mth_ss_i
  ST r0,r10,0
mth_ss_token:
  MOVI r10,0x4001
  LD r3,r10,0
  MOVI r10,@mth_ss_i
  LD r4,r10,0
  CMP r4,r3
  JMP[GE] @mth_ss_bias_ctx
  MOVI r10,0x7000
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r10,0x7400
  ADD r10,r10,r4
  LD r6,r10,0
  MOVI r10,@mth_ss_tok
  ST r5,r10,0
  MOVI r10,@mth_ss_slot
  ST r6,r10,0
  MOVI r7,0
mth_ss_token_d:
  MOVI r8,8
  CMP r7,r8
  JMP[GE] @mth_ss_token_next
  MOVI r10,@mth_ss_tok
  LD r9,r10,0
  MOVI r10,8
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r11,0x7100
  ADD r11,r11,r9
  LD r12,r11,0
  MOVI r10,@mth_ss_slot
  LD r9,r10,0
  MOVI r10,8
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r10,0x7300
  ADD r10,r10,r9
  LD r14,r10,0
  MOVI r9,0x7540
  ADD r9,r9,r7
  LD r13,r9,0
  MOVI r9,@mth_ce_norm
  LD r9,r9,0
  FMUL r13,r13,r9
  MOVI r9,0x7522
  LD r9,r9,0
  FMUL r13,r13,r9
  FMUL r9,r13,r14
  ADD r8,r12,r0
  FSUB r8,r8,r9
  ST r8,r11,0
  FMUL r9,r13,r12
  FSUB r14,r14,r9
  ST r14,r10,0
  ADDI r7,r7,1
  JMP @mth_ss_token_d
mth_ss_token_next:
  MOVI r10,@mth_ss_i
  LD r4,r10,0
  ADDI r4,r4,1
  ST r4,r10,0
  JMP @mth_ss_token
mth_ss_bias_ctx:
  MOVI r4,0
mth_ss_bias_ctx_loop:
  MOVI r5,8
  CMP r4,r5
  JMP[GE] @mth_ss_order_ctx
  MOVI r10,0x7380
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r6,0x7540
  ADD r6,r6,r4
  LD r6,r6,0
  MOVI r7,0x7522
  LD r7,r7,0
  FMUL r6,r6,r7
  FSUB r5,r5,r6
  ST r5,r10,0
  ADDI r4,r4,1
  JMP @mth_ss_bias_ctx_loop
mth_ss_order_ctx:
  MOVI r4,0
mth_ss_order_ctx_loop:
  MOVI r5,8
  CMP r4,r5
  JMP[GE] @mth_ss_out
  MOVI r10,0x7390
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r6,0x7540
  ADD r6,r6,r4
  LD r6,r6,0
  MOVI r7,0x7522
  LD r7,r7,0
  FMUL r6,r6,r7
  MOVI r7,0x4002
  LD r7,r7,0
  FMUL r6,r6,r7
  FSUB r5,r5,r6
  ST r5,r10,0
  ADDI r4,r4,1
  JMP @mth_ss_order_ctx_loop
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
mth_ss_i:
  .word 0
mth_ss_tok:
  .word 0
mth_ss_slot:
  .word 0
