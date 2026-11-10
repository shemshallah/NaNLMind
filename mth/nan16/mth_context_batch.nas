; Raw NaN16 batched context-indexed 16x16 readout driver.
;
; The host marshals four guest word arrays. The guest walks them in order,
; calls the same mth_context_hier kernel used by the per-sample path, and
; accumulates the aggregate result. No training arithmetic moves to the host.
;
; ABI:
;   r1 = sample count N
;   r2 = target array pointer (one word per sample)
;   r3 = context bucket array pointer (one word per sample)
;   r4 = learning-rate float32-bits array pointer (one word per sample)
;   r5 = bucket count B
; Returns:
;   r1 = number of samples whose high and low predictions were both correct
;   r2 = sum of per-sample cross-entropy loss float32 bits
;   r3 = number of samples processed
;   r4 = 0 (reserved)
mth_context_batch:
  MOVI r12,@mth_ctxb_link
  ST r15,r12,0
  MOVI r12,@mth_ctxb_count
  ST r1,r12,0
  MOVI r12,@mth_ctxb_targets
  ST r2,r12,0
  MOVI r12,@mth_ctxb_buckets
  ST r3,r12,0
  MOVI r12,@mth_ctxb_lrs
  ST r4,r12,0
  MOVI r12,@mth_ctxb_bucket_count
  ST r5,r12,0

  MOVI r8,0
  MOVI r12,@mth_ctxb_correct
  ST r8,r12,0
  MOVI r12,@mth_ctxb_loss
  ST r8,r12,0
  MOVI r12,@mth_ctxb_i
  ST r8,r12,0

mth_ctxb_loop:
  MOVI r12,@mth_ctxb_i
  LD r6,r12,0
  MOVI r12,@mth_ctxb_count
  LD r7,r12,0
  CMP r6,r7
  JMP[GE] @mth_ctxb_done

  MOVI r12,@mth_ctxb_targets
  LD r8,r12,0
  ADD r8,r8,r6
  LD r1,r8,0

  MOVI r12,@mth_ctxb_buckets
  LD r8,r12,0
  ADD r8,r8,r6
  LD r3,r8,0

  MOVI r12,@mth_ctxb_lrs
  LD r8,r12,0
  ADD r8,r8,r6
  LD r2,r8,0

  MOVI r12,@mth_ctxb_bucket_count
  LD r4,r12,0

  CALL @mth_context_hier

  ; r1 = correct flag, r2 = per-sample loss float32 bits
  MOVI r12,@mth_ctxb_correct
  LD r8,r12,0
  ADD r8,r8,r1
  ST r8,r12,0

  MOVI r12,@mth_ctxb_loss
  LD r8,r12,0
  FADD r8,r8,r2
  ST r8,r12,0

  MOVI r12,@mth_ctxb_i
  LD r6,r12,0
  ADDI r6,r6,1
  ST r6,r12,0
  JMP @mth_ctxb_loop

mth_ctxb_done:
  MOVI r12,@mth_ctxb_correct
  LD r1,r12,0
  MOVI r12,@mth_ctxb_loss
  LD r2,r12,0
  MOVI r12,@mth_ctxb_count
  LD r3,r12,0
  MOVI r4,0
  MOVI r12,@mth_ctxb_link
  LD r15,r12,0
  RET

mth_ctxb_link:
  .word 0
mth_ctxb_count:
  .word 0
mth_ctxb_targets:
  .word 0
mth_ctxb_buckets:
  .word 0
mth_ctxb_lrs:
  .word 0
mth_ctxb_bucket_count:
  .word 0
mth_ctxb_i:
  .word 0
mth_ctxb_correct:
  .word 0
mth_ctxb_loss:
  .word 0
