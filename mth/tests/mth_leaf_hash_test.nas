.org 0
JMP @mth_lh_main
.include "../nan16/mth_leaf_verify.nas"
.include "../nan16/mth_ckpt_hash.nas"

mth_lh_main:
  MOVI r13,1
  ; expected [5,7]
  MOVI r10,0x7000
  MOVI r11,5
  ST r11,r10,0
  MOVI r11,7
  ST r11,r10,1
  ; codebook row0 [0,0]
  MOVI r10,0x0000
  MOVHI r10,0x0001
  ST r0,r10,0
  ST r0,r10,1
  ; residual [5,7] reconstructs exactly
  MOVI r10,0x0000
  MOVHI r10,0x0003
  MOVI r11,5
  ST r11,r10,0
  MOVI r11,7
  ST r11,r10,1
  MOVI r1,0x7000
  MOVI r2,0x0000
  MOVHI r2,0x0001
  MOVI r3,0x0000
  MOVHI r3,0x0003
  MOVI r4,0
  MOVI r5,2
  MOVI r6,0
  CALL @mth_leaf_verify
  MOVI r12,1
  CMP r1,r12
  JMP[NE] @mth_lh_fail
  CMP r2,r0
  JMP[NE] @mth_lh_fail

  ; corrupt residual -> reject with L1 error 12
  MOVI r10,0x0000
  MOVHI r10,0x0003
  ST r0,r10,0
  ST r0,r10,1
  MOVI r1,0x7000
  MOVI r2,0x0000
  MOVHI r2,0x0001
  MOVI r3,0x0000
  MOVHI r3,0x0003
  MOVI r4,0
  MOVI r5,2
  MOVI r6,0
  CALL @mth_leaf_verify
  CMP r1,r0
  JMP[NE] @mth_lh_fail
  MOVI r12,12
  CMP r2,r12
  JMP[NE] @mth_lh_fail

  ; FNV digest is stable and payload-sensitive
  MOVI r10,0x0000
  MOVHI r10,0x0035
  MOVI r11,1
  ST r11,r10,0
  MOVI r11,2
  ST r11,r10,1
  MOVI r11,3
  ST r11,r10,2
  MOVI r1,0x0000
  MOVHI r1,0x0035
  MOVI r2,3
  CALL @mth_ckpt_hash
  MOVI r10,0x7100
  ST r1,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0035
  MOVI r2,3
  CALL @mth_ckpt_hash
  MOVI r10,0x7100
  LD r11,r10,0
  CMP r1,r11
  JMP[NE] @mth_lh_fail
  MOVI r10,0x0000
  MOVHI r10,0x0035
  MOVI r11,4
  ST r11,r10,0
  MOVI r1,0x0000
  MOVHI r1,0x0035
  MOVI r2,3
  CALL @mth_ckpt_hash
  MOVI r10,0x7100
  LD r11,r10,0
  CMP r1,r11
  JMP[EQ] @mth_lh_fail

  MOVI r1,@mth_lh_pass
  CALL @mth_lh_puts
  HALT
mth_lh_fail:
  MOVI r1,@mth_lh_bad
  CALL @mth_lh_puts
  HALT
mth_lh_puts:
  MOVI r4,255
mth_lh_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_lh_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_lh_puts_byte
  ADD r1,r1,r13
  JMP @mth_lh_puts_word
mth_lh_pass:
.str "MTH LEAF HASH PASS\n"
mth_lh_bad:
.str "MTH LEAF HASH FAIL\n"
