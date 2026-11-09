.org 0
JMP @mth_remap_test_main
.include "../nan16/mth_remap_decision.nas"

mth_remap_test_main:
  MOVI r13,1

  ; A = [CONST1, CONST0, CONST0], B = [CONST1, CONST0, CONST0].
  ; Swapping A1 with B0 improves A to two correct members and is accepted.
  MOVI r10,@mth_remap_masks
  MOVI r5,0x8000
  ST r5,r10,0
  ST r0,r10,4
  ST r0,r10,8
  ST r5,r10,12
  ST r0,r10,16
  ST r0,r10,20
  MOVI r1,@mth_remap_masks
  MOVI r2,0
  MOVI r3,0
  MOVI r4,1
  CALL @mth_remap_decision
  MOVI r10,1
  CMP r1,r10
  JMP[NE] @mth_remap_fail
  MOVI r10,@mth_remap_masks
  LD r11,r10,4
  MOVI r12,0x8000
  CMP r11,r12
  JMP[NE] @mth_remap_fail
  LD r11,r10,12
  CMP r11,r0
  JMP[NE] @mth_remap_fail

  ; A = [CONST1, CONST1, CONST0], B = [CONST0, CONST0, CONST0].
  ; The trial swap destroys A's majority and must roll back.
  MOVI r10,@mth_remap_masks
  MOVI r5,0x8000
  ST r5,r10,0
  ST r5,r10,4
  ST r0,r10,8
  ST r0,r10,12
  ST r0,r10,16
  ST r0,r10,20
  MOVI r1,@mth_remap_masks
  MOVI r2,0
  MOVI r3,0
  MOVI r4,1
  CALL @mth_remap_decision
  CMP r1,r0
  JMP[NE] @mth_remap_fail
  MOVI r10,@mth_remap_masks
  LD r11,r10,4
  MOVI r12,0x8000
  CMP r11,r12
  JMP[NE] @mth_remap_fail
  LD r11,r10,12
  CMP r11,r0
  JMP[NE] @mth_remap_fail

  MOVI r1,@mth_remap_pass
  CALL @mth_puts
  HALT
mth_remap_fail:
  MOVI r1,@mth_remap_bad
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

mth_remap_pass:
.str "MTH TRIAD REMAP PASS\n"
mth_remap_bad:
.str "MTH TRIAD REMAP FAIL\n"
mth_remap_masks:
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
