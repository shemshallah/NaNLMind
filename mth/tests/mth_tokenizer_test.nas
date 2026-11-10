.org 0
JMP @main
.include "../nan16/mth_tokenizer.nas"
main:
  MOVI r13,1
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r10,72
  ST r10,r1,0
  MOVI r10,101
  ST r10,r1,1
  MOVI r10,108
  ST r10,r1,2
  MOVI r10,108
  ST r10,r1,3
  MOVI r10,111
  ST r10,r1,4
  MOVI r10,44
  ST r10,r1,5
  MOVI r10,32
  ST r10,r1,6
  MOVI r10,119
  ST r10,r1,7
  MOVI r10,111
  ST r10,r1,8
  MOVI r10,114
  ST r10,r1,9
  MOVI r10,108
  ST r10,r1,10
  MOVI r10,100
  ST r10,r1,11
  MOVI r1,0x0000
  MOVHI r1,0x0001
  MOVI r2,12
  MOVI r3,0x0000
  MOVHI r3,0x0002
  MOVI r4,0x0000
  MOVHI r4,0x0003
  MOVI r5,0x0000
  MOVHI r5,0x0004
  MOVI r6,16
  CALL @mth_tokenize
  MOVI r12,2
  CMP r1,r12
  JMP[NE] @mth_tok_test_fail
  MOVI r12,4
  CMP r2,r12
  JMP[NE] @mth_tok_test_fail
  ; meta triad field must be a valid 0..84 triad
  MOVI r10,0x0000
  MOVHI r10,0x0004
  LD r11,r10,2
  MOVI r12,85
  CMP r11,r12
  JMP[GE] @mth_tok_test_fail
  MOVI r1,@mth_tok_test_pass
  CALL @mth_tok_test_puts
  HALT
mth_tok_test_fail:
  MOVI r1,@mth_tok_test_bad
  CALL @mth_tok_test_puts
  HALT
mth_tok_test_puts:
  MOVI r4,255
mth_tok_test_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_tok_test_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_tok_test_puts_byte
  ADD r1,r1,r13
  JMP @mth_tok_test_puts_word
mth_tok_test_pass:
.str "MTH TOKENIZER PASS\n"
mth_tok_test_bad:
.str "MTH TOKENIZER FAIL\n"
