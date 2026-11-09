.org 0
JMP @mth_q16_mul_main
.include "../nan16/mth_q16_mul.nas"
mth_q16_mul_main:
  MOVI r13,1
  MOVI r1,0
  MOVHI r1,1
  MOVI r2,0x9999
  CALL @mth_q16_mul
  MOVI r10,0x9999
  CMP r1,r10
  JMP[NE] @mth_q16_mul_fail

  MOVI r1,0
  MOVHI r1,1
  SUB r1,r0,r1
  MOVI r2,0x9999
  CALL @mth_q16_mul
  MOVI r10,0x6667
  MOVHI r10,0xFFFF
  CMP r1,r10
  JMP[NE] @mth_q16_mul_fail

  MOVI r1,0x8000
  MOVI r2,0x8000
  CALL @mth_q16_mul
  MOVI r10,0x4000
  CMP r1,r10
  JMP[NE] @mth_q16_mul_fail

  MOVI r1,@mth_q16_mul_pass
  CALL @mth_puts
  HALT
mth_q16_mul_fail:
  MOVI r1,@mth_q16_mul_bad
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
mth_q16_mul_pass:
.str "MTH Q16 MUL PASS\n"
mth_q16_mul_bad:
.str "MTH Q16 MUL FAIL\n"
