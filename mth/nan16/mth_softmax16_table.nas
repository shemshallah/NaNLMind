; Raw NaN16 16-class softmax head over a context-indexed table.
;
; The table is 16 rows x B buckets of float32 scores. A sample supplies one
; context bucket; the head reads/writes only that column. This is the sparse
; n-gram class-memory primitive, not a dense feature dot product.
;
; ABI:
;   r1 = table base word address
;   r2 = bucket count B
;   r3 = context bucket (0..B-1)
;   r4 = target class (0..15)
;   r5 = learning-rate float32 bits (0 disables updates)
; Returns:
;   r1 = argmax class
;   r2 = cross-entropy loss bits
;   r3 = 1 when argmax == target
mth_softmax16_table:
  MOVI r12,@mth_s16t_link
  ST r15,r12,0
  MOVI r12,@mth_s16t_table
  ST r1,r12,0
  MOVI r12,@mth_s16t_buckets
  ST r2,r12,0
  MOVI r12,@mth_s16t_bucket
  ST r3,r12,0
  MOVI r12,@mth_s16t_target
  ST r4,r12,0
  MOVI r12,@mth_s16t_lr
  ST r5,r12,0

  ; scores[h] = table[h*B + bucket]
  MOVI r5,0
mth_s16t_h:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16t_h_done
  MOVI r12,@mth_s16t_buckets
  LD r12,r12,0
  MUL r14,r5,r12
  MOVI r12,@mth_s16t_bucket
  LD r12,r12,0
  ADD r14,r14,r12
  MOVI r12,@mth_s16t_table
  LD r12,r12,0
  ADD r14,r14,r12
  LD r7,r14,0
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  ST r7,r10,0
  ADDI r5,r5,1
  JMP @mth_s16t_h
mth_s16t_h_done:

  ; max and argmax
  MOVI r9,0
  MOVHI r9,0xFF80
  MOVI r8,0
  MOVI r5,0
mth_s16t_max:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16t_max_done
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  LD r7,r10,0
  FCMP r7,r9
  JMP[LE] @mth_s16t_max_next
  ADD r9,r7,r0
  ADD r8,r5,r0
mth_s16t_max_next:
  ADDI r5,r5,1
  JMP @mth_s16t_max
mth_s16t_max_done:
  MOVI r12,@mth_s16t_pred
  ST r8,r12,0
  MOVI r12,@mth_s16t_max_score
  ST r9,r12,0

  ; exponentials and sum
  MOVI r12,@mth_s16t_sum
  ST r0,r12,0
  MOVI r5,0
mth_s16t_exp:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16t_exp_done
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r14,r10,r5
  LD r7,r14,0
  MOVI r12,@mth_s16t_max_score
  LD r8,r12,0
  FSUB r7,r7,r8
  FEXP r7,r7
  ST r7,r14,0
  MOVI r12,@mth_s16t_sum
  LD r8,r12,0
  FADD r8,r8,r7
  ST r8,r12,0
  ADDI r5,r5,1
  JMP @mth_s16t_exp
mth_s16t_exp_done:

  MOVI r12,@mth_s16t_sum
  LD r8,r12,0
  MOVI r6,0
  MOVHI r6,0x3F80
  FDIV r6,r6,r8
  MOVI r12,@mth_s16t_inv
  ST r6,r12,0

  ; target probability and loss
  MOVI r12,@mth_s16t_target
  LD r10,r12,0
  MOVI r8,0x0000
  MOVHI r8,0x0003
  ADD r8,r8,r10
  LD r7,r8,0
  FMUL r7,r7,r6
  MOVI r12,@mth_s16t_target_p
  ST r7,r12,0
  FLOG r4,r7
  FSUB r4,r0,r4
  MOVI r12,@mth_s16t_loss
  ST r4,r12,0

  ; update one column: table[h,Bucket] -= lr*(p[h]-onehot)
  MOVI r5,0
mth_s16t_update_h:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_s16t_update_done
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  LD r7,r10,0
  MOVI r12,@mth_s16t_inv
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r12,@mth_s16t_target
  LD r9,r12,0
  CMP r5,r9
  JMP[NE] @mth_s16t_no_target
  MOVI r9,0
  MOVHI r9,0x3F80
  FSUB r7,r7,r9
mth_s16t_no_target:
  MOVI r12,@mth_s16t_lr
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r12,@mth_s16t_buckets
  LD r12,r12,0
  MUL r14,r5,r12
  MOVI r12,@mth_s16t_bucket
  LD r12,r12,0
  ADD r14,r14,r12
  MOVI r12,@mth_s16t_table
  LD r12,r12,0
  ADD r14,r14,r12
  LD r9,r14,0
  FSUB r9,r9,r7
  ST r9,r14,0
  ADDI r5,r5,1
  JMP @mth_s16t_update_h
mth_s16t_update_done:

  MOVI r12,@mth_s16t_pred
  LD r1,r12,0
  MOVI r12,@mth_s16t_loss
  LD r2,r12,0
  ; r4 = max class probability (1/sum_exp); r4 is float bits.
  MOVI r12,@mth_s16t_inv
  LD r4,r12,0
  MOVI r12,@mth_s16t_target
  LD r12,r12,0
  CMP r1,r12
  JMP[NE] @mth_s16t_wrong
  MOVI r3,1
  JMP @mth_s16t_out
mth_s16t_wrong:
  MOVI r3,0
mth_s16t_out:
  MOVI r12,@mth_s16t_link
  LD r15,r12,0
  RET

mth_s16t_link:
  .word 0
mth_s16t_table:
  .word 0
mth_s16t_buckets:
  .word 0
mth_s16t_bucket:
  .word 0
mth_s16t_target:
  .word 0
mth_s16t_lr:
  .word 0
mth_s16t_pred:
  .word 0
mth_s16t_max_score:
  .word 0
mth_s16t_sum:
  .word 0
mth_s16t_inv:
  .word 0
mth_s16t_target_p:
  .word 0
mth_s16t_loss:
  .word 0
