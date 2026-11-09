.org 0
JMP @mth_driver_test_main
.include "../drivers/field_driver.nas"

mth_driver_test_main:
  MOVI r13,1

  ; proposal: true candidate, two agreeing members -> accepted
  MOVI r10,0x4000
  MOVI r11,1
  ST r11,r10,0
  MOVI r10,0x4001
  MOVI r11,0x0001
  ST r11,r10,0
  MOVI r11,0x0003
  ST r11,r10,1
  MOVI r11,0x0001
  ST r11,r10,2
  MOVI r11,0x0002
  ST r11,r10,3
  ST r11,r10,4
  ST r0,r10,5
  ST r0,r10,6
  MOVI r11,1
  ST r11,r10,7
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  MOVI r12,6
  CMP r11,r12
  JMP[NE] @mth_driver_fail
  LD r11,r10,1
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_driver_fail

  ; field vote: 43 accepted triads
  MOVI r10,0x5000
  MOVI r11,0
mth_driver_clear:
  ST r0,r10,0
  ADDI r10,r10,1
  ADDI r11,r11,1
  MOVI r12,85
  CMP r11,r12
  JMP[LT] @mth_driver_clear
  MOVI r10,0x5000
  MOVI r11,43
  MOVI r12,6
mth_driver_seed:
  ST r12,r10,0
  ADDI r10,r10,1
  SUB r11,r11,r13
  CMP r11,r0
  JMP[NE] @mth_driver_seed
  MOVI r10,0x4000
  MOVI r11,2
  ST r11,r10,0
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  MOVI r12,43
  CMP r11,r12
  JMP[NE] @mth_driver_fail
  LD r11,r10,1
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_driver_fail

  ; coherence: all phases zero -> 65536
  MOVI r10,0x6000
  MOVI r11,0
mth_driver_phase_clear:
  ST r0,r10,0
  ADDI r10,r10,1
  ADDI r11,r11,1
  MOVI r12,255
  CMP r11,r12
  JMP[LT] @mth_driver_phase_clear
  MOVI r10,0x4000
  MOVI r11,3
  ST r11,r10,0
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  MOVI r12,65500
  CMP r11,r12
  JMP[LT] @mth_driver_fail

  ; remap: fixed A1/B0 trial improves
  MOVI r10,0x4000
  MOVI r11,4
  ST r11,r10,0
  MOVI r10,0x4001
  MOVI r11,0x8000
  ST r11,r10,0
  ST r0,r10,1
  ST r0,r10,2
  ST r11,r10,3
  ST r0,r10,4
  ST r0,r10,5
  ST r0,r10,6
  ST r0,r10,7
  MOVI r11,1
  ST r11,r10,8
  ST r11,r10,9
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_driver_fail

  MOVI r1,@mth_driver_pass
  CALL @mth_puts
  HALT
mth_driver_fail:
  MOVI r1,@mth_driver_bad
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

mth_driver_pass:
.str "MTH FIELD DRIVER PASS\n"
mth_driver_bad:
.str "MTH FIELD DRIVER FAIL\n"
