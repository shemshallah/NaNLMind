; Raw NaN16 one-step candidate-vector readout trainer.
;
; ABI:
;   r1 = state f32[128]
;   r2 = candidate vectors f32[N][128], row-major, updated in place
;   r3 = output probabilities f32[N]
;   r4 = N 1..64
;   r5 = target index 0..N-1
;   r6 = learning-rate f32 bits
; Returns r1=1, r2=loss f32 bits, r3=predicted index, r4=0.
; Rejection r1=0,r4=1.
;
; The guest computes all scores, softmax, cross-entropy and the SGD update.
; The host only transports the state/candidates and reads the updated bytes.
mth_head_state_readout_train:
  MOVI r0,0
  ST r15,r0,@hstr_link
  ST r1,r0,@hstr_state
  ST r2,r0,@hstr_cand
  ST r3,r0,@hstr_out
  ST r4,r0,@hstr_n
  ST r5,r0,@hstr_target
  ST r6,r0,@hstr_lr
  CMP r1,r0
  JMP[EQ] @hstr_bad
  CMP r2,r0
  JMP[EQ] @hstr_bad
  CMP r3,r0
  JMP[EQ] @hstr_bad
  CMP r4,r0
  JMP[EQ] @hstr_bad
  MOVI r7,64
  CMP r4,r7
  JMP[GT] @hstr_bad
  CMP r5,r4
  JMP[GE] @hstr_bad

  ; scores[n] = dot(state, candidate[n]); track max and argmax.
  MOVI r5,0
  ST r5,r0,@hstr_i
  MOVI r5,0
  ST r5,r0,@hstr_pred
  MOVI r5,0
  MOVHI r5,0xFF80
  ST r5,r0,@hstr_max
hstr_row:
  LD r5,r0,@hstr_i
  LD r6,r0,@hstr_n
  CMP r5,r6
  JMP[GE] @hstr_scores_done
  MOVI r7,128
  MUL r7,r5,r7
  LD r8,r0,@hstr_cand
  ADD r8,r8,r7
  MOVI r9,0
  MOVI r10,0
hstr_col:
  MOVI r11,128
  CMP r9,r11
  JMP[GE] @hstr_store
  LD r11,r0,@hstr_state
  ADD r11,r11,r9
  LD r11,r11,0
  ADD r12,r8,r9
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r10,r10,r11
  ADDI r9,r9,1
  JMP @hstr_col
hstr_store:
  LD r11,r0,@hstr_out
  ADD r11,r11,r5
  ST r10,r11,0
  MOVI r12,@hstr_max
  LD r13,r12,0
  FCMP r10,r13
  JMP[LE] @hstr_next
  ST r10,r12,0
  ST r5,r0,@hstr_pred
hstr_next:
  LD r5,r0,@hstr_i
  ADDI r5,r5,1
  ST r5,r0,@hstr_i
  JMP @hstr_row
hstr_scores_done:

  ; probabilities = softmax(scores)
  MOVI r5,0
  ST r5,r0,@hstr_i
  MOVI r5,0
  ST r5,r0,@hstr_sum
hstr_exp:
  LD r5,r0,@hstr_i
  LD r6,r0,@hstr_n
  CMP r5,r6
  JMP[GE] @hstr_exp_done
  LD r7,r0,@hstr_out
  ADD r7,r7,r5
  LD r8,r7,0
  MOVI r9,@hstr_max
  LD r9,r9,0
  FSUB r8,r8,r9
  FEXP r8,r8
  ST r8,r7,0
  MOVI r9,@hstr_sum
  LD r10,r9,0
  FADD r10,r10,r8
  ST r10,r9,0
  ADDI r5,r5,1
  ST r5,r0,@hstr_i
  JMP @hstr_exp
hstr_exp_done:
  MOVI r5,0
  ST r5,r0,@hstr_i
hstr_norm:
  LD r5,r0,@hstr_i
  LD r6,r0,@hstr_n
  CMP r5,r6
  JMP[GE] @hstr_norm_done
  LD r7,r0,@hstr_out
  ADD r7,r7,r5
  LD r8,r7,0
  MOVI r9,@hstr_sum
  LD r9,r9,0
  FDIV r8,r8,r9
  ST r8,r7,0
  ADDI r5,r5,1
  ST r5,r0,@hstr_i
  JMP @hstr_norm
hstr_norm_done:

  ; loss = -log(prob[target])
  LD r5,r0,@hstr_target
  LD r7,r0,@hstr_out
  ADD r7,r7,r5
  LD r8,r7,0
  FLOG r8,r8
  MOVI r9,0
  FSUB r8,r9,r8
  ST r8,r0,@hstr_loss

  ; SGD: candidate[n] -= lr * (p[n] - [n==target]) * state
  MOVI r5,0
  ST r5,r0,@hstr_i
hstr_update_row:
  LD r5,r0,@hstr_i
  LD r6,r0,@hstr_n
  CMP r5,r6
  JMP[GE] @hstr_ok
  LD r7,r0,@hstr_out
  ADD r7,r7,r5
  LD r7,r7,0
  LD r8,r0,@hstr_target
  CMP r5,r8
  JMP[NE] @hstr_grad_ready
  MOVI r9,0
  MOVHI r9,0x3F80
  FSUB r7,r7,r9
hstr_grad_ready:
  LD r8,r0,@hstr_lr
  FMUL r7,r7,r8
  ST r7,r0,@hstr_scale
  MOVI r9,128
  MUL r9,r5,r9
  LD r10,r0,@hstr_cand
  ADD r10,r10,r9
  MOVI r9,0
hstr_update_d:
  MOVI r11,128
  CMP r9,r11
  JMP[GE] @hstr_update_next
  LD r11,r0,@hstr_state
  ADD r11,r11,r9
  LD r11,r11,0
  LD r12,r0,@hstr_scale
  FMUL r11,r11,r12
  ADD r12,r10,r9
  LD r13,r12,0
  FSUB r13,r13,r11
  ST r13,r12,0
  ADDI r9,r9,1
  JMP @hstr_update_d
hstr_update_next:
  LD r5,r0,@hstr_i
  ADDI r5,r5,1
  ST r5,r0,@hstr_i
  JMP @hstr_update_row

hstr_ok:
  MOVI r1,1
  LD r2,r0,@hstr_loss
  LD r3,r0,@hstr_pred
  MOVI r4,0
  LD r15,r0,@hstr_link
  RET
hstr_bad:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r4,1
  LD r15,r0,@hstr_link
  RET

hstr_link:
  .word 0
hstr_state:
  .word 0
hstr_cand:
  .word 0
hstr_out:
  .word 0
hstr_n:
  .word 0
hstr_target:
  .word 0
hstr_lr:
  .word 0
hstr_i:
  .word 0
hstr_pred:
  .word 0
hstr_max:
  .word 0
hstr_sum:
  .word 0
hstr_loss:
  .word 0
hstr_scale:
  .word 0
