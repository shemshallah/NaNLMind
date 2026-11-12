; Raw NaN16 local layer-1 Wo update using the final output error.
; Local approximation; does not backpropagate through layer 2.
;
; The six-token worker produces the current last-token state.  The host supplies
; a 128D target vector and a learning rate.  This kernel computes
;   e = target - state
; and applies the local error-corrective update for LAYER 1's Wo:
;   Wo_layer1[j,k] += lr * e[j] * context_layer1[k]
; where context_layer1 is the retained layer-1 last-token attention context.
; This is a local approximation, not full layer-2 backpropagation.
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
mth_head_page_train_l1wo:
  MOVI r0,0
  ST r15,r0,@hl1wo_link
  ST r1,r0,@hl1wo_context
  ST r2,r0,@hl1wo_output
  ST r3,r0,@hl1wo_slot
  ST r4,r0,@hl1wo_t
  ST r5,r0,@hl1wo_target
  ST r6,r0,@hl1wo_lr
  CMP r1,r0
  JMP[EQ] @hl1wo_bad
  CMP r2,r0
  JMP[EQ] @hl1wo_bad
  CMP r5,r0
  JMP[EQ] @hl1wo_bad
  CMP r4,r0
  JMP[EQ] @hl1wo_bad
  MOVI r7,6
  CMP r4,r7
  JMP[GT] @hl1wo_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @hl1wo_bad
  ; Forward pass. The worker writes the full T-token output and leaves the
  ; last-token tanh hidden at 0xD01500.
  LD r1,r0,@hl1wo_context
  LD r2,r0,@hl1wo_output
  LD r3,r0,@hl1wo_slot
  LD r4,r0,@hl1wo_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @hl1wo_forward_bad

  ; Target/state/error norm for the last token.
  MOVI r10,0
  ST r10,r0,@hl1wo_err_norm
  LD r10,r0,@hl1wo_t
  MOVI r11,128
  MUL r10,r10,r11
  MOVI r12,128
  SUB r10,r10,r12
  LD r11,r0,@hl1wo_output
  ADD r11,r11,r10
  MOVI r10,0
  ST r10,r0,@hl1wo_j
hl1wo_err_row:
  LD r10,r0,@hl1wo_j
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1wo_err_done
  ADD r12,r11,r10
  LD r12,r12,0
  LD r13,r0,@hl1wo_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r14,r13,r12
  FMUL r14,r14,r14
  MOVI r15,@hl1wo_err_norm
  LD r15,r15,0
  FADD r15,r15,r14
  ST r15,r0,@hl1wo_err_norm
  LD r10,r0,@hl1wo_j
  ADDI r10,r10,1
  ST r10,r0,@hl1wo_j
  JMP @hl1wo_err_row
hl1wo_err_done:

  ; Page base and layer-1 Wo word offset (layer1: 0x14000 + Wo 0x6000).
  LD r10,r0,@hl1wo_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  MOVI r11,0xA000
  MOVHI r11,0x0001
  ADD r10,r10,r11
  ST r10,r0,@hl1wo_w2
  ; Retained layer-1 last-token attention context.
  MOVI r10,0x2080
  MOVHI r10,0x00D1
  ST r10,r0,@hl1wo_ctx
  MOVI r10,0
  ST r10,r0,@hl1wo_j
hl1wo_update_row:
  LD r10,r0,@hl1wo_j
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @hl1wo_ok
  ; e_j and lr*e_j
  MOVI r12,128
  LD r13,r0,@hl1wo_t
  MUL r13,r13,r12
  SUB r13,r13,r12
  LD r12,r0,@hl1wo_output
  ADD r12,r12,r13
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hl1wo_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r13,r13,r12
  LD r14,r0,@hl1wo_lr
  FMUL r13,r13,r14
  ST r13,r0,@hl1wo_scale
  ; Wo row word pointer: base + j*64 words (128 bf16 columns)
  MOVI r12,64
  MUL r12,r10,r12
  LD r13,r0,@hl1wo_w2
  ADD r13,r13,r12
  ST r13,r0,@hl1wo_row
  MOVI r12,0
  ST r12,r0,@hl1wo_k
hl1wo_update_col:
  LD r12,r0,@hl1wo_k
  MOVI r14,128
  CMP r12,r14
  JMP[GE] @hl1wo_next_row
  ; packed word pointer = row + k/2
  SHR r14,r12,1
  LD r15,r0,@hl1wo_row
  ADD r15,r15,r14
  LD r14,r15,0
  ; extract current bf16 depending on k parity
  SHL r8,r12,31
  SHR r8,r8,31
  CMP r8,r0
  JMP[EQ] @hl1wo_low
  SHR r8,r14,16
  SHL r8,r8,16
  JMP @hl1wo_have_old
hl1wo_low:
  SHL r8,r14,16
hl1wo_have_old:
  ; r8 is the current bf16 value widened to f32 bits
  ; delta = lr*e_j*h[k]
  LD r9,r0,@hl1wo_scale
  LD r11,r0,@hl1wo_ctx
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
  JMP[EQ] @hl1wo_merge_low
  SHL r9,r8,16
  SHL r14,r14,16
  SHR r14,r14,16
  ADD r14,r14,r9
  JMP @hl1wo_store_word
hl1wo_merge_low:
  SHR r9,r14,16
  SHL r9,r9,16
  ADD r14,r9,r8
hl1wo_store_word:
  ST r14,r15,0
  LD r12,r0,@hl1wo_k
  ADDI r12,r12,1
  ST r12,r0,@hl1wo_k
  JMP @hl1wo_update_col
hl1wo_next_row:
  LD r10,r0,@hl1wo_j
  ADDI r10,r10,1
  ST r10,r0,@hl1wo_j
  JMP @hl1wo_update_row
hl1wo_ok:
  MOVI r1,1
  LD r2,r0,@hl1wo_err_norm
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hl1wo_link
  RET
hl1wo_forward_bad:
  MOVI r4,2
  JMP @hl1wo_reject
hl1wo_bad:
  MOVI r4,1
hl1wo_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@hl1wo_link
  RET

hl1wo_link:
  .word 0
hl1wo_context:
  .word 0
hl1wo_output:
  .word 0
hl1wo_slot:
  .word 0
hl1wo_t:
  .word 0
hl1wo_target:
  .word 0
hl1wo_lr:
  .word 0
hl1wo_j:
  .word 0
hl1wo_k:
  .word 0
hl1wo_w2:
  .word 0
hl1wo_row:
  .word 0
hl1wo_scale:
  .word 0
hl1wo_err_norm:
  .word 0
hl1wo_ctx:
  .word 0
