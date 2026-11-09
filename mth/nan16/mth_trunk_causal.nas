; Raw NaN16 learned QKV/MLP causal feature block.
;
; ABI:
;   r1 = token count T (1..256)
; Fixed memory:
;   0x7000 tokens: T x 8 float32 lanes
;   0x9000 Wq 8x8, 0x9040 Wk 8x8, 0x9080 Wv 8x8
;   0x90C0 Wout 8x8, 0x9100 W1 16x8, 0x9180 W2 8x16
;   0xA000 output feature[8]
;
; Only the last token queries the causal context.  For each earlier token s:
;   k_s = Wk x_s, v_s = Wv x_s
; then softmax(q_last . k_s) over s<=last, followed by Wout, residual and a
; tanh MLP (8 -> 16 -> 8).  All arithmetic is raw NaN16 float32; no host math.

mth_trunk_causal:
  MOVI r12,@mth_tc_link
  ST r15,r12,0
  MOVI r12,@mth_tc_T
  ST r1,r12,0

  ; q_last = Wq * x_last
  MOVI r10,@mth_tc_T
  LD r1,r10,0
  SUB r1,r1,r13
  MOVI r2,8
  MUL r1,r1,r2
  MOVI r2,0x7000
  ADD r2,r2,r1
  MOVI r1,0x9000
  MOVI r3,0x7900
  MOVI r4,8
  MOVI r5,8
  CALL @mth_mv

  MOVI r10,@mth_tc_s
  ST r0,r10,0
mth_tc_kv_loop:
  MOVI r10,@mth_tc_T
  LD r4,r10,0
  MOVI r10,@mth_tc_s
  LD r6,r10,0
  CMP r6,r4
  JMP[GE] @mth_tc_kv_done

  ; x_s pointer
  MOVI r7,8
  MUL r7,r6,r7
  MOVI r2,0x7000
  ADD r2,r2,r7

  ; k_s = Wk x_s
  MOVI r1,0x9040
  MOVI r3,0x7A00
  MOVI r4,8
  MOVI r5,8
  CALL @mth_mv

  ; v_s = Wv x_s
  MOVI r10,@mth_tc_s
  LD r6,r10,0
  MOVI r7,8
  MUL r7,r6,r7
  MOVI r3,0x7B00
  ADD r3,r3,r7
  MOVI r1,0x9080
  MOVI r2,0x7000
  MOVI r7,8
  MUL r7,r6,r7
  ADD r2,r2,r7
  MOVI r4,8
  MOVI r5,8
  CALL @mth_mv

  ; score = dot(q_last, k_s)
  MOVI r6,0
  MOVI r7,8
  MOVI r14,0
mth_tc_dot_loop:
  CMP r6,r7
  JMP[GE] @mth_tc_dot_done
  MOVI r10,0x7900
  ADD r10,r10,r6
  LD r11,r10,0
  MOVI r10,0x7A00
  ADD r10,r10,r6
  LD r12,r10,0
  FMUL r12,r11,r12
  FADD r14,r14,r12
  ADDI r6,r6,1
  JMP @mth_tc_dot_loop
mth_tc_dot_done:
  MOVI r10,@mth_tc_s
  LD r6,r10,0
  MOVI r10,0x7800
  ADD r10,r10,r6
  ST r14,r10,0
  ADDI r6,r6,1
  MOVI r10,@mth_tc_s
  ST r6,r10,0
  JMP @mth_tc_kv_loop

mth_tc_kv_done:
  ; exponentiate scores and sum.
  MOVI r10,@mth_tc_sum
  ST r0,r10,0
  MOVI r10,@mth_tc_s
  ST r0,r10,0
mth_tc_exp_loop:
  MOVI r10,@mth_tc_T
  LD r4,r10,0
  MOVI r10,@mth_tc_s
  LD r6,r10,0
  CMP r6,r4
  JMP[GE] @mth_tc_exp_done
  MOVI r10,0x7800
  ADD r10,r10,r6
  LD r7,r10,0
  FEXP r7,r7
  ST r7,r10,0
  MOVI r10,@mth_tc_sum
  LD r8,r10,0
  FADD r8,r8,r7
  ST r8,r10,0
  ADDI r6,r6,1
  MOVI r10,@mth_tc_s
  ST r6,r10,0
  JMP @mth_tc_exp_loop

mth_tc_exp_done:
  ; context[8] = 0
  MOVI r10,0x8400
  MOVI r6,0
  MOVI r8,8
mth_tc_clear_ctx:
  CMP r6,r8
  JMP[GE] @mth_tc_clear_done
  ADD r7,r10,r6
  ST r0,r7,0
  ADDI r6,r6,1
  JMP @mth_tc_clear_ctx
mth_tc_clear_done:

  ; outer s; inner d: context[d] += softmax_s * v_s[d]
  MOVI r10,@mth_tc_s
  ST r0,r10,0
mth_tc_ctx_s:
  MOVI r10,@mth_tc_T
  LD r4,r10,0
  MOVI r10,@mth_tc_s
  LD r6,r10,0
  CMP r6,r4
  JMP[GE] @mth_tc_ctx_done

  MOVI r10,0x7800
  ADD r10,r10,r6
  LD r7,r10,0
  MOVI r10,@mth_tc_sum
  LD r8,r10,0
  FDIV r7,r7,r8             ; softmax weight
  MOVI r8,0                 ; d
mth_tc_ctx_d:
  MOVI r9,8
  CMP r8,r9
  JMP[GE] @mth_tc_ctx_next_s
  MOVI r10,8
  MUL r10,r6,r10
  ADD r10,r10,r8
  MOVI r9,0x7B00
  ADD r9,r9,r10
  LD r11,r9,0
  FMUL r11,r11,r7
  MOVI r9,0x8400
  ADD r9,r9,r8
  LD r12,r9,0
  FADD r12,r12,r11
  ST r12,r9,0
  ADDI r8,r8,1
  JMP @mth_tc_ctx_d
mth_tc_ctx_next_s:
  MOVI r10,@mth_tc_s
  LD r6,r10,0
  ADDI r6,r6,1
  ST r6,r10,0
  JMP @mth_tc_ctx_s
mth_tc_ctx_done:

  ; h = x_last + Wout * context
  MOVI r1,0x90C0
  MOVI r2,0x8400
  MOVI r3,0x8500
  MOVI r4,8
  MOVI r5,8
  CALL @mth_mv
  MOVI r10,@mth_tc_T
  LD r1,r10,0
  SUB r1,r1,r13
  MOVI r2,8
  MUL r1,r1,r2
  MOVI r2,0x7000
  ADD r2,r2,r1
  MOVI r6,0
mth_tc_h_loop:
  MOVI r7,8
  CMP r6,r7
  JMP[GE] @mth_tc_h_done
  MOVI r10,0x8500
  ADD r10,r10,r6
  LD r7,r10,0
  ADD r9,r2,r6
  LD r8,r9,0
  FADD r7,r7,r8
  MOVI r10,0x8600
  ADD r10,r10,r6
  ST r7,r10,0
  ADDI r6,r6,1
  JMP @mth_tc_h_loop
mth_tc_h_done:

  ; hidden = tanh(W1 * h)
  MOVI r1,0x9100
  MOVI r2,0x8600
  MOVI r3,0x8700
  MOVI r4,16
  MOVI r5,8
  CALL @mth_mv
  MOVI r6,0
mth_tc_tanh_loop:
  MOVI r7,16
  CMP r6,r7
  JMP[GE] @mth_tc_tanh_done
  MOVI r10,0x8700
  ADD r10,r10,r6
  LD r7,r10,0
  FTANH r7,r7
  ST r7,r10,0
  ADDI r6,r6,1
  JMP @mth_tc_tanh_loop
mth_tc_tanh_done:

  ; mlp = W2 * hidden
  MOVI r1,0x9180
  MOVI r2,0x8700
  MOVI r3,0x8800
  MOVI r4,8
  MOVI r5,16
  CALL @mth_mv

  ; output = h + mlp
  MOVI r6,0
mth_tc_out_loop:
  MOVI r7,8
  CMP r6,r7
  JMP[GE] @mth_tc_out_done
  MOVI r10,0x8600
  ADD r10,r10,r6
  LD r7,r10,0
  MOVI r10,0x8800
  ADD r10,r10,r6
  LD r8,r10,0
  FADD r7,r7,r8
  MOVI r10,0xA000
  ADD r10,r10,r6
  ST r7,r10,0
  ADDI r6,r6,1
  JMP @mth_tc_out_loop
mth_tc_out_done:

  MOVI r1,8
  MOVI r13,1
  MOVI r12,@mth_tc_link
  LD r15,r12,0
  RET

; Matrix-vector: r1=W rows x cols, r2=x[cols], r3=y[rows],
; r4=rows, r5=cols.  Row-major float32.
mth_mv:
  MOVI r12,@mth_mv_link
  ST r15,r12,0
  MOVI r11,0
mth_mv_row:
  CMP r11,r4
  JMP[GE] @mth_mv_done
  MOVI r14,0
  MOVI r10,0
mth_mv_col:
  CMP r10,r5
  JMP[GE] @mth_mv_row_done
  MUL r6,r11,r5
  ADD r6,r6,r10
  ADD r6,r1,r6
  LD r7,r6,0
  ADD r6,r2,r10
  LD r8,r6,0
  FMUL r7,r7,r8
  FADD r14,r14,r7
  ADDI r10,r10,1
  JMP @mth_mv_col
mth_mv_row_done:
  ADD r6,r3,r11
  ST r14,r6,0
  ADDI r11,r11,1
  JMP @mth_mv_row
mth_mv_done:
  MOVI r13,1
  MOVI r12,@mth_mv_link
  LD r15,r12,0
  RET

mth_tc_link:
  .word 0
mth_tc_T:
  .word 0
mth_tc_s:
  .word 0
mth_tc_sum:
  .word 0
mth_mv_link:
  .word 0
