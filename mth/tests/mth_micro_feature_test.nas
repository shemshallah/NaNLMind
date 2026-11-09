.org 0
JMP @mth_mf_test_main
.include "../nan16/mth_micro_feature.nas"

mth_mf_test_main:
  MOVI r13,1
  ; x0 = 1.0, x1 = 0.5 for all eight lanes.
  MOVI r10,0x7000
  MOVI r11,0
  MOVHI r11,16256
  MOVI r9,8
  MOVI r2,0
mth_mf_fill0:
  CMP r2,r9
  JMP[GE] @mth_mf_fill1
  ADD r3,r10,r2
  ST r11,r3,0
  ADDI r2,r2,1
  JMP @mth_mf_fill0
mth_mf_fill1:
  MOVI r10,0x7100
  MOVI r11,0
  MOVHI r11,16128
  MOVI r2,0
mth_mf_fill1_loop:
  CMP r2,r9
  JMP[GE] @mth_mf_run
  ADD r3,r10,r2
  ST r11,r3,0
  ADDI r2,r2,1
  JMP @mth_mf_fill1_loop
mth_mf_run:
  MOVI r1,0x7000
  MOVI r2,0x7100
  MOVI r3,0x7200
  CALL @mth_micro_feature
  MOVI r10,8
  CMP r1,r10
  JMP[NE] @mth_mf_fail
  MOVI r10,0x7200
  LD r11,r10,0
  CMP r11,r0
  JMP[EQ] @mth_mf_fail

  MOVI r1,@mth_mf_pass
  CALL @mth_puts
  HALT
mth_mf_fail:
  MOVI r1,@mth_mf_bad
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

mth_mf_pass:
.str "MTH MICRO FEATURE PASS\n"
mth_mf_bad:
.str "MTH MICRO FEATURE FAIL\n"
