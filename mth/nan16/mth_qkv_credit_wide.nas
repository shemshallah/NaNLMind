; Raw NaN16 QKV local-credit update for the runtime-width wide trunk.
;
; ABI:
;   r1 = target readout row
;   r2 = best wrong readout row
;   r3 = learning-rate float32 bits
;
; Prerequisite: one mth_trunk_wide forward.  It provides D/H/T and the
; alpha[s] state at 0x58000, v_s at 0x30000+s*D, q at 0x51000, h at 0x55000,
; hidden at 0x56000, and all weight pointers.
; Readout rows are at 0x180000 + row*D.
;
; This is local credit through the causal softmax, not a global tape.  It
; updates Wq/Wk/Wv for the wide path and leaves Wout/W1/W2 to the fixed
; output/MLP credit step until the wide MLP credit primitive lands.
mth_qkv_credit_wide:
  MOVI r12,@mth_qkw_link
  ST r15,r12,0
  MOVI r12,@mth_qkw_target
  ST r1,r12,0
  MOVI r12,@mth_qkw_best
  ST r2,r12,0
  MOVI r12,@mth_qkw_lr
  ST r3,r12,0

  ; e[d] = readout[target][d] - readout[best][d]
  MOVI r5,0x0000
  MOVHI r5,0x0018          ; 0x180000
  MOVI r12,@mth_qkw_target
  LD r6,r12,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r6,r6,r7
  ADD r6,r5,r6
  MOVI r12,@mth_qkw_best
  LD r8,r12,0
  MUL r8,r8,r7
  ADD r8,r5,r8
  MOVI r9,0x9000
  MOVHI r9,0x0005
  MOVI r10,0
mth_qkw_e:
  CMP r10,r7
  JMP[GE] @mth_qkw_e_done
  ADD r11,r6,r10
  LD r11,r11,0
  ADD r12,r8,r10
  LD r12,r12,0
  FSUB r11,r11,r12
  ADD r12,r9,r10
  ST r11,r12,0
  ADDI r10,r10,1
  JMP @mth_qkw_e
mth_qkw_e_done:

  ; g[j] = sum_d e[d] W2[d][j] (1-hidden[j]^2)
  MOVI r12,@mth_wd_w2
  LD r6,r12,0
  MOVI r12,@mth_wd_H
  LD r7,r12,0
  MOVI r8,0
mth_qkw_g_j:
  CMP r8,r7
  JMP[GE] @mth_qkw_g_done
  MOVI r14,0
  MOVI r9,0
  MOVI r12,@mth_wd_D
  LD r10,r12,0
mth_qkw_g_d:
  CMP r9,r10
  JMP[GE] @mth_qkw_g_store
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
  JMP @mth_qkw_g_d
mth_qkw_g_store:
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
  JMP @mth_qkw_g_j
mth_qkw_g_done:

  ; h_err[d] = e[d] + sum_j W2[d][j] g[j]
  MOVI r12,@mth_wd_w2
  LD r6,r12,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r8,0
mth_qkw_herr_d:
  CMP r8,r7
  JMP[GE] @mth_qkw_herr_done
  MOVI r14,0
  MOVI r9,0
  MOVI r12,@mth_wd_H
  LD r10,r12,0
mth_qkw_herr_j:
  CMP r9,r10
  JMP[GE] @mth_qkw_herr_store
  MOVI r12,@mth_wd_H
  LD r11,r12,0
  MUL r11,r8,r11
  ADD r11,r11,r9
  ADD r11,r6,r11
  LD r11,r11,0
  MOVI r12,0x9200
  MOVHI r12,0x0005
  ADD r12,r12,r9
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r9,r9,1
  JMP @mth_qkw_herr_j
mth_qkw_herr_store:
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
  JMP @mth_qkw_herr_d
mth_qkw_herr_done:

  ; dc[k] = sum_i h_err[i] Wout[i][k]
  MOVI r12,@mth_wd_wout
  LD r6,r12,0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r8,0
mth_qkw_dc_k:
  CMP r8,r7
  JMP[GE] @mth_qkw_dc_done
  MOVI r14,0
  MOVI r9,0
mth_qkw_dc_i:
  CMP r9,r7
  JMP[GE] @mth_qkw_dc_store
  MUL r11,r9,r7
  ADD r11,r11,r8
  ADD r11,r6,r11
  LD r11,r11,0
  MOVI r12,0x9400
  MOVHI r12,0x0005
  ADD r12,r12,r9
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r9,r9,1
  JMP @mth_qkw_dc_i
mth_qkw_dc_store:
  MOVI r12,0x9600
  MOVHI r12,0x0005
  ADD r12,r12,r8
  ST r14,r12,0
  ADDI r8,r8,1
  JMP @mth_qkw_dc_k
mth_qkw_dc_done:

  ; dalpha[s] = dot(dc, v_s); sum alpha*dalpha
  MOVI r12,@mth_wd_s
  ST r0,r12,0
  MOVI r12,@mth_qkw_sum
  ST r0,r12,0
mth_qkw_dalpha_s:
  MOVI r12,@mth_wd_T
  LD r4,r12,0
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  CMP r6,r4
  JMP[GE] @mth_qkw_dalpha_done
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r8,r6,r7
  MOVI r9,0x0000
  MOVHI r9,0x0003
  ADD r9,r9,r8
  MOVI r10,0
  MOVI r14,0
mth_qkw_dalpha_d:
  CMP r10,r7
  JMP[GE] @mth_qkw_dalpha_store
  ADD r11,r9,r10
  LD r11,r11,0
  MOVI r12,0x9600
  MOVHI r12,0x0005
  ADD r12,r12,r10
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r10,r10,1
  JMP @mth_qkw_dalpha_d
mth_qkw_dalpha_store:
  MOVI r12,0x9800
  MOVHI r12,0x0005
  ADD r12,r12,r6
  ST r14,r12,0
  MOVI r12,0x8000
  MOVHI r12,0x0005
  ADD r12,r12,r6
  LD r11,r12,0
  FMUL r11,r11,r14
  MOVI r12,@mth_qkw_sum
  LD r10,r12,0
  FADD r10,r10,r11
  ST r10,r12,0
  ADDI r6,r6,1
  MOVI r12,@mth_wd_s
  ST r6,r12,0
  JMP @mth_qkw_dalpha_s
mth_qkw_dalpha_done:

  ; dq[d]=0
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r8,0
  MOVI r9,0xA400
  MOVHI r9,0x0005
mth_qkw_dq_zero:
  CMP r8,r7
  JMP[GE] @mth_qkw_dq_zero_done
  ADD r10,r9,r8
  ST r0,r10,0
  ADDI r8,r8,1
  JMP @mth_qkw_dq_zero
mth_qkw_dq_zero_done:

  ; per-s K recompute, dz, Wk/Wv updates, dq
  MOVI r12,@mth_wd_s
  ST r0,r12,0
mth_qkw_s_loop:
  MOVI r12,@mth_wd_T
  LD r4,r12,0
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  CMP r6,r4
  JMP[GE] @mth_qkw_s_done

  ; x_s pointer
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r8,r6,r7
  MOVI r9,0x0000
  MOVHI r9,0x0001
  ADD r9,r9,r8
  MOVI r12,@mth_qkw_xs
  ST r9,r12,0

  ; k_s = Wk x_s into 0x52000
  MOVI r12,@mth_wd_wk
  LD r1,r12,0
  ADD r2,r9,r0
  MOVI r3,0x2000
  MOVHI r3,0x0005
  MOVI r12,@mth_wd_D
  LD r4,r12,0
  ADD r5,r4,r0
  CALL @mth_wmv

  ; dz = alpha[s]*(dalpha[s]-sum)
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  MOVI r12,0x8000
  MOVHI r12,0x0005
  ADD r12,r12,r6
  LD r7,r12,0
  MOVI r12,0x9800
  MOVHI r12,0x0005
  ADD r12,r12,r6
  LD r8,r12,0
  MOVI r12,@mth_qkw_sum
  LD r9,r12,0
  FSUB r8,r8,r9
  FMUL r7,r7,r8
  MOVI r12,@mth_qkw_dz
  ST r7,r12,0

  ; dq += dz*k_s
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r8,0
mth_qkw_dq_add:
  CMP r8,r7
  JMP[GE] @mth_qkw_dq_add_done
  MOVI r9,0x2000
  MOVHI r9,0x0005
  ADD r9,r9,r8
  LD r10,r9,0
  MOVI r12,@mth_qkw_dz
  LD r11,r12,0
  FMUL r10,r10,r11
  MOVI r12,0xA400
  MOVHI r12,0x0005
  ADD r12,r12,r8
  LD r11,r12,0
  FADD r11,r11,r10
  ST r11,r12,0
  ADDI r8,r8,1
  JMP @mth_qkw_dq_add
mth_qkw_dq_add_done:

  ; dk = dz*q; Wk[d][i] += lr*dk[d]*x_s[i]
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r8,0
mth_qkw_wk_d:
  CMP r8,r7
  JMP[GE] @mth_qkw_wk_done
  MOVI r12,@mth_qkw_dz
  LD r15,r12,0
  MOVI r9,0x1000
  MOVHI r9,0x0005
  ADD r9,r9,r8
  LD r9,r9,0
  FMUL r9,r9,r15
  MOVI r12,@mth_qkw_xs
  LD r10,r12,0
  MOVI r11,0
mth_qkw_wk_i:
  CMP r11,r7
  JMP[GE] @mth_qkw_wk_next_d
  ADD r12,r10,r11
  LD r12,r12,0
  MOVI r13,@mth_qkw_lr
  LD r13,r13,0
  FMUL r12,r12,r13
  FMUL r12,r12,r9
  MUL r13,r8,r7
  ADD r13,r13,r11
  MOVI r14,@mth_wd_wk
  LD r14,r14,0
  ADD r14,r14,r13
  LD r15,r14,0
  FADD r15,r15,r12
  ST r15,r14,0
  ADDI r11,r11,1
  JMP @mth_qkw_wk_i
mth_qkw_wk_next_d:
  ADDI r8,r8,1
  JMP @mth_qkw_wk_d
mth_qkw_wk_done:

  ; dv = alpha*dc; Wv[d][i] += lr*dv[d]*x_s[i]
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MOVI r8,0
mth_qkw_wv_d:
  CMP r8,r7
  JMP[GE] @mth_qkw_wv_done
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  MOVI r12,0x8000
  MOVHI r12,0x0005
  ADD r12,r12,r6
  LD r15,r12,0
  MOVI r9,0x9600
  MOVHI r9,0x0005
  ADD r9,r9,r8
  LD r9,r9,0
  FMUL r9,r9,r15
  MOVI r12,@mth_qkw_xs
  LD r10,r12,0
  MOVI r11,0
mth_qkw_wv_i:
  CMP r11,r7
  JMP[GE] @mth_qkw_wv_next_d
  ADD r12,r10,r11
  LD r12,r12,0
  MOVI r13,@mth_qkw_lr
  LD r13,r13,0
  FMUL r12,r12,r13
  FMUL r12,r12,r9
  MUL r13,r8,r7
  ADD r13,r13,r11
  MOVI r14,@mth_wd_wv
  LD r14,r14,0
  ADD r14,r14,r13
  LD r15,r14,0
  FADD r15,r15,r12
  ST r15,r14,0
  ADDI r11,r11,1
  JMP @mth_qkw_wv_i
mth_qkw_wv_next_d:
  ADDI r8,r8,1
  JMP @mth_qkw_wv_d
mth_qkw_wv_done:
  MOVI r12,@mth_wd_s
  LD r6,r12,0
  ADDI r6,r6,1
  ST r6,r12,0
  JMP @mth_qkw_s_loop
mth_qkw_s_done:

  ; Wq[d][i] += lr*dq[d]*x_last[i]
  MOVI r12,@mth_wd_T
  LD r6,r12,0
  SUB r6,r6,r13
  MOVI r12,@mth_wd_D
  LD r7,r12,0
  MUL r8,r6,r7
  MOVI r9,0x0000
  MOVHI r9,0x0001
  ADD r9,r9,r8
  MOVI r12,@mth_qkw_xlast
  ST r9,r12,0
  MOVI r8,0
mth_qkw_wq_d:
  CMP r8,r7
  JMP[GE] @mth_qkw_done
  MOVI r9,0xA400
  MOVHI r9,0x0005
  ADD r9,r9,r8
  LD r9,r9,0
  MOVI r12,@mth_qkw_xlast
  LD r10,r12,0
  MOVI r11,0
mth_qkw_wq_i:
  CMP r11,r7
  JMP[GE] @mth_qkw_wq_next_d
  ADD r12,r10,r11
  LD r12,r12,0
  MOVI r13,@mth_qkw_lr
  LD r13,r13,0
  FMUL r12,r12,r13
  FMUL r12,r12,r9
  MUL r13,r8,r7
  ADD r13,r13,r11
  MOVI r14,@mth_wd_wq
  LD r14,r14,0
  ADD r14,r14,r13
  LD r15,r14,0
  FADD r15,r15,r12
  ST r15,r14,0
  ADDI r11,r11,1
  JMP @mth_qkw_wq_i
mth_qkw_wq_next_d:
  ADDI r8,r8,1
  JMP @mth_qkw_wq_d
mth_qkw_done:
  MOVI r1,1
  MOVI r13,1
  MOVI r12,@mth_qkw_link
  LD r15,r12,0
  RET
mth_qkw_link:
  .word 0
mth_qkw_target:
  .word 0
mth_qkw_best:
  .word 0
mth_qkw_lr:
  .word 0
mth_qkw_sum:
  .word 0
mth_qkw_dz:
  .word 0
mth_qkw_xs:
  .word 0
mth_qkw_xlast:
  .word 0
