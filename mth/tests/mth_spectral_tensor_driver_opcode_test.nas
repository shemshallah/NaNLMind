; Real native field-driver opcode 106: entire guest request -> CANDIDATE
; 128MiB dual-bank address proposal, with no host-language arithmetic.
.org 0
JMP @sto_main
.include "../drivers/field_driver_base.nas"

sto_main:
  MOVI r0,0
  MOVI r13,1
  ; Only head1 has spectral energy and a current writer lease.
  MOVI r10,0x0002
  MOVHI r10,0x003D
  MOVI r11,0
  MOVHI r11,1
  ST r11,r10,0
  MOVI r10,0x0801
  MOVHI r10,0x003D
  ST r13,r10,0
  ; Head1's pair = (1,2), offset 0x04040BF8 candidate bank.
  MOVI r10,0x0502
  MOVHI r10,0x003D
  ST r13,r10,0
  MOVI r11,2
  ST r11,r10,1

  MOVI r9,0
sto_vote_loop:
  MOVI r10,0x0400
  MOVHI r10,0x003D
  ADD r10,r10,r9
  MOVI r11,7
  ST r11,r10,0
  ADDI r9,r9,1
  MOVI r11,85
  CMP r9,r11
  JMP[LT] @sto_vote_loop

  MOVI r10,0x4000
  MOVI r11,106
  ST r11,r10,0
  MOVI r11,12
  ST r11,r10,1
  ST r11,r10,2
  ST r13,r10,3
  ST r13,r10,4
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  CMP r11,r13
  JMP[NE] @sto_fail
  LD r11,r10,1
  MOVI r12,85
  CMP r11,r12
  JMP[NE] @sto_fail
  LD r11,r10,2
  CMP r11,r13
  JMP[NE] @sto_fail
  LD r11,r10,3
  CMP r11,r0
  JMP[NE] @sto_fail

  MOVI r10,0x1000
  MOVHI r10,0x003D
  LD r11,r10,0
  CMP r11,r13
  JMP[NE] @sto_fail
  LD r11,r10,1
  CMP r11,r13
  JMP[NE] @sto_fail
  LD r11,r10,2
  MOVI r12,2
  CMP r11,r12
  JMP[NE] @sto_fail
  LD r11,r10,3
  MOVI r12,0x0BF8
  MOVHI r12,0x0404
  CMP r11,r12
  JMP[NE] @sto_fail
  LD r11,r10,4
  MOVI r12,0
  MOVHI r12,1
  CMP r11,r12
  JMP[NE] @sto_fail

  ; Deny global gate. The guest must reject and leave output unchanged.
  MOVI r10,0x4003
  ST r0,r10,0
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  CMP r11,r0
  JMP[NE] @sto_fail
  MOVI r10,0x1003
  MOVHI r10,0x003D
  LD r11,r10,0
  MOVI r12,0x0BF8
  MOVHI r12,0x0404
  CMP r11,r12
  JMP[NE] @sto_fail
  MOVI r1,@sto_pass
  CALL @sto_puts
  HALT
sto_fail:
  MOVI r1,@sto_bad
  CALL @sto_puts
  HALT
sto_puts:
  MOVI r4,255
sto_puts_word:
  LD r2,r1,0
  MOVI r3,4
sto_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @sto_puts_byte
  ADD r1,r1,r13
  JMP @sto_puts_word
sto_pass:
.str "MTH 48M SPECTRAL TENSOR OPCODE106 PASS\n"
sto_bad:
.str "MTH 48M SPECTRAL TENSOR OPCODE106 FAIL\n"
