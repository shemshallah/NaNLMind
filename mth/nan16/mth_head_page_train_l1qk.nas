; Raw NaN16 local layer-1 Wq/Wk update through layer-1 softmax attention.
; Uses the final output error as a local approximation; no layer-2 backprop.
;
; For layer 1's last query token:
;   e       = target - final state
;   g_ctx   = Wo_layer1^T e
;   g_v[j]  = g_ctx . V[j]
;   mean    = sum_j p[j] * g_v[j]
;   d_s[j]  = p[j] * (g_v[j] - mean)          (dL/dscaled-score)
;   d_q     = sum_j d_s[j] * K[j] / sqrt(128)
;   d_k[j]  = d_s[j] * Q[last] / sqrt(128)
;   Wq_layer1[k,d] += lr * d_q[k] * xn1[last][d]
;   Wk_layer1[k,d] += lr * sum_j d_k[j][k] * xn1[j][d]
;
; Only layer 1's Q/K projections are updated. No earlier layers, no optimizer
; state, and no tensor promotion. All math is guest-side.
mth_head_page_train_l1qk:
  MOVI r0,0
  ST r15,r0,@hl1qk_link
  ST r1,r0,@hl1qk_context
  ST r2,r0,@hl1qk_output
  ST r3,r0,@hl1qk_slot
  ST r4,r0,@hl1qk_t
  ST r5,r0,@hl1qk_target
  ST r6,r0,@hl1qk_lr
  CMP r1,r0
  JMP[EQ] @hl1qk_bad
  CMP r2,r0
  JMP[EQ] @hl1qk_bad
  CMP r5,r0
  JMP[EQ] @hl1qk_bad
  CMP r4,r0
  JMP[EQ] @hl1qk_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hl1qk_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hl1qk_bad
  LD r1,r0,@hl1qk_context
  LD r2,r0,@hl1qk_output
  LD r3,r0,@hl1qk_slot
  LD r4,r0,@hl1qk_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hl1qk_forward_bad

  ; Last state and error array/norm.
  LD r10,r0,@hl1qk_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  LD r11,r0,@hl1qk_output
  ADD r11,r11,r10
  ST r11,r0,@hl1qk_state
  MOVI r10,0
  ST r10,r0,@hl1qk_err_norm
  MOVI r10,0
  ST r10,r0,@hl1qk_d
hl1qk_err:
  LD r10,r0,@hl1qk_d
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1qk_err_done
  LD r12,r0,@hl1qk_state
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1qk_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r10
  ST r14,r15,0
  FMUL r14,r14,r14
  MOVI r15,@hl1qk_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hl1qk_err_norm
  ADDI r10,r10,1
  ST r10,r0,@hl1qk_d
  JMP @hl1qk_err
hl1qk_err_done:

  ; Page bases: layer2 Wq=0x28000, Wk=0x2A000, Wo=0x2E000 words.
  LD r10,r0,@hl1qk_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0x4000
  MOVHI r11,0x0001
  ADD r10,r10,r11
  ST r10,r0,@hl1qk_wq
  LD r10,r0,@hl1qk_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0x6000
  MOVHI r11,0x0001
  ADD r10,r10,r11
  ST r10,r0,@hl1qk_wk
  LD r10,r0,@hl1qk_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0xA000
  MOVHI r11,0x0001
  ADD r10,r10,r11
  ST r10,r0,@hl1qk_wo

  ; g_ctx[k] = sum_j Wo[j,k] * error[j]
  MOVI r10,0
  ST r10,r0,@hl1qk_k
hl1qk_gctx_row:
  LD r10,r0,@hl1qk_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1qk_gctx_done
  MOVI r13,0
  MOVI r12,0
  ST r12,r0,@hl1qk_j
hl1qk_gctx_j:
  LD r12,r0,@hl1qk_j
  MOVI r14,128
  CMP r12,r14
  JMP[GE] @hl1qk_gctx_store
  MOVI r14,64
  MUL r14,r12,r14
  SHR r15,r10,1
  ADD r14,r14,r15
  LD r15,r0,@hl1qk_wo
  ADD r15,r15,r14
  LD r14,r15,0
  MOVI r15,1
  SHL r15,r10,31
  SHR r15,r15,31
  CMP r15,r0
  JMP[EQ] @hl1qk_wo_low
  SHR r14,r14,16
  SHL r14,r14,16
  JMP @hl1qk_wo_have
hl1qk_wo_low:
  SHL r14,r14,16
hl1qk_wo_have:
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r12
  LD r15,r15,0
  FMUL r14,r14,r15
  FADD r13,r13,r14
  ADDI r12,r12,1
  ST r12,r0,@hl1qk_j
  JMP @hl1qk_gctx_j
hl1qk_gctx_store:
  MOVI r14,0x3200
  MOVHI r14,0x00D0
  ADD r14,r14,r10
  ST r13,r14,0
  LD r10,r0,@hl1qk_k
  ADDI r10,r10,1
  ST r10,r0,@hl1qk_k
  JMP @hl1qk_gctx_row
hl1qk_gctx_done:

  ; g_v[j] and mean over last-query probabilities.
  MOVI r10,0
  ST r10,r0,@hl1qk_mean
  MOVI r10,0
  ST r10,r0,@hl1qk_j
hl1qk_gv:
  LD r10,r0,@hl1qk_j
  LD r11,r0,@hl1qk_t
  CMP r10,r11
  JMP[GE] @hl1qk_gv_done
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r13,0x2400
  MOVHI r13,0x00D2
  ADD r13,r13,r12
  MOVI r14,0
  ST r14,r0,@hl1qk_k
  MOVI r15,0
hl1qk_gv_k:
  LD r14,r0,@hl1qk_k
  MOVI r12,128
  CMP r14,r12
  JMP[GE] @hl1qk_gv_store
  MOVI r12,0x3200
  MOVHI r12,0x00D0
  ADD r12,r12,r14
  LD r12,r12,0
  ADD r11,r13,r14
  LD r11,r11,0
  FMUL r12,r12,r11
  FADD r15,r15,r12
  ADDI r14,r14,1
  ST r14,r0,@hl1qk_k
  JMP @hl1qk_gv_k
hl1qk_gv_store:
  MOVI r14,0x3310
  MOVHI r14,0x00D0
  LD r12,r0,@hl1qk_j
  ADD r14,r14,r12
  ST r15,r14,0
  MOVI r14,0x4008
  MOVHI r14,0x00D2
  ADD r14,r14,r12
  LD r14,r14,0
  FMUL r14,r14,r15
  MOVI r15,@hl1qk_mean
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hl1qk_mean
  ADDI r12,r12,1
  ST r12,r0,@hl1qk_j
  JMP @hl1qk_gv
hl1qk_gv_done:

  ; d_s[j] = p[j] * (g_v[j] - mean)
  MOVI r10,0
  ST r10,r0,@hl1qk_j
hl1qk_ds:
  LD r10,r0,@hl1qk_j
  LD r11,r0,@hl1qk_t
  CMP r10,r11
  JMP[GE] @hl1qk_ds_done
  MOVI r12,0x4008
  MOVHI r12,0x00D2
  ADD r12,r12,r10
  LD r12,r12,0
  MOVI r13,0x3310
  MOVHI r13,0x00D0
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,@hl1qk_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  FMUL r12,r12,r13
  MOVI r13,0x3300
  MOVHI r13,0x00D0
  ADD r13,r13,r10
  ST r12,r13,0
  ADDI r10,r10,1
  ST r10,r0,@hl1qk_j
  JMP @hl1qk_ds
hl1qk_ds_done:

  ; d_q[k] = inv_sqrt * sum_j d_s[j] * K[j][k]
  MOVI r10,0
  ST r10,r0,@hl1qk_k
hl1qk_dq_row:
  LD r10,r0,@hl1qk_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1qk_dq_done
  MOVI r13,0
  MOVI r12,0
  ST r12,r0,@hl1qk_j
hl1qk_dq_j:
  LD r12,r0,@hl1qk_j
  LD r11,r0,@hl1qk_t
  CMP r12,r11
  JMP[GE] @hl1qk_dq_store
  MOVI r14,0x3300
  MOVHI r14,0x00D0
  ADD r14,r14,r12
  LD r14,r14,0
  MOVI r15,128
  MUL r15,r12,r15
  ADD r15,r15,r10
  MOVI r11,0x1400
  MOVHI r11,0x00D2
  ADD r15,r15,r11
  LD r15,r15,0
  FMUL r14,r14,r15
  FADD r13,r13,r14
  ADDI r12,r12,1
  ST r12,r0,@hl1qk_j
  JMP @hl1qk_dq_j
hl1qk_dq_store:
  MOVI r14,@hl1qk_inv_sqrt
  LD r14,r14,0
  FMUL r13,r13,r14
  MOVI r14,0x3400
  MOVHI r14,0x00D0
  ADD r14,r14,r10
  ST r13,r14,0
  LD r10,r0,@hl1qk_k
  ADDI r10,r10,1
  ST r10,r0,@hl1qk_k
  JMP @hl1qk_dq_row
hl1qk_dq_done:

  ; Wq update with xn[last].
  LD r10,r0,@hl1qk_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  MOVI r11,0x3400
  MOVHI r11,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@hl1qk_xn_last
  MOVI r10,0
  ST r10,r0,@hl1qk_k
hl1qk_wq_row:
  LD r10,r0,@hl1qk_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1qk_wq_done
  MOVI r12,0x3400
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1qk_lr
  FMUL r12,r12,r13
  ST r12,r0,@hl1qk_scale
  MOVI r12,64
  MUL r12,r10,r12
  LD r13,r0,@hl1qk_wq
  ADD r13,r13,r12
  ST r13,r0,@hl1qk_rowptr
  MOVI r12,0
  ST r12,r0,@hl1qk_d
hl1qk_wq_col:
  LD r12,r0,@hl1qk_d
  MOVI r15,128
  CMP r12,r15
  JMP[GE] @hl1qk_wq_next
  SHR r15,r12,1
  LD r14,r0,@hl1qk_rowptr
  ADD r14,r14,r15
  LD r15,r14,0
  MOVI r11,1
  SHL r11,r12,31
  SHR r11,r11,31
  CMP r11,r0
  JMP[EQ] @hl1qk_wq_low
  SHR r11,r15,16
  SHL r11,r11,16
  JMP @hl1qk_wq_have
hl1qk_wq_low:
  SHL r11,r15,16
hl1qk_wq_have:
  LD r9,r0,@hl1qk_scale
  LD r8,r0,@hl1qk_xn_last
  ADD r8,r8,r12
  LD r8,r8,0
  FMUL r9,r9,r8
  FADD r11,r11,r9
  MOVI r9,0x8000
  ADD r11,r11,r9
  SHR r11,r11,16
  MOVI r9,1
  SHL r9,r12,31
  SHR r9,r9,31
  CMP r9,r0
  JMP[EQ] @hl1qk_wq_merge_low
  SHL r9,r11,16
  SHL r15,r15,16
  SHR r15,r15,16
  ADD r15,r15,r9
  JMP @hl1qk_wq_store
hl1qk_wq_merge_low:
  SHR r9,r15,16
  SHL r9,r9,16
  ADD r15,r9,r11
hl1qk_wq_store:
  ST r15,r14,0
  ADDI r12,r12,1
  ST r12,r0,@hl1qk_d
  JMP @hl1qk_wq_col
hl1qk_wq_next:
  LD r10,r0,@hl1qk_k
  ADDI r10,r10,1
  ST r10,r0,@hl1qk_k
  JMP @hl1qk_wq_row
hl1qk_wq_done:

  ; Wk updates for each key token j: d_k[j]=d_s[j]*Q[last]/sqrt(128).
  LD r10,r0,@hl1qk_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  MOVI r11,0x0400
  MOVHI r11,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@hl1qk_q_last
  MOVI r10,0
  ST r10,r0,@hl1qk_j
hl1qk_wk_token:
  LD r10,r0,@hl1qk_j
  LD r11,r0,@hl1qk_t
  CMP r10,r11
  JMP[GE] @hl1qk_ok
  MOVI r12,0x3300
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1qk_lr
  FMUL r12,r12,r13
  MOVI r13,@hl1qk_inv_sqrt
  LD r13,r13,0
  FMUL r12,r12,r13
  ST r12,r0,@hl1qk_ds_scale
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r13,0x0300
  MOVHI r13,0x00D0
  ADD r13,r13,r12
  ST r13,r0,@hl1qk_xn
  MOVI r10,0
  ST r10,r0,@hl1qk_k
hl1qk_wk_row:
  LD r10,r0,@hl1qk_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1qk_wk_next_token
  LD r12,r0,@hl1qk_q_last
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1qk_ds_scale
  FMUL r12,r12,r13
  ST r12,r0,@hl1qk_scale
  MOVI r12,64
  MUL r12,r10,r12
  LD r13,r0,@hl1qk_wk
  ADD r13,r13,r12
  ST r13,r0,@hl1qk_rowptr
  MOVI r12,0
  ST r12,r0,@hl1qk_d
hl1qk_wk_col:
  LD r12,r0,@hl1qk_d
  MOVI r15,128
  CMP r12,r15
  JMP[GE] @hl1qk_wk_next
  SHR r15,r12,1
  LD r14,r0,@hl1qk_rowptr
  ADD r14,r14,r15
  LD r15,r14,0
  MOVI r11,1
  SHL r11,r12,31
  SHR r11,r11,31
  CMP r11,r0
  JMP[EQ] @hl1qk_wk_low
  SHR r11,r15,16
  SHL r11,r11,16
  JMP @hl1qk_wk_have
hl1qk_wk_low:
  SHL r11,r15,16
hl1qk_wk_have:
  LD r9,r0,@hl1qk_scale
  LD r8,r0,@hl1qk_xn
  ADD r8,r8,r12
  LD r8,r8,0
  FMUL r9,r9,r8
  FADD r11,r11,r9
  MOVI r9,0x8000
  ADD r11,r11,r9
  SHR r11,r11,16
  MOVI r9,1
  SHL r9,r12,31
  SHR r9,r9,31
  CMP r9,r0
  JMP[EQ] @hl1qk_wk_merge_low
  SHL r9,r11,16
  SHL r15,r15,16
  SHR r15,r15,16
  ADD r15,r15,r9
  JMP @hl1qk_wk_store
hl1qk_wk_merge_low:
  SHR r9,r15,16
  SHL r9,r9,16
  ADD r15,r9,r11
hl1qk_wk_store:
  ST r15,r14,0
  ADDI r12,r12,1
  ST r12,r0,@hl1qk_d
  JMP @hl1qk_wk_col
hl1qk_wk_next:
  LD r10,r0,@hl1qk_k
  ADDI r10,r10,1
  ST r10,r0,@hl1qk_k
  JMP @hl1qk_wk_row
hl1qk_wk_next_token:
  LD r10,r0,@hl1qk_j
  ADDI r10,r10,1
  ST r10,r0,@hl1qk_j
  JMP @hl1qk_wk_token
hl1qk_ok:
  MOVI r1,1
  LD r2,r0,@hl1qk_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hl1qk_link
  RET
hl1qk_forward_bad:
  MOVI r4,2
  JMP @hl1qk_reject
hl1qk_bad:
  MOVI r4,1
hl1qk_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hl1qk_link
  RET

hl1qk_link:
  .word 0
hl1qk_context:
  .word 0
hl1qk_output:
  .word 0
hl1qk_slot:
  .word 0
hl1qk_t:
  .word 0
hl1qk_target:
  .word 0
hl1qk_lr:
  .word 0
hl1qk_state:
  .word 0
hl1qk_err_norm:
  .word 0
hl1qk_d:
  .word 0
hl1qk_j:
  .word 0
hl1qk_k:
  .word 0
hl1qk_mean:
  .word 0
hl1qk_inv_sqrt:
  .word 0x3DB504F3
hl1qk_wq:
  .word 0
hl1qk_wk:
  .word 0
hl1qk_wo:
  .word 0
hl1qk_q_last:
  .word 0
hl1qk_xn_last:
  .word 0
hl1qk_xn:
  .word 0
hl1qk_scale:
  .word 0
hl1qk_ds_scale:
  .word 0
hl1qk_rowptr:
  .word 0
