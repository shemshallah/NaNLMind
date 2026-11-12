; Raw NaN16 one-step local W1 update through the final W2 projection.
;
; Forward (last token): h = tanh(W1*xn2), y = x1 + W2*h.
; Given target t and e = t - y:
;   g_h[k]  = sum_j W2[j,k] * e[j]
;   g_z[k]  = g_h[k] * (1 - h[k]^2)
;   W1[k,d] += lr * g_z[k] * xn2[d]
;
; This is a local hidden-projection update using the final W2 layer. It does
; not update the earlier layers or Wo/W2 in the same step. All arithmetic is
; guest-side; the host only transports target/lr and exports the page bytes.
;
; ABI same as opcode125/126:
;   r1 context f32[T*128], r2 output, r3 slot, r4 T,
;   r5 target f32[128], r6 lr bits.
; Returns r1=1, r2=error norm f32 bits, r3=0, r4=0.
mth_head_page_train_w1:
  MOVI r0,0
  ST r15,r0,@hw1_link
  ST r1,r0,@hw1_context
  ST r2,r0,@hw1_output
  ST r3,r0,@hw1_slot
  ST r4,r0,@hw1_t
  ST r5,r0,@hw1_target
  ST r6,r0,@hw1_lr
  CMP r1,r0
  JMP[EQ] @hw1_bad
  CMP r2,r0
  JMP[EQ] @hw1_bad
  CMP r5,r0
  JMP[EQ] @hw1_bad
  CMP r4,r0
  JMP[EQ] @hw1_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hw1_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hw1_bad
  LD r1,r0,@hw1_context
  LD r2,r0,@hw1_output
  LD r3,r0,@hw1_slot
  LD r4,r0,@hw1_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hw1_forward_bad

  ; Last-token output pointer and error vector/norm.
  LD r10,r0,@hw1_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  LD r11,r0,@hw1_output
  ADD r11,r11,r10
  ST r11,r0,@hw1_state
  MOVI r10,0
  ST r10,r0,@hw1_err_norm
  MOVI r10,0
  ST r10,r0,@hw1_d
hw1_err:
  LD r10,r0,@hw1_d
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hw1_err_done
  LD r12,r0,@hw1_state
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hw1_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r10
  ST r14,r15,0
  FMUL r14,r14,r14
  MOVI r15,@hw1_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hw1_err_norm
  ADDI r10,r10,1
  ST r10,r0,@hw1_d
  JMP @hw1_err
hw1_err_done:

  ; Page base and layer-2 W1/W2 word offsets.
  LD r10,r0,@hw1_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0x0000
  MOVHI r11,0x0003
  ADD r10,r10,r11
  ST r10,r0,@hw1_w1
  LD r10,r0,@hw1_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0x6000
  MOVHI r11,0x0003
  ADD r10,r10,r11
  ST r10,r0,@hw1_w2

  ; xn2 for the last token.
  LD r10,r0,@hw1_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  MOVI r11,0x0300
  MOVHI r11,0x00D0
  ADD r10,r10,r11
  ST r10,r0,@hw1_xn2

  MOVI r10,0
  ST r10,r0,@hw1_k
hw1_row:
  LD r10,r0,@hw1_k
  MOVI r12,384
  CMP r10,r12
  JMP[GE] @hw1_ok
  ; g_h = sum_j W2[j,k] * error[j]
  MOVI r13,0
  MOVI r12,0
  ST r12,r0,@hw1_j
hw1_grad_h:
  LD r12,r0,@hw1_j
  MOVI r14,128
  CMP r12,r14
  JMP[GE] @hw1_grad_done
  MOVI r14,192
  MUL r14,r12,r14
  SHR r15,r10,1
  ADD r14,r14,r15
  LD r15,r0,@hw1_w2
  ADD r15,r15,r14
  LD r14,r15,0
  MOVI r15,1
  SHL r15,r10,31
  SHR r15,r15,31
  CMP r15,r0
  JMP[EQ] @hw1_w2_low
  SHR r14,r14,16
  SHL r14,r14,16
  JMP @hw1_w2_have
hw1_w2_low:
  SHL r14,r14,16
hw1_w2_have:
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r12
  LD r15,r15,0
  FMUL r14,r14,r15
  FADD r13,r13,r14
  ADDI r12,r12,1
  ST r12,r0,@hw1_j
  JMP @hw1_grad_h
hw1_grad_done:
  ; g_z = g_h * (1 - h^2)
  MOVI r12,0x1500
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r12,r12,0
  FMUL r14,r12,r12
  MOVI r15,0
  MOVHI r15,0x3F80
  FSUB r15,r15,r14
  FMUL r13,r13,r15
  LD r14,r0,@hw1_lr
  FMUL r13,r13,r14
  ST r13,r0,@hw1_scale
  ; W1 row pointer = W1 + k*64
  MOVI r12,64
  MUL r12,r10,r12
  LD r14,r0,@hw1_w1
  ADD r14,r14,r12
  ST r14,r0,@hw1_rowptr
  MOVI r12,0
  ST r12,r0,@hw1_d
hw1_col:
  LD r12,r0,@hw1_d
  MOVI r15,128
  CMP r12,r15
  JMP[GE] @hw1_next_row
  SHR r15,r12,1
  LD r14,r0,@hw1_rowptr
  ADD r14,r14,r15
  LD r15,r14,0
  MOVI r11,1
  SHL r11,r12,31
  SHR r11,r11,31
  CMP r11,r0
  JMP[EQ] @hw1_low
  SHR r11,r15,16
  SHL r11,r11,16
  JMP @hw1_have
hw1_low:
  SHL r11,r15,16
hw1_have:
  LD r9,r0,@hw1_scale
  LD r8,r0,@hw1_xn2
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
  JMP[EQ] @hw1_merge_low
  SHL r9,r11,16
  SHL r15,r15,16
  SHR r15,r15,16
  ADD r15,r15,r9
  JMP @hw1_store
hw1_merge_low:
  SHR r9,r15,16
  SHL r9,r9,16
  ADD r15,r9,r11
hw1_store:
  ST r15,r14,0
  ADDI r12,r12,1
  ST r12,r0,@hw1_d
  JMP @hw1_col
hw1_next_row:
  LD r10,r0,@hw1_k
  ADDI r10,r10,1
  ST r10,r0,@hw1_k
  JMP @hw1_row
hw1_ok:
  MOVI r1,1
  LD r2,r0,@hw1_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hw1_link
  RET
hw1_forward_bad:
  MOVI r4,2
  JMP @hw1_reject
hw1_bad:
  MOVI r4,1
hw1_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hw1_link
  RET

hw1_link:
  .word 0
hw1_context:
  .word 0
hw1_output:
  .word 0
hw1_slot:
  .word 0
hw1_t:
  .word 0
hw1_target:
  .word 0
hw1_lr:
  .word 0
hw1_state:
  .word 0
hw1_err_norm:
  .word 0
hw1_d:
  .word 0
hw1_j:
  .word 0
hw1_k:
  .word 0
hw1_w1:
  .word 0
hw1_w2:
  .word 0
hw1_xn2:
  .word 0
hw1_scale:
  .word 0
hw1_rowptr:
  .word 0
