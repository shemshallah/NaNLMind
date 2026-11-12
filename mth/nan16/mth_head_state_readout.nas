; Raw NaN16 linear head-state readout.
;
; The state comes from the native six-token head worker.  Candidate vectors
; are transported f32 features (128 lanes); this kernel computes their dot
; product with the state in the guest.  It is an inference/readout primitive,
; not a trained decoder and not a promotion gate.
;
; ABI:
;   r1 = state f32[128]
;   r2 = candidate vectors f32[N][128], row-major
;   r3 = output scores f32[N]
;   r4 = N 1..64
; Returns r1=1,r2=N,r3=0,r4=0; rejection r1=r2=r3=0,r4=reason.
mth_head_state_readout:
  MOVI r0,0
  ST r15,r0,@hsr_link
  ST r1,r0,@hsr_state
  ST r2,r0,@hsr_cand
  ST r3,r0,@hsr_out
  ST r4,r0,@hsr_n
  CMP r1,r0
  JMP[EQ] @hsr_bad
  CMP r2,r0
  JMP[EQ] @hsr_bad
  CMP r3,r0
  JMP[EQ] @hsr_bad
  CMP r4,r0
  JMP[EQ] @hsr_bad
  MOVI r5,64
  CMP r4,r5
  JMP[GT] @hsr_bad
  MOVI r5,0
  ST r5,r0,@hsr_i
hsr_row:
  LD r5,r0,@hsr_i
  LD r6,r0,@hsr_n
  CMP r5,r6
  JMP[GE] @hsr_ok
  MOVI r7,128
  MUL r7,r5,r7
  LD r8,r0,@hsr_cand
  ADD r8,r8,r7
  MOVI r9,0
  MOVI r10,0
hsr_col:
  MOVI r11,128
  CMP r9,r11
  JMP[GE] @hsr_store
  LD r11,r0,@hsr_state
  ADD r11,r11,r9
  LD r11,r11,0
  ADD r12,r8,r9
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r10,r10,r11
  ADDI r9,r9,1
  JMP @hsr_col
hsr_store:
  LD r11,r0,@hsr_out
  ADD r11,r11,r5
  ST r10,r11,0
  LD r5,r0,@hsr_i
  ADDI r5,r5,1
  ST r5,r0,@hsr_i
  JMP @hsr_row
hsr_ok:
  MOVI r1,1
  LD r2,r0,@hsr_n
  MOVI r3,0
  MOVI r4,0
  LD r15,r0,@hsr_link
  RET
hsr_bad:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r4,1
  LD r15,r0,@hsr_link
  RET

hsr_link:
  .word 0
hsr_state:
  .word 0
hsr_cand:
  .word 0
hsr_out:
  .word 0
hsr_n:
  .word 0
hsr_i:
  .word 0
