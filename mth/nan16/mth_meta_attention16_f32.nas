; Raw NaN16 MC0-compatible meta attention over up to 16 committed slots.
; ABI:
;   r1=query[D], r2=keys[B][D], r3=values[B][D], r4=B, r5=D,
;   r6=mask[B] (1 valid), r7=out[D]
; Returns r1=1 success, r9=0; all scores/softmax/context are guest f32.
; Invalid/future slots are masked with -1e9 before softmax.

mth_meta_attention16_f32:
  MOVI r0,0
  ST r15,r0,@mth_ma_link
  MOVI r10,@mth_ma_q
  ST r1,r10,0
  MOVI r10,@mth_ma_keys
  ST r2,r10,0
  MOVI r10,@mth_ma_values
  ST r3,r10,0
  MOVI r10,@mth_ma_out
  ST r7,r10,0
  CMP r4,r0
  JMP[LE] @mth_ma_reject
  MOVI r10,16
  CMP r4,r10
  JMP[GT] @mth_ma_reject
  CMP r5,r0
  JMP[LE] @mth_ma_reject
  MOVI r10,256
  CMP r5,r10
  JMP[GT] @mth_ma_reject
  ; At least one committed slot must be valid; mask entries are 0/1.
  MOVI r8,0
  MOVI r9,0
mth_ma_mask_gate:
  CMP r8,r4
  JMP[GE] @mth_ma_mask_gate_done
  ADD r10,r6,r8
  LD r10,r10,0
  CMP r10,r0
  JMP[EQ] @mth_ma_mask_gate_next
  MOVI r11,1
  CMP r10,r11
  JMP[NE] @mth_ma_reject
  ADDI r9,r9,1
mth_ma_mask_gate_next:
  ADDI r8,r8,1
  JMP @mth_ma_mask_gate
mth_ma_mask_gate_done:
  CMP r9,r0
  JMP[EQ] @mth_ma_reject
  ; scale = 1/sqrt(D)
  CVTIF r1,r5
  FSQRT r1,r1
  MOVI r2,0
  MOVHI r2,0x3F80
  FDIV r2,r2,r1
  ST r2,r0,@mth_ma_scale
  ; scores
  MOVI r8,0
mth_ma_score_loop:
  CMP r8,r4
  JMP[GE] @mth_ma_score_done
  ADD r9,r6,r8
  LD r9,r9,0
  CMP r9,r0
  JMP[EQ] @mth_ma_masked
  MOVI r15,0
  MUL r11,r8,r5
  MOVI r12,0
mth_ma_dot:
  CMP r12,r5
  JMP[GE] @mth_ma_dot_done
  MOVI r10,@mth_ma_q
  LD r13,r10,0
  ADD r13,r13,r12
  LD r13,r13,0
  MOVI r10,@mth_ma_keys
  LD r14,r10,0
  ADD r14,r14,r11
  ADD r14,r14,r12
  LD r14,r14,0
  FMUL r13,r13,r14
  FADD r15,r15,r13
  ADDI r12,r12,1
  JMP @mth_ma_dot
mth_ma_dot_done:
  LD r12,r0,@mth_ma_scale
  FMUL r15,r15,r12
  MOVI r11,@mth_ma_scores
  ADD r11,r11,r8
  ST r15,r11,0
  ADDI r8,r8,1
  JMP @mth_ma_score_loop
mth_ma_masked:
  MOVI r10,0
  MOVHI r10,0xFF7F
  MOVI r11,@mth_ma_scores
  ADD r11,r11,r8
  ST r10,r11,0
  ADDI r8,r8,1
  JMP @mth_ma_score_loop
mth_ma_score_done:
  ; max
  MOVI r10,0
  MOVHI r10,0xFF7F
  MOVI r8,0
mth_ma_max_loop:
  CMP r8,r4
  JMP[GE] @mth_ma_max_done
  MOVI r11,@mth_ma_scores
  ADD r11,r11,r8
  LD r11,r11,0
  FCMP r11,r10
  JMP[LE] @mth_ma_max_next
  ADD r10,r11,r0
mth_ma_max_next:
  ADDI r8,r8,1
  JMP @mth_ma_max_loop
mth_ma_max_done:
  ST r10,r0,@mth_ma_max
  ; exp and sum
  MOVI r8,0
  MOVI r10,0
mth_ma_exp_loop:
  CMP r8,r4
  JMP[GE] @mth_ma_exp_done
  MOVI r11,@mth_ma_scores
  ADD r11,r11,r8
  LD r11,r11,0
  LD r12,r0,@mth_ma_max
  FSUB r11,r11,r12
  FEXP r11,r11
  MOVI r12,@mth_ma_weights
  ADD r12,r12,r8
  ST r11,r12,0
  FADD r10,r10,r11
  ADDI r8,r8,1
  JMP @mth_ma_exp_loop
mth_ma_exp_done:
  ST r10,r0,@mth_ma_sum
  ; normalize and weighted values
  MOVI r8,0
mth_ma_out_loop:
  CMP r8,r5
  JMP[GE] @mth_ma_ok
  MOVI r10,0
  MOVI r9,0
mth_ma_b_loop:
  CMP r9,r4
  JMP[GE] @mth_ma_b_done
  MOVI r11,@mth_ma_weights
  ADD r11,r11,r9
  LD r11,r11,0
  LD r12,r0,@mth_ma_sum
  FDIV r11,r11,r12
  MOVI r13,@mth_ma_values
  LD r14,r13,0
  MUL r13,r9,r5
  ADD r13,r13,r8
  ADD r13,r14,r13
  LD r13,r13,0
  FMUL r13,r11,r13
  FADD r10,r10,r13
  ADDI r9,r9,1
  JMP @mth_ma_b_loop
mth_ma_b_done:
  MOVI r12,@mth_ma_out
  LD r11,r12,0
  ADD r11,r11,r8
  ST r10,r11,0
  ADDI r8,r8,1
  JMP @mth_ma_out_loop
mth_ma_ok:
  MOVI r1,1
  LD r15,r0,@mth_ma_link
  RET
mth_ma_reject:
  MOVI r1,0
  MOVI r9,1
  LD r15,r0,@mth_ma_link
  RET

mth_ma_q:
  .word 0
mth_ma_keys:
  .word 0
mth_ma_values:
  .word 0
mth_ma_out:
  .word 0
mth_ma_link:
  .word 0
mth_ma_scale:
  .word 0
mth_ma_max:
  .word 0
mth_ma_sum:
  .word 0
mth_ma_scores:
  .word 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
mth_ma_weights:
  .word 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
