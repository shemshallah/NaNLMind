; Raw NaN16 conditional 16x16 readout over context-indexed class memory.
;
; High table: 16 x B scores at 0x100000.
; Low tables: 16 groups x 16 x B scores immediately after the high table.
;
; ABI:
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits
;   r3 = context bucket
;   r4 = bucket count B
; Returns:
;   r1 = 1 when both high and low predictions are correct
;   r2 = high CE + low CE (training target group)
;   r3 = predicted high class
;   r4 = predicted low class
mth_context_hier:
  MOVI r12,@mth_ctx_link
  ST r15,r12,0
  MOVI r12,@mth_ctx_target
  ST r1,r12,0
  MOVI r12,@mth_ctx_lr
  ST r2,r12,0
  MOVI r12,@mth_ctx_bucket
  ST r3,r12,0
  MOVI r12,@mth_ctx_buckets
  ST r4,r12,0

  ; target nibbles
  MOVI r12,@mth_ctx_target
  LD r1,r12,0
  SHR r4,r1,4
  MOVI r12,@mth_ctx_high
  ST r4,r12,0
  SHL r4,r1,28
  SHR r4,r4,28
  MOVI r12,@mth_ctx_low
  ST r4,r12,0

  ; high head at 0x100000
  MOVI r1,0x0000
  MOVHI r1,0x0010
  MOVI r12,@mth_ctx_buckets
  LD r2,r12,0
  MOVI r12,@mth_ctx_bucket
  LD r3,r12,0
  MOVI r12,@mth_ctx_high
  LD r4,r12,0
  MOVI r12,@mth_ctx_lr
  LD r5,r12,0
  CALL @mth_softmax16_table
  MOVI r12,@mth_ctx_pred_high
  ST r1,r12,0
  MOVI r12,@mth_ctx_loss_high
  ST r2,r12,0

  ; low table base = 0x100000 + 16*B
  MOVI r12,@mth_ctx_buckets
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r2,0x0000
  MOVHI r2,0x0010
  ADD r2,r2,r10
  ; condition on true high: base + high*16*B
  MOVI r12,@mth_ctx_high
  LD r4,r12,0
  MOVI r12,16
  MUL r4,r4,r12
  MOVI r12,@mth_ctx_buckets
  LD r10,r12,0
  MUL r4,r4,r10
  ADD r2,r2,r4
  MOVI r12,@mth_ctx_buckets
  LD r2,r12,0
  MOVI r12,@mth_ctx_buckets
  LD r2,r12,0
  ; recompute low pointer because r2 was reused
  MOVI r12,@mth_ctx_buckets
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r2,0x0000
  MOVHI r2,0x0010
  ADD r2,r2,r10
  MOVI r12,@mth_ctx_high
  LD r4,r12,0
  MOVI r12,16
  MUL r4,r4,r12
  MOVI r12,@mth_ctx_buckets
  LD r10,r12,0
  MUL r4,r4,r10
  ADD r2,r2,r4
  ADD r1,r2,r0
  MOVI r12,@mth_ctx_buckets
  LD r2,r12,0
  MOVI r12,@mth_ctx_bucket
  LD r3,r12,0
  MOVI r12,@mth_ctx_low
  LD r4,r12,0
  MOVI r12,@mth_ctx_lr
  LD r5,r12,0
  CALL @mth_softmax16_table
  MOVI r12,@mth_ctx_loss_true_low
  ST r2,r12,0

  ; low head for predicted high (inference), no update
  MOVI r12,@mth_ctx_buckets
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r2,0x0000
  MOVHI r2,0x0010
  ADD r2,r2,r10
  MOVI r12,@mth_ctx_pred_high
  LD r4,r12,0
  MOVI r12,16
  MUL r4,r4,r12
  MOVI r12,@mth_ctx_buckets
  LD r10,r12,0
  MUL r4,r4,r10
  ADD r2,r2,r4
  ADD r1,r2,r0
  MOVI r12,@mth_ctx_buckets
  LD r2,r12,0
  MOVI r12,@mth_ctx_bucket
  LD r3,r12,0
  MOVI r12,@mth_ctx_low
  LD r4,r12,0
  MOVI r5,0
  CALL @mth_softmax16_table
  MOVI r12,@mth_ctx_pred_low
  ST r1,r12,0

  ; correctness
  MOVI r12,@mth_ctx_pred_high
  LD r1,r12,0
  MOVI r12,@mth_ctx_high
  LD r4,r12,0
  CMP r1,r4
  JMP[NE] @mth_ctx_wrong
  MOVI r12,@mth_ctx_pred_low
  LD r1,r12,0
  MOVI r12,@mth_ctx_low
  LD r4,r12,0
  CMP r1,r4
  JMP[NE] @mth_ctx_wrong
  MOVI r1,1
  JMP @mth_ctx_correct
mth_ctx_wrong:
  MOVI r1,0
mth_ctx_correct:
  MOVI r12,@mth_ctx_loss_high
  LD r2,r12,0
  MOVI r12,@mth_ctx_loss_true_low
  LD r4,r12,0
  FADD r2,r2,r4
  MOVI r12,@mth_ctx_pred_high
  LD r3,r12,0
  MOVI r12,@mth_ctx_pred_low
  LD r4,r12,0
  MOVI r12,@mth_ctx_link
  LD r15,r12,0
  RET

mth_ctx_link:
  .word 0
mth_ctx_target:
  .word 0
mth_ctx_lr:
  .word 0
mth_ctx_bucket:
  .word 0
mth_ctx_buckets:
  .word 0
mth_ctx_high:
  .word 0
mth_ctx_low:
  .word 0
mth_ctx_pred_high:
  .word 0
mth_ctx_pred_low:
  .word 0
mth_ctx_loss_high:
  .word 0
mth_ctx_loss_true_low:
  .word 0
