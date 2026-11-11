; End-to-end opcode107 from same 48M raw NaN16 field driver.
; Verify causal future isolation and a legitimate 6-slot bidirectional infill.
.org 0
JMP @test_ctx107_main
.include "../drivers/field_driver.nas"
test_ctx107_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r10,0x4000
  MOVI r11,107
  ST r11,r10,0
  MOVI r10,0x4000
  MOVHI r10,0x003E
  MOVI r11,8192
  ST r11,r10,0
  MOVI r11,100
  ST r11,r10,1
  MOVI r11,500
  ST r11,r10,2
  MOVI r11,900
  ST r11,r10,3
  MOVI r11,7
  ST r11,r10,7
  ST r0,r10,8
  MOVI r11,42
  ST r11,r10,9
  ST r11,r10,10
  MOVI r11,255
  ST r11,r10,11
  MOVI r10,0x4100
  MOVHI r10,0x003E
  MOVI r11,4444
  ST r11,r10,0

  ; Future bit is forbidden in a causal task and output is unchanged.
  MOVI r10,0x4007
  MOVHI r10,0x003E
  MOVI r11,15
  ST r11,r10,0
  MOVI r10,0x4004
  MOVHI r10,0x003E
  MOVI r11,7200
  ST r11,r10,0
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r0
  JMP[NE] @test_ctx107_fail
  LD r10,r0,0x4013
  MOVI r11,2
  CMP r10,r11
  JMP[NE] @test_ctx107_fail
  MOVI r10,0x4100
  MOVHI r10,0x003E
  LD r11,r10,0
  MOVI r12,4444
  CMP r11,r12
  JMP[NE] @test_ctx107_fail

  ; Redact future payload, run genuine causal attention.
  MOVI r10,0x4004
  MOVHI r10,0x003E
  ST r0,r10,0
  MOVI r10,0x4007
  MOVHI r10,0x003E
  MOVI r11,7
  ST r11,r10,0
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r13
  JMP[NE] @test_ctx107_fail
  LD r10,r0,0x4011
  MOVI r11,3
  CMP r10,r11
  JMP[NE] @test_ctx107_fail
  MOVI r10,0x4102
  MOVHI r10,0x003E
  LD r11,r10,0
  MOVI r12,0
  MOVHI r12,0x3F80
  FCMP r11,r12
  JMP[GE] @test_ctx107_fail
  MOVI r10,0x4106
  MOVHI r10,0x003E
  LD r11,r10,0
  MOVI r12,255
  CMP r11,r12
  JMP[NE] @test_ctx107_fail

  ; Six distinct observed neighbors allowed ONLY in explicit task1.
  MOVI r10,0x4004
  MOVHI r10,0x003E
  MOVI r11,16384
  ST r11,r10,0
  MOVI r11,32768
  ST r11,r10,1
  MOVI r11,48000
  ST r11,r10,2
  MOVI r10,0x4007
  MOVHI r10,0x003E
  MOVI r11,63
  ST r11,r10,0
  ST r13,r10,1
  CALL @field_driver_main
  LD r10,r0,0x4010
  CMP r10,r13
  JMP[NE] @test_ctx107_fail
  LD r10,r0,0x4011
  MOVI r11,6
  CMP r10,r11
  JMP[NE] @test_ctx107_fail
  MOVI r1,@test_ctx107_pass
  CALL @test_ctx107_puts
  HALT
test_ctx107_fail:
  MOVI r1,@test_ctx107_bad
  CALL @test_ctx107_puts
  HALT
test_ctx107_puts:
  MOVI r13,1
  MOVI r4,255
test_ctx107_puts_word:
  LD r2,r1,0
  MOVI r3,4
test_ctx107_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @test_ctx107_puts_byte
  ADD r1,r1,r13
  JMP @test_ctx107_puts_word
test_ctx107_pass:
.str "MTH 48M CONTEXT6 OPCODE107 PASS\n"
test_ctx107_bad:
.str "MTH 48M CONTEXT6 OPCODE107 FAIL\n"
