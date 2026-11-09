.org 0
JMP @mth_ht_test_main
.include "../nan16/mth_hot_trihead.nas"

mth_ht_test_main:
  MOVI r13,1

  ; Three non-contiguous hot heads 3,17,99 -> one hot triad.
  MOVI r10,0x7000
  MOVI r11,100
  MOVI r12,3
  ADD r12,r10,r12
  ST r11,r12,0
  MOVI r12,17
  ADD r12,r10,r12
  ST r11,r12,0
  MOVI r12,99
  ADD r12,r10,r12
  ST r11,r12,0
  MOVI r1,0x7000
  MOVI r2,10
  CALL @mth_hot_trihead
  MOVI r10,3
  CMP r1,r10
  JMP[NE] @mth_ht_fail
  MOVI r10,1
  CMP r2,r10
  JMP[NE] @mth_ht_fail
  CMP r3,r0
  JMP[NE] @mth_ht_fail
  MOVI r10,255
  CMP r4,r10
  JMP[NE] @mth_ht_fail
  MOVI r10,0x8000
  LD r11,r10,0
  MOVI r12,3
  CMP r11,r12
  JMP[NE] @mth_ht_fail
  LD r11,r10,1
  MOVI r12,17
  CMP r11,r12
  JMP[NE] @mth_ht_fail
  LD r11,r10,2
  MOVI r12,99
  CMP r11,r12
  JMP[NE] @mth_ht_fail

  ; 129 hot heads -> 43 complete hot triads -> field gate.
  MOVI r10,0x7000
  MOVI r11,100
  MOVI r12,0
mth_ht_fill_seed:
  MOVI r9,129
  CMP r12,r9
  JMP[GE] @mth_ht_fill_done
  ADD r9,r10,r12
  ST r11,r9,0
  ADDI r12,r12,1
  JMP @mth_ht_fill_seed
mth_ht_fill_done:
  MOVI r1,0x7000
  MOVI r2,10
  CALL @mth_hot_trihead
  MOVI r10,129
  CMP r1,r10
  JMP[NE] @mth_ht_fail
  MOVI r10,43
  CMP r2,r10
  JMP[NE] @mth_ht_fail
  MOVI r10,1
  CMP r3,r10
  JMP[NE] @mth_ht_fail
  MOVI r10,255
  CMP r4,r10
  JMP[NE] @mth_ht_fail

  MOVI r1,@mth_ht_pass
  CALL @mth_puts
  HALT
mth_ht_fail:
  MOVI r1,@mth_ht_bad
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

mth_ht_pass:
.str "MTH HOT TRIHEAD PASS\n"
mth_ht_bad:
.str "MTH HOT TRIHEAD FAIL\n"
