; Raw NaN16 contextual sense step over the shared encoder.
; Candidate exact synset heads/biases and the shared encoder are trained by
; softmax CE and its local encoder gradient.
;
; Memory:
;   candidate heads K x 8 at 0x8800, biases at 0x8900 (K<=8)
;   K 0x4003, target index 0x8783, learning rate 0x8782
;   command 42; returns r1=target probability, r2=loss
mth_sense_step24:
  MOVI r12,@mth_ss24_link
  ST r15,r12,0
  CALL @mth_context_encode24

  MOVI r10,0x4003
  LD r3,r10,0
  MOVI r4,0
  MOVI r14,0
mth_ss24_logits:
  CMP r4,r3
  JMP[GE] @mth_ss24_softmax
  MOVI r10,24
  MUL r10,r4,r10
  MOVI r11,0x8800
  ADD r11,r11,r10
  MOVI r12,0
  MOVI r6,0
mth_ss24_dot:
  MOVI r7,24
  CMP r6,r7
  JMP[GE] @mth_ss24_store_logit
  ADD r7,r11,r6
  LD r7,r7,0
  MOVI r12,0x8740
  ADD r12,r12,r6
  LD r12,r12,0
  FMUL r7,r7,r12
  FADD r14,r14,r7
  ADDI r6,r6,1
  JMP @mth_ss24_dot
mth_ss24_store_logit:
  MOVI r10,0x8900
  ADD r10,r10,r4
  LD r10,r10,0
  FADD r14,r14,r10
  MOVI r10,0x8980
  ADD r10,r10,r4
  ST r14,r10,0
  ADDI r4,r4,1
  JMP @mth_ss24_logits

mth_ss24_softmax:
  MOVI r4,0
  MOVI r5,0
mth_ss24_exp:
  CMP r4,r3
  JMP[GE] @mth_ss24_norm
  MOVI r10,0x8980
  ADD r10,r10,r4
  LD r1,r10,0
  FEXP r1,r1
  ST r1,r10,0
  FADD r5,r5,r1
  ADDI r4,r4,1
  JMP @mth_ss24_exp
mth_ss24_norm:
  MOVI r4,0
mth_ss24_norm_loop:
  CMP r4,r3
  JMP[GE] @mth_ss24_update
  MOVI r10,0x8980
  ADD r10,r10,r4
  LD r1,r10,0
  FDIV r1,r1,r5
  ST r1,r10,0
  ADDI r4,r4,1
  JMP @mth_ss24_norm_loop

mth_ss24_update:
  ; dh[d] = (1-h^2) * sum_k (p_k-y_k) * head[k][d]
  MOVI r4,0
mth_ss24_dh_zero:
  MOVI r5,24
  CMP r4,r5
  JMP[GE] @mth_ss24_dh_k
  MOVI r10,0x87A0
  ADD r10,r10,r4
  ST r0,r10,0
  ADDI r4,r4,1
  JMP @mth_ss24_dh_zero
mth_ss24_dh_k:
  MOVI r4,0
mth_ss24_dh_k_loop:
  MOVI r5,0x4003
  LD r5,r5,0
  CMP r4,r5
  JMP[GE] @mth_ss24_dh_tanh
  MOVI r10,0x8980
  ADD r10,r10,r4
  LD r7,r10,0
  MOVI r10,0x8783
  LD r6,r10,0
  CMP r4,r6
  JMP[NE] @mth_ss24_dh_diff
  MOVI r10,0
  MOVHI r10,0x3F80
  FSUB r7,r7,r10
mth_ss24_dh_diff:
  MOVI r10,24
  MUL r10,r4,r10
  MOVI r11,0x8800
  ADD r11,r11,r10
  MOVI r6,0
mth_ss24_dh_d:
  MOVI r5,24
  CMP r6,r5
  JMP[GE] @mth_ss24_dh_next_k
  ADD r8,r11,r6
  LD r8,r8,0
  FMUL r8,r8,r7
  MOVI r10,0x87A0
  ADD r10,r10,r6
  LD r9,r10,0
  FADD r9,r9,r8
  ST r9,r10,0
  ADDI r6,r6,1
  JMP @mth_ss24_dh_d
mth_ss24_dh_next_k:
  ADDI r4,r4,1
  JMP @mth_ss24_dh_k_loop
mth_ss24_dh_tanh:
  MOVI r4,0
mth_ss24_dh_tanh_loop:
  MOVI r5,24
  CMP r4,r5
  JMP[GE] @mth_ss24_update_heads
  MOVI r10,0x8740
  ADD r10,r10,r4
  LD r5,r10,0
  FMUL r5,r5,r5
  MOVI r6,0
  MOVHI r6,0x3F80
  FSUB r5,r6,r5
  MOVI r10,0x87A0
  ADD r10,r10,r4
  LD r6,r10,0
  FMUL r6,r6,r5
  ST r6,r10,0
  ADDI r4,r4,1
  JMP @mth_ss24_dh_tanh_loop
mth_ss24_update_heads:
  MOVI r10,0x8783
  LD r6,r10,0
  MOVI r4,0
mth_ss24_update_k:
  CMP r4,r3
  JMP[GE] @mth_ss24_encoder
  MOVI r10,0x8980
  ADD r10,r10,r4
  LD r7,r10,0
  MOVI r10,0x8783
  LD r6,r10,0
  CMP r4,r6
  JMP[NE] @mth_ss24_no_target
  MOVI r10,0
  MOVHI r10,0x3F80
  FSUB r7,r7,r10
mth_ss24_no_target:
  MOVI r10,24
  MUL r10,r4,r10
  MOVI r11,0x8800
  ADD r11,r11,r10
  MOVI r6,0
mth_ss24_head_d:
  MOVI r8,24
  CMP r6,r8
  JMP[GE] @mth_ss24_bias
  ADD r8,r11,r6
  LD r9,r8,0
  MOVI r12,0x8740
  ADD r12,r12,r6
  LD r12,r12,0
  MOVI r10,0x8782
  LD r10,r10,0
  FMUL r12,r12,r10
  FMUL r12,r12,r7
  FSUB r9,r9,r12
  ST r9,r8,0
  ADDI r6,r6,1
  JMP @mth_ss24_head_d
mth_ss24_bias:
  MOVI r10,0x8900
  ADD r10,r10,r4
  LD r9,r10,0
  ; bias -= lr*(p-y)
  MOVI r12,0x8900
  ADD r12,r12,r4
  LD r9,r12,0
  MOVI r11,0x8782
  LD r11,r11,0
  FMUL r11,r11,r7
  FSUB r9,r9,r11
  ST r9,r12,0
  ADDI r4,r4,1
  JMP @mth_ss24_update_k
mth_ss24_encoder:
  MOVI r10,@mth_ss24_i
  ST r0,r10,0
mth_ss24_token:
  MOVI r10,0x4001
  LD r3,r10,0
  MOVI r10,@mth_ss24_i
  LD r4,r10,0
  CMP r4,r3
  JMP[GE] @mth_ss24_bias_ctx
  MOVI r10,0x7000
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r10,0x7400
  ADD r10,r10,r4
  LD r6,r10,0
  MOVI r10,@mth_ss24_tok
  ST r5,r10,0
  MOVI r10,@mth_ss24_slot
  ST r6,r10,0
  MOVI r7,0
mth_ss24_token_d:
  MOVI r8,24
  CMP r7,r8
  JMP[GE] @mth_ss24_token_next
  MOVI r10,@mth_ss24_tok
  LD r9,r10,0
  MOVI r10,24
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r11,0x8000
  ADD r11,r11,r9
  LD r12,r11,0
  MOVI r10,@mth_ss24_slot
  LD r9,r10,0
  MOVI r10,24
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r10,0x8600
  ADD r10,r10,r9
  LD r14,r10,0
  MOVI r9,0x87A0
  ADD r9,r9,r7
  LD r13,r9,0
  MOVI r9,@mth_ce24_norm
  LD r9,r9,0
  FMUL r13,r13,r9
  MOVI r9,0x8782
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
  JMP @mth_ss24_token_d
mth_ss24_token_next:
  MOVI r10,@mth_ss24_i
  LD r4,r10,0
  ADDI r4,r4,1
  ST r4,r10,0
  JMP @mth_ss24_token
mth_ss24_bias_ctx:
  MOVI r4,0
mth_ss24_bias_ctx_loop:
  MOVI r5,24
  CMP r4,r5
  JMP[GE] @mth_ss24_order_ctx
  MOVI r10,0x8700
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r6,0x87A0
  ADD r6,r6,r4
  LD r6,r6,0
  MOVI r7,0x8782
  LD r7,r7,0
  FMUL r6,r6,r7
  FSUB r5,r5,r6
  ST r5,r10,0
  ADDI r4,r4,1
  JMP @mth_ss24_bias_ctx_loop
mth_ss24_order_ctx:
  MOVI r4,0
mth_ss24_order_ctx_loop:
  MOVI r5,24
  CMP r4,r5
  JMP[GE] @mth_ss24_out
  MOVI r10,0x8720
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r6,0x87A0
  ADD r6,r6,r4
  LD r6,r6,0
  MOVI r7,0x8782
  LD r7,r7,0
  FMUL r6,r6,r7
  MOVI r7,0x4002
  LD r7,r7,0
  FMUL r6,r6,r7
  FSUB r5,r5,r6
  ST r5,r10,0
  ADDI r4,r4,1
  JMP @mth_ss24_order_ctx_loop
mth_ss24_out:
  MOVI r10,0x8980
  MOVI r11,0x8783
  LD r11,r11,0
  ADD r10,r10,r11
  LD r1,r10,0
  MOVI r2,0
  ; loss = -log(p_target): approximate via FLOG
  FLOG r2,r1
  SUB r2,r0,r2
  MOVI r13,1
  MOVI r12,@mth_ss24_link
  LD r15,r12,0
  RET
mth_ss24_link:
  .word 0
mth_ss24_i:
  .word 0
mth_ss24_tok:
  .word 0
mth_ss24_slot:
  .word 0
