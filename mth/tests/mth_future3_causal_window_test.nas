; NaN16 three-horizon causal prefix test. Simulates a frozen decoder's
; own predicted IDs 66,77; never accepts any future ground-truth token.
.org 0
JMP @f3t_main
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_meta_attention16_f32.nas"
.include "../nan16/mth_six_context_poincare_attention.nas"
.include "../nan16/mth_future3_causal_window.nas"
f3t_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r10,@f3t_words
  MOVI r11,11
  ST r11,r10,0
  MOVI r11,22
  ST r11,r10,1
  MOVI r11,33
  ST r11,r10,2
  MOVI r11,44
  ST r11,r10,3
  MOVI r11,55
  ST r11,r10,4
  MOVI r10,@f3t_generated
  MOVI r11,66
  ST r11,r10,0
  MOVI r11,77
  ST r11,r10,1
  MOVI r11,12345
  ST r11,r10,2              ; poisoned NOT GENERATED future
  MOVI r10,0
  ST r10,r0,@f3t_g
f3t_horizon:
  ; Each call generates exactly ONE new causal window based on own prefix.
  MOVI r1,@f3t_words
  MOVI r2,5
  MOVI r3,@f3t_generated
  LD r4,r0,@f3t_g
  MOVI r5,9
  MOVI r6,9
  MOVI r7,@f3t_request
  CALL @mth_future3_causal_window
  CMP r1,r13
  JMP[NE] @f3t_bad
  MOVI r10,7
  CMP r2,r10
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_g
  ADDI r10,r10,1
  CMP r3,r10
  JMP[NE] @f3t_bad
  CMP r4,r0
  JMP[NE] @f3t_bad
  ; Exactly 3 past words, no future slots in any horizon.
  LD r10,r0,@f3t_request+7
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_request+4
  CMP r10,r0
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_request+5
  CMP r10,r0
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_request+6
  CMP r10,r0
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_request+8
  CMP r10,r0
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_request+11
  MOVI r11,255
  CMP r10,r11
  JMP[NE] @f3t_bad
  ; Expected distinct neighborhoods: [33,44,55], [44,55,66],
  ; [55,66,77]. Test both selected words and preserved order.
  MOVI r10,@f3t_expected
  LD r11,r0,@f3t_g
  MOVI r12,3
  MUL r11,r11,r12
  ADD r10,r10,r11
  MOVI r9,0
f3t_check:
  MOVI r12,3
  CMP r9,r12
  JMP[GE] @f3t_math
  MOVI r11,@f3t_request
  ADD r11,r11,r9
  LD r11,r11,1
  ADD r12,r10,r9
  LD r12,r12,0
  CMP r11,r12
  JMP[NE] @f3t_bad
  ADDI r9,r9,1
  JMP @f3t_check
f3t_math:
  ; Reuse the REAL guest trig/MC0/Poincare attention at every horizon.
  MOVI r1,@f3t_request
  MOVI r2,@f3t_mathout
  CALL @mth_six_context_poincare_attention
  CMP r1,r13
  JMP[NE] @f3t_bad
  MOVI r10,3
  CMP r2,r10
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_mathout+4
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_g
  ADDI r10,r10,1
  MOVI r11,3
  CMP r10,r11
  JMP[GE] @f3t_poison
  ST r10,r0,@f3t_g
  JMP @f3t_horizon

f3t_poison:
  ; A different ungenerated future ID may NOT change h3, even 1 bit.
  MOVI r11,54321
  ST r11,r0,@f3t_generated+2
  MOVI r1,@f3t_words
  MOVI r2,5
  MOVI r3,@f3t_generated
  MOVI r4,2
  MOVI r5,9
  MOVI r6,9
  MOVI r7,@f3t_second
  CALL @mth_future3_causal_window
  CMP r1,r13
  JMP[NE] @f3t_bad
  MOVI r9,0
f3t_equal:
  MOVI r10,12
  CMP r9,r10
  JMP[GE] @f3t_stale
  MOVI r10,@f3t_request
  ADD r10,r10,r9
  LD r11,r10,0
  MOVI r10,@f3t_second
  ADD r10,r10,r9
  LD r12,r10,0
  CMP r11,r12
  JMP[NE] @f3t_bad
  ADDI r9,r9,1
  JMP @f3t_equal
f3t_stale:
  ; Stale generation MUST NOT publish any output.
  MOVI r11,9999
  ST r11,r0,@f3t_second
  MOVI r1,@f3t_words
  MOVI r2,5
  MOVI r3,@f3t_generated
  MOVI r4,2
  MOVI r5,9
  MOVI r6,10
  MOVI r7,@f3t_second
  CALL @mth_future3_causal_window
  CMP r1,r0
  JMP[NE] @f3t_bad
  MOVI r10,2
  CMP r4,r10
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_second
  MOVI r11,9999
  CMP r10,r11
  JMP[NE] @f3t_bad
  ; Invalid generated count >2 also preserves output.
  MOVI r1,@f3t_words
  MOVI r2,5
  MOVI r3,@f3t_generated
  MOVI r4,3
  MOVI r5,9
  MOVI r6,9
  MOVI r7,@f3t_second
  CALL @mth_future3_causal_window
  CMP r1,r0
  JMP[NE] @f3t_bad
  MOVI r10,1
  CMP r4,r10
  JMP[NE] @f3t_bad
  LD r10,r0,@f3t_second
  MOVI r11,9999
  CMP r10,r11
  JMP[NE] @f3t_bad
  MOVI r1,@f3t_pass
  CALL @f3t_puts
  HALT
f3t_bad:
  MOVI r1,@f3t_fail
  CALL @f3t_puts
  HALT
f3t_puts:
  MOVI r13,1
  MOVI r4,255
f3t_puts_word:
  LD r2,r1,0
  MOVI r3,4
f3t_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @f3t_puts_byte
  ADD r1,r1,r13
  JMP @f3t_puts_word
f3t_pass:
.str "MTH FUTURE3 NATIVE CAUSAL PREFIX PASS\n"
f3t_fail:
.str "MTH FUTURE3 NATIVE CAUSAL PREFIX FAIL\n"
f3t_g:
  .word 0
f3t_expected:
  .word 33,44,55,44,55,66,55,66,77
.org 30000
f3t_words:
  .word 0,0,0,0,0
f3t_generated:
  .word 0,0,0
f3t_request:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
f3t_second:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
f3t_mathout:
  .word 0,0,0,0,0,0,0,0
