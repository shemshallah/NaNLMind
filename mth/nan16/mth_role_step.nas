; Raw NaN16 contextual role step: shared encoder + sigmoid + encoder gradients.
;
; Memory:
;   encoder state per mth_context_encode
;   relation vector 0x7500[8], relation bias 0x7520
;   label 0x7521, learning rate 0x7522, dh 0x7540[8]
;   command 41; returns r1=p, r2=delta.
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

  ; dh[d] = delta*rel[d]*(1-h^2)
  MOVI r10,0
mth_rs_dh:
  MOVI r11,8
  CMP r10,r11
  JMP[GE] @mth_rs_rel
  MOVI r11,0x7500
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r11,0x73A0
  ADD r11,r11,r10
  LD r13,r11,0
  FMUL r13,r13,r13
  MOVI r11,0
  MOVHI r11,0x3F80
  FSUB r13,r11,r13
  FMUL r12,r12,r13
  MOVI r13,@mth_rs_delta
  LD r13,r13,0
  FMUL r12,r12,r13
  MOVI r11,0x7540
  ADD r11,r11,r10
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs_dh

  ; rel[d] -= lr*delta*h[d]
mth_rs_rel:
  MOVI r10,0
mth_rs_rel_loop:
  MOVI r11,8
  CMP r10,r11
  JMP[GE] @mth_rs_rb
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
  JMP @mth_rs_rel_loop
mth_rs_rb:
  MOVI r10,0x7520
  LD r11,r10,0
  MOVI r12,@mth_rs_delta
  LD r12,r12,0
  MOVI r13,0x7522
  LD r13,r13,0
  FMUL r12,r12,r13
  FSUB r11,r11,r12
  ST r11,r10,0

  ; Update token embeddings and position gates through dh.
  MOVI r10,@mth_rs_i
  ST r0,r10,0
mth_rs_token:
  MOVI r10,0x4001
  LD r3,r10,0
  MOVI r10,@mth_rs_i
  LD r4,r10,0
  CMP r4,r3
  JMP[GE] @mth_rs_bias
  MOVI r10,0x7000
  ADD r10,r10,r4
  LD r5,r10,0
  MOVI r10,0x7400
  ADD r10,r10,r4
  LD r6,r10,0
  MOVI r10,@mth_rs_tok
  ST r5,r10,0
  MOVI r10,@mth_rs_slot
  ST r6,r10,0
  MOVI r7,0
mth_rs_token_d:
  MOVI r8,8
  CMP r7,r8
  JMP[GE] @mth_rs_next
  MOVI r10,@mth_rs_tok
  LD r9,r10,0
  MOVI r10,8
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r11,0x7100
  ADD r11,r11,r9
  LD r12,r11,0            ; old embedding
  MOVI r10,@mth_rs_slot
  LD r9,r10,0
  MOVI r10,8
  MUL r9,r9,r10
  ADD r9,r9,r7
  MOVI r10,0x7300
  ADD r10,r10,r9
  LD r14,r10,0            ; old gate
  MOVI r9,0x7540
  ADD r9,r9,r7
  LD r13,r9,0             ; dh
  MOVI r9,@mth_ce_norm
  LD r9,r9,0
  FMUL r13,r13,r9
  MOVI r9,0x7522
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
  JMP @mth_rs_token_d
mth_rs_next:
  MOVI r10,@mth_rs_i
  LD r4,r10,0
  ADDI r4,r4,1
  ST r4,r10,0
  JMP @mth_rs_token

mth_rs_bias:
  MOVI r10,0
mth_rs_bias_loop:
  MOVI r11,8
  CMP r10,r11
  JMP[GE] @mth_rs_order
  MOVI r11,0x7380
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r13,0x7540
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,0x7522
  LD r14,r14,0
  FMUL r13,r13,r14
  FSUB r12,r12,r13
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs_bias_loop
mth_rs_order:
  MOVI r10,0
mth_rs_order_loop:
  MOVI r11,8
  CMP r10,r11
  JMP[GE] @mth_rs_done
  MOVI r11,0x7390
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r13,0x7540
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,0x7522
  LD r14,r14,0
  FMUL r13,r13,r14
  MOVI r14,0x4002
  LD r14,r14,0
  FMUL r13,r13,r14
  FSUB r12,r12,r13
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_rs_order_loop
mth_rs_done:
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
mth_rs_i:
  .word 0
mth_rs_tok:
  .word 0
mth_rs_slot:
  .word 0
