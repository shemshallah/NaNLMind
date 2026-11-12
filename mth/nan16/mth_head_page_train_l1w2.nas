; Raw NaN16 local layer-1 W2 update using the final output error.
; This is intentionally a local approximation: it reuses the final state error
; for layer 1 and does not backpropagate through layer 2.
;
; The six-token worker produces the current last-token state and retains each
; layer's last-token hidden vector.  This kernel uses the final state error:
;   e = target - state
;   W2_layer1[j,k] += lr * e[j] * hidden_layer1[k]
; It does not propagate the error through layer 2.
; All gradient/error/update arithmetic is guest-side; the host only transports
; the target/lr and reads back the modified page bytes.
;
; ABI:
;   r1 = context f32[T*128]
;   r2 = output f32[T*128]
;   r3 = page slot 0..15
;   r4 = T 1..6
;   r5 = target f32[128]
;   r6 = learning-rate f32 bits
; Returns r1=1, r2=error norm f32 bits, r3=0, r4=0; rejection r1=0,r4=reason.
mth_head_page_train_l1w2:
  MOVI r0,0
  ST r15,r0,@hl1w2_link
  ST r1,r0,@hl1w2_context
  ST r2,r0,@hl1w2_output
  ST r3,r0,@hl1w2_slot
  ST r4,r0,@hl1w2_t
  ST r5,r0,@hl1w2_target
  ST r6,r0,@hl1w2_lr
  CMP r1,r0
  JMP[EQ] @hl1w2_bad
  CMP r2,r0
  JMP[EQ] @hl1w2_bad
  CMP r5,r0
  JMP[EQ] @hl1w2_bad
  CMP r4,r0
  JMP[EQ] @hl1w2_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hl1w2_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hl1w2_bad
  ; Forward pass. The worker writes the full T-token output and leaves the
  ; last-token tanh hidden at 0xD01500.
  LD r1,r0,@hl1w2_context
  LD r2,r0,@hl1w2_output
  LD r3,r0,@hl1w2_slot
  LD r4,r0,@hl1w2_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hl1w2_forward_bad

  ; Target/state/error norm for the last token.
  MOVI r10,0
  ST r10,r0,@hl1w2_err_norm
  LD r10,r0,@hl1w2_t
  MOVI r11,128
  MUL r10,r10,r11
  MOVI r12,128
  SUB r10,r10,r12
  LD r11,r0,@hl1w2_output
  ADD r11,r11,r10
  MOVI r10,0
  ST r10,r0,@hl1w2_j
hl1w2_err_row:
  LD r10,r0,@hl1w2_j
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1w2_err_done
  ADD r12,r11,r10
  LD r12,r12,0
  LD r13,r0,@hl1w2_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  FMUL r14,r14,r14
  MOVI r15,@hl1w2_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hl1w2_err_norm
  LD r10,r0,@hl1w2_j
  ADDI r10,r10,1
  ST r10,r0,@hl1w2_j
  JMP @hl1w2_err_row
hl1w2_err_done:

  ; Page base and layer-1 W2 word offset (layer1: 0x14000 + W2 0xE000).
  LD r10,r0,@hl1w2_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0x2000
  MOVHI r11,0x0002
  ADD r10,r10,r11
  ST r10,r0,@hl1w2_w2
  MOVI r10,0
  ST r10,r0,@hl1w2_j
hl1w2_update_row:
  LD r10,r0,@hl1w2_j
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1w2_ok
  ; e_j and lr*e_j
  MOVI r12,128
  LD r13,r0,@hl1w2_t
  MUL r13,r13,r12
  SUB r13,r13,r12
  LD r12,r0,@hl1w2_output
  ADD r12,r12,r13
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1w2_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r13,r13,r12
  LD r14,r0,@hl1w2_lr
  FMUL r13,r13,r14
  ST r13,r0,@hl1w2_scale
  ; W2 row word pointer: base + j*192 words
  MOVI r12,192
  MUL r12,r10,r12
  LD r13,r0,@hl1w2_w2
  ADD r13,r13,r12
  ST r13,r0,@hl1w2_row
  MOVI r12,0
  ST r12,r0,@hl1w2_k
hl1w2_update_col:
  LD r12,r0,@hl1w2_k
  MOVI r14,384
  CMP r12,r14
  JMP[GE] @hl1w2_next_row
  ; packed word pointer = row + k/2
  SHR r14,r12,1
  LD r15,r0,@hl1w2_row
  ADD r15,r15,r14
  LD r14,r15,0
  ; extract current bf16 depending on k parity
  SHL r8,r12,31
  SHR r8,r8,31
  CMP r8,r0
  JMP[EQ] @hl1w2_low
  SHR r8,r14,16
  SHL r8,r8,16
  JMP @hl1w2_have_old
hl1w2_low:
  SHL r8,r14,16
hl1w2_have_old:
  ; r8 is the current bf16 value widened to f32 bits
  ; delta = lr*e_j*h[k]
  LD r9,r0,@hl1w2_scale
  MOVI r11,0x0180
  MOVHI r11,0x00D1
  ADD r11,r11,r12
  LD r11,r11,0
  FMUL r9,r9,r11
  FADD r8,r8,r9
  ; f32 -> bf16 with round-to-nearest approximation (ADDI immediate is signed)
  MOVI r9,0x8000
  ADD r8,r8,r9
  SHR r8,r8,16
  ; merge into packed word
  SHL r9,r12,31
  SHR r9,r9,31
  CMP r9,r0
  JMP[EQ] @hl1w2_merge_low
  SHL r9,r8,16
  SHL r14,r14,16
  SHR r14,r14,16
  ADD r14,r14,r9
  JMP @hl1w2_store_word
hl1w2_merge_low:
  SHR r9,r14,16
  SHL r9,r9,16
  ADD r14,r9,r8
hl1w2_store_word:
  ST r14,r15,0
  LD r12,r0,@hl1w2_k
  ADDI r12,r12,1
  ST r12,r0,@hl1w2_k
  JMP @hl1w2_update_col
hl1w2_next_row:
  LD r10,r0,@hl1w2_j
  ADDI r10,r10,1
  ST r10,r0,@hl1w2_j
  JMP @hl1w2_update_row
hl1w2_ok:
  MOVI r1,1
  LD r2,r0,@hl1w2_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hl1w2_link
  RET
hl1w2_forward_bad:
  MOVI r4,2
  JMP @hl1w2_reject
hl1w2_bad:
  MOVI r4,1
hl1w2_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hl1w2_link
  RET

hl1w2_link:
  .word 0
hl1w2_context:
  .word 0
hl1w2_output:
  .word 0
hl1w2_slot:
  .word 0
hl1w2_t:
  .word 0
hl1w2_target:
  .word 0
hl1w2_lr:
  .word 0
hl1w2_j:
  .word 0
hl1w2_k:
  .word 0
hl1w2_w2:
  .word 0
hl1w2_row:
  .word 0
hl1w2_scale:
  .word 0
hl1w2_err_norm:
  .word 0
