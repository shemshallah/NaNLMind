; Raw NaN16 generic 16-class softmax head.
;
; ABI:
;   r1 = feature pointer
;   r2 = weight pointer (16 x D float32)
;   r3 = D
;   r4 = target class (0..15)
;   r5 = learning-rate float32 bits (0 disables updates)
; Returns:
;   r1 = argmax class
;   r2 = cross-entropy loss bits
;   r3 = 1 when argmax == target
;
; Scratch probabilities/logits live at 0x30000[16]. The caller owns the
; feature and weight storage. This is a local full-softmax step, not BPTT.
mth_softmax16:
  MOVI r12,@mth_s16_link
  ST r15,r12,0
  MOVI r12,@mth_s16_feature
  ST r1,r12,0
  MOVI r12,@mth_s16_w
  ST r2,r12,0
  MOVI r12,@mth_s16_dim
  ST r3,r12,0
  MOVI r12,@mth_s16_target
  ST r4,r12,0
  MOVI r12,@mth_s16_lr
  ST r5,r12,0

  ; logits[h] = dot(W[h], feature)
  MOVI r5,0
mth_s16_h:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16_h_done
  MOVI r12,@mth_s16_dim
  LD r12,r12,0
  MUL r14,r5,r12
  MOVI r10,@mth_s16_w
  LD r10,r10,0
  ADD r14,r14,r10
  MOVI r6,0
  MOVI r7,0
mth_s16_dot:
  MOVI r12,@mth_s16_dim
  LD r12,r12,0
  CMP r6,r12
  JMP[GE] @mth_s16_d_done
  ADD r10,r14,r6
  LD r10,r10,0
  MOVI r12,@mth_s16_feature
  LD r12,r12,0
  ADD r12,r12,r6
  LD r12,r12,0
  FMUL r10,r10,r12
  FADD r7,r7,r10
  ADDI r6,r6,1
  JMP @mth_s16_dot
mth_s16_d_done:
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  ST r7,r10,0
  ADDI r5,r5,1
  JMP @mth_s16_h
mth_s16_h_done:

  ; max and argmax
  MOVI r9,0
  MOVHI r9,0xFF80
  MOVI r8,0
  MOVI r5,0
mth_s16_max:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16_max_done
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  LD r7,r10,0
  FCMP r7,r9
  JMP[LE] @mth_s16_max_next
  ADD r9,r7,r0
  ADD r8,r5,r0
mth_s16_max_next:
  ADDI r5,r5,1
  JMP @mth_s16_max
mth_s16_max_done:
  MOVI r12,@mth_s16_pred
  ST r8,r12,0
  MOVI r12,@mth_s16_max_score
  ST r9,r12,0

  ; exponentials and sum
  MOVI r12,@mth_s16_sum
  ST r0,r12,0
  MOVI r5,0
mth_s16_exp:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16_exp_done
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r14,r10,r5
  LD r7,r14,0
  MOVI r12,@mth_s16_max_score
  LD r8,r12,0
  FSUB r7,r7,r8
  FEXP r7,r7
  ST r7,r14,0
  MOVI r12,@mth_s16_sum
  LD r8,r12,0
  FADD r8,r8,r7
  ST r8,r12,0
  ADDI r5,r5,1
  JMP @mth_s16_exp
mth_s16_exp_done:

  ; inv = 1/sum
  MOVI r12,@mth_s16_sum
  LD r8,r12,0
  MOVI r6,0
  MOVHI r6,0x3F80
  FDIV r6,r6,r8
  MOVI r12,@mth_s16_inv
  ST r6,r12,0

  ; target probability and loss
  MOVI r12,@mth_s16_target
  LD r10,r12,0
  MOVI r8,0x0000
  MOVHI r8,0x0003
  ADD r8,r8,r10
  LD r7,r8,0
  FMUL r7,r7,r6
  MOVI r12,@mth_s16_target_p
  ST r7,r12,0
  FLOG r4,r7
  FSUB r4,r0,r4
  MOVI r12,@mth_s16_loss
  ST r4,r12,0

  ; W[h][d] -= lr * (p[h] - onehot_target) * feature[d]
  MOVI r5,0
mth_s16_update_h:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16_update_done
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  LD r7,r10,0
  MOVI r12,@mth_s16_inv
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r12,@mth_s16_target
  LD r9,r12,0
  CMP r5,r9
  JMP[NE] @mth_s16_no_target
  MOVI r9,0
  MOVHI r9,0x3F80
  FSUB r7,r7,r9
mth_s16_no_target:
  MOVI r12,@mth_s16_lr
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r12,@mth_s16_dim
  LD r12,r12,0
  MUL r14,r5,r12
  MOVI r10,@mth_s16_w
  LD r10,r10,0
  ADD r14,r14,r10
  MOVI r6,0
mth_s16_update_d:
  MOVI r12,@mth_s16_dim
  LD r12,r12,0
  CMP r6,r12
  JMP[GE] @mth_s16_next_h
  MOVI r12,@mth_s16_feature
  LD r12,r12,0
  ADD r12,r12,r6
  LD r10,r12,0
  FMUL r10,r10,r7
  ADD r8,r14,r6
  LD r9,r8,0
  FSUB r9,r9,r10
  ST r9,r8,0
  ADDI r6,r6,1
  JMP @mth_s16_update_d
mth_s16_next_h:
  ADDI r5,r5,1
  JMP @mth_s16_update_h
mth_s16_update_done:

  MOVI r12,@mth_s16_pred
  LD r1,r12,0
  MOVI r12,@mth_s16_loss
  LD r2,r12,0
  MOVI r12,@mth_s16_pred
  LD r3,r12,0
  MOVI r12,@mth_s16_target
  LD r12,r12,0
  CMP r3,r12
  JMP[NE] @mth_s16_not_correct
  MOVI r3,1
  JMP @mth_s16_out
mth_s16_not_correct:
  MOVI r3,0
mth_s16_out:
  MOVI r12,@mth_s16_link
  LD r15,r12,0
  RET

mth_s16_link:
  .word 0
mth_s16_feature:
  .word 0
mth_s16_w:
  .word 0
mth_s16_dim:
  .word 0
mth_s16_target:
  .word 0
mth_s16_lr:
  .word 0
mth_s16_pred:
  .word 0
mth_s16_max_score:
  .word 0
mth_s16_sum:
  .word 0
mth_s16_inv:
  .word 0
mth_s16_target_p:
  .word 0
mth_s16_loss:
  .word 0
