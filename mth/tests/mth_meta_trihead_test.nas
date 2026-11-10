.org 0
JMP @main
.include "../nan16/mth_tokenizer.nas"
.include "../nan16/mth_meta_trihead.nas"
main:
  MOVI r13,1
  ; words 1,2,3,4 at 0x20000
  MOVI r10,0x0000
  MOVHI r10,0x0002
  MOVI r11,1
  ST r11,r10,0
  MOVI r11,2
  ST r11,r10,1
  MOVI r11,3
  ST r11,r10,2
  MOVI r11,4
  ST r11,r10,3
  CALL @mth_meta_trihead_reset
  MOVI r1,0x0000
  MOVHI r1,0x0002
  MOVI r2,4
  CALL @mth_meta_trihead_observe_batch
  MOVI r12,4
  CMP r1,r12
  JMP[NE] @mth_mt_test_fail
  MOVI r10,0x0000
  MOVHI r10,0x0022
  MOVI r5,0
  MOVI r6,0
mth_mt_test_scan:
  MOVI r12,85
  CMP r5,r12
  JMP[GE] @mth_mt_test_done
  ADD r11,r10,r5
  LD r11,r11,0
  CMP r11,r0
  JMP[EQ] @mth_mt_test_next
  ADDI r6,r6,1
mth_mt_test_next:
  ADDI r5,r5,1
  JMP @mth_mt_test_scan
mth_mt_test_done:
  CMP r6,r0
  JMP[EQ] @mth_mt_test_fail
  MOVI r1,@mth_mt_test_pass
  CALL @mth_mt_test_puts
  HALT
mth_mt_test_fail:
  MOVI r1,@mth_mt_test_bad
  CALL @mth_mt_test_puts
  HALT
mth_mt_test_puts:
  MOVI r13,1
  MOVI r4,255
mth_mt_test_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_mt_test_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_mt_test_puts_byte
  ADD r1,r1,r13
  JMP @mth_mt_test_puts_word
mth_mt_test_pass:
.str "MTH META TRIHEAD PASS\n"
mth_mt_test_bad:
.str "MTH META TRIHEAD FAIL\n"
