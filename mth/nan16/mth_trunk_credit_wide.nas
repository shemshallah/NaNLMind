; Raw NaN16 local output/MLP credit for the wide trunk.
;
; ABI:
;   r1 = target readout row, r2 = best wrong row, r3 = learning-rate bits.
; Uses the last mth_trunk_wide forward:
;   context 0x53000[D], h 0x55000[D], hidden 0x56000[H]
;   Wout/W1/W2 pointers from mth_wd_*; readout rows at 0x180000 + row*D.
;
; e      = R[target] - R[best]
; g[j]   = (1-hidden[j]^2) sum_d e[d] W2[d][j]
; h_err  = e + W1^T g
; Wout  += lr h_err context^T
; W2    += lr e hidden^T
; W1    += lr g h^T
mth_trunk_credit_wide:
  MOVI r12,@mth_tcw_link
  ST r15,r12,0
  MOVI r12,@mth_tcw_target
  ST r1,r12,0
  MOVI r12,@mth_tcw_best
  ST r2,r12,0
  MOVI r12,@mth_tcw_lr
  ST r3,r12,0

  ; e[d]
  MOVI r5,0x0000
  MOVHI r5,0x0018          ; 0x180000 readout base
  MOVI r12,@mth_tcw_target
  LD r6,r12,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r6,r6,r7
  ADD r6,r5,r6
  MOVI r12,@mth_tcw_best
  LD r8,r12,0
  MUL r8,r8,r7
  ADD r8,r5,r8
  MOVI r9,0x9000
  MOVHI r9,0x0005
  MOVI r10,0
mth_tcw_e:
  CMP r10,r7
  JMP[GE] @mth_tcw_e_done
  ADD r11,r6,r10
  LD r11,r11,0
  ADD r12,r8,r10
  LD r12,r12,0
  FSUB r11,r11,r12
  ADD r12,r9,r10
  ST r11,r12,0
  ADDI r10,r10,1
  JMP @mth_tcw_e
mth_tcw_e_done:

  ; g[j]
  MOVI r12,@mth_wd_w2
  LD r6,r12,0
  MOVI r12,@mth_wd_H
  LD r7,r12,0
  MOVI r8,0
mth_tcw_g_j:
  CMP r8,r7
  JMP[GE] @mth_tcw_g_done
  MOVI r14,0
  MOVI r9,0
  MOVI r12,@mth_wd_D
  LD r10,r12,0
mth_tcw_g_d:
  CMP r9,r10
  JMP[GE] @mth_tcw_g_store
  MUL r11,r9,r7
  ADD r11,r11,r8
  ADD r11,r6,r11
  LD r11,r11,0
  MOVI r12,0x9000
  MOVHI r12,0x0005
  ADD r12,r12,r9
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r9,r9,1
  JMP @mth_tcw_g_d
mth_tcw_g_store:
  MOVI r12,0x6000
  MOVHI r12,0x0005
  ADD r12,r12,r8
  LD r12,r12,0
  FMUL r11,r12,r12
  MOVI r12,0
  MOVHI r12,0x3F80
  FSUB r11,r12,r11
  FMUL r14,r14,r11
  MOVI r12,0x9200
  MOVHI r12,0x0005
  ADD r12,r12,r8
  ST r14,r12,0
  ADDI r8,r8,1
  JMP @mth_tcw_g_j
mth_tcw_g_done:

  ; h_err[d] = e[d] + sum_j W1[j][d] g[j]
  MOVI r12,@mth_wd_w1
  LD r6,r12,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r8,0
mth_tcw_herr_d:
  CMP r8,r7
  JMP[GE] @mth_tcw_herr_done
  MOVI r14,0
  MOVI r9,0
  MOVI r12,@mth_wd_H
  LD r10,r12,0
mth_tcw_herr_j:
  CMP r9,r10
  JMP[GE] @mth_tcw_herr_store
  MOVI r12,@mth_wd_D
  LD r11,r12,0
  MUL r11,r9,r11
  ADD r11,r11,r8
  ADD r11,r6,r11
  LD r11,r11,0
  MOVI r12,0x9200
  MOVHI r12,0x0005
  ADD r12,r12,r9
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r9,r9,1
  JMP @mth_tcw_herr_j
mth_tcw_herr_store:
  MOVI r12,0x9000
  MOVHI r12,0x0005
  ADD r12,r12,r8
  LD r12,r12,0
  FADD r14,r14,r12
  MOVI r12,0x9400
  MOVHI r12,0x0005
  ADD r12,r12,r8
  ST r14,r12,0
  ADDI r8,r8,1
  JMP @mth_tcw_herr_d
mth_tcw_herr_done:

  ; Wout[d][i] += lr*h_err[d]*context[i]
  MOVI r12,@mth_wd_wout
  LD r6,r12,0
  MOVI r7,0x3000
  MOVHI r7,0x0005
  MOVI r12,@mth_wd_D
  LD r8,r12,0
  MOVI r9,0
mth_tcw_wout_d:
  CMP r9,r8
  JMP[GE] @mth_tcw_wout_done
  MOVI r12,0x9400
  MOVHI r12,0x0005
  ADD r12,r12,r9
  LD r10,r12,0
  MOVI r11,0
mth_tcw_wout_i:
  CMP r11,r8
  JMP[GE] @mth_tcw_wout_next
  MUL r12,r9,r8
  ADD r12,r12,r11
  ADD r12,r6,r12
  LD r13,r12,0
  ADD r14,r7,r11
  LD r14,r14,0
  MOVI r15,@mth_tcw_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r10
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r11,r11,1
  JMP @mth_tcw_wout_i
mth_tcw_wout_next:
  ADDI r9,r9,1
  JMP @mth_tcw_wout_d
mth_tcw_wout_done:

  ; W2[d][j] += lr*e[d]*hidden[j]
  MOVI r12,@mth_wd_w2
  LD r6,r12,0
  MOVI r12,@mth_wd_D
  LD r8,r12,0
  MOVI r12,@mth_wd_H
  LD r9,r12,0
  MOVI r7,0
mth_tcw_w2_d:
  CMP r7,r8
  JMP[GE] @mth_tcw_w2_done
  MOVI r12,0x9000
  MOVHI r12,0x0005
  ADD r12,r12,r7
  LD r10,r12,0
  MOVI r11,0
mth_tcw_w2_j:
  CMP r11,r9
  JMP[GE] @mth_tcw_w2_next
  MUL r12,r7,r9
  ADD r12,r12,r11
  ADD r12,r6,r12
  LD r13,r12,0
  MOVI r14,0x6000
  MOVHI r14,0x0005
  ADD r14,r14,r11
  LD r14,r14,0
  MOVI r15,@mth_tcw_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r10
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r11,r11,1
  JMP @mth_tcw_w2_j
mth_tcw_w2_next:
  ADDI r7,r7,1
  JMP @mth_tcw_w2_d
mth_tcw_w2_done:

  ; W1[j][i] += lr*g[j]*h[i]
  MOVI r12,@mth_wd_w1
  LD r6,r12,0
  MOVI r12,@mth_wd_H
  LD r8,r12,0
  MOVI r12,@mth_wd_D
  LD r9,r12,0
  MOVI r7,0
mth_tcw_w1_j:
  CMP r7,r8
  JMP[GE] @mth_tcw_done
  MOVI r12,0x9200
  MOVHI r12,0x0005
  ADD r12,r12,r7
  LD r10,r12,0
  MOVI r11,0
mth_tcw_w1_i:
  CMP r11,r9
  JMP[GE] @mth_tcw_w1_next
  MUL r12,r7,r9
  ADD r12,r12,r11
  ADD r12,r6,r12
  LD r13,r12,0
  MOVI r14,0x5000
  MOVHI r14,0x0005
  ADD r14,r14,r11
  LD r14,r14,0
  MOVI r15,@mth_tcw_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r10
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r11,r11,1
  JMP @mth_tcw_w1_i
mth_tcw_w1_next:
  ADDI r7,r7,1
  JMP @mth_tcw_w1_j
mth_tcw_done:
  MOVI r1,1
  MOVI r13,1
  MOVI r12,@mth_tcw_link
  LD r15,r12,0
  RET
mth_tcw_link:
  .word 0
mth_tcw_target:
  .word 0
mth_tcw_best:
  .word 0
mth_tcw_lr:
  .word 0
