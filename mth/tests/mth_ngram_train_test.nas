.org 0
JMP @main
.include "../nan16/mth_ngram_train.nas"
main:
  MOVI r13,1
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r10,97
  ST r10,r1,0
  MOVI r10,98
  ST r10,r1,1
  MOVI r10,97
  ST r10,r1,2
  MOVI r10,98
  ST r10,r1,3
  MOVI r10,97
  ST r10,r1,4
  CALL @mth_ngram_reset
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r2,5
  MOVI r3,0
  CALL @mth_ngram_train
  CALL @mth_ngram_topk
  ; unigram a/b are the top two entries (order 1, keys at 0x2D0000)
  MOVI r10,0x0000
  MOVHI r10,0x002D
  LD r11,r10,0
  MOVI r12,97
  CMP r11,r12
  JMP[NE] @mth_ng_test_fail
  LD r11,r10,1
  MOVI r12,98
  CMP r11,r12
  JMP[NE] @mth_ng_test_fail
  MOVI r9,0x1000
  MOVHI r9,0x002D
  LD r11,r9,0
  MOVI r12,3
  CMP r11,r12
  JMP[NE] @mth_ng_test_fail
  MOVI r1,@mth_ng_test_pass
  CALL @mth_ng_test_puts
  HALT
mth_ng_test_fail:
  MOVI r1,@mth_ng_test_bad
  CALL @mth_ng_test_puts
  HALT
mth_ng_test_puts:
  MOVI r13,1
  MOVI r4,255
mth_ng_test_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_ng_test_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_ng_test_puts_byte
  ADD r1,r1,r13
  JMP @mth_ng_test_puts_word
mth_ng_test_pass:
.str "MTH NGRAM TRAIN PASS\n"
mth_ng_test_bad:
.str "MTH NGRAM TRAIN FAIL\n"
