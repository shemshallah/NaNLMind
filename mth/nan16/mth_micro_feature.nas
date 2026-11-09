; Raw NaN16 two-token QKV/softmax/tanh feature feed.
;
; ABI:
;   r1 = pointer to x0[8] (float32 payloads)
;   r2 = pointer to x1[8]
;   r3 = pointer to output[8]
; Returns r1 = 8.
;
; This is the shared-trunk feature-feed primitive: identity Q/K/V, two-token
; causal softmax, context mix and tanh.  It is deliberately small and has no
; host arithmetic.  Learned QKV/MLP matrices replace the identity path in the
; next P1 step; the output contract remains the same.
mth_micro_feature:
  MOVI r12,@mth_mf_link
  ST r15,r12,0
  MOVI r4,8
  MOVI r5,0
mth_mf_loop:
  CMP r5,r4
  JMP[GE] @mth_mf_done
  ADD r6,r1,r5
  LD r7,r6,0
  ADD r6,r2,r5
  LD r8,r6,0

  ; q0=k0=x0, q1=k1=x1, identity projections.
  FMUL r9,r7,r7
  FMUL r10,r8,r8
  FEXP r9,r9
  FEXP r10,r10
  FADD r11,r9,r10
  FDIV r9,r9,r11
  FDIV r10,r10,r11
  ; context = w0*x0 + w1*x1
  FMUL r7,r9,r7
  FMUL r8,r10,r8
  FADD r7,r7,r8
  FTANH r7,r7
  ADD r6,r3,r5
  ST r7,r6,0
  ADDI r5,r5,1
  JMP @mth_mf_loop
mth_mf_done:
  MOVI r1,8
  MOVI r13,1
  MOVI r12,@mth_mf_link
  LD r15,r12,0
  RET
mth_mf_link:
  .word 0
