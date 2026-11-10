.org 0
JMP @mth_vm_test_main
.include "../nan16/mth_vector_matrix.nas"

mth_vm_test_main:
  MOVI r13,1
  CALL @mth_vm_reset

  ; pair (0,1) -> cell 0, value 65536
  MOVI r1,0
  MOVI r2,1
  MOVI r3,0
  MOVHI r3,0x0001
  CALL @mth_vm_accum
  CMP r1,r0
  JMP[NE] @mth_vm_fail
  MOVI r12,0
  MOVHI r12,0x0001
  CMP r2,r12
  JMP[NE] @mth_vm_fail

  ; reversed pair accumulates into the same cell
  MOVI r1,1
  MOVI r2,0
  MOVI r3,0
  MOVHI r3,0x0001
  CALL @mth_vm_accum
  CMP r1,r0
  JMP[NE] @mth_vm_fail
  MOVI r12,0
  MOVHI r12,0x0002
  CMP r2,r12
  JMP[NE] @mth_vm_fail

  ; equal heads use the sentinel
  MOVI r1,4
  MOVI r2,4
  MOVI r3,1
  CALL @mth_vm_accum
  MOVI r12,32640
  CMP r1,r12
  JMP[NE] @mth_vm_fail

  ; last pair (254,255) -> 32639
  MOVI r1,254
  MOVI r2,255
  MOVI r3,0
  MOVHI r3,0x0001
  CALL @mth_vm_accum
  MOVI r12,32639
  CMP r1,r12
  JMP[NE] @mth_vm_fail

  ; probe head 0 must return head 1 with score 131072
  MOVI r1,0
  MOVI r2,1
  CALL @mth_vm_probe
  MOVI r12,1
  CMP r1,r12
  JMP[NE] @mth_vm_fail
  MOVI r12,0
  MOVHI r12,0x0002
  CMP r2,r12
  JMP[NE] @mth_vm_fail

  ; read back cell 0 and the last cell from guest memory
  MOVI r10,0x0000
  MOVHI r10,0x0030
  LD r11,r10,0
  MOVI r12,0
  MOVHI r12,0x0002
  CMP r11,r12
  JMP[NE] @mth_vm_fail
  MOVI r1,254
  MOVI r2,255
  CALL @mth_vm_pair
  MOVI r12,32639
  CMP r1,r12
  JMP[NE] @mth_vm_fail

  ; head credits: 0 and 1 have 131072, head 4 has none
  MOVI r1,0x7000
  CALL @mth_vm_credits
  MOVI r12,255
  CMP r1,r12
  JMP[NE] @mth_vm_fail
  MOVI r10,0x7000
  LD r11,r10,0
  MOVI r12,0
  MOVHI r12,0x0002
  CMP r11,r12
  JMP[NE] @mth_vm_fail
  LD r11,r10,4
  CMP r11,r0
  JMP[NE] @mth_vm_fail
  MOVI r10,0x7000
  ADDI r10,r10,254
  LD r11,r10,0
  MOVI r12,0
  MOVHI r12,0x0001
  CMP r11,r12
  JMP[NE] @mth_vm_fail

  MOVI r1,@mth_vm_pass
  CALL @mth_vm_puts
  HALT
mth_vm_fail:
  MOVI r1,@mth_vm_bad
  CALL @mth_vm_puts
  HALT
mth_vm_puts:
  MOVI r4,255
mth_vm_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_vm_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_vm_puts_byte
  ADD r1,r1,r13
  JMP @mth_vm_puts_word
mth_vm_pass:
.str "MTH VECTOR MATRIX PASS\n"
mth_vm_bad:
.str "MTH VECTOR MATRIX FAIL\n"
