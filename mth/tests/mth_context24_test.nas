.org 0
JMP @mth_c24_main
.include "../nan16/mth_context_encode24.nas"
.include "../nan16/mth_role_step24.nas"
.include "../nan16/mth_sense_step24.nas"
mth_c24_main:
  MOVI r13,1
  ; one token, one position, embedding[0][0]=1, gate[0][0]=1
  MOVI r10,0x7000
  ST r0,r10,0
  MOVI r10,0x7400
  ST r0,r10,0
  MOVI r10,0x8000
  MOVI r11,0
  MOVHI r11,0x3F80
  ST r11,r10,0
  MOVI r10,0x8600
  ST r11,r10,0
  MOVI r10,0x4001
  MOVI r11,1
  ST r11,r10,0
  MOVI r10,0x4002
  MOVI r11,0
  MOVHI r11,0x3F80
  ST r11,r10,0
  CALL @mth_context_encode24
  MOVI r10,0x8740
  LD r11,r10,0
  ; tanh(1) ~= 0.761594; accept 0.75..0.77 by integer float compare
  MOVI r12,0
  MOVHI r12,0x3F42     ; 0.7578125
  FCMP r11,r12
  JMP[LT] @mth_c24_fail
  MOVI r12,0
  MOVHI r12,0x3F45     ; 0.7695
  FCMP r11,r12
  JMP[GT] @mth_c24_fail
  MOVI r12,0x8744
  LD r11,r12,0
  CMP r11,r0
  JMP[NE] @mth_c24_fail
  ; role24 one step
  MOVI r10,0x8760
  MOVI r11,0
  MOVHI r11,0x3F80
  ST r11,r10,0
  MOVI r10,0x8780
  ST r0,r10,0
  MOVI r10,0x8781
  MOVI r11,1
  MOVI r12,0
  MOVHI r12,0x3F80
  ST r12,r10,0
  MOVI r10,0x8782
  MOVI r12,0
  MOVHI r12,0x3F00
  ST r12,r10,0
  CALL @mth_role_step24
  MOVI r10,0
  MOVHI r10,0x3F00
  FCMP r1,r10
  JMP[LT] @mth_c24_fail

  ; sense24 one step
  MOVI r10,0x8800
  ST r0,r10,0
  MOVI r10,0x8808
  MOVI r11,0
  MOVHI r11,0x3F80
  ST r11,r10,0
  MOVI r10,0x8900
  ST r0,r10,0
  ST r0,r10,1
  MOVI r10,0x4003
  MOVI r11,2
  ST r11,r10,0
  MOVI r10,0x8783
  MOVI r11,1
  ST r11,r10,0
  MOVI r10,0x8782
  MOVI r11,0
  MOVHI r11,0x3F00
  ST r11,r10,0
  CALL @mth_sense_step24
  MOVI r10,0
  MOVHI r10,0x3F00
  FCMP r1,r10
  JMP[LT] @mth_c24_fail

  MOVI r1,@mth_c24_pass
  CALL @mth_puts
  HALT
mth_c24_fail:
  MOVI r1,@mth_c24_bad
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
mth_c24_pass:
.str "MTH CONTEXT24 PASS\n"
mth_c24_bad:
.str "MTH CONTEXT24 FAIL\n"
