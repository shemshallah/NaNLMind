; NaN16 field phase coherence over exactly 85 triads.
;
; ABI:
;   r1 = pointer to 255 32-bit words: three 16-bit phase turns per triad
; Returns:
;   r1 = average pairwise cos(phase_i - phase_j), Q16.16
;
; Each triad contributes three pair terms. Values are bounded to
; [-65536, 65536]; the final division is signed integer division by 255.
; CORDIC is entirely raw NaN16; this kernel contains no host trig.
.include "mth_q16_sin_cos.nas"

mth_field_coherence:
  MOVI r9,@mth_field_coherence_link
  ST r15,r9,0
  ADD r11,r1,r0
  MOVI r10,0
  MOVI r12,85
  MOVI r13,1

mth_fc_loop:
  LD r1,r11,0
  LD r2,r11,4
  SUB r1,r1,r2
  CALL @mth_q16_sin_cos
  ADD r10,r10,r1

  LD r1,r11,0
  LD r2,r11,8
  SUB r1,r1,r2
  CALL @mth_q16_sin_cos
  ADD r10,r10,r1

  LD r1,r11,4
  LD r2,r11,8
  SUB r1,r1,r2
  CALL @mth_q16_sin_cos
  ADD r10,r10,r1

  ADDI r11,r11,12
  SUB r12,r12,r13
  CMP r12,r0
  JMP[NE] @mth_fc_loop

  MOVI r2,255
  ADD r1,r10,r0
  DIV r1,r1,r2
  MOVI r13,1
  MOVI r9,@mth_field_coherence_link
  LD r15,r9,0
  RET

mth_field_coherence_link:
  .word 0
