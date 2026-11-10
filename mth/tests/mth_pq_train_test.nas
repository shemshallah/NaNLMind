.org 0
JMP @mth_pqt_test_main
.include "../nan16/mth_pq_train.nas"

mth_pqt_test_main:
  MOVI r13,1
  ; samples: [0,0], [100,100] at 0x10000
  MOVI r10,0x0000
  MOVHI r10,0x0001
  ST r0,r10,0
  ST r0,r10,1
  MOVI r11,100
  ST r11,r10,2
  ST r11,r10,3

  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r2,2
  MOVI r3,2
  MOVI r4,2
  MOVI r5,1
  MOVI r6,0x0000
  MOVHI r6,0x0005
  CALL @mth_pq_train

  MOVI r10,0x0000
  MOVHI r10,0x0005
  MOVI r12,0
  LD r11,r10,0
  CMP r11,r12
  JMP[NE] @mth_pqt_fail
  LD r11,r10,1
  CMP r11,r12
  JMP[NE] @mth_pqt_fail
  LD r11,r10,2
  MOVI r12,100
  CMP r11,r12
  JMP[NE] @mth_pqt_fail
  LD r11,r10,3
  CMP r11,r12
  JMP[NE] @mth_pqt_fail

  MOVI r1,@mth_pqt_pass
  CALL @mth_pqt_puts
  HALT
mth_pqt_fail:
  MOVI r1,@mth_pqt_bad
  CALL @mth_pqt_puts
  HALT
mth_pqt_puts:
  MOVI r4,255
mth_pqt_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_pqt_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_pqt_puts_byte
  ADD r1,r1,r13
  JMP @mth_pqt_puts_word
mth_pqt_pass:
.str "MTH PQ TRAIN PASS\n"
mth_pqt_bad:
.str "MTH PQ TRAIN FAIL\n"
