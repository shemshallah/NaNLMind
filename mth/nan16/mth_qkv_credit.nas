; Raw NaN16 QKV local-credit update for the fixed 8-wide causal trunk.
;
; ABI:
;   r1 = target readout row, r2 = best wrong row, r3 = learning-rate bits.
; Prerequisite: one forward through mth_trunk_causal, which stores alpha[s]
; at 0x8B00 and v_s at 0x7B00+s*8.
;
; This computes the local output/MLP credit (via mth_trunk_credit) and then
; backpropagates through the causal softmax to Wq/Wk/Wv.  It is not a global
; tape; it uses the last forward's alpha/q/k/v state.
mth_qkv_credit:
  MOVI r12,@mth_qk_link
  ST r15,r12,0
  MOVI r12,@mth_qk_target
  ST r1,r12,0
  MOVI r12,@mth_qk_best
  ST r2,r12,0
  MOVI r12,@mth_qk_lr
  ST r3,r12,0

  ; e[d] = readout[target][d] - readout[best][d]
  MOVI r12,@mth_qk_target
  LD r6,r12,0
  MOVI r7,8
  MUL r6,r6,r7
  MOVI r8,0xB000
  ADD r6,r8,r6
  MOVI r12,@mth_qk_best
  LD r9,r12,0
  MUL r9,r9,r7
  ADD r9,r8,r9
  MOVI r10,0x8A00
  MOVI r11,0
mth_qk_e:
  CMP r11,r7
  JMP[GE] @mth_qk_e_done
  ADD r12,r6,r11
  LD r12,r12,0
  ADD r13,r9,r11
  LD r13,r13,0
  FSUB r12,r12,r13
  ADD r13,r10,r11
  ST r12,r13,0
  ADDI r11,r11,1
  JMP @mth_qk_e
mth_qk_e_done:

  ; g[j] = sum_d e[d] W2[d][j] * (1-hidden[j]^2)
  MOVI r6,0x9180
  MOVI r7,0
mth_qk_g_j:
  MOVI r9,16
  CMP r7,r9
  JMP[GE] @mth_qk_g_done
  MOVI r14,0
  MOVI r8,0
mth_qk_g_d:
  MOVI r10,8
  CMP r8,r10
  JMP[GE] @mth_qk_g_store
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
  JMP @mth_qk_g_d
mth_qk_g_store:
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
  JMP @mth_qk_g_j
mth_qk_g_done:

  ; h_err[d] = e[d] + sum_j W2[d][j] g[j]
  MOVI r6,0x9180
  MOVI r7,0
mth_qk_herr_d:
  MOVI r9,8
  CMP r7,r9
  JMP[GE] @mth_qk_herr_done
  MOVI r14,0
  MOVI r8,0
mth_qk_herr_j:
  MOVI r10,16
  CMP r8,r10
  JMP[GE] @mth_qk_herr_store
  MOVI r10,16
  MUL r10,r7,r10
  ADD r10,r10,r8
  ADD r10,r6,r10
  LD r10,r10,0
  MOVI r11,0x8A80
  ADD r11,r11,r8
  LD r11,r11,0
  FMUL r10,r10,r11
  FADD r14,r14,r10
  ADDI r8,r8,1
  JMP @mth_qk_herr_j
mth_qk_herr_store:
  MOVI r10,0x8A00
  ADD r10,r10,r7
  LD r10,r10,0
  FADD r14,r14,r10
  MOVI r10,0x8F00
  ADD r10,r10,r7
  ST r14,r10,0
  ADDI r7,r7,1
  JMP @mth_qk_herr_d
mth_qk_herr_done:

  ; dc[k] = sum_i h_err[i] Wout[i][k]
  MOVI r6,0x90C0
  MOVI r7,0
mth_qk_dc_k:
  MOVI r9,8
  CMP r7,r9
  JMP[GE] @mth_qk_dc_done
  MOVI r14,0
  MOVI r8,0
mth_qk_dc_i:
  CMP r8,r9
  JMP[GE] @mth_qk_dc_store
  MOVI r10,8
  MUL r10,r8,r10
  ADD r10,r10,r7
  ADD r10,r6,r10
  LD r10,r10,0
  MOVI r11,0x8F00
  ADD r11,r11,r8
  LD r11,r11,0
  FMUL r10,r10,r11
  FADD r14,r14,r10
  ADDI r8,r8,1
  JMP @mth_qk_dc_i
mth_qk_dc_store:
  MOVI r10,0x8E00
  ADD r10,r10,r7
  ST r14,r10,0
  ADDI r7,r7,1
  JMP @mth_qk_dc_k
mth_qk_dc_done:

  ; Output/MLP local credit (Wout, W2, W1).
  MOVI r12,@mth_qk_target
  LD r1,r12,0
  MOVI r12,@mth_qk_best
  LD r2,r12,0
  MOVI r12,@mth_qk_lr
  LD r3,r12,0
  CALL @mth_trunk_credit

  ; dalpha[s] = dot(dc, v_s)
  MOVI r10,@mth_qk_s
  ST r0,r10,0
  MOVI r10,0x8D00
  ST r0,r10,0
mth_qk_dalpha_s:
  MOVI r10,@mth_tc_T
  LD r4,r10,0
  MOVI r10,@mth_qk_s
  LD r6,r10,0
  CMP r6,r4
  JMP[GE] @mth_qk_dalpha_done
  MOVI r7,0
  MOVI r14,0
  MOVI r8,8
  MOVI r10,8
  MUL r10,r6,r10
  MOVI r11,0x7B00
  ADD r11,r11,r10
mth_qk_dalpha_d:
  CMP r7,r8
  JMP[GE] @mth_qk_dalpha_store
  ADD r9,r11,r7
  LD r9,r9,0
  MOVI r10,0x8E00
  ADD r10,r10,r7
  LD r10,r10,0
  FMUL r9,r9,r10
  FADD r14,r14,r9
  ADDI r7,r7,1
  JMP @mth_qk_dalpha_d
mth_qk_dalpha_store:
  MOVI r10,0x8C00
  ADD r10,r10,r6
  ST r14,r10,0
  ; sum += alpha[s]*dalpha[s]
  MOVI r10,0x8B00
  ADD r10,r10,r6
  LD r10,r10,0
  FMUL r10,r10,r14
  MOVI r11,0x8D00
  LD r12,r11,0
  FADD r12,r12,r10
  ST r12,r11,0
  ADDI r6,r6,1
  MOVI r10,@mth_qk_s
  ST r6,r10,0
  JMP @mth_qk_dalpha_s
mth_qk_dalpha_done:

  ; dq[d] = 0
  MOVI r10,0x8F80
  MOVI r7,0
  MOVI r8,8
mth_qk_dq_zero:
  CMP r7,r8
  JMP[GE] @mth_qk_dq_zero_done
  ADD r11,r10,r7
  ST r0,r11,0
  ADDI r7,r7,1
  JMP @mth_qk_dq_zero
mth_qk_dq_zero_done:

  ; For each s: recompute k_s, dz, Wk/Wv updates, dq accumulation.
  MOVI r10,@mth_qk_s
  ST r0,r10,0
mth_qk_s_loop:
  MOVI r10,@mth_tc_T
  LD r4,r10,0
  MOVI r10,@mth_qk_s
  LD r6,r10,0
  CMP r6,r4
  JMP[GE] @mth_qk_s_done

  ; x_s pointer
  MOVI r7,8
  MUL r7,r6,r7
  MOVI r2,0x7000
  ADD r2,r2,r7
  MOVI r12,@mth_qk_xs
  ST r2,r12,0

  ; k_s = Wk x_s
  MOVI r1,0x9040
  MOVI r3,0x7A00
  MOVI r4,8
  MOVI r5,8
  CALL @mth_mv

  ; dz = alpha[s] * (dalpha[s] - sum)
  MOVI r10,@mth_qk_s
  LD r6,r10,0
  MOVI r10,0x8B00
  ADD r10,r10,r6
  LD r7,r10,0
  MOVI r10,0x8C00
  ADD r10,r10,r6
  LD r8,r10,0
  MOVI r10,0x8D00
  LD r9,r10,0
  FSUB r8,r8,r9
  FMUL r7,r7,r8
  MOVI r12,@mth_qk_dz
  ST r7,r12,0

  ; dq[d] += dz * k_s[d]
  MOVI r7,0
  MOVI r8,8
mth_qk_dq_add:
  CMP r7,r8
  JMP[GE] @mth_qk_dq_add_done
  MOVI r10,0x7A00
  ADD r10,r10,r7
  LD r9,r10,0
  MOVI r12,@mth_qk_dz
  LD r11,r12,0
  FMUL r9,r9,r11
  MOVI r10,0x8F80
  ADD r10,r10,r7
  LD r12,r10,0
  FADD r12,r12,r9
  ST r12,r10,0
  ADDI r7,r7,1
  JMP @mth_qk_dq_add
mth_qk_dq_add_done:

  ; dk[d] = dz*q[d]; Wk[d][i] += lr*dk[d]*x_s[i]
  MOVI r7,0
  MOVI r8,8
  MOVI r10,@mth_qk_dz
  LD r12,r10,0
mth_qk_wk_d:
  CMP r7,r8
  JMP[GE] @mth_qk_wk_done
  MOVI r10,0x7900
  ADD r10,r10,r7
  LD r9,r10,0
  FMUL r9,r9,r12
  MOVI r10,@mth_qk_xs
  LD r10,r10,0
  MOVI r11,0
mth_qk_wk_i:
  CMP r11,r8
  JMP[GE] @mth_qk_wk_next_d
  ADD r14,r10,r11
  LD r14,r14,0
  MOVI r15,@mth_qk_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r9
  MOVI r15,8
  MUL r15,r7,r15
  ADD r15,r15,r11
  MOVI r13,0x9040
  ADD r13,r13,r15
  LD r15,r13,0
  FADD r15,r15,r14
  ST r15,r13,0
  ADDI r11,r11,1
  JMP @mth_qk_wk_i
mth_qk_wk_next_d:
  ADDI r7,r7,1
  JMP @mth_qk_wk_d
mth_qk_wk_done:

  ; dv[d] = alpha[s]*dc[d]; Wv[d][i] += lr*dv[d]*x_s[i]
  MOVI r7,0
  MOVI r8,8
  MOVI r10,@mth_qk_s
  LD r6,r10,0
  MOVI r10,0x8B00
  ADD r10,r10,r6
  LD r12,r10,0
mth_qk_wv_d:
  CMP r7,r8
  JMP[GE] @mth_qk_wv_done
  MOVI r10,0x8E00
  ADD r10,r10,r7
  LD r9,r10,0
  FMUL r9,r9,r12
  MOVI r10,@mth_qk_xs
  LD r10,r10,0
  MOVI r11,0
mth_qk_wv_i:
  CMP r11,r8
  JMP[GE] @mth_qk_wv_next_d
  ADD r14,r10,r11
  LD r14,r14,0
  MOVI r15,@mth_qk_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r9
  MOVI r15,8
  MUL r15,r7,r15
  ADD r15,r15,r11
  MOVI r13,0x9080
  ADD r13,r13,r15
  LD r15,r13,0
  FADD r15,r15,r14
  ST r15,r13,0
  ADDI r11,r11,1
  JMP @mth_qk_wv_i
mth_qk_wv_next_d:
  ADDI r7,r7,1
  JMP @mth_qk_wv_d
mth_qk_wv_done:
  MOVI r10,@mth_qk_s
  LD r6,r10,0
  ADDI r6,r6,1
  ST r6,r10,0
  JMP @mth_qk_s_loop
mth_qk_s_done:

  ; Wq[d][i] += lr*dq[d]*x_last[i]
  MOVI r10,@mth_tc_T
  LD r6,r10,0
  SUB r6,r6,r13
  MOVI r7,8
  MUL r6,r6,r7
  MOVI r10,0x7000
  ADD r10,r10,r6
  MOVI r12,@mth_qk_xlast
  ST r10,r12,0
  MOVI r7,0
  MOVI r8,8
mth_qk_wq_d:
  CMP r7,r8
  JMP[GE] @mth_qk_done
  MOVI r10,0x8F80
  ADD r10,r10,r7
  LD r9,r10,0
  MOVI r10,@mth_qk_xlast
  LD r10,r10,0
  MOVI r11,0
mth_qk_wq_i:
  CMP r11,r8
  JMP[GE] @mth_qk_wq_next_d
  ADD r14,r10,r11
  LD r14,r14,0
  MOVI r15,@mth_qk_lr
  LD r15,r15,0
  FMUL r14,r14,r15
  FMUL r14,r14,r9
  MOVI r15,8
  MUL r15,r7,r15
  ADD r15,r15,r11
  MOVI r13,0x9000
  ADD r13,r13,r15
  LD r15,r13,0
  FADD r15,r15,r14
  ST r15,r13,0
  ADDI r11,r11,1
  JMP @mth_qk_wq_i
mth_qk_wq_next_d:
  ADDI r7,r7,1
  JMP @mth_qk_wq_d
mth_qk_done:
  MOVI r1,1
  MOVI r13,1
  MOVI r12,@mth_qk_link
  LD r15,r12,0
  RET
mth_qk_link:
  .word 0
mth_qk_target:
  .word 0
mth_qk_best:
  .word 0
mth_qk_lr:
  .word 0
mth_qk_s:
  .word 0
mth_qk_dz:
  .word 0
mth_qk_xs:
  .word 0
mth_qk_xlast:
  .word 0
