; Raw NaN16 one-step local page trainer for the final Wo projection.
;
; The six-token worker produces the current last-token state.  The host supplies
; a 128D target vector and a learning rate.  This kernel computes
;   e = target - state
; and applies the local error-corrective update for the LAST layer's Wo:
;   Wo[j,k] += lr * e[j] * context[k]
; where context is the last-token attention context already computed by the
; worker.
;
; This is a local final-attention-projection update, not full three-layer
; backpropagation.
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
mth_head_page_train_wo:
  MOVI r0,0
  ST r15,r0,@hwo_link
  ST r1,r0,@hwo_context
  ST r2,r0,@hwo_output
  ST r3,r0,@hwo_slot
  ST r4,r0,@hwo_t
  ST r5,r0,@hwo_target
  ST r6,r0,@hwo_lr
  CMP r1,r0
  JMP[EQ] @hwo_bad
  CMP r2,r0
  JMP[EQ] @hwo_bad
  CMP r5,r0
  JMP[EQ] @hwo_bad
  CMP r4,r0
  JMP[EQ] @hwo_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hwo_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hwo_bad
  ; Forward pass. The worker writes the full T-token output and leaves the
  ; last-token tanh hidden at 0xD01500.
  LD r1,r0,@hwo_context
  LD r2,r0,@hwo_output
  LD r3,r0,@hwo_slot
  LD r4,r0,@hwo_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hwo_forward_bad

  ; Target/state/error norm for the last token.
  MOVI r10,0
  ST r10,r0,@hwo_err_norm
  LD r10,r0,@hwo_t
  MOVI r11,128
  MUL r10,r10,r11
  MOVI r12,128
  SUB r10,r10,r12
  LD r11,r0,@hwo_output
  ADD r11,r11,r10
  MOVI r10,0
  ST r10,r0,@hwo_j
hwo_err_row:
  LD r10,r0,@hwo_j
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hwo_err_done
  ADD r12,r11,r10
  LD r12,r12,0
  LD r13,r0,@hwo_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  FMUL r14,r14,r14
  MOVI r15,@hwo_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hwo_err_norm
  LD r10,r0,@hwo_j
  ADDI r10,r10,1
  ST r10,r0,@hwo_j
  JMP @hwo_err_row
hwo_err_done:

  ; Page base and final-layer Wo word offset (layer2: 0x28000 + Wo 0x6000).
  LD r10,r0,@hwo_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0xE000
  MOVHI r11,0x0002
  ADD r10,r10,r11
  ST r10,r0,@hwo_w2
  ; Last-token attention context base.
  LD r10,r0,@hwo_t
  MOVI r11,128
  MUL r10,r10,r11
  SUB r10,r10,r11
  MOVI r11,0x0F00
  MOVHI r11,0x00D0
  ADD r10,r10,r11
  ST r10,r0,@hwo_ctx
  MOVI r10,0
  ST r10,r0,@hwo_j
hwo_update_row:
  LD r10,r0,@hwo_j
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hwo_ok
  ; e_j and lr*e_j
  MOVI r12,128
  LD r13,r0,@hwo_t
  MUL r13,r13,r12
  SUB r13,r13,r12
  LD r12,r0,@hwo_output
  ADD r12,r12,r13
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hwo_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r13,r13,r12
  LD r14,r0,@hwo_lr
  FMUL r13,r13,r14
  ST r13,r0,@hwo_scale
  ; Wo row word pointer: base + j*64 words (128 bf16 columns)
  MOVI r12,64
  MUL r12,r10,r12
  LD r13,r0,@hwo_w2
  ADD r13,r13,r12
  ST r13,r0,@hwo_row
  MOVI r12,0
  ST r12,r0,@hwo_k
hwo_update_col:
  LD r12,r0,@hwo_k
  MOVI r14,128
  CMP r12,r14
  JMP[GE] @hwo_next_row
  ; packed word pointer = row + k/2
  SHR r14,r12,1
  LD r15,r0,@hwo_row
  ADD r15,r15,r14
  LD r14,r15,0
  ; extract current bf16 depending on k parity
  SHL r8,r12,31
  SHR r8,r8,31
  CMP r8,r0
  JMP[EQ] @hwo_low
  SHR r8,r14,16
  SHL r8,r8,16
  JMP @hwo_have_old
hwo_low:
  SHL r8,r14,16
hwo_have_old:
  ; r8 is the current bf16 value widened to f32 bits
  ; delta = lr*e_j*h[k]
  LD r9,r0,@hwo_scale
  LD r11,r0,@hwo_ctx
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
  JMP[EQ] @hwo_merge_low
  SHL r9,r8,16
  SHL r14,r14,16
  SHR r14,r14,16
  ADD r14,r14,r9
  JMP @hwo_store_word
hwo_merge_low:
  SHR r9,r14,16
  SHL r9,r9,16
  ADD r14,r9,r8
hwo_store_word:
  ST r14,r15,0
  LD r12,r0,@hwo_k
  ADDI r12,r12,1
  ST r12,r0,@hwo_k
  JMP @hwo_update_col
hwo_next_row:
  LD r10,r0,@hwo_j
  ADDI r10,r10,1
  ST r10,r0,@hwo_j
  JMP @hwo_update_row
hwo_ok:
  MOVI r1,1
  LD r2,r0,@hwo_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hwo_link
  RET
hwo_forward_bad:
  MOVI r4,2
  JMP @hwo_reject
hwo_bad:
  MOVI r4,1
hwo_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hwo_link
  RET

hwo_link:
  .word 0
hwo_context:
  .word 0
hwo_output:
  .word 0
hwo_slot:
  .word 0
hwo_t:
  .word 0
hwo_target:
  .word 0
hwo_lr:
  .word 0
hwo_j:
  .word 0
hwo_k:
  .word 0
hwo_w2:
  .word 0
hwo_row:
  .word 0
hwo_scale:
  .word 0
hwo_err_norm:
  .word 0
hwo_ctx:
  .word 0
