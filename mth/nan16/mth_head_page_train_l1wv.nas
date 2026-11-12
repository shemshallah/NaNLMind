; Raw NaN16 local layer-1 Wv update through layer-1 Wo.
; Uses the final output error as a local approximation; no layer-2 backprop.
;
; For the last query token:
;   e       = target - state
;   g_ctx   = Wo^T e
;   p[j]    = softmax probability of key token j (already in guest scratch)
;   Wv_layer1[k,d] += lr * p[j] * g_ctx[k] * xn1[j][d]
;
; Only layer 1's V projection is updated. Q/K and earlier layers are
; unchanged. This is a local approximation using the final output error.
mth_head_page_train_l1wv:
  MOVI r0,0
  ST r15,r0,@hl1wv_link
  ST r1,r0,@hl1wv_context
  ST r2,r0,@hl1wv_output
  ST r3,r0,@hl1wv_slot
  ST r4,r0,@hl1wv_t
  ST r5,r0,@hl1wv_target
  ST r6,r0,@hl1wv_lr
  CMP r1,r0
  JMP[EQ] @hl1wv_bad
  CMP r2,r0
  JMP[EQ] @hl1wv_bad
  CMP r5,r0
  JMP[EQ] @hl1wv_bad
  CMP r4,r0
  JMP[EQ] @hl1wv_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hl1wv_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hl1wv_bad
  LD r1,r0,@hl1wv_context
  LD r2,r0,@hl1wv_output
  LD r3,r0,@hl1wv_slot
  LD r4,r0,@hl1wv_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hl1wv_forward_bad

  ; Last-token state and error array/norm.
  LD r10,r0,@hl1wv_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  LD r11,r0,@hl1wv_output
  ADD r11,r11,r10
  ST r11,r0,@hl1wv_state
  MOVI r10,0
  ST r10,r0,@hl1wv_err_norm
  MOVI r10,0
  ST r10,r0,@hl1wv_d
hl1wv_err:
  LD r10,r0,@hl1wv_d
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1wv_err_done
  LD r12,r0,@hl1wv_state
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1wv_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r10
  ST r14,r15,0
  FMUL r14,r14,r14
  MOVI r15,@hl1wv_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hl1wv_err_norm
  ADDI r10,r10,1
  ST r10,r0,@hl1wv_d
  JMP @hl1wv_err
hl1wv_err_done:

  ; Page base, Wo and Wv layer-2 offsets.
  LD r10,r0,@hl1wv_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0xA000
  MOVHI r11,0x0001
  ADD r10,r10,r11
  ST r10,r0,@hl1wv_wo
  LD r10,r0,@hl1wv_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0x8000
  MOVHI r11,0x0001
  ADD r10,r10,r11
  ST r10,r0,@hl1wv_wv

  ; g_ctx[k] = sum_j Wo[j,k] * error[j]
  MOVI r10,0
  ST r10,r0,@hl1wv_k
hl1wv_gctx_row:
  LD r10,r0,@hl1wv_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1wv_gctx_done
  MOVI r13,0
  MOVI r12,0
  ST r12,r0,@hl1wv_j
hl1wv_gctx_j:
  LD r12,r0,@hl1wv_j
  MOVI r14,128
  CMP r12,r14
  JMP[GE] @hl1wv_gctx_store
  MOVI r14,64
  MUL r14,r12,r14
  SHR r15,r10,1
  ADD r14,r14,r15
  LD r15,r0,@hl1wv_wo
  ADD r15,r15,r14
  LD r14,r15,0
  MOVI r15,1
  SHL r15,r10,31
  SHR r15,r15,31
  CMP r15,r0
  JMP[EQ] @hl1wv_wo_low
  SHR r14,r14,16
  SHL r14,r14,16
  JMP @hl1wv_wo_have
hl1wv_wo_low:
  SHL r14,r14,16
hl1wv_wo_have:
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r12
  LD r15,r15,0
  FMUL r14,r14,r15
  FADD r13,r13,r14
  ADDI r12,r12,1
  ST r12,r0,@hl1wv_j
  JMP @hl1wv_gctx_j
hl1wv_gctx_store:
  MOVI r14,0x3200
  MOVHI r14,0x00D0
  ADD r14,r14,r10
  ST r13,r14,0
  LD r10,r0,@hl1wv_k
  ADDI r10,r10,1
  ST r10,r0,@hl1wv_k
  JMP @hl1wv_gctx_row
hl1wv_gctx_done:

  ; For each key token j, update Wv with probability p[j].
  MOVI r10,0
  ST r10,r0,@hl1wv_j
hl1wv_token:
  LD r10,r0,@hl1wv_j
  LD r11,r0,@hl1wv_t
  CMP r10,r11
  JMP[GE] @hl1wv_ok
  MOVI r12,0x4008
  MOVHI r12,0x00D2
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1wv_lr
  FMUL r12,r12,r13
  ST r12,r0,@hl1wv_p_lr
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r13,0x3400
  MOVHI r13,0x00D2
  ADD r13,r13,r12
  ST r13,r0,@hl1wv_xn
  MOVI r10,0
  ST r10,r0,@hl1wv_k
hl1wv_wv_row:
  LD r10,r0,@hl1wv_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1wv_next_token
  MOVI r12,0x3200
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1wv_p_lr
  FMUL r12,r12,r13
  ST r12,r0,@hl1wv_scale
  MOVI r12,64
  MUL r12,r10,r12
  LD r13,r0,@hl1wv_wv
  ADD r13,r13,r12
  ST r13,r0,@hl1wv_rowptr
  MOVI r12,0
  ST r12,r0,@hl1wv_d
hl1wv_wv_col:
  LD r12,r0,@hl1wv_d
  MOVI r15,128
  CMP r12,r15
  JMP[GE] @hl1wv_next_row
  SHR r15,r12,1
  LD r14,r0,@hl1wv_rowptr
  ADD r14,r14,r15
  LD r15,r14,0
  MOVI r11,1
  SHL r11,r12,31
  SHR r11,r11,31
  CMP r11,r0
  JMP[EQ] @hl1wv_low
  SHR r11,r15,16
  SHL r11,r11,16
  JMP @hl1wv_have
hl1wv_low:
  SHL r11,r15,16
hl1wv_have:
  LD r9,r0,@hl1wv_scale
  LD r8,r0,@hl1wv_xn
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
  JMP[EQ] @hl1wv_merge_low
  SHL r9,r11,16
  SHL r15,r15,16
  SHR r15,r15,16
  ADD r15,r15,r9
  JMP @hl1wv_store
hl1wv_merge_low:
  SHR r9,r15,16
  SHL r9,r9,16
  ADD r15,r9,r11
hl1wv_store:
  ST r15,r14,0
  ADDI r12,r12,1
  ST r12,r0,@hl1wv_d
  JMP @hl1wv_wv_col
hl1wv_next_row:
  LD r10,r0,@hl1wv_k
  ADDI r10,r10,1
  ST r10,r0,@hl1wv_k
  JMP @hl1wv_wv_row
hl1wv_next_token:
  LD r10,r0,@hl1wv_j
  ADDI r10,r10,1
  ST r10,r0,@hl1wv_j
  JMP @hl1wv_token
hl1wv_ok:
  MOVI r1,1
  LD r2,r0,@hl1wv_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hl1wv_link
  RET
hl1wv_forward_bad:
  MOVI r4,2
  JMP @hl1wv_reject
hl1wv_bad:
  MOVI r4,1
hl1wv_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hl1wv_link
  RET

hl1wv_link:
  .word 0
hl1wv_context:
  .word 0
hl1wv_output:
  .word 0
hl1wv_slot:
  .word 0
hl1wv_t:
  .word 0
hl1wv_target:
  .word 0
hl1wv_lr:
  .word 0
hl1wv_state:
  .word 0
hl1wv_err_norm:
  .word 0
hl1wv_d:
  .word 0
hl1wv_j:
  .word 0
hl1wv_k:
  .word 0
hl1wv_wo:
  .word 0
hl1wv_wv:
  .word 0
hl1wv_xn:
  .word 0
hl1wv_p_lr:
  .word 0
hl1wv_scale:
  .word 0
hl1wv_rowptr:
  .word 0
