; Raw NaNVM1 micro-transformer forward primitive.
; Two tokens, identity Q/K/V, 2-way softmax via FEXP, context mix, tanh MLP.
; This is a forward primitive, not a full shared trunk or a training kernel.
MOVI r13,1
MOVI r1,0
MOVHI r1,16256      ; x0 = 1.0
MOVI r2,0
MOVHI r2,16128      ; x1 = 0.5
MOVI r3,0
MOVHI r3,16256      ; identity projection 1.0
FMUL r4,r1,r3
FMUL r5,r2,r3
FMUL r6,r4,r4
FMUL r7,r5,r5
FEXP r8,r6
FEXP r9,r7
FADD r10,r8,r9
FDIV r11,r8,r10
FDIV r12,r9,r10
FMUL r4,r11,r1
FMUL r5,r12,r2
FADD r4,r4,r5
FTANH r4,r4
CVTFI r4,r4
MOVI r5,48
ADD r5,r5,r4
PUTC r5
MOVI r5,10
PUTC r5
MOVI r1,@mth_micro_pass
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
mth_micro_pass:
.str "MTH MICRO BLOCK PASS\n"
