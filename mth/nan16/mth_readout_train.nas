; Raw NaN16 trunk-feature readout trainer.
;
; Fixed memory:
;   0x7000 tokens: T x 8 float32
;   0x9000 trunk weights (see mth_trunk_causal)
;   0xA000 trunk output feature[8]
;   0xB000 readout W[255][8] float32
;   0xC000 scores[255]
;
; ABI:
;   r1 = token count T
;   r2 = target byte 0..254
;   r3 = learning-rate float32 bits
; Returns:
;   r1 = 1 when target beats every other readout
;   r2 = target score bits
;   r3 = best wrong score bits
;
; The trunk forward and the readout update are raw NaN16/NaNVM1. The readout
; update is a local error-corrective step; it is not a BPTT tape.
mth_readout_train:
  MOVI r12,@mth_rt_link
  ST r15,r12,0
  MOVI r12,@mth_rt_T
  ST r1,r12,0
  MOVI r12,@mth_rt_target_byte
  ST r2,r12,0
  MOVI r12,@mth_rt_lr
  ST r3,r12,0

  MOVI r1,@mth_rt_T
  LD r1,r1,0
  CALL @mth_trunk_causal

  ; scores[h] = dot(W[h], feature)
  MOVI r10,0xC000
  MOVI r11,0
mth_rt_h:
  MOVI r12,255
  CMP r11,r12
  JMP[GE] @mth_rt_scores_done
  MOVI r12,8
  MUL r12,r11,r12
  MOVI r14,0xB000
  ADD r14,r14,r12
  MOVI r5,0
  MOVI r6,0
mth_rt_d:
  MOVI r7,8
  CMP r5,r7
  JMP[GE] @mth_rt_store
  ADD r7,r14,r5
  LD r7,r7,0
  MOVI r8,0xA000
  ADD r8,r8,r5
  LD r8,r8,0
  FMUL r7,r7,r8
  FADD r6,r6,r7
  ADDI r5,r5,1
  JMP @mth_rt_d
mth_rt_store:
  ADD r7,r10,r11
  ST r6,r7,0
  ADDI r11,r11,1
  JMP @mth_rt_h
mth_rt_scores_done:

  ; target score and best wrong score
  MOVI r10,0xC000
  MOVI r9,0
  MOVHI r9,0xFF80          ; -inf
  MOVI r8,0
  MOVI r5,0
  MOVI r12,@mth_rt_target_score
  ST r0,r12,0
mth_rt_find:
  MOVI r12,255
  CMP r5,r12
  JMP[GE] @mth_rt_find_done
  ADD r7,r10,r5
  LD r7,r7,0
  MOVI r12,@mth_rt_target_byte
  LD r12,r12,0
  CMP r5,r12
  JMP[EQ] @mth_rt_target
  FCMP r7,r9
  JMP[LE] @mth_rt_next
  ADD r9,r7,r0
  ADD r8,r5,r0
  JMP @mth_rt_next
mth_rt_target:
  MOVI r12,@mth_rt_target_score
  ST r7,r12,0
mth_rt_next:
  ADDI r5,r5,1
  JMP @mth_rt_find
mth_rt_find_done:
  MOVI r12,@mth_rt_target_score
  LD r7,r12,0
  FCMP r7,r9
  JMP[GT] @mth_rt_correct

  ; wrong: update target row += lr*h, best row -= lr*h
  MOVI r12,@mth_rt_target_byte
  LD r10,r12,0
  MOVI r12,8
  MUL r10,r10,r12
  MOVI r14,0xB000
  ADD r14,r14,r10
  ADD r8,r8,r0
  MOVI r12,8
  MUL r8,r8,r12
  MOVI r12,0xB000
  ADD r12,r12,r8
  MOVI r5,0
mth_rt_update:
  MOVI r7,8
  CMP r5,r7
  JMP[GE] @mth_rt_wrong
  MOVI r8,0xA000
  ADD r8,r8,r5
  LD r8,r8,0
  MOVI r7,@mth_rt_lr
  LD r7,r7,0
  FMUL r8,r8,r7
  ADD r7,r14,r5
  LD r9,r7,0
  FADD r9,r9,r8
  ST r9,r7,0
  ADD r7,r12,r5
  LD r9,r7,0
  FSUB r9,r9,r8
  ST r9,r7,0
  ADDI r5,r5,1
  JMP @mth_rt_update
mth_rt_wrong:
  MOVI r1,0
  JMP @mth_rt_out
mth_rt_correct:
  MOVI r1,1
mth_rt_out:
  MOVI r12,@mth_rt_target_score
  LD r2,r12,0
  ADD r3,r9,r0
  ; one-margin hinge loss = max(0, best_wrong - target_score + 1.0)
  MOVI r4,0
  MOVHI r4,0x3F80
  FADD r4,r3,r4
  FSUB r4,r4,r2
  MOVI r5,0
  FCMP r4,r5
  JMP[LE] @mth_rt_loss_zero
  JMP @mth_rt_loss_store
mth_rt_loss_zero:
  MOVI r4,0
mth_rt_loss_store:
  MOVI r12,@mth_rt_loss
  ST r4,r12,0
  MOVI r13,1
  MOVI r12,@mth_rt_link
  LD r15,r12,0
  RET

mth_rt_link:
  .word 0
mth_rt_T:
  .word 0
mth_rt_target_byte:
  .word 0
mth_rt_lr:
  .word 0
mth_rt_target_score:
  .word 0
mth_rt_loss:
  .word 0
