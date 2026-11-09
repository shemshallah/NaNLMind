.org 0
JMP @mth_q16_test_main
.include "../nan16/mth_q16_sin_cos.nas"

mth_q16_test_main:
  MOVI r13,1

  MOVI r1,0
  CALL @mth_q16_sin_cos
  MOVI r10,65500
  CMP r1,r10
  JMP[LT] @mth_q16_fail
  MOVI r10,32
  CMPS r2,r10
  JMP[GT] @mth_q16_fail
  MOVI r10,32
  SUB r10,r0,r10
  CMPS r2,r10
  JMP[LT] @mth_q16_fail

  MOVI r1,0x4000
  CALL @mth_q16_sin_cos
  MOVI r10,32
  CMP r1,r10
  JMP[GT] @mth_q16_fail
  MOVI r10,65500
  CMP r2,r10
  JMP[LT] @mth_q16_fail

  MOVI r1,0x8000
  CALL @mth_q16_sin_cos
  MOVI r10,65500
  SUB r10,r0,r10
  CMPS r1,r10
  JMP[GT] @mth_q16_fail
  MOVI r10,32
  CMPS r2,r10
  JMP[GT] @mth_q16_fail
  MOVI r10,32
  SUB r10,r0,r10
  CMPS r2,r10
  JMP[LT] @mth_q16_fail

  MOVI r1,0xC000
  CALL @mth_q16_sin_cos
  MOVI r10,32
  CMPS r1,r10
  JMP[GT] @mth_q16_fail
  MOVI r10,32
  SUB r10,r0,r10
  CMPS r1,r10
  JMP[LT] @mth_q16_fail
  MOVI r10,65500
  SUB r10,r0,r10
  CMPS r2,r10
  JMP[GT] @mth_q16_fail

  MOVI r1,@mth_q16_pass
  CALL @mth_puts
  HALT
mth_q16_fail:
  MOVI r1,@mth_q16_bad
  CALL @mth_puts
  HALT

mth_puts:
  MOVI r4,255
mth_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_puts_byte
  ADD r1,r1,r13
  JMP @mth_puts_word

mth_q16_pass:
.str "MTH Q16 SIN COS PASS\n"
mth_q16_bad:
.str "MTH Q16 SIN COS FAIL\n"
