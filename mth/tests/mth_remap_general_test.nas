.org 0
JMP @mth_rg_test_main
.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_triad_score.nas"
.include "../nan16/mth_remap_general.nas"

mth_rg_test_main:
  MOVI r13,1
  ; A=[CONST1,CONST0,CONST0], B=[CONST1,CONST0,CONST0].
  ; Swap A slot 1 with B slot 0 -> A gains a majority.
  MOVI r10,@mth_rg_masks
  MOVI r5,0x8000
  ST r5,r10,0
  ST r0,r10,1
  ST r0,r10,2
  ST r5,r10,3
  ST r0,r10,4
  ST r0,r10,5
  MOVI r1,@mth_rg_masks
  MOVI r2,1
  MOVI r3,0
  MOVI r4,0
  MOVI r5,0
  MOVI r6,1
  CALL @mth_remap_general
  MOVI r10,1
  CMP r1,r10
  JMP[NE] @mth_rg_fail
  MOVI r10,2
  CMP r2,r10
  JMP[NE] @mth_rg_fail
  MOVI r10,4
  CMP r3,r10
  JMP[NE] @mth_rg_fail
  ; table restored: A1=0, B0=0x8000
  MOVI r10,@mth_rg_masks
  LD r11,r10,1
  CMP r11,r0
  JMP[NE] @mth_rg_fail
  LD r11,r10,3
  MOVI r12,0x8000
  CMP r11,r12
  JMP[NE] @mth_rg_fail

  ; A=[CONST1,CONST1,CONST0], B=[0,0,0]; swap A slot1/B slot0 is worse.
  MOVI r10,@mth_rg_masks
  MOVI r5,0x8000
  ST r5,r10,0
  ST r5,r10,1
  ST r0,r10,2
  ST r0,r10,3
  ST r0,r10,4
  ST r0,r10,5
  MOVI r1,@mth_rg_masks
  MOVI r2,1
  MOVI r3,0
  MOVI r4,0
  MOVI r5,0
  MOVI r6,1
  CALL @mth_remap_general
  CMP r1,r0
  JMP[NE] @mth_rg_fail
  ; table restored
  MOVI r10,@mth_rg_masks
  LD r11,r10,1
  MOVI r12,0x8000
  CMP r11,r12
  JMP[NE] @mth_rg_fail
  LD r11,r10,3
  CMP r11,r0
  JMP[NE] @mth_rg_fail

  MOVI r1,@mth_rg_pass
  CALL @mth_puts
  HALT
mth_rg_fail:
  MOVI r1,@mth_rg_bad
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

mth_rg_pass:
.str "MTH GENERAL REMAP PASS\n"
mth_rg_bad:
.str "MTH GENERAL REMAP FAIL\n"
mth_rg_masks:
.word 0
.word 0
.word 0
.word 0
.word 0
.word 0
