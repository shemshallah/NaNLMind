; Real NaN16 six-slot content-attention / Poincare / causal leakage tests.
.org 0
JMP @ctx6_test_main
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_meta_attention16_f32.nas"
.include "../nan16/mth_six_context_poincare_attention.nas"

ctx6_test_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r10,@ctx6_req
  MOVI r11,8192
  ST r11,r10,0        ; observed anchor, never the target label
  MOVI r11,100
  ST r11,r10,1
  MOVI r11,500
  ST r11,r10,2
  MOVI r11,900
  ST r11,r10,3
  MOVI r11,7
  ST r11,r10,7        ; 3 causal past words
  ST r0,r10,8        ; task 0 causal
  MOVI r11,42
  ST r11,r10,9
  ST r11,r10,10
  MOVI r11,255
  ST r11,r10,11
  MOVI r11,1234
  ST r11,r0,@ctx6_out

  ; Future bit in causal mode must fail BEFORE touching output.
  MOVI r11,15
  ST r11,r10,7
  MOVI r11,7000
  ST r11,r10,4
  MOVI r1,@ctx6_req
  MOVI r2,@ctx6_out
  CALL @mth_six_context_poincare_attention
  CMP r1,r0
  JMP[NE] @ctx6_test_fail
  MOVI r11,2
  CMP r4,r11
  JMP[NE] @ctx6_test_fail
  LD r11,r0,@ctx6_out
  MOVI r12,1234
  CMP r11,r12
  JMP[NE] @ctx6_test_fail

  ; Future payload still present with MASKED bit must also reject.
  MOVI r10,@ctx6_req
  MOVI r11,8192
  ST r11,r10,0
  MOVI r11,7
  ST r11,r10,7
  MOVI r1,@ctx6_req
  MOVI r2,@ctx6_out
  CALL @mth_six_context_poincare_attention
  CMP r1,r0
  JMP[NE] @ctx6_test_fail
  MOVI r11,1
  CMP r4,r11
  JMP[NE] @ctx6_test_fail
  LD r11,r0,@ctx6_out
  MOVI r12,1234
  CMP r11,r12
  JMP[NE] @ctx6_test_fail

  ; Generation stale rejects and leaves output sentinel intact.
  MOVI r10,@ctx6_req
  ST r0,r10,4
  MOVI r11,41
  ST r11,r10,10
  MOVI r1,@ctx6_req
  MOVI r2,@ctx6_out
  CALL @mth_six_context_poincare_attention
  CMP r1,r0
  JMP[NE] @ctx6_test_fail
  MOVI r11,3
  CMP r4,r11
  JMP[NE] @ctx6_test_fail
  LD r11,r0,@ctx6_out
  MOVI r12,1234
  CMP r11,r12
  JMP[NE] @ctx6_test_fail

  ; Real causal inference: three past valid, all future zero.
  MOVI r10,@ctx6_req
  MOVI r11,42
  ST r11,r10,10
  MOVI r1,@ctx6_req
  MOVI r2,@ctx6_out
  CALL @mth_six_context_poincare_attention
  CMP r1,r13
  JMP[NE] @ctx6_test_fail
  MOVI r11,3
  CMP r2,r11
  JMP[NE] @ctx6_test_fail
  CMP r3,r0
  JMP[NE] @ctx6_test_fail
  CMP r4,r0
  JMP[NE] @ctx6_test_fail
  MOVI r10,@ctx6_out
  LD r11,r10,4
  MOVI r12,7
  CMP r11,r12
  JMP[NE] @ctx6_test_fail
  LD r11,r10,6
  MOVI r12,255
  CMP r11,r12
  JMP[NE] @ctx6_test_fail
  LD r11,r10,7
  MOVI r12,8192
  CMP r11,r12
  JMP[NE] @ctx6_test_fail
  ; Strictly within Poincare unit disk and positive distance.
  LD r11,r10,2
  MOVI r12,0
  FCMP r11,r12
  JMP[LE] @ctx6_test_fail
  MOVI r12,0
  MOVHI r12,0x3F80
  FCMP r11,r12
  JMP[GE] @ctx6_test_fail
  LD r11,r10,3
  MOVI r12,0
  FCMP r11,r12
  JMP[LE] @ctx6_test_fail
  LD r11,r10,0
  ST r11,r0,@ctx6_causal_x

  ; Causal mode with no past cannot use future-only context.
  MOVI r10,@ctx6_req
  MOVI r11,0
  ST r11,r10,1
  ST r11,r10,2
  ST r11,r10,3
  ST r11,r10,7
  MOVI r1,@ctx6_req
  MOVI r2,@ctx6_out
  CALL @mth_six_context_poincare_attention
  CMP r1,r0
  JMP[NE] @ctx6_test_fail
  ; Restore past and add real future to infill mode.
  MOVI r10,@ctx6_req
  MOVI r11,100
  ST r11,r10,1
  MOVI r11,500
  ST r11,r10,2
  MOVI r11,900
  ST r11,r10,3
  MOVI r11,16384
  ST r11,r10,4
  MOVI r11,32768
  ST r11,r10,5
  MOVI r11,48000
  ST r11,r10,6
  MOVI r11,63
  ST r11,r10,7
  ST r13,r10,8       ; bidirectional MASKED INFILL only
  MOVI r1,@ctx6_req
  MOVI r2,@ctx6_out
  CALL @mth_six_context_poincare_attention
  CMP r1,r13
  JMP[NE] @ctx6_test_fail
  MOVI r11,6
  CMP r2,r11
  JMP[NE] @ctx6_test_fail
  CMP r3,r13
  JMP[NE] @ctx6_test_fail
  MOVI r10,@ctx6_out
  LD r11,r10,4
  MOVI r12,63
  CMP r11,r12
  JMP[NE] @ctx6_test_fail
  LD r11,r10,5
  CMP r11,r13
  JMP[NE] @ctx6_test_fail
  LD r11,r10,0
  LD r12,r0,@ctx6_causal_x
  CMP r11,r12
  JMP[EQ] @ctx6_test_fail  ; genuine content-dependent change
  LD r11,r10,2
  MOVI r12,0
  MOVHI r12,0x3F80
  FCMP r11,r12
  JMP[GE] @ctx6_test_fail

  MOVI r1,@ctx6_test_pass
  CALL @ctx6_test_puts
  HALT
ctx6_test_fail:
  MOVI r1,@ctx6_test_bad
  CALL @ctx6_test_puts
  HALT
ctx6_test_puts:
  MOVI r13,1
  MOVI r4,255
ctx6_test_puts_word:
  LD r2,r1,0
  MOVI r3,4
ctx6_test_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @ctx6_test_puts_byte
  ADD r1,r1,r13
  JMP @ctx6_test_puts_word
ctx6_test_pass:
.str "MTH SIX CONTEXT POINCARE ATTENTION PASS\n"
ctx6_test_bad:
.str "MTH SIX CONTEXT POINCARE ATTENTION FAIL\n"

.org 30000
ctx6_req:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
ctx6_out:
  .word 0,0,0,0,0,0,0,0
ctx6_causal_x:
  .word 0
