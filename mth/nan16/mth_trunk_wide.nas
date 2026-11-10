; Raw NaN16 wide causal trunk feature block.
;
; ABI:
;   r1 = token count T (1..1024)
;   r2 = feature width D (1..128)
;   r3 = hidden width H (1..512), normally 4*D
; Fixed memory:
;   0x10000 tokens: T x D float32
;   0x30000 values: T x D
;   0x50000 scores: T
;   0x51000 q[D], 0x52000 k[D], 0x53000 context[D],
;   0x54000 Wout result[D], 0x55000 h[D], 0x56000 hidden[H],
;   0x57000 MLP result[D]
;   0x60000 Wq,D2; Wk,D2; Wv,D2; Wout,D2; W1,H*D; W2,D*H
;   0x200000 output feature[D]
;
; Same math as mth_trunk_causal, but every loop is driven by runtime D/H/T.
; This is the arbitrary-width/1024-context path.  No host arithmetic.

mth_trunk_wide:
  MOVI r12,@mth_wd_link
  ST r15,r12,0
  MOVI r12,@mth_wd_T
  ST r1,r12,0
  MOVI r12,@mth_wd_D
  ST r2,r12,0
  MOVI r12,@mth_wd_H
  ST r3,r12,0

  ; Compute weight pointers from D/H.
  MOVI r10,0x0000
  MOVHI r10,0x0006
  MOVI r12,@mth_wd_wq
  ST r10,r12,0
  MOVI r12,@mth_wd_D
  LD r1,r12,0
  MUL r2,r1,r1
  ADD r10,r10,r2
  MOVI r12,@mth_wd_wk
  ST r10,r12,0
  ADD r10,r10,r2
  MOVI r12,@mth_wd_wv
  ST r10,r12,0
  ADD r10,r10,r2
  MOVI r12,@mth_wd_wout
  ST r10,r12,0
  ADD r10,r10,r2
  MOVI r12,@mth_wd_w1
  ST r10,r12,0
  MOVI r12,@mth_wd_H
  LD r3,r12,0
  MOVI r12,@mth_wd_D
  LD r1,r12,0
  MUL r2,r3,r1
  ADD r10,r10,r2
  MOVI r12,@mth_wd_w2
  ST r10,r12,0

  ; q_last = Wq * x_last
  MOVI r12,@mth_wd_T
  LD r1,r12,0
  SUB r1,r1,r13
  MOVI r12,@mth_wd_D
  LD r2,r12,0
  MUL r1,r1,r2
  MOVI r2,0x0000
  MOVHI r2,0x0001
  ADD r2,r2,r1
  MOVI r12,@mth_wd_wq
  LD r1,r12,0
  MOVI r3,0x1000
  MOVHI r3,0x0005
  MOVI r12,@mth_wd_D
  LD r4,r12,0
  ADD r5,r4,r0
  CALL @mth_wmv

  MOVI r10,@mth_wd_s
  ST r0,r10,0
mth_wd_kv_loop:
  MOVI r12,@mth_wd_T
  LD r4,r12,0
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  CMP r6,r4
  JMP[GE] @mth_wd_kv_done

  ; x_s pointer
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r7,r6,r7
  MOVI r2,0x0000
  MOVHI r2,0x0001
  ADD r2,r2,r7

  ; k_s = Wk x_s
  MOVI r12,@mth_wd_wk
  LD r1,r12,0
  MOVI r3,0x2000
  MOVHI r3,0x0005
  MOVI r12,@mth_wd_D
  LD r4,r12,0
  ADD r5,r4,r0
  CALL @mth_wmv

  ; v_s = Wv x_s
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r7,r6,r7
  MOVI r3,0x0000
  MOVHI r3,0x0003
  ADD r3,r3,r7
  MOVI r12,@mth_wd_wv
  LD r1,r12,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r7,r6,r7
  MOVI r2,0x0000
  MOVHI r2,0x0001
  ADD r2,r2,r7
  MOVI r12,@mth_wd_D
  LD r4,r12,0
  ADD r5,r4,r0
  CALL @mth_wmv

  ; score = dot(q_last, k_s)
  MOVI r6,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r14,0
mth_wd_dot_loop:
  CMP r6,r7
  JMP[GE] @mth_wd_dot_done
  MOVI r10,0x1000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r11,r10,0
  MOVI r10,0x2000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r12,r10,0
  FMUL r12,r11,r12
  FADD r14,r14,r12
  ADDI r6,r6,1
  JMP @mth_wd_dot_loop
mth_wd_dot_done:
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  MOVI r10,0x0000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  ST r14,r10,0
  ADDI r6,r6,1
  MOVI r12,@mth_wd_s
  ST r6,r12,0
  JMP @mth_wd_kv_loop

mth_wd_kv_done:
  ; softmax exponent and sum
  MOVI r10,@mth_wd_sum
  ST r0,r10,0
  MOVI r10,@mth_wd_s
  ST r0,r10,0
mth_wd_exp_loop:
  MOVI r12,@mth_wd_T
  LD r4,r12,0
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  CMP r6,r4
  JMP[GE] @mth_wd_exp_done
  MOVI r10,0x0000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r7,r10,0
  FEXP r7,r7
  ST r7,r10,0
  MOVI r12,@mth_wd_sum
  LD r8,r12,0
  FADD r8,r8,r7
  ST r8,r12,0
  ADDI r6,r6,1
  MOVI r12,@mth_wd_s
  ST r6,r12,0
  JMP @mth_wd_exp_loop
mth_wd_exp_done:

  ; context[D] = 0
  MOVI r10,0x3000
  MOVHI r10,0x0005
  MOVI r6,0
  MOVI r12,@mth_wd_D
  LD r8,r12,0
mth_wd_clear_ctx:
  CMP r6,r8
  JMP[GE] @mth_wd_clear_done
  ADD r7,r10,r6
  ST r0,r7,0
  ADDI r6,r6,1
  JMP @mth_wd_clear_ctx
mth_wd_clear_done:

  MOVI r12,@mth_wd_s
  ST r0,r12,0
mth_wd_ctx_s:
  MOVI r12,@mth_wd_T
  LD r4,r12,0
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  CMP r6,r4
  JMP[GE] @mth_wd_ctx_done
  MOVI r10,0x0000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r7,r10,0
  MOVI r12,@mth_wd_sum
  LD r8,r12,0
  FDIV r7,r7,r8
  MOVI r10,0x8000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  ST r7,r10,0
  MOVI r12,@mth_wd_D
  LD r9,r12,0
  MOVI r8,0
mth_wd_ctx_d:
  CMP r8,r9
  JMP[GE] @mth_wd_ctx_next_s
  MUL r10,r6,r9
  ADD r10,r10,r8
  MOVI r11,0x0000
  MOVHI r11,0x0003
  ADD r11,r11,r10
  LD r11,r11,0
  FMUL r11,r11,r7
  MOVI r10,0x3000
  MOVHI r10,0x0005
  ADD r10,r10,r8
  LD r12,r10,0
  FADD r12,r12,r11
  ST r12,r10,0
  ADDI r8,r8,1
  JMP @mth_wd_ctx_d
mth_wd_ctx_next_s:
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  ADDI r6,r6,1
  ST r6,r12,0
  JMP @mth_wd_ctx_s
mth_wd_ctx_done:

  ; h = x_last + Wout * context
  MOVI r12,@mth_wd_wout
  LD r1,r12,0
  MOVI r2,0x3000
  MOVHI r2,0x0005
  MOVI r3,0x4000
  MOVHI r3,0x0005
  MOVI r12,@mth_wd_D
  LD r4,r12,0
  ADD r5,r4,r0
  CALL @mth_wmv
  MOVI r12,@mth_wd_T
  LD r1,r12,0
  SUB r1,r1,r13
  MOVI r12,@mth_wd_D
  LD r2,r12,0
  MUL r1,r1,r2
  MOVI r2,0x0000
  MOVHI r2,0x0001
  ADD r2,r2,r1
  MOVI r6,0
mth_wd_h_loop:
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  CMP r6,r7
  JMP[GE] @mth_wd_h_done
  MOVI r10,0x4000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r7,r10,0
  ADD r9,r2,r6
  LD r8,r9,0
  FADD r7,r7,r8
  MOVI r10,0x5000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  ST r7,r10,0
  ADDI r6,r6,1
  JMP @mth_wd_h_loop
mth_wd_h_done:

  ; hidden = tanh(W1 h)
  MOVI r12,@mth_wd_w1
  LD r1,r12,0
  MOVI r2,0x5000
  MOVHI r2,0x0005
  MOVI r3,0x6000
  MOVHI r3,0x0005
  MOVI r12,@mth_wd_H
  LD r4,r12,0
  MOVI r12,@mth_wd_D
  LD r5,r12,0
  CALL @mth_wmv
  MOVI r6,0
mth_wd_tanh_loop:
  MOVI r12,@mth_wd_H
  LD r7,r12,0
  CMP r6,r7
  JMP[GE] @mth_wd_tanh_done
  MOVI r10,0x6000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r7,r10,0
  FTANH r7,r7
  ST r7,r10,0
  ADDI r6,r6,1
  JMP @mth_wd_tanh_loop
mth_wd_tanh_done:

  ; mlp = W2 hidden
  MOVI r12,@mth_wd_w2
  LD r1,r12,0
  MOVI r2,0x6000
  MOVHI r2,0x0005
  MOVI r3,0x7000
  MOVHI r3,0x0005
  MOVI r12,@mth_wd_D
  LD r4,r12,0
  MOVI r12,@mth_wd_H
  LD r5,r12,0
  CALL @mth_wmv

  ; output = h + mlp
  MOVI r6,0
mth_wd_out_loop:
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  CMP r6,r7
  JMP[GE] @mth_wd_out_done
  MOVI r10,0x5000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r7,r10,0
  MOVI r10,0x7000
  MOVHI r10,0x0005
  ADD r10,r10,r6
  LD r8,r10,0
  FADD r7,r7,r8
  MOVI r10,0x0000
  MOVHI r10,0x0020
  ADD r10,r10,r6
  ST r7,r10,0
  ADDI r6,r6,1
  JMP @mth_wd_out_loop
mth_wd_out_done:

  MOVI r12,@mth_wd_D
  LD r1,r12,0
  MOVI r13,1
  MOVI r12,@mth_wd_link
  LD r15,r12,0
  RET

; Matrix-vector with runtime rows/cols.
mth_wmv:
  MOVI r12,@mth_wmv_link
  ST r15,r12,0
  MOVI r11,0
mth_wmv_row:
  CMP r11,r4
  JMP[GE] @mth_wmv_done
  MOVI r14,0
  MOVI r10,0
mth_wmv_col:
  CMP r10,r5
  JMP[GE] @mth_wmv_row_done
  MUL r6,r11,r5
  ADD r6,r6,r10
  ADD r6,r1,r6
  LD r7,r6,0
  ADD r6,r2,r10
  LD r8,r6,0
  FMUL r7,r7,r8
  FADD r14,r14,r7
  ADDI r10,r10,1
  JMP @mth_wmv_col
mth_wmv_row_done:
  ADD r6,r3,r11
  ST r14,r6,0
  ADDI r11,r11,1
  JMP @mth_wmv_row
mth_wmv_done:
  MOVI r13,1
  MOVI r12,@mth_wmv_link
  LD r15,r12,0
  RET

mth_wd_link:
  .word 0
mth_wd_T:
  .word 0
mth_wd_D:
  .word 0
mth_wd_H:
  .word 0
mth_wd_s:
  .word 0
mth_wd_sum:
  .word 0
mth_wd_wq:
  .word 0
mth_wd_wk:
  .word 0
mth_wd_wv:
  .word 0
mth_wd_wout:
  .word 0
mth_wd_w1:
  .word 0
mth_wd_w2:
  .word 0
mth_wmv_link:
  .word 0
