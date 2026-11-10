; Raw NaN16 conditional 16x16 readout.
;
; The top-level class is split into a high nibble head (16 classes) and a
; low nibble head (16 classes). The low head is conditioned on the high
; class, so the model has 16 groups x 16 classes while each training step
; evaluates only the high head and one low head.
;
; ABI:
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits
;   r3 = feature width D (1..256)
; Fixed memory:
;   0xA000 feature[D]
;   0xB000 high W[16][D]
;   0xB000 + 16*D low W[16][16][D]  (group, class, feature)
;   0x30000 scratch logits[16]
; Returns:
;   r1 = 1 when both high and low predictions are correct
;   r2 = high CE + low CE (training target group)
;   r3 = predicted high class
;   r4 = predicted low class
mth_readout_hier:
  MOVI r12,@mth_hier_link
  ST r15,r12,0
  MOVI r12,@mth_hier_target
  ST r1,r12,0
  MOVI r12,@mth_hier_lr
  ST r2,r12,0
  MOVI r12,@mth_hier_d
  ST r3,r12,0

  ; high/low target nibbles
  MOVI r12,@mth_hier_target
  LD r1,r12,0
  SHR r4,r1,4
  MOVI r12,@mth_hier_high
  ST r4,r12,0
  SHL r4,r1,28
  SHR r4,r4,28
  MOVI r12,@mth_hier_low
  ST r4,r12,0

  ; high head
  MOVI r1,0xA000
  MOVI r2,0xB000
  MOVI r12,@mth_hier_d
  LD r3,r12,0
  MOVI r12,@mth_hier_high
  LD r4,r12,0
  MOVI r12,@mth_hier_lr
  LD r5,r12,0
  CALL @mth_softmax16
  MOVI r12,@mth_hier_pred_high
  ST r1,r12,0
  MOVI r12,@mth_hier_loss_high
  ST r2,r12,0

  ; low head for the true high nibble
  MOVI r12,@mth_hier_d
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r2,0xB000
  ADD r2,r2,r10
  MOVI r12,@mth_hier_high
  LD r4,r12,0
  MOVI r12,16
  MUL r4,r4,r12
  MOVI r12,@mth_hier_d
  LD r10,r12,0
  MUL r4,r4,r10
  ADD r2,r2,r4
  MOVI r1,0xA000
  MOVI r12,@mth_hier_d
  LD r3,r12,0
  MOVI r12,@mth_hier_low
  LD r4,r12,0
  MOVI r12,@mth_hier_lr
  LD r5,r12,0
  CALL @mth_softmax16
  MOVI r12,@mth_hier_loss_true_low
  ST r2,r12,0

  ; low head for the predicted high nibble (inference)
  MOVI r12,@mth_hier_d
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r2,0xB000
  ADD r2,r2,r10
  MOVI r12,@mth_hier_pred_high
  LD r4,r12,0
  MOVI r12,16
  MUL r4,r4,r12
  MOVI r12,@mth_hier_d
  LD r10,r12,0
  MUL r4,r4,r10
  ADD r2,r2,r4
  MOVI r1,0xA000
  MOVI r12,@mth_hier_d
  LD r3,r12,0
  MOVI r12,@mth_hier_low
  LD r4,r12,0
  MOVI r5,0
  CALL @mth_softmax16
  MOVI r12,@mth_hier_pred_low
  ST r1,r12,0
  MOVI r12,@mth_hier_loss_pred_low
  ST r2,r12,0

  ; correct = high correct and low correct
  MOVI r12,@mth_hier_pred_high
  LD r1,r12,0
  MOVI r12,@mth_hier_high
  LD r4,r12,0
  CMP r1,r4
  JMP[NE] @mth_hier_wrong
  MOVI r12,@mth_hier_pred_low
  LD r1,r12,0
  MOVI r12,@mth_hier_low
  LD r4,r12,0
  CMP r1,r4
  JMP[NE] @mth_hier_wrong
  MOVI r1,1
  JMP @mth_hier_correct
mth_hier_wrong:
  MOVI r1,0
mth_hier_correct:
  MOVI r12,@mth_hier_correct_flag
  ST r1,r12,0
  MOVI r12,@mth_hier_loss_high
  LD r2,r12,0
  MOVI r12,@mth_hier_loss_true_low
  LD r4,r12,0
  FADD r2,r2,r4
  MOVI r12,@mth_hier_pred_high
  LD r3,r12,0
  MOVI r12,@mth_hier_pred_low
  LD r4,r12,0
  MOVI r12,@mth_hier_link
  LD r15,r12,0
  RET

mth_hier_link:
  .word 0
mth_hier_target:
  .word 0
mth_hier_lr:
  .word 0
mth_hier_d:
  .word 0
mth_hier_high:
  .word 0
mth_hier_low:
  .word 0
mth_hier_pred_high:
  .word 0
mth_hier_pred_low:
  .word 0
mth_hier_loss_high:
  .word 0
mth_hier_loss_true_low:
  .word 0
mth_hier_loss_pred_low:
  .word 0
mth_hier_correct_flag:
  .word 0
