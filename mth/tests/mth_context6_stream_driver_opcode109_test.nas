; One native NaN16 call: corpus stream -> target-safe six-slot attention ->
; Poincare disk. Check target mutation invariance THROUGH attention.
.org 0
JMP @c109_main
.include "../drivers/field_driver_base.nas"

c109_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r10,0x6000
  MOVHI r10,0x003E
  MOVI r11,10
  ST r11,r10,0
  MOVI r11,20
  ST r11,r10,1
  MOVI r11,30
  ST r11,r10,2
  MOVI r11,40
  ST r11,r10,3
  MOVI r11,50
  ST r11,r10,4
  MOVI r11,60
  ST r11,r10,5
  MOVI r11,70
  ST r11,r10,6
  MOVI r10,0x4000
  MOVI r11,109
  ST r11,r10,0
  MOVI r11,7
  ST r11,r10,1   ; count=7
  ST r11,r10,2   ; predict next at i=7
  ST r0,r10,3   ; task0 causal
  ST r0,r10,4   ; query anchor derived from last observed token
  MOVI r11,42
  ST r11,r10,5
  ST r11,r10,6
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r13
  JMP[NE] @c109_fail
  MOVI r11,3
  LD r10,r0,0x4011
  CMP r10,r11
  JMP[NE] @c109_fail
  MOVI r10,0x4104
  MOVHI r10,0x003E
  LD r11,r10,0
  MOVI r12,7
  CMP r11,r12
  JMP[NE] @c109_fail
  LD r11,r10,2
  MOVI r12,255
  CMP r11,r12
  JMP[NE] @c109_fail
  LD r11,r10,3
  MOVI r12,70
  CMP r11,r12
  JMP[NE] @c109_fail

  ; Bidirectional *masked* infill center3; observe 3 past and 3 future.
  MOVI r10,0x4002
  MOVI r11,3
  ST r11,r10,0  ; center3
  ST r13,r10,1  ; task1
  MOVI r11,8192
  ST r11,r10,2  ; anchor is explicit mask symbol, not target word
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r13
  JMP[NE] @c109_fail
  MOVI r11,6
  LD r10,r0,0x4011
  CMP r10,r11
  JMP[NE] @c109_fail
  MOVI r10,0x4104
  MOVHI r10,0x003E
  LD r11,r10,0
  MOVI r12,63
  CMP r11,r12
  JMP[NE] @c109_fail
  LD r11,r10,3
  MOVI r12,8192
  CMP r11,r12
  JMP[NE] @c109_fail
  MOVI r10,0x4100
  MOVHI r10,0x003E
  LD r11,r10,0
  ST r11,r0,@c109_px
  LD r11,r10,1
  ST r11,r0,@c109_py
  LD r11,r10,3
  ST r11,r0,@c109_depth

  ; Swap w[3] from 40 to 12345; output must not change by even 1 bit.
  MOVI r10,0x6003
  MOVHI r10,0x003E
  MOVI r11,12345
  ST r11,r10,0
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r13
  JMP[NE] @c109_fail
  MOVI r10,0x4100
  MOVHI r10,0x003E
  LD r11,r10,0
  LD r12,r0,@c109_px
  CMP r11,r12
  JMP[NE] @c109_fail
  LD r11,r10,1
  LD r12,r0,@c109_py
  CMP r11,r12
  JMP[NE] @c109_fail
  LD r11,r10,3
  LD r12,r0,@c109_depth
  CMP r11,r12
  JMP[NE] @c109_fail

  ; Wrong observed-center mode: no new output must be published.
  MOVI r10,0x4003
  ST r0,r10,0    ; task0 but index3 and count7 -> reject
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r0
  JMP[NE] @c109_fail
  LD r10,r0,0x4013
  CMP r10,r13
  JMP[NE] @c109_fail
  MOVI r10,0x4100
  MOVHI r10,0x003E
  LD r11,r10,0
  LD r12,r0,@c109_px
  CMP r11,r12
  JMP[NE] @c109_fail

  MOVI r1,@c109_pass
  CALL @c109_puts
  HALT
c109_fail:
  MOVI r1,@c109_bad
  CALL @c109_puts
  HALT
c109_puts:
  MOVI r13,1
  MOVI r4,255
c109_puts_word:
  LD r2,r1,0
  MOVI r3,4
c109_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @c109_puts_byte
  ADD r1,r1,r13
  JMP @c109_puts_word
c109_pass:
.str "MTH 48M STREAM CONTEXT6 OPCODE109 PASS\n"
c109_bad:
.str "MTH 48M STREAM CONTEXT6 OPCODE109 FAIL\n"
c109_px:
  .word 0
c109_py:
  .word 0
c109_depth:
  .word 0
