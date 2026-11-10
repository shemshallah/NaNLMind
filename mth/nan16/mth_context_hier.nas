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
;
; Greedy mode (default): high argmax, then low argmax under that group.
; Joint mode (mth_ctx_joint != 0, entered through mth_context_hier_joint):
; classify by argmax_h P(h|ctx) * max_l P(l|h,ctx), i.e. jointly route the
; high group and the conditional low head. Training updates are identical;
; only the inference/selection rule changes.
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

  ; Joint inference needs all 16 high probabilities.  The softmax table
  ; leaves exp(logit-max) in scratch 0x30000; copy it before the low calls
  ; reuse that scratch.  A common 1/sum factor is omitted because it does
  ; not change the argmax.
  MOVI r12,@mth_ctx_joint
  LD r10,r12,0
  CMP r10,r0
  JMP[EQ] @mth_ctx_exp_copied
  MOVI r7,0x0000
  MOVHI r7,0x0003
  MOVI r8,0x2000
  MOVHI r8,0x0003
  MOVI r6,0
mth_ctx_copy_exp:
  MOVI r12,16
  CMP r6,r12
  JMP[GE] @mth_ctx_exp_copied
  ADD r9,r7,r6
  LD r10,r9,0
  ADD r9,r8,r6
  ST r10,r9,0
  ADDI r6,r6,1
  JMP @mth_ctx_copy_exp
mth_ctx_exp_copied:

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

  ; Inference: either greedy high->low or joint head-pair routing.
  MOVI r12,@mth_ctx_joint
  LD r10,r12,0
  CMP r10,r0
  JMP[NE] @mth_ctx_joint_infer

  ; low head for predicted high (greedy inference), no update
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
  JMP @mth_ctx_correctness

mth_ctx_joint_infer:
  ; score_h = exp_high[h] * max_low_prob(h)
  MOVI r12,@mth_ctx_best_score
  ST r0,r12,0
  MOVI r12,@mth_ctx_best_high
  ST r0,r12,0
  MOVI r12,@mth_ctx_best_low
  ST r0,r12,0
  MOVI r6,0
mth_ctx_joint_h:
  MOVI r12,16
  CMP r6,r12
  JMP[GE] @mth_ctx_joint_done
  MOVI r12,@mth_ctx_buckets
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r1,0x0000
  MOVHI r1,0x0010
  ADD r1,r1,r10
  MOVI r12,16
  MUL r10,r6,r12
  MOVI r12,@mth_ctx_buckets
  LD r12,r12,0
  MUL r10,r10,r12
  ADD r1,r1,r10
  MOVI r12,@mth_ctx_buckets
  LD r2,r12,0
  MOVI r12,@mth_ctx_bucket
  LD r3,r12,0
  MOVI r12,@mth_ctx_low
  LD r4,r12,0
  MOVI r5,0
  MOVI r12,@mth_ctx_joint_index
  ST r6,r12,0
  CALL @mth_softmax16_table
  MOVI r12,@mth_ctx_joint_index
  LD r6,r12,0
  MOVI r7,0x2000
  MOVHI r7,0x0003
  ADD r7,r7,r6
  LD r8,r7,0
  FMUL r8,r8,r4
  MOVI r12,@mth_ctx_best_score
  LD r9,r12,0
  FCMP r8,r9
  JMP[LE] @mth_ctx_joint_next
  ST r8,r12,0
  MOVI r12,@mth_ctx_best_high
  ST r6,r12,0
  MOVI r12,@mth_ctx_best_low
  ST r1,r12,0
mth_ctx_joint_next:
  ADDI r6,r6,1
  JMP @mth_ctx_joint_h
mth_ctx_joint_done:
  MOVI r12,@mth_ctx_best_high
  LD r1,r12,0
  MOVI r12,@mth_ctx_pred_high
  ST r1,r12,0
  MOVI r12,@mth_ctx_best_low
  LD r1,r12,0
  MOVI r12,@mth_ctx_pred_low
  ST r1,r12,0

mth_ctx_correctness:

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

; Joint-selection entry point.  Same ABI as mth_context_hier.
mth_context_hier_joint:
  MOVI r12,@mth_ctx_joint_link
  ST r15,r12,0
  MOVI r12,@mth_ctx_joint
  MOVI r13,1
  ST r13,r12,0
  CALL @mth_context_hier
  MOVI r12,@mth_ctx_joint
  ST r0,r12,0
  MOVI r12,@mth_ctx_joint_link
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
mth_ctx_joint:
  .word 0
mth_ctx_joint_link:
  .word 0
mth_ctx_joint_index:
  .word 0
mth_ctx_best_score:
  .word 0
mth_ctx_best_high:
  .word 0
mth_ctx_best_low:
  .word 0
