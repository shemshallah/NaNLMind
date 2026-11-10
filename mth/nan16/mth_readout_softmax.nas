; Raw NaN16 softmax readout trainer over a cached trunk feature.
;
; Fixed memory:
;   0xA000 feature[8] float32
;   0xB000 readout W[255][8] float32
;   0xC000 logits/probabilities[255]
;
; ABI:
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits
; Returns:
;   r1 = 1 when target is the argmax class
;   r2 = cross-entropy loss bits
;   r3 = target probability bits
;
; One raw full-softmax step: all 255 class logits, exponentiation and
; normalisation, then a gradient step for every row. This is a local
; error-corrective step, not a BPTT tape.
mth_readout_softmax:
  MOVI r12,@mth_rsm_link
  ST r15,r12,0
  MOVI r12,@mth_rsm_target
  ST r1,r12,0
  MOVI r12,@mth_rsm_lr
  ST r2,r12,0

  ; logits[h] = dot(W[h], feature)
  MOVI r10,0xC000
  MOVI r11,0
mth_rsm_logit_h:
  MOVI r12,255
  CMP r11,r12
  JMP[GE] @mth_rsm_logit_done
  MOVI r12,8
  MUL r12,r11,r12
  MOVI r14,0xB000
  ADD r14,r14,r12
  MOVI r5,0
  MOVI r6,0
mth_rsm_dot:
  MOVI r7,8
  CMP r5,r7
  JMP[GE] @mth_rsm_dot_done
  ADD r7,r14,r5
  LD r7,r7,0
  MOVI r8,0xA000
  ADD r8,r8,r5
  LD r8,r8,0
  FMUL r7,r7,r8
  FADD r6,r6,r7
  ADDI r5,r5,1
  JMP @mth_rsm_dot
mth_rsm_dot_done:
  ADD r7,r10,r11
  ST r6,r7,0
  ADDI r11,r11,1
  JMP @mth_rsm_logit_h
mth_rsm_logit_done:

  ; max logit and best class
  MOVI r9,0
  MOVHI r9,0xFF80
  MOVI r8,0
  MOVI r5,0
mth_rsm_max:
  MOVI r12,255
  CMP r5,r12
  JMP[GE] @mth_rsm_max_done
  MOVI r10,0xC000
  ADD r7,r10,r5
  LD r7,r7,0
  FCMP r7,r9
  JMP[LE] @mth_rsm_max_next
  ADD r9,r7,r0
  ADD r8,r5,r0
mth_rsm_max_next:
  ADDI r5,r5,1
  JMP @mth_rsm_max
mth_rsm_max_done:
  MOVI r12,@mth_rsm_max_score
  ST r9,r12,0
  MOVI r12,@mth_rsm_best_idx
  ST r8,r12,0

  ; correct = (best_idx == target)
  MOVI r12,@mth_rsm_target
  LD r10,r12,0
  CMP r10,r8
  JMP[NE] @mth_rsm_not_correct
  MOVI r7,1
  MOVI r12,@mth_rsm_correct
  ST r7,r12,0
  JMP @mth_rsm_correct_done
mth_rsm_not_correct:
  MOVI r12,@mth_rsm_correct
  ST r0,r12,0
mth_rsm_correct_done:

  ; probabilities = exp(logit - max), then normalize
  MOVI r12,@mth_rsm_sum
  ST r0,r12,0
  MOVI r5,0
mth_rsm_exp:
  MOVI r12,255
  CMP r5,r12
  JMP[GE] @mth_rsm_exp_done
  MOVI r10,0xC000
  ADD r14,r10,r5
  LD r7,r14,0
  MOVI r12,@mth_rsm_max_score
  LD r8,r12,0
  FSUB r7,r7,r8
  FEXP r7,r7
  ST r7,r14,0
  MOVI r12,@mth_rsm_sum
  LD r8,r12,0
  FADD r8,r8,r7
  ST r8,r12,0
  ADDI r5,r5,1
  JMP @mth_rsm_exp
mth_rsm_exp_done:

  ; inv = 1 / sum
  MOVI r12,@mth_rsm_sum
  LD r8,r12,0
  MOVI r6,0
  MOVHI r6,0x3F80
  FDIV r6,r6,r8
  MOVI r12,@mth_rsm_inv
  ST r6,r12,0

  ; target probability and cross-entropy loss
  MOVI r12,@mth_rsm_target
  LD r10,r12,0
  MOVI r8,0xC000
  ADD r8,r8,r10
  LD r7,r8,0
  FMUL r7,r7,r6
  MOVI r12,@mth_rsm_target_p
  ST r7,r12,0
  FLOG r4,r7
  FSUB r4,r0,r4
  MOVI r12,@mth_rsm_loss
  ST r4,r12,0

  ; gradient step: W[h][d] += lr * (p[h] - [h == target]) * feature[d]
  MOVI r5,0
mth_rsm_update_h:
  MOVI r12,255
  CMP r5,r12
  JMP[GE] @mth_rsm_update_done
  MOVI r10,0xC000
  ADD r7,r10,r5
  LD r7,r7,0
  MOVI r12,@mth_rsm_inv
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r12,@mth_rsm_target
  LD r9,r12,0
  CMP r5,r9
  JMP[NE] @mth_rsm_no_target
  MOVI r9,0
  MOVHI r9,0x3F80
  FSUB r7,r7,r9
mth_rsm_no_target:
  MOVI r12,@mth_rsm_lr
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r12,8
  MUL r14,r5,r12
  MOVI r12,0xB000
  ADD r14,r14,r12
  MOVI r6,0
mth_rsm_update_d:
  MOVI r12,8
  CMP r6,r12
  JMP[GE] @mth_rsm_next_h
  MOVI r10,0xA000
  ADD r10,r10,r6
  LD r10,r10,0
  FMUL r10,r10,r7
  ADD r8,r14,r6
  LD r9,r8,0
  FSUB r9,r9,r10
  ST r9,r8,0
  ADDI r6,r6,1
  JMP @mth_rsm_update_d
mth_rsm_next_h:
  ADDI r5,r5,1
  JMP @mth_rsm_update_h
mth_rsm_update_done:

  MOVI r12,@mth_rsm_correct
  LD r1,r12,0
  MOVI r12,@mth_rsm_loss
  LD r2,r12,0
  MOVI r12,@mth_rsm_target_p
  LD r3,r12,0
  MOVI r12,@mth_rsm_link
  LD r15,r12,0
  RET

mth_rsm_link:
  .word 0
mth_rsm_target:
  .word 0
mth_rsm_lr:
  .word 0
mth_rsm_max_score:
  .word 0
mth_rsm_best_idx:
  .word 0
mth_rsm_correct:
  .word 0
mth_rsm_sum:
  .word 0
mth_rsm_inv:
  .word 0
mth_rsm_target_p:
  .word 0
mth_rsm_loss:
  .word 0
