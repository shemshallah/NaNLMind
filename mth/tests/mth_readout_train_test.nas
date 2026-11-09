.org 0
JMP @mth_rt_main
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_trunk_causal.nas"
.include "../nan16/mth_readout_train.nas"
mth_rt_main:
  MOVI r13,1
  ; one token x=[1,0,...]
  MOVI r10,0x7000
  MOVI r11,0
  MOVHI r11,0x3F80
  ST r11,r10,0
  ; identity trunk matrices
  MOVI r10,0x9000
  MOVI r12,0
mth_rt_clear_trunk:
  ST r0,r10,0
  ADDI r10,r10,1
  ADDI r12,r12,1
  MOVI r9,0x1200
  CMP r12,r9
  JMP[LT] @mth_rt_clear_trunk
  MOVI r10,0x9000
  MOVI r12,0
mth_rt_identity:
  MOVI r9,8
  MUL r9,r12,r9
  ADD r9,r9,r12
  ADD r11,r10,r9
  MOVI r8,0
  MOVHI r8,0x3F80
  ST r8,r11,0
  ADDI r12,r12,1
  MOVI r9,8
  CMP r12,r9
  JMP[LT] @mth_rt_identity
  ; Wout identity at 0x90C0 and W1/W2 identity
  MOVI r10,0x90C0
  MOVI r12,0
mth_rt_wout:
  MOVI r9,8
  MUL r9,r12,r9
  ADD r9,r9,r12
  ADD r11,r10,r9
  MOVI r8,0
  MOVHI r8,0x3F80
  ST r8,r11,0
  ADDI r12,r12,1
  MOVI r9,8
  CMP r12,r9
  JMP[LT] @mth_rt_wout
  MOVI r10,0x9100
  MOVI r12,0
mth_rt_w1:
  MOVI r9,8
  MUL r9,r12,r9
  ADD r9,r9,r12
  ADD r11,r10,r9
  MOVI r8,0
  MOVHI r8,0x3F80
  ST r8,r11,0
  ADDI r12,r12,1
  MOVI r9,8
  CMP r12,r9
  JMP[LT] @mth_rt_w1
  MOVI r10,0x9180
  MOVI r12,0
mth_rt_w2:
  MOVI r9,16
  MUL r9,r12,r9
  ADD r9,r9,r12
  ADD r11,r10,r9
  MOVI r8,0
  MOVHI r8,0x3F80
  ST r8,r11,0
  ADDI r12,r12,1
  MOVI r9,8
  CMP r12,r9
  JMP[LT] @mth_rt_w2
  ; zero readout
  MOVI r10,0xB000
  MOVI r12,0
mth_rt_zero:
  ST r0,r10,0
  ADDI r10,r10,1
  ADDI r12,r12,1
  MOVI r9,0x7F8
  CMP r12,r9
  JMP[LT] @mth_rt_zero
  ; train target 1 with lr 0.5
  MOVI r1,1
  MOVI r2,1
  MOVI r3,0
  MOVHI r3,0x3F00
  CALL @mth_readout_train
  CMP r1,r0
  JMP[NE] @mth_rt_fail
  ; second step should predict target 1
  MOVI r1,1
  MOVI r2,1
  MOVI r3,0
  CALL @mth_readout_train
  MOVI r10,1
  CMP r1,r10
  JMP[NE] @mth_rt_fail
  MOVI r1,@mth_rt_pass
  CALL @mth_puts
  HALT
mth_rt_fail:
  MOVI r1,@mth_rt_bad
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
mth_rt_pass:
.str "MTH READOUT TRAIN PASS\n"
mth_rt_bad:
.str "MTH READOUT TRAIN FAIL\n"
