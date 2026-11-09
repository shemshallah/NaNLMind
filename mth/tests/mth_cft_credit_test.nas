.org 0
JMP @mth_cft_main
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_cft_credit.nas"
mth_cft_main:
  MOVI r13,1
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r4,0
  MOVHI r4,1             ; 65536 = 1.0
  MOVI r5,0x9999
  MOVHI r5,0x0000        ; 39321 ~= 0.6
  CALL @mth_cft_credit
  ; delta = 65536*39321/65536/3 = 13107 (0x3333)
  MOVI r10,0x3333
  CMP r1,r10
  JMP[NE] @mth_cft_fail
  CMP r2,r10
  JMP[NE] @mth_cft_fail
  ; c,a gets -delta = 0xFFFFCCCD (two's complement)
  MOVI r10,0xCCCD
  MOVHI r10,0xFFFF
  CMP r3,r10
  JMP[NE] @mth_cft_fail
  ; residual = delta
  MOVI r10,0x3333
  CMP r4,r10
  JMP[NE] @mth_cft_fail
  ; negative error reverses the circulation.
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r4,0
  MOVHI r4,1
  SUB r4,r0,r4
  MOVI r5,0x9999
  CALL @mth_cft_credit
  MOVI r10,0xCCCD
  MOVHI r10,0xFFFF
  CMP r1,r10
  JMP[NE] @mth_cft_fail
  CMP r2,r10
  JMP[NE] @mth_cft_fail
  MOVI r10,0x3333
  CMP r3,r10
  JMP[NE] @mth_cft_fail
  MOVI r10,0xCCCD
  MOVHI r10,0xFFFF
  CMP r4,r10
  JMP[NE] @mth_cft_fail

  MOVI r1,@mth_cft_pass
  CALL @mth_puts
  HALT
mth_cft_fail:
  MOVI r1,@mth_cft_bad
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
mth_cft_pass:
.str "MTH CFT CREDIT PASS\n"
mth_cft_bad:
.str "MTH CFT CREDIT FAIL\n"
