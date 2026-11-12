; Raw NaN16 local Wv update through final Wo attention projection.
;
; For the last query token:
;   e       = target - state
;   g_ctx   = Wo^T e
;   p[j]    = softmax probability of key token j (already in guest scratch)
;   Wv[k,d] += lr * p[j] * g_ctx[k] * xn[j][d]
;
; Only the last layer's V projection is updated. Q/K and earlier layers are
; unchanged. All arithmetic is guest-side; the host transports target/lr and
; exports the modified page slot.
mth_head_page_train_wv:
  MOVI r0,0
  ST r15,r0,@hwv_link
  ST r1,r0,@hwv_context
  ST r2,r0,@hwv_output
  ST r3,r0,@hwv_slot
  ST r4,r0,@hwv_t
  ST r5,r0,@hwv_target
  ST r6,r0,@hwv_lr
  CMP r1,r0
  JMP[EQ] @hwv_bad
  CMP r2,r0
  JMP[EQ] @hwv_bad
  CMP r5,r0
  JMP[EQ] @hwv_bad
  CMP r4,r0
  JMP[EQ] @hwv_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hwv_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hwv_bad
  LD r1,r0,@hwv_context
  LD r2,r0,@hwv_output
  LD r3,r0,@hwv_slot
  LD r4,r0,@hwv_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hwv_forward_bad

  ; Last-token state and error array/norm.
  LD r10,r0,@hwv_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  LD r11,r0,@hwv_output
  ADD r11,r11,r10
  ST r11,r0,@hwv_state
  MOVI r10,0
  ST r10,r0,@hwv_err_norm
  MOVI r10,0
  ST r10,r0,@hwv_d
hwv_err:
  LD r10,r0,@hwv_d
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hwv_err_done
  LD r12,r0,@hwv_state
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hwv_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r10
  ST r14,r15,0
  FMUL r14,r14,r14
  MOVI r15,@hwv_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hwv_err_norm
  ADDI r10,r10,1
  ST r10,r0,@hwv_d
  JMP @hwv_err
hwv_err_done:

  ; Page base, Wo and Wv layer-2 offsets.
  LD r10,r0,@hwv_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0xE000
  MOVHI r11,0x0002
  ADD r10,r10,r11
  ST r10,r0,@hwv_wo
  LD r10,r0,@hwv_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0xC000
  MOVHI r11,0x0002
  ADD r10,r10,r11
  ST r10,r0,@hwv_wv

  ; g_ctx[k] = sum_j Wo[j,k] * error[j]
  MOVI r10,0
  ST r10,r0,@hwv_k
hwv_gctx_row:
  LD r10,r0,@hwv_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hwv_gctx_done
  MOVI r13,0
  MOVI r12,0
  ST r12,r0,@hwv_j
hwv_gctx_j:
  LD r12,r0,@hwv_j
  MOVI r14,128
  CMP r12,r14
  JMP[GE] @hwv_gctx_store
  MOVI r14,64
  MUL r14,r12,r14
  SHR r15,r10,1
  ADD r14,r14,r15
  LD r15,r0,@hwv_wo
  ADD r15,r15,r14
  LD r14,r15,0
  MOVI r15,1
  SHL r15,r10,31
  SHR r15,r15,31
  CMP r15,r0
  JMP[EQ] @hwv_wo_low
  SHR r14,r14,16
  SHL r14,r14,16
  JMP @hwv_wo_have
hwv_wo_low:
  SHL r14,r14,16
hwv_wo_have:
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r12
  LD r15,r15,0
  FMUL r14,r14,r15
  FADD r13,r13,r14
  ADDI r12,r12,1
  ST r12,r0,@hwv_j
  JMP @hwv_gctx_j
hwv_gctx_store:
  MOVI r14,0x3200
  MOVHI r14,0x00D0
  ADD r14,r14,r10
  ST r13,r14,0
  LD r10,r0,@hwv_k
  ADDI r10,r10,1
  ST r10,r0,@hwv_k
  JMP @hwv_gctx_row
hwv_gctx_done:

  ; For each key token j, update Wv with probability p[j].
  MOVI r10,0
  ST r10,r0,@hwv_j
hwv_token:
  LD r10,r0,@hwv_j
  LD r11,r0,@hwv_t
  CMP r10,r11
  JMP[GE] @hwv_ok
  MOVI r12,0x1810
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hwv_lr
  FMUL r12,r12,r13
  ST r12,r0,@hwv_p_lr
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r13,0x0300
  MOVHI r13,0x00D0
  ADD r13,r13,r12
  ST r13,r0,@hwv_xn
  MOVI r10,0
  ST r10,r0,@hwv_k
hwv_wv_row:
  LD r10,r0,@hwv_k
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hwv_next_token
  MOVI r12,0x3200
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hwv_p_lr
  FMUL r12,r12,r13
  ST r12,r0,@hwv_scale
  MOVI r12,64
  MUL r12,r10,r12
  LD r13,r0,@hwv_wv
  ADD r13,r13,r12
  ST r13,r0,@hwv_rowptr
  MOVI r12,0
  ST r12,r0,@hwv_d
hwv_wv_col:
  LD r12,r0,@hwv_d
  MOVI r15,128
  CMP r12,r15
  JMP[GE] @hwv_next_row
  SHR r15,r12,1
  LD r14,r0,@hwv_rowptr
  ADD r14,r14,r15
  LD r15,r14,0
  MOVI r11,1
  SHL r11,r12,31
  SHR r11,r11,31
  CMP r11,r0
  JMP[EQ] @hwv_low
  SHR r11,r15,16
  SHL r11,r11,16
  JMP @hwv_have
hwv_low:
  SHL r11,r15,16
hwv_have:
  LD r9,r0,@hwv_scale
  LD r8,r0,@hwv_xn
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
  JMP[EQ] @hwv_merge_low
  SHL r9,r11,16
  SHL r15,r15,16
  SHR r15,r15,16
  ADD r15,r15,r9
  JMP @hwv_store
hwv_merge_low:
  SHR r9,r15,16
  SHL r9,r9,16
  ADD r15,r9,r11
hwv_store:
  ST r15,r14,0
  ADDI r12,r12,1
  ST r12,r0,@hwv_d
  JMP @hwv_wv_col
hwv_next_row:
  LD r10,r0,@hwv_k
  ADDI r10,r10,1
  ST r10,r0,@hwv_k
  JMP @hwv_wv_row
hwv_next_token:
  LD r10,r0,@hwv_j
  ADDI r10,r10,1
  ST r10,r0,@hwv_j
  JMP @hwv_token
hwv_ok:
  MOVI r1,1
  LD r2,r0,@hwv_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hwv_link
  RET
hwv_forward_bad:
  MOVI r4,2
  JMP @hwv_reject
hwv_bad:
  MOVI r4,1
hwv_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hwv_link
  RET

hwv_link:
  .word 0
hwv_context:
  .word 0
hwv_output:
  .word 0
hwv_slot:
  .word 0
hwv_t:
  .word 0
hwv_target:
  .word 0
hwv_lr:
  .word 0
hwv_state:
  .word 0
hwv_err_norm:
  .word 0
hwv_d:
  .word 0
hwv_j:
  .word 0
hwv_k:
  .word 0
hwv_wo:
  .word 0
hwv_wv:
  .word 0
hwv_xn:
  .word 0
hwv_p_lr:
  .word 0
hwv_scale:
  .word 0
hwv_rowptr:
  .word 0
