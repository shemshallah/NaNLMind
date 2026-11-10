; Raw NaN16 contextual role step: shared encoder + sigmoid + encoder gradients.
;
; Memory:
;   encoder state per mth_context_encode
;   relation vector 0x8760[8], relation bias 0x8780
;   label 0x8781, learning rate 0x8782, dh 0x87A0[8]
;   command 41; returns r1=p, r2=delta.
mth_role_step24:
  MOVI r12,@mth_rs24_link
  ST r15,r12,0
  CALL @mth_context_encode24

  MOVI r10,0x8780
  LD r14,r10,0
  MOVI r10,0
mth_rs24_score:
  MOVI r11,24
  CMP r10,r11
  JMP[GE] @mth_rs24_prob
  MOVI r11,0x8760
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r11,0x8740
  ADD r11,r11,r10
  LD r13,r11,0
  FMUL r12,r12,r13
  FADD r14,r14,r12
  ADDI r10,r10,1
  JMP @mth_rs24_score
mth_rs24_prob:
  ADD r1,r14,r0
  MOVI r2,0
  FSUB r2,r2,r1
  FEXP r2,r2
  MOVI r3,0
  MOVHI r3,0x3F80
  FADD r2,r2,r3
  FDIV r1,r3,r2
  MOVI r12,@mth_rs24_p
  ST r1,r12,0
  MOVI r10,0x8781
  LD r2,r10,0
  FSUB r3,r1,r2
  MOVI r12,@mth_rs24_delta
  ST r3,r12,0

  ; dh[d] = delta*rel[d]*(1-h^2)
  MOVI r10,0
mth_rs24_dh:
  MOVI r11,24
  CMP r10,r11
  JMP[GE] @mth_rs24_rel
  MOVI r11,0x8760
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r11,0x8740
  ADD r11,r11,r10
  LD r13,r11,0
  FMUL r13,r13,r13
  MOVI r11,0
  MOVHI r11,0x3F80
  FSUB r13,r11,r13
  FMUL r12,r12,r13
  MOVI r13,@mth_rs24_delta
  LD r13,r13,0
  FMUL r12,r12,r13
  MOVI r11,0x87A0
  ADD r11,r11,r10
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs24_dh

  ; rel[d] -= lr*delta*h[d]
mth_rs24_rel:
  MOVI r10,0
mth_rs24_rel_loop:
  MOVI r11,24
  CMP r10,r11
  JMP[GE] @mth_rs24_rb
  MOVI r11,0x8760
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r13,0x8740
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,@mth_rs24_delta
  LD r14,r14,0
  FMUL r13,r13,r14
  MOVI r14,0x8782
  LD r14,r14,0
  FMUL r13,r13,r14
  FSUB r12,r12,r13
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs24_rel_loop
mth_rs24_rb:
  MOVI r10,0x8780
  LD r11,r10,0
  MOVI r12,@mth_rs24_delta
  LD r12,r12,0
  MOVI r13,0x8782
  LD r13,r13,0
  FMUL r12,r12,r13
  FSUB r11,r11,r12
  ST r11,r10,0

  ; Update token embeddings and position gates through dh.
  MOVI r10,@mth_rs24_i
  ST r0,r10,0
mth_rs24_token:
  MOVI r10,0x4001
  LD r3,r10,0
  MOVI r10,@mth_rs24_i
  LD r4,r10,0
  CMP r4,r3
  JMP[GE] @mth_rs24_bias
  MOVI r10,0x7000
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r10,0x7400
  ADD r10,r10,r4
  LD r6,r10,0
  MOVI r10,@mth_rs24_tok
  ST r5,r10,0
  MOVI r10,@mth_rs24_slot
  ST r6,r10,0
  MOVI r7,0
mth_rs24_token_d:
  MOVI r8,24
  CMP r7,r8
  JMP[GE] @mth_rs24_next
  MOVI r10,@mth_rs24_tok
  LD r9,r10,0
  MOVI r10,24
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r11,0x8000
  ADD r11,r11,r9
  LD r12,r11,0            ; old embedding
  MOVI r10,@mth_rs24_slot
  LD r9,r10,0
  MOVI r10,24
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r10,0x8600
  ADD r10,r10,r9
  LD r14,r10,0            ; old gate
  MOVI r9,0x87A0
  ADD r9,r9,r7
  LD r13,r9,0             ; dh
  MOVI r9,@mth_ce24_norm
  LD r9,r9,0
  FMUL r13,r13,r9
  MOVI r9,0x8782
  LD r9,r9,0
  FMUL r13,r13,r9         ; step = lr*dh*norm
  ; e_new = old_e - step*old_gate
  FMUL r9,r13,r14
  ADD r8,r12,r0
  FSUB r8,r8,r9
  ST r8,r11,0
  ; gate_new = old_gate - step*old_e
  FMUL r9,r13,r12
  FSUB r14,r14,r9
  ST r14,r10,0
  ADDI r7,r7,1
  JMP @mth_rs24_token_d
mth_rs24_next:
  MOVI r10,@mth_rs24_i
  LD r4,r10,0
  ADDI r4,r4,1
  ST r4,r10,0
  JMP @mth_rs24_token

mth_rs24_bias:
  MOVI r10,0
mth_rs24_bias_loop:
  MOVI r11,24
  CMP r10,r11
  JMP[GE] @mth_rs24_order
  MOVI r11,0x8700
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r13,0x87A0
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,0x8782
  LD r14,r14,0
  FMUL r13,r13,r14
  FSUB r12,r12,r13
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs24_bias_loop
mth_rs24_order:
  MOVI r10,0
mth_rs24_order_loop:
  MOVI r11,24
  CMP r10,r11
  JMP[GE] @mth_rs24_done
  MOVI r11,0x8720
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r13,0x87A0
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,0x8782
  LD r14,r14,0
  FMUL r13,r13,r14
  MOVI r14,0x4002
  LD r14,r14,0
  FMUL r13,r13,r14
  FSUB r12,r12,r13
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs24_order_loop
mth_rs24_done:
  MOVI r12,@mth_rs24_p
  LD r1,r12,0
  MOVI r12,@mth_rs24_delta
  LD r2,r12,0
  MOVI r13,1
  MOVI r12,@mth_rs24_link
  LD r15,r12,0
  RET
mth_rs24_link:
  .word 0
mth_rs24_p:
  .word 0
mth_rs24_delta:
  .word 0
mth_rs24_i:
  .word 0
mth_rs24_tok:
  .word 0
mth_rs24_slot:
  .word 0
