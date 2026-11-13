; Kept above the command block (0x4000..0x4015) so the base driver and native
; head block can continue to occupy their fixed low-memory region.
.org 0x4200

; Fixed high-memory entry used by the base driver's mode-6 CALLF trampoline.
mth_context_backoff_top5:
  JMP @mth_ct5_entry

; Raw NaN16 full 16x16 top-5 readout for the context class memory.
;
; This is the evaluation companion to mth_context_backoff.  It performs no
; updates.  A byte is factorized as high nibble h and low nibble l:
;
;   P(byte | bucket) = P(h | bucket) * P(l | h, bucket)
;
; Both 16-way softmaxes are evaluated for every high group, so the returned
; top-5 is a true full 256-class ranking rather than a greedy high/low panel.
;
; ABI for mth_context_backoff_top5:
;   r1 = target byte 0..254 (used only for the returned loss)
;   r2 = packed k=4 key
;   r3 = bucket count B
; Returns:
;   r1..r5 = top-5 byte classes, descending probability
;   r6     = natural-log loss of the target under the same ranking
;
; Scratch is private to this route:
;   0x30000  one 16-entry softmax scratch
;   0x32000  top-5 probabilities
;   0x33000  top-5 classes
;   0x34000  high probabilities
;   0x34100  low probabilities for the current high group

; r1 = table base, r2 = buckets, r3 = bucket, r4 = float32 output[16].
; Returns r1 = argmax class.  No table mutation.
mth_ctxp16:
  MOVI r12,@mth_ctxp_link
  ST r15,r12,0
  MOVI r12,@mth_ctxp_table
  ST r1,r12,0
  MOVI r12,@mth_ctxp_buckets
  ST r2,r12,0
  MOVI r12,@mth_ctxp_bucket
  ST r3,r12,0
  MOVI r12,@mth_ctxp_out
  ST r4,r12,0

  ; scores[h] = table[h*B + bucket]
  MOVI r5,0
mth_ctxp_load:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_ctxp_load_done
  MOVI r12,@mth_ctxp_buckets
  LD r12,r12,0
  MUL r14,r5,r12
  MOVI r12,@mth_ctxp_bucket
  LD r12,r12,0
  ADD r14,r14,r12
  MOVI r12,@mth_ctxp_table
  LD r12,r12,0
  ADD r14,r14,r12
  LD r7,r14,0
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  ST r7,r10,0
  ADDI r5,r5,1
  JMP @mth_ctxp_load
mth_ctxp_load_done:

  ; max and argmax
  MOVI r9,0
  MOVHI r9,0xFF80
  MOVI r8,0
  MOVI r11,0
  MOVI r5,0
mth_ctxp_max:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_ctxp_max_done
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ADD r10,r10,r5
  LD r7,r10,0
  FCMP r7,r9
  JMP[LE] @mth_ctxp_max_next
  ADD r9,r7,r0
  ADD r8,r5,r0
mth_ctxp_max_next:
  ADDI r5,r5,1
  JMP @mth_ctxp_max
mth_ctxp_max_done:
  MOVI r12,@mth_ctxp_max_score
  ST r9,r12,0
  MOVI r12,@mth_ctxp_argmax
  ST r8,r12,0

  ; exponentials and sum
  MOVI r12,@mth_ctxp_sum
  ST r0,r12,0
  MOVI r5,0
mth_ctxp_exp:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_ctxp_exp_done
  MOVI r14,0x0000
  MOVHI r14,0x0003
  ADD r14,r14,r5
  LD r7,r14,0
  MOVI r12,@mth_ctxp_max_score
  LD r8,r12,0
  FSUB r7,r7,r8
  FEXP r7,r7
  ST r7,r14,0
  MOVI r12,@mth_ctxp_sum
  LD r8,r12,0
  FADD r8,r8,r7
  ST r8,r12,0
  ADDI r5,r5,1
  JMP @mth_ctxp_exp
mth_ctxp_exp_done:

  MOVI r12,@mth_ctxp_sum
  LD r8,r12,0
  MOVI r6,0
  MOVHI r6,0x3F80
  FDIV r6,r6,r8
  MOVI r12,@mth_ctxp_inv
  ST r6,r12,0

  ; probabilities[h] = exp[h] / sum
  MOVI r5,0
mth_ctxp_prob:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_ctxp_prob_done
  MOVI r14,0x0000
  MOVHI r14,0x0003
  ADD r14,r14,r5
  LD r7,r14,0
  MOVI r12,@mth_ctxp_inv
  LD r6,r12,0
  FMUL r7,r7,r6
  MOVI r12,@mth_ctxp_out
  LD r6,r12,0
  ADD r6,r6,r5
  ST r7,r6,0
  ADDI r5,r5,1
  JMP @mth_ctxp_prob
mth_ctxp_prob_done:
  MOVI r12,@mth_ctxp_argmax
  LD r1,r12,0
  MOVI r12,@mth_ctxp_link
  LD r15,r12,0
  RET

mth_ct5_entry:
  MOVI r12,@mth_ct5_link
  ST r15,r12,0
  MOVI r12,@mth_ct5_target
  ST r1,r12,0
  MOVI r12,@mth_ct5_key
  ST r2,r12,0
  MOVI r12,@mth_ct5_buckets
  ST r3,r12,0

  ; Route the key to an exact slot or the k=3 FNV fallback bucket.
  MOVI r12,@mth_ct5_key
  LD r1,r12,0
  CALL @mth_ctxb_route
  MOVI r12,@mth_ct5_bucket
  ST r1,r12,0

  ; Clear top-5 score and class scratch.
  MOVI r10,0
mth_ct5_clear:
  MOVI r12,5
  CMP r10,r12
  JMP[GE] @mth_ct5_clear_done
  MOVI r12,0x2000
  MOVHI r12,0x0003
  ADD r12,r12,r10
  ST r0,r12,0
  MOVI r12,0x3000
  MOVHI r12,0x0003
  ADD r12,r12,r10
  ST r0,r12,0
  ADDI r10,r10,1
  JMP @mth_ct5_clear
mth_ct5_clear_done:

  ; High-group probabilities.
  MOVI r1,0x0000
  MOVHI r1,0x0010
  MOVI r12,@mth_ct5_buckets
  LD r2,r12,0
  MOVI r12,@mth_ct5_bucket
  LD r3,r12,0
  MOVI r4,0x0000
  MOVHI r4,0x0003
  MOVI r12,0x4000
  ADD r4,r4,r12
  CALL @mth_ctxp16

  ; target_high = target >> 4, target_low = target & 15
  MOVI r12,@mth_ct5_target
  LD r10,r12,0
  SHR r11,r10,4
  MOVI r12,@mth_ct5_targ_high
  ST r11,r12,0
  SHL r10,r10,28
  SHR r10,r10,28
  MOVI r12,@mth_ct5_targ_low
  ST r10,r12,0
  MOVI r12,@mth_ct5_targ_p
  ST r0,r12,0

  ; For every high group, compute its low conditional distribution and merge
  ; all 16 candidates into the running top-5.
  MOVI r10,0
mth_ct5_high:
  MOVI r12,16
  CMP r10,r12
  JMP[GE] @mth_ct5_high_done
  MOVI r12,@mth_ct5_h
  ST r10,r12,0
  MOVI r12,@mth_ct5_l
  ST r0,r12,0

  ; low base = 0x100000 + 16*B*(h+1)
  MOVI r12,@mth_ct5_buckets
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r12,@mth_ct5_h
  LD r11,r12,0
  ADDI r11,r11,1
  MUL r10,r10,r11
  MOVI r1,0x0000
  MOVHI r1,0x0010
  ADD r1,r1,r10
  MOVI r12,@mth_ct5_buckets
  LD r2,r12,0
  MOVI r12,@mth_ct5_bucket
  LD r3,r12,0
  MOVI r4,0x0000
  MOVHI r4,0x0003
  MOVI r12,0x4100
  ADD r4,r4,r12
  CALL @mth_ctxp16

  MOVI r12,@mth_ct5_h
  LD r10,r12,0
  MOVI r12,0x4000
  MOVHI r12,0x0003
  ADD r12,r12,r10
  LD r9,r12,0
  MOVI r12,@mth_ct5_high_p
  ST r9,r12,0

mth_ct5_low:
  MOVI r12,@mth_ct5_l
  LD r10,r12,0
  MOVI r12,16
  CMP r10,r12
  JMP[GE] @mth_ct5_low_done
  MOVI r12,0x4100
  MOVHI r12,0x0003
  ADD r12,r12,r10
  LD r7,r12,0
  MOVI r12,@mth_ct5_high_p
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r12,@mth_ct5_p
  ST r7,r12,0

  ; class = h*16 + l
  MOVI r12,@mth_ct5_h
  LD r8,r12,0
  MOVI r12,16
  MUL r8,r8,r12
  ADD r8,r8,r10
  MOVI r12,@mth_ct5_class
  ST r8,r12,0

  ; Save the target probability while the correct high group is active.
  MOVI r12,@mth_ct5_targ_high
  LD r11,r12,0
  MOVI r12,@mth_ct5_h
  LD r12,r12,0
  CMP r11,r12
  JMP[NE] @mth_ct5_not_target_high
  MOVI r12,@mth_ct5_targ_low
  LD r11,r12,0
  CMP r11,r10
  JMP[NE] @mth_ct5_not_target_high
  MOVI r12,@mth_ct5_p
  LD r11,r12,0
  MOVI r12,@mth_ct5_targ_p
  ST r11,r12,0
mth_ct5_not_target_high:

  ; Insert into the descending top-5 if larger than the current worst.
  MOVI r11,4
mth_ct5_find:
  CMPS r11,r0
  JMP[LT] @mth_ct5_insert
  MOVI r12,0x2000
  MOVHI r12,0x0003
  ADD r12,r12,r11
  LD r9,r12,0
  MOVI r12,@mth_ct5_p
  LD r8,r12,0
  FCMP r8,r9
  JMP[GT] @mth_ct5_find_prev
  JMP @mth_ct5_insert
mth_ct5_find_prev:
  ADDI r11,r11,-1
  JMP @mth_ct5_find

mth_ct5_insert:
  ; insertion index = r11 + 1
  ADDI r11,r11,1
  MOVI r12,4
  CMP r11,r12
  JMP[GT] @mth_ct5_next_low
  MOVI r10,4
mth_ct5_shift:
  CMP r10,r11
  JMP[LE] @mth_ct5_shift_done
  MOVI r12,0x2000
  MOVHI r12,0x0003
  ADD r12,r12,r10
  MOVI r13,0x2000
  MOVHI r13,0x0003
  ADDI r14,r10,-1
  ADD r13,r13,r14
  LD r9,r13,0
  ST r9,r12,0
  MOVI r12,0x3000
  MOVHI r12,0x0003
  ADD r12,r12,r10
  MOVI r13,0x3000
  MOVHI r13,0x0003
  ADD r13,r13,r14
  LD r9,r13,0
  ST r9,r12,0
  ADDI r10,r10,-1
  JMP @mth_ct5_shift
mth_ct5_shift_done:
  MOVI r12,0x2000
  MOVHI r12,0x0003
  ADD r12,r12,r11
  MOVI r13,@mth_ct5_p
  LD r9,r13,0
  ST r9,r12,0
  MOVI r12,0x3000
  MOVHI r12,0x0003
  ADD r12,r12,r11
  MOVI r13,@mth_ct5_class
  LD r9,r13,0
  ST r9,r12,0

mth_ct5_next_low:
  ; The insertion loop clobbers r10, so keep l in a memory cell.
  MOVI r12,@mth_ct5_l
  LD r10,r12,0
  ADDI r10,r10,1
  ST r10,r12,0
  JMP @mth_ct5_low

mth_ct5_low_done:
  MOVI r12,@mth_ct5_h
  LD r10,r12,0
  ADDI r10,r10,1
  ST r10,r12,0
  JMP @mth_ct5_high
mth_ct5_high_done:

  ; loss = -ln(target probability).  Softmax probabilities are positive.
  MOVI r12,@mth_ct5_targ_p
  LD r7,r12,0
  FLOG r7,r7
  FSUB r7,r0,r7
  MOVI r12,@mth_ct5_loss
  ST r7,r12,0

  MOVI r12,0x3000
  MOVHI r12,0x0003
  LD r1,r12,0
  LD r2,r12,1
  LD r3,r12,2
  LD r4,r12,3
  LD r5,r12,4
  MOVI r12,@mth_ct5_loss
  LD r6,r12,0
  MOVI r12,@mth_ct5_link
  LD r15,r12,0
  RET

mth_ctxp_link:
  .word 0
mth_ctxp_table:
  .word 0
mth_ctxp_buckets:
  .word 0
mth_ctxp_bucket:
  .word 0
mth_ctxp_out:
  .word 0
mth_ctxp_max_score:
  .word 0
mth_ctxp_argmax:
  .word 0
mth_ctxp_sum:
  .word 0
mth_ctxp_inv:
  .word 0
mth_ct5_link:
  .word 0
mth_ct5_target:
  .word 0
mth_ct5_key:
  .word 0
mth_ct5_buckets:
  .word 0
mth_ct5_bucket:
  .word 0
mth_ct5_h:
  .word 0
mth_ct5_l:
  .word 0
mth_ct5_high_p:
  .word 0
mth_ct5_p:
  .word 0
mth_ct5_class:
  .word 0
mth_ct5_targ_high:
  .word 0
mth_ct5_targ_low:
  .word 0
mth_ct5_targ_p:
  .word 0
mth_ct5_loss:
  .word 0
