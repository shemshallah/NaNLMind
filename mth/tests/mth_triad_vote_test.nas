.org 0
JMP @mth_triad_test_main
.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_triad_vote.nas"

mth_triad_test_main:
  MOVI r13,1

  ; Candidate true, members 0/1/2 = false/true/true -> mask 6, accepted.
  MOVI r1,0x0001
  MOVI r2,0x0003
  MOVI r3,0x0001
  MOVI r4,0x0002
  MOVI r5,0x0002
  MOVI r6,0
  MOVI r7,0
  MOVI r8,1
  CALL @mth_triad_vote
  MOVI r10,6
  CMP r1,r10
  JMP[NE] @mth_triad_fail
  MOVI r10,1
  CMP r2,r10
  JMP[NE] @mth_triad_fail
  MOVI r10,2
  CMP r3,r10
  JMP[NE] @mth_triad_fail
  MOVI r10,1
  CMP r4,r10
  JMP[NE] @mth_triad_fail

  ; Candidate false -> no votes, rejected; mask 1, rule 0.
  MOVI r1,0x0002
  MOVI r2,0x0003
  MOVI r3,0x0002
  MOVI r4,0x0002
  MOVI r5,0x0002
  MOVI r6,0
  MOVI r7,0
  MOVI r8,1
  CALL @mth_triad_vote
  CMP r1,r0
  JMP[NE] @mth_triad_fail
  CMP r2,r0
  JMP[NE] @mth_triad_fail
  MOVI r10,1
  CMP r3,r10
  JMP[NE] @mth_triad_fail
  CMP r4,r0
  JMP[NE] @mth_triad_fail

  ; Candidate true but only member 2 agrees -> mask 4, rejected.
  MOVI r1,0x0001
  MOVI r2,0x0003
  MOVI r3,0x0001
  MOVI r4,0x0001
  MOVI r5,0x0002
  MOVI r6,0
  MOVI r7,0
  MOVI r8,1
  CALL @mth_triad_vote
  MOVI r10,4
  CMP r1,r10
  JMP[NE] @mth_triad_fail
  CMP r2,r0
  JMP[NE] @mth_triad_fail

  MOVI r1,@mth_triad_pass
  CALL @mth_puts
  HALT
mth_triad_fail:
  MOVI r1,@mth_triad_bad
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

mth_triad_pass:
.str "MTH TRIAD VOTE PASS\n"
mth_triad_bad:
.str "MTH TRIAD VOTE FAIL\n"
