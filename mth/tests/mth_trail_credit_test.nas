.org 0
JMP @mth_trail_main
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_trail_credit.nas"
mth_trail_main:
  MOVI r13,1
  MOVI r1,0x8000          ; r = 0.5
  MOVI r2,0x6666          ; V-(next) ~= 0.4
  MOVI r3,0x4CCC          ; V+(s_t) ~= 0.3
  MOVI r4,0x3333          ; V+(prev) ~= 0.2
  MOVI r5,0x1999          ; V-(s_t) ~= 0.1
  MOVI r6,0x1999          ; e+
  MOVI r7,0x3333          ; e-
  MOVI r8,0x0CCC          ; dV+
  MOVI r9,0x051E          ; dV-
  MOVI r10,0xE666         ; gamma ~= 0.9
  MOVI r11,0xCCCC         ; lambda ~= 0.8
  CALL @mth_trail_credit
  MOVI r10,0x1F39
  CMP r1,r10
  JMP[NE] @mth_trail_fail
  MOVI r10,0x29FA
  CMP r2,r10
  JMP[NE] @mth_trail_fail
  MOVI r10,0xF924
  MOVHI r10,0xFFFF
  CMP r3,r10
  JMP[NE] @mth_trail_fail
  MOVI r1,@mth_trail_pass
  CALL @mth_puts
  HALT
mth_trail_fail:
  MOVI r1,@mth_trail_bad
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
mth_trail_pass:
.str "MTH TRAIL CREDIT PASS\n"
mth_trail_bad:
.str "MTH TRAIL CREDIT FAIL\n"
