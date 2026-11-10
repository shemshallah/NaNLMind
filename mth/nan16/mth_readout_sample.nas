; Raw NaN16 sampled-negative readout trainer.
;
; Fixed memory:
;   0xA000 feature[8] float32
;   0xB000 readout W[255][8] float32
;
; ABI:
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits
; Returns:
;   r1 = 1 when target beats the sampled negatives
;   r2 = target score bits
;   r3 = best sampled-negative score bits
;   r4 = one-margin hinge loss bits
;
; The trainer scores the target plus 16 deterministic negatives
; idx = (target + k*37) mod 255, k=1..16. This is a sampled training step,
; not the full 255-class evaluation. Full evaluation remains readout-only.
mth_readout_sample:
  MOVI r12,@mth_rs_link
  ST r15,r12,0
  MOVI r12,@mth_rs_target
  ST r1,r12,0
  MOVI r12,@mth_rs_lr
  ST r2,r12,0

  ; target row pointer
  MOVI r12,@mth_rs_target
  LD r10,r12,0
  MOVI r11,8
  MUL r10,r10,r11
  MOVI r12,0xB000
  ADD r10,r10,r12
  MOVI r12,@mth_rs_target_row
  ST r10,r12,0

  ; target score = dot(W[target], feature)
  MOVI r6,0
  MOVI r7,0
mth_rs_td:
  MOVI r8,8
  CMP r6,r8
  JMP[GE] @mth_rs_target_done
  ADD r8,r10,r6
  LD r8,r8,0
  MOVI r9,0xA000
  ADD r9,r9,r6
  LD r9,r9,0
  FMUL r8,r8,r9
  FADD r7,r7,r8
  ADDI r6,r6,1
  JMP @mth_rs_td
mth_rs_target_done:
  MOVI r12,@mth_rs_target_score
  ST r7,r12,0

  ; best sampled negative
  MOVI r9,0
  MOVHI r9,0xFF80
  MOVI r12,@mth_rs_best_score
  ST r9,r12,0
  MOVI r12,@mth_rs_best_idx
  ST r0,r12,0
  MOVI r5,1
mth_rs_neg:
  MOVI r8,16
  CMP r5,r8
  JMP[GT] @mth_rs_neg_done
  MOVI r8,37
  MUL r6,r5,r8
  MOVI r8,@mth_rs_target
  LD r8,r8,0
  ADD r6,r6,r8
  MOVI r7,255
  MODU r6,r6,r7
  MOVI r12,@mth_rs_neg_idx
  ST r6,r12,0
  MOVI r7,8
  MUL r6,r6,r7
  MOVI r7,0xB000
  ADD r6,r6,r7
  MOVI r7,0
  MOVI r8,0
mth_rs_nd:
  MOVI r9,8
  CMP r7,r9
  JMP[GE] @mth_rs_neg_done_score
  ADD r9,r6,r7
  LD r9,r9,0
  MOVI r10,0xA000
  ADD r10,r10,r7
  LD r10,r10,0
  FMUL r9,r9,r10
  FADD r8,r8,r9
  ADDI r7,r7,1
  JMP @mth_rs_nd
mth_rs_neg_done_score:
  MOVI r12,@mth_rs_best_score
  LD r9,r12,0
  FCMP r8,r9
  JMP[LE] @mth_rs_next_neg
  ST r8,r12,0
  MOVI r12,@mth_rs_neg_idx
  LD r9,r12,0
  MOVI r12,@mth_rs_best_idx
  ST r9,r12,0
mth_rs_next_neg:
  ADDI r5,r5,1
  JMP @mth_rs_neg
mth_rs_neg_done:

  ; loss = max(0, best - target + 1.0)
  MOVI r12,@mth_rs_target_score
  LD r2,r12,0
  MOVI r12,@mth_rs_best_score
  LD r3,r12,0
  MOVI r4,0
  MOVHI r4,0x3F80
  FADD r4,r3,r4
  FSUB r4,r4,r2
  MOVI r5,0
  FCMP r4,r5
  JMP[LE] @mth_rs_no_update
  ; update target row += lr*feature
  MOVI r12,@mth_rs_lr
  LD r5,r12,0
  MOVI r12,@mth_rs_target_row
  LD r10,r12,0
  ; best row pointer
  MOVI r12,@mth_rs_best_idx
  LD r6,r12,0
  MOVI r7,8
  MUL r6,r6,r7
  MOVI r7,0xB000
  ADD r6,r6,r7
  MOVI r7,0
mth_rs_update:
  MOVI r8,8
  CMP r7,r8
  JMP[GE] @mth_rs_no_update
  MOVI r8,0xA000
  ADD r8,r8,r7
  LD r8,r8,0
  FMUL r8,r8,r5
  ADD r9,r10,r7
  LD r11,r9,0
  FADD r11,r11,r8
  ST r11,r9,0
  ADD r9,r6,r7
  LD r11,r9,0
  FSUB r11,r11,r8
  ST r11,r9,0
  ADDI r7,r7,1
  JMP @mth_rs_update
mth_rs_no_update:
  ; accuracy = target > best
  MOVI r1,0
  MOVI r12,@mth_rs_target_score
  LD r2,r12,0
  MOVI r12,@mth_rs_best_score
  LD r3,r12,0
  FCMP r2,r3
  JMP[LE] @mth_rs_out
  MOVI r1,1
mth_rs_out:
  ; recompute loss for output (same formula)
  MOVI r4,0
  MOVHI r4,0x3F80
  FADD r4,r3,r4
  FSUB r4,r4,r2
  MOVI r5,0
  FCMP r4,r5
  JMP[GT] @mth_rs_loss_store
  MOVI r4,0
mth_rs_loss_store:
  MOVI r13,1
  MOVI r12,@mth_rs_link
  LD r15,r12,0
  RET

mth_rs_link:
  .word 0
mth_rs_target:
  .word 0
mth_rs_lr:
  .word 0
mth_rs_target_row:
  .word 0
mth_rs_target_score:
  .word 0
mth_rs_best_score:
  .word 0
mth_rs_best_idx:
  .word 0
mth_rs_neg_idx:
  .word 0
