; Raw NaN16 readout-only trainer over a precomputed feature.
;
; Fixed memory:
;   0xA000 feature[8] float32 (already computed by the frozen trunk)
;   0xB000 readout W[255][8] float32
;   0xC000 scores[255]
;
; ABI:
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits
; The feature pointer is fixed at 0xA000, so the per-epoch loop does not
; recompute the frozen trunk.
; Returns:
;   r1 = 1 when target beats every other readout
;   r2 = target score bits
;   r3 = best wrong score bits
;
; The trunk forward and the readout update are raw NaN16/NaNVM1. The readout
; update is a local error-corrective step; it is not a BPTT tape.
mth_readout_only:
  MOVI r12,@mth_ro_link
  ST r15,r12,0
  MOVI r12,@mth_ro_target_byte
  ST r1,r12,0
  MOVI r12,@mth_ro_lr
  ST r2,r12,0

  ; scores[h] = dot(W[h], feature)
  MOVI r10,0xC000
  MOVI r11,0
mth_ro_h:
  MOVI r12,255
  CMP r11,r12
  JMP[GE] @mth_ro_scores_done
  MOVI r12,8
  MUL r12,r11,r12
  MOVI r14,0xB000
  ADD r14,r14,r12
  MOVI r5,0
  MOVI r6,0
mth_ro_d:
  MOVI r7,8
  CMP r5,r7
  JMP[GE] @mth_ro_store
  ADD r7,r14,r5
  LD r7,r7,0
  MOVI r8,0xA000
  ADD r8,r8,r5
  LD r8,r8,0
  FMUL r7,r7,r8
  FADD r6,r6,r7
  ADDI r5,r5,1
  JMP @mth_ro_d
mth_ro_store:
  ADD r7,r10,r11
  ST r6,r7,0
  ADDI r11,r11,1
  JMP @mth_ro_h
mth_ro_scores_done:

  ; target score and best wrong score
  MOVI r10,0xC000
  MOVI r9,0
  MOVHI r9,0xFF80          ; -inf
  MOVI r8,0
  MOVI r5,0
  MOVI r12,@mth_ro_target_score
  ST r0,r12,0
mth_ro_find:
  MOVI r12,255
  CMP r5,r12
  JMP[GE] @mth_ro_find_done
  ADD r7,r10,r5
  LD r7,r7,0
  MOVI r12,@mth_ro_target_byte
  LD r12,r12,0
  CMP r5,r12
  JMP[EQ] @mth_ro_target
  FCMP r7,r9
  JMP[LE] @mth_ro_next
  ADD r9,r7,r0
  ADD r8,r5,r0
  JMP @mth_ro_next
mth_ro_target:
  MOVI r12,@mth_ro_target_score
  ST r7,r12,0
mth_ro_next:
  ADDI r5,r5,1
  JMP @mth_ro_find
mth_ro_find_done:
  MOVI r12,@mth_ro_best_score
  ST r9,r12,0
  MOVI r12,@mth_ro_target_score
  LD r7,r12,0
  FCMP r7,r9
  JMP[GT] @mth_ro_correct

  ; wrong: update target row += lr*h, best row -= lr*h
  MOVI r12,@mth_ro_target_byte
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
mth_ro_update:
  MOVI r7,8
  CMP r5,r7
  JMP[GE] @mth_ro_wrong
  MOVI r8,0xA000
  ADD r8,r8,r5
  LD r8,r8,0
  MOVI r7,@mth_ro_lr
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
  JMP @mth_ro_update
mth_ro_wrong:
  MOVI r1,0
  JMP @mth_ro_out
mth_ro_correct:
  MOVI r1,1
mth_ro_out:
  MOVI r12,@mth_ro_target_score
  LD r2,r12,0
  MOVI r12,@mth_ro_best_score
  LD r3,r12,0
  ; one-margin hinge loss = max(0, best_wrong - target_score + 1.0)
  MOVI r4,0
  MOVHI r4,0x3F80
  FADD r4,r3,r4
  FSUB r4,r4,r2
  MOVI r5,0
  FCMP r4,r5
  JMP[LE] @mth_ro_loss_zero
  JMP @mth_ro_loss_store
mth_ro_loss_zero:
  MOVI r4,0
mth_ro_loss_store:
  MOVI r12,@mth_ro_loss
  ST r4,r12,0
  MOVI r13,1
  MOVI r12,@mth_ro_link
  LD r15,r12,0
  RET

mth_ro_link:
  .word 0
mth_ro_target_byte:
  .word 0
mth_ro_lr:
  .word 0
mth_ro_target_score:
  .word 0
mth_ro_best_score:
  .word 0
mth_ro_loss:
  .word 0
