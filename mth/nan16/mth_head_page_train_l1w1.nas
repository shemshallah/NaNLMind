; Raw NaN16 local layer-1 W1 update through layer-1 W2.
; Uses the final output error as a local approximation; does not backpropagate
; through layer 2.
;
; Forward (layer 1, last token): h1 = tanh(W1_1*xn1), x2 = x1 + W2_1*h1.
; Given the final target error e:
;   g_h[k]  = sum_j W2[j,k] * e[j]
;   g_z[k]  = g_h[k] * (1 - h[k]^2)
;   W1_layer1[k,d] += lr * g_z[k] * xn1[d]
;
; This is a local layer-1 hidden-projection update using layer-1 W2 and the
; final output error. It does not propagate through layer 2. All arithmetic is
; guest-side; the host only transports target/lr and exports the page bytes.
;
; ABI same as opcode125/126:
;   r1 context f32[T*128], r2 output, r3 slot, r4 T,
;   r5 target f32[128], r6 lr bits.
; Returns r1=1, r2=error norm f32 bits, r3=0, r4=0.
mth_head_page_train_l1w1:
  MOVI r0,0
  ST r15,r0,@hl1w1_link
  ST r1,r0,@hl1w1_context
  ST r2,r0,@hl1w1_output
  ST r3,r0,@hl1w1_slot
  ST r4,r0,@hl1w1_t
  ST r5,r0,@hl1w1_target
  ST r6,r0,@hl1w1_lr
  CMP r1,r0
  JMP[EQ] @hl1w1_bad
  CMP r2,r0
  JMP[EQ] @hl1w1_bad
  CMP r5,r0
  JMP[EQ] @hl1w1_bad
  CMP r4,r0
  JMP[EQ] @hl1w1_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hl1w1_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hl1w1_bad
  LD r1,r0,@hl1w1_context
  LD r2,r0,@hl1w1_output
  LD r3,r0,@hl1w1_slot
  LD r4,r0,@hl1w1_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hl1w1_forward_bad

  ; Last-token output pointer and error vector/norm.
  LD r10,r0,@hl1w1_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  LD r11,r0,@hl1w1_output
  ADD r11,r11,r10
  ST r11,r0,@hl1w1_state
  MOVI r10,0
  ST r10,r0,@hl1w1_err_norm
  MOVI r10,0
  ST r10,r0,@hl1w1_d
hl1w1_err:
  LD r10,r0,@hl1w1_d
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1w1_err_done
  LD r12,r0,@hl1w1_state
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1w1_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r10
  ST r14,r15,0
  FMUL r14,r14,r14
  MOVI r15,@hl1w1_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hl1w1_err_norm
  ADDI r10,r10,1
  ST r10,r0,@hl1w1_d
  JMP @hl1w1_err
hl1w1_err_done:

  ; Page base and layer-1 W1/W2 word offsets.
  LD r10,r0,@hl1w1_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0xC000
  MOVHI r11,0x0001
  ADD r10,r10,r11
  ST r10,r0,@hl1w1_w1
  LD r10,r0,@hl1w1_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0x2000
  MOVHI r11,0x0002
  ADD r10,r10,r11
  ST r10,r0,@hl1w1_w2

  ; xn1 for the last token (already captured at layer-1 base + 0x80).
  MOVI r10,0x1080
  MOVHI r10,0x00D1
  ST r10,r0,@hl1w1_xn2

  MOVI r10,0
  ST r10,r0,@hl1w1_k
hl1w1_row:
  LD r10,r0,@hl1w1_k
  MOVI r12,384
  CMP r10,r12
  JMP[GE] @hl1w1_ok
  ; g_h = sum_j W2[j,k] * error[j]
  MOVI r13,0
  MOVI r12,0
  ST r12,r0,@hl1w1_j
hl1w1_grad_h:
  LD r12,r0,@hl1w1_j
  MOVI r14,128
  CMP r12,r14
  JMP[GE] @hl1w1_grad_done
  MOVI r14,192
  MUL r14,r12,r14
  SHR r15,r10,1
  ADD r14,r14,r15
  LD r15,r0,@hl1w1_w2
  ADD r15,r15,r14
  LD r14,r15,0
  MOVI r15,1
  SHL r15,r10,31
  SHR r15,r15,31
  CMP r15,r0
  JMP[EQ] @hl1w1_w2_low
  SHR r14,r14,16
  SHL r14,r14,16
  JMP @hl1w1_w2_have
hl1w1_w2_low:
  SHL r14,r14,16
hl1w1_w2_have:
  MOVI r15,0x3100
  MOVHI r15,0x00D0
  ADD r15,r15,r12
  LD r15,r15,0
  FMUL r14,r14,r15
  FADD r13,r13,r14
  ADDI r12,r12,1
  ST r12,r0,@hl1w1_j
  JMP @hl1w1_grad_h
hl1w1_grad_done:
  ; g_z = g_h * (1 - h^2)
  MOVI r12,0x0180
  MOVHI r12,0x00D1
  ADD r12,r12,r10
  LD r12,r12,0
  FMUL r14,r12,r12
  MOVI r15,0
  MOVHI r15,0x3F80
  FSUB r15,r15,r14
  FMUL r13,r13,r15
  LD r14,r0,@hl1w1_lr
  FMUL r13,r13,r14
  ST r13,r0,@hl1w1_scale
  ; W1 row pointer = W1 + k*64
  MOVI r12,64
  MUL r12,r10,r12
  LD r14,r0,@hl1w1_w1
  ADD r14,r14,r12
  ST r14,r0,@hl1w1_rowptr
  MOVI r12,0
  ST r12,r0,@hl1w1_d
hl1w1_col:
  LD r12,r0,@hl1w1_d
  MOVI r15,128
  CMP r12,r15
  JMP[GE] @hl1w1_next_row
  SHR r15,r12,1
  LD r14,r0,@hl1w1_rowptr
  ADD r14,r14,r15
  LD r15,r14,0
  MOVI r11,1
  SHL r11,r12,31
  SHR r11,r11,31
  CMP r11,r0
  JMP[EQ] @hl1w1_low
  SHR r11,r15,16
  SHL r11,r11,16
  JMP @hl1w1_have
hl1w1_low:
  SHL r11,r15,16
hl1w1_have:
  LD r9,r0,@hl1w1_scale
  LD r8,r0,@hl1w1_xn2
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
  JMP[EQ] @hl1w1_merge_low
  SHL r9,r11,16
  SHL r15,r15,16
  SHR r15,r15,16
  ADD r15,r15,r9
  JMP @hl1w1_store
hl1w1_merge_low:
  SHR r9,r15,16
  SHL r9,r9,16
  ADD r15,r9,r11
hl1w1_store:
  ST r15,r14,0
  ADDI r12,r12,1
  ST r12,r0,@hl1w1_d
  JMP @hl1w1_col
hl1w1_next_row:
  LD r10,r0,@hl1w1_k
  ADDI r10,r10,1
  ST r10,r0,@hl1w1_k
  JMP @hl1w1_row
hl1w1_ok:
  MOVI r1,1
  LD r2,r0,@hl1w1_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hl1w1_link
  RET
hl1w1_forward_bad:
  MOVI r4,2
  JMP @hl1w1_reject
hl1w1_bad:
  MOVI r4,1
hl1w1_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hl1w1_link
  RET

hl1w1_link:
  .word 0
hl1w1_context:
  .word 0
hl1w1_output:
  .word 0
hl1w1_slot:
  .word 0
hl1w1_t:
  .word 0
hl1w1_target:
  .word 0
hl1w1_lr:
  .word 0
hl1w1_state:
  .word 0
hl1w1_err_norm:
  .word 0
hl1w1_d:
  .word 0
hl1w1_j:
  .word 0
hl1w1_k:
  .word 0
hl1w1_w1:
  .word 0
hl1w1_w2:
  .word 0
hl1w1_xn2:
  .word 0
hl1w1_scale:
  .word 0
hl1w1_rowptr:
  .word 0
