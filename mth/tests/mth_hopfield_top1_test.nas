.org 0
JMP @mth_hop_main
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_hopfield_top1.nas"
mth_hop_main:
  MOVI r13,1
  MOVI r1,@mth_hop_q
  MOVI r2,@mth_hop_p
  CALL @mth_hopfield_top1
  MOVI r10,2
  CMP r1,r10
  JMP[NE] @mth_hop_fail
  MOVI r10,0
  MOVHI r10,1
  CMP r2,r10
  JMP[NE] @mth_hop_fail
  MOVI r1,@mth_hop_pass
  CALL @mth_puts
  HALT
mth_hop_fail:
  MOVI r1,@mth_hop_bad
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
mth_hop_pass:
.str "MTH HOPFIELD TOP1 PASS\n"
mth_hop_bad:
.str "MTH HOPFIELD TOP1 FAIL\n"
mth_hop_q:
.word 0x00010000
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
mth_hop_p:
.word 0x00008000
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0x00010000
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0x00010000
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
