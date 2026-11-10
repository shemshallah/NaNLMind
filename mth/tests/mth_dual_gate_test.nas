.org 0
JMP @mth_dg_test_main
.include "../nan16/mth_dual_gate.nas"

mth_dg_test_main:
  MOVI r13,1
  ; fast=1 slow=1 medium=1 coh=60000 threshold=50000 mask=1 patch=3
  MOVI r1,1
  MOVI r2,1
  MOVI r3,1
  MOVI r4,60000
  MOVI r5,50000
  MOVI r6,1
  MOVI r7,3
  CALL @mth_dual_gate
  MOVI r10,1
  CMP r1,r10
  JMP[NE] @mth_dg_fail
  MOVI r10,2
  CMP r2,r10
  JMP[NE] @mth_dg_fail
  CMP r3,r10
  JMP[EQ] @mth_dg_fail
  MOVI r10,1
  CMP r4,r10
  JMP[NE] @mth_dg_fail
  MOVI r10,-1
  CMP r5,r10
  JMP[EQ] @mth_dg_fail

  ; medium field false -> no commit, mask unchanged
  MOVI r1,1
  MOVI r2,1
  MOVI r3,0
  MOVI r4,60000
  MOVI r5,50000
  MOVI r6,1
  MOVI r7,3
  CALL @mth_dual_gate
  CMP r1,r0
  JMP[NE] @mth_dg_fail
  MOVI r10,1
  CMP r2,r10
  JMP[NE] @mth_dg_fail

  ; slow coherence below threshold -> no commit
  MOVI r1,1
  MOVI r2,1
  MOVI r3,1
  MOVI r4,40000
  MOVI r5,50000
  MOVI r6,1
  MOVI r7,3
  CALL @mth_dual_gate
  CMP r1,r0
  JMP[NE] @mth_dg_fail

  MOVI r1,@mth_dg_pass
  CALL @mth_dg_puts
  HALT
mth_dg_fail:
  MOVI r1,@mth_dg_bad
  CALL @mth_dg_puts
  HALT
mth_dg_puts:
  MOVI r4,255
mth_dg_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_dg_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_dg_puts_byte
  ADD r1,r1,r13
  JMP @mth_dg_puts_word
mth_dg_pass:
.str "MTH DUAL GATE PASS\n"
mth_dg_bad:
.str "MTH DUAL GATE FAIL\n"
