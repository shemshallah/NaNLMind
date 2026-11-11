; Real field-driver opcode112: each 48M future horizon invokes the SAME
; native causal-window + CORDIC/MC0 + Poincare guest, without gold words.
.org 0
JMP @f112_main
.include "../drivers/field_driver.nas"
f112_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r8,0x6000
  MOVHI r8,0x003E
  MOVI r11,11
  ST r11,r8,0
  MOVI r11,22
  ST r11,r8,1
  MOVI r11,33
  ST r11,r8,2
  MOVI r11,44
  ST r11,r8,3
  MOVI r11,55
  ST r11,r8,4
  MOVI r8,0x5000
  MOVHI r8,0x003E
  MOVI r11,66
  ST r11,r8,0
  MOVI r11,77
  ST r11,r8,1
  MOVI r11,12345
  ST r11,r8,2 ; ungenerated future poison is UNREAD
  MOVI r8,0x4000
  MOVI r11,112
  ST r11,r8,0
  MOVI r11,5
  ST r11,r8,1
  MOVI r11,9
  ST r11,r8,3
  ST r11,r8,4
  MOVI r9,0
  ST r9,r0,0x4002      ; generated count = 0,1,2
f112_step:
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r13
  JMP[NE] @f112_bad
  LD r10,r0,0x4011
  MOVI r11,3
  CMP r10,r11
  JMP[NE] @f112_bad
  LD r10,r0,0x4012
  LD r11,r0,0x4002
  ADD r11,r11,r13
  CMP r10,r11
  JMP[NE] @f112_bad
  MOVI r10,0x4000
  MOVHI r10,0x003E
  LD r11,r10,7
  MOVI r12,7
  CMP r11,r12
  JMP[NE] @f112_bad
  LD r11,r10,4
  CMP r11,r0
  JMP[NE] @f112_bad
  LD r11,r10,5
  CMP r11,r0
  JMP[NE] @f112_bad
  LD r11,r10,6
  CMP r11,r0
  JMP[NE] @f112_bad
  LD r9,r0,0x4002
  ADDI r9,r9,1
  ST r9,r0,0x4002
  MOVI r10,3
  CMP r9,r10
  JMP[LT] @f112_step
  ; Save h3 actual guest Poincare output and mutate ungenerated slot2.
  MOVI r8,0x4100
  MOVHI r8,0x003E
  LD r10,r8,0
  ST r10,r0,@f112_x
  LD r10,r8,1
  ST r10,r0,@f112_y
  LD r10,r8,3
  ST r10,r0,@f112_depth
  MOVI r8,0x5002
  MOVHI r8,0x003E
  MOVI r11,54321
  ST r11,r8,0
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r13
  JMP[NE] @f112_bad
  MOVI r8,0x4100
  MOVHI r8,0x003E
  LD r10,r8,0
  LD r11,r0,@f112_x
  CMP r10,r11
  JMP[NE] @f112_bad
  LD r10,r8,1
  LD r11,r0,@f112_y
  CMP r10,r11
  JMP[NE] @f112_bad
  LD r10,r8,3
  LD r11,r0,@f112_depth
  CMP r10,r11
  JMP[NE] @f112_bad
  ; Source generation mismatch rejects and does NOT touch prior readout.
  MOVI r8,0x4004
  MOVI r11,10
  ST r11,r8,0
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r0
  JMP[NE] @f112_bad
  LD r10,r0,0x4013
  MOVI r11,2
  CMP r10,r11
  JMP[NE] @f112_bad
  MOVI r8,0x4100
  MOVHI r8,0x003E
  LD r10,r8,3
  LD r11,r0,@f112_depth
  CMP r10,r11
  JMP[NE] @f112_bad
  MOVI r1,@f112_pass
  CALL @f112_puts
  HALT
f112_bad:
  MOVI r1,@f112_fail
  CALL @f112_puts
  HALT
f112_puts:
  MOVI r13,1
  MOVI r4,255
f112_puts_word:
  LD r2,r1,0
  MOVI r3,4
f112_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @f112_puts_byte
  ADD r1,r1,r13
  JMP @f112_puts_word
f112_pass:
.str "MTH FUTURE3 OPCODE112 CAUSAL GUEST PASS\n"
f112_fail:
.str "MTH FUTURE3 OPCODE112 CAUSAL GUEST FAIL\n"
f112_x:
.word 0
f112_y:
.word 0
f112_depth:
.word 0
