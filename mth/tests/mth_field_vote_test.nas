.org 0
JMP @mth_field_test_main
.include "../nan16/mth_field_vote.nas"

mth_field_test_main:
  MOVI r13,1
  ; Fill 85 words with zero, then set the first 43 to mask 6.
  MOVI r1,@mth_field_votes
  MOVI r2,0
mth_field_clear:
  ST r0,r1,0
  ADDI r1,r1,4
  ADDI r2,r2,1
  MOVI r3,85
  CMP r2,r3
  JMP[LT] @mth_field_clear
  MOVI r1,@mth_field_votes
  MOVI r2,43
  MOVI r3,6
mth_field_seed:
  ST r3,r1,0
  ADDI r1,r1,4
  SUB r2,r2,r13
  CMP r2,r0
  JMP[NE] @mth_field_seed

  MOVI r1,@mth_field_votes
  MOVI r2,85
  CALL @mth_field_vote
  MOVI r10,43
  CMP r1,r10
  JMP[NE] @mth_field_fail
  MOVI r10,1
  CMP r2,r10
  JMP[NE] @mth_field_fail

  ; 42 accepted triads must not pass the one-field majority.
  MOVI r1,@mth_field_votes
  ST r0,r1,0
  MOVI r2,85
  CALL @mth_field_vote
  MOVI r10,42
  CMP r1,r10
  JMP[NE] @mth_field_fail
  CMP r2,r0
  JMP[NE] @mth_field_fail

  MOVI r1,@mth_field_pass
  CALL @mth_puts
  HALT
mth_field_fail:
  MOVI r1,@mth_field_bad
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

mth_field_pass:
.str "MTH FIELD VOTE PASS\n"
mth_field_bad:
.str "MTH FIELD VOTE FAIL\n"
mth_field_votes:
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
