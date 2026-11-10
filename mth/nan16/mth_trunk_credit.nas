; Raw NaN16 local credit update for the fixed 8-wide trunk output/MLP.
;
; ABI:
;   r1 = target readout row (0..254)
;   r2 = best wrong readout row (0..254)
;   r3 = learning-rate float32 bits
;
; Activations from mth_trunk_causal:
;   context 0x8400[8], h 0x8600[8], hidden 0x8700[16]
; Weights:
;   Wout 0x90C0, W1 0x9100 (16x8), W2 0x9180 (8x16)
; Readout rows: 0xB000 + row*8.
;
; This is a local error-corrective gradient for Wout, W1 and W2.  It does not
; update Q/K/V or claim full transformer BPTT; the host reference performs the
; exact backprop check.  Return r1=1.
mth_trunk_credit:
  MOVI r12,@mth_tcrd_link
  ST r15,r12,0
  MOVI r12,@mth_tcrd_target
  ST r1,r12,0
  MOVI r12,@mth_tcrd_best
  ST r2,r12,0
  MOVI r12,@mth_tcrd_lr
  ST r3,r12,0

  ; e[d] = W[target][d] - W[best][d]
  MOVI r12,@mth_tcrd_target
  LD r6,r12,0
  MOVI r7,8
  MUL r6,r6,r7
  MOVI r8,0xB000
  ADD r6,r8,r6
  MOVI r12,@mth_tcrd_best
  LD r9,r12,0
  MUL r9,r9,r7
  ADD r9,r8,r9
  MOVI r10,0x8A00
  MOVI r11,0
mth_tcrd_e:
  CMP r11,r7
  JMP[GE] @mth_tcrd_e_done
  ADD r12,r6,r11
  LD r12,r12,0
  ADD r13,r9,r11
  LD r13,r13,0
  FSUB r12,r12,r13
  ADD r13,r10,r11
  ST r12,r13,0
  ADDI r11,r11,1
  JMP @mth_tcrd_e
mth_tcrd_e_done:

  ; Wout[d][i] += lr * e[d] * context[i]
  MOVI r6,0x90C0
  MOVI r7,0x8400
  MOVI r8,0
mth_tcrd_wout_d:
  MOVI r9,8
  CMP r8,r9
  JMP[GE] @mth_tcrd_wout_done
  MOVI r10,0x8A00
  ADD r10,r10,r8
  LD r10,r10,0
  MOVI r11,0
mth_tcrd_wout_i:
  CMP r11,r9
  JMP[GE] @mth_tcrd_wout_next
  MOVI r12,8
  MUL r12,r8,r12
  ADD r12,r12,r11
  ADD r12,r6,r12
  LD r13,r12,0
  ADD r14,r7,r11
  LD r14,r14,0
  MOVI r15,@mth_tcrd_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r10
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r11,r11,1
  JMP @mth_tcrd_wout_i
mth_tcrd_wout_next:
  ADDI r8,r8,1
  JMP @mth_tcrd_wout_d
mth_tcrd_wout_done:

  ; g[j] = sum_d e[d] W2[d][j] * (1 - hidden[j]^2)
  MOVI r6,0x9180
  MOVI r7,0
mth_tcrd_g_j:
  MOVI r9,16
  CMP r7,r9
  JMP[GE] @mth_tcrd_g_done
  MOVI r14,0
  MOVI r8,0
mth_tcrd_g_d:
  MOVI r10,8
  CMP r8,r10
  JMP[GE] @mth_tcrd_g_store
  MOVI r10,8
  MUL r10,r8,r10
  ADD r10,r10,r7
  ADD r10,r6,r10
  LD r10,r10,0
  MOVI r11,0x8A00
  ADD r11,r11,r8
  LD r11,r11,0
  FMUL r10,r10,r11
  FADD r14,r14,r10
  ADDI r8,r8,1
  JMP @mth_tcrd_g_d
mth_tcrd_g_store:
  MOVI r10,0x8700
  ADD r10,r10,r7
  LD r10,r10,0
  FMUL r11,r10,r10
  MOVI r12,0
  MOVHI r12,0x3F80
  FSUB r11,r12,r11
  FMUL r14,r14,r11
  MOVI r10,0x8A80
  ADD r10,r10,r7
  ST r14,r10,0
  ADDI r7,r7,1
  JMP @mth_tcrd_g_j
mth_tcrd_g_done:

  ; W2[d][j] += lr * e[d] * hidden[j]
  MOVI r6,0x9180
  MOVI r8,0
mth_tcrd_w2_d:
  MOVI r9,8
  CMP r8,r9
  JMP[GE] @mth_tcrd_w2_done
  MOVI r10,0x8A00
  ADD r10,r10,r8
  LD r10,r10,0
  MOVI r11,0
mth_tcrd_w2_j:
  MOVI r9,16
  CMP r11,r9
  JMP[GE] @mth_tcrd_w2_next
  MOVI r12,16
  MUL r12,r8,r12
  ADD r12,r12,r11
  ADD r12,r6,r12
  LD r13,r12,0
  MOVI r14,0x8700
  ADD r14,r14,r11
  LD r14,r14,0
  MOVI r15,@mth_tcrd_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r10
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r11,r11,1
  JMP @mth_tcrd_w2_j
mth_tcrd_w2_next:
  ADDI r8,r8,1
  JMP @mth_tcrd_w2_d
mth_tcrd_w2_done:

  ; W1[j][i] += lr * g[j] * h[i]
  MOVI r6,0x9100
  MOVI r7,0
mth_tcrd_w1_j:
  MOVI r9,16
  CMP r7,r9
  JMP[GE] @mth_tcrd_done
  MOVI r10,0x8A80
  ADD r10,r10,r7
  LD r10,r10,0
  MOVI r11,0
mth_tcrd_w1_i:
  MOVI r9,8
  CMP r11,r9
  JMP[GE] @mth_tcrd_w1_next
  MOVI r12,8
  MUL r12,r7,r12
  ADD r12,r12,r11
  ADD r12,r6,r12
  LD r13,r12,0
  MOVI r14,0x8600
  ADD r14,r14,r11
  LD r14,r14,0
  MOVI r15,@mth_tcrd_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r10
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r11,r11,1
  JMP @mth_tcrd_w1_i
mth_tcrd_w1_next:
  ADDI r7,r7,1
  JMP @mth_tcrd_w1_j
mth_tcrd_done:
  MOVI r1,1
  MOVI r13,1
  MOVI r12,@mth_tcrd_link
  LD r15,r12,0
  RET
mth_tcrd_link:
  .word 0
mth_tcrd_target:
  .word 0
mth_tcrd_best:
  .word 0
mth_tcrd_lr:
  .word 0
