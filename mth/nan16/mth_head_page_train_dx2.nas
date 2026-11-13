; Raw NaN16 layer-2 dX2 reverse pass for T=1 and T=2.
; Computes the exact gradient of 0.5*||Y_last-target||^2 with respect to the
; layer-2 input, using captured A1/A2, inverse-std, hidden, Q/K/V, attention
; probabilities and layer-2 weights. No page mutation. T>2 is rejected.
;
; mth_head_block6 uses full per-query softmax over all T keys (it has no
; causal mask), so the T=2 reverse below is the exact reverse of that form:
; dV[j]=sum_i p[i][j] dctx[i], dK[j]=sum_i ds[i][j] Q[i]/sqrt(D),
; dQ[i]=sum_j ds[i][j] K[j]/sqrt(D), ds[i][j]=p[i][j](dP[i][j]-mean_i).
;
; ABI: r1=context, r2=output, r3=slot, r4=T, r5=target, r6=dx2.
; Returns r1=1,r2=dx2 norm^2,r3=T,r4=0; rejection r1=0,r4=reason.
mth_head_page_train_dx2:
  MOVI r0,0
  ST r15,r0,@dx2_link
  ST r1,r0,@dx2_context
  ST r2,r0,@dx2_output
  ST r3,r0,@dx2_slot
  ST r4,r0,@dx2_t
  ST r5,r0,@dx2_target
  ST r6,r0,@dx2_out
  CMP r1,r0
  JMP[EQ] @dx2_bad
  CMP r2,r0
  JMP[EQ] @dx2_bad
  CMP r5,r0
  JMP[EQ] @dx2_bad
  CMP r6,r0
  JMP[EQ] @dx2_bad
  CMP r4,r0
  JMP[EQ] @dx2_bad
  MOVI r7,2
  CMP r4,r7
  JMP[GT] @dx2_t_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @dx2_bad
  MOVI r10,0
  ST r10,r0,@dx2_norm
  LD r1,r0,@dx2_context
  LD r2,r0,@dx2_output
  LD r3,r0,@dx2_slot
  LD r4,r0,@dx2_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @dx2_forward_bad
  LD r7,r0,@dx2_t
  MOVI r8,1
  CMP r7,r8
  JMP[EQ] @dx2_t1
  JMP @dx2_t2

dx2_t1:
  ; dY = output - target.
  MOVI r10,0
dx2_dy:
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @dx2_dy_done
  LD r12,r0,@dx2_output
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@dx2_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r12,r12,r13
  MOVI r13,0x5000
  MOVHI r13,0x00D0
  ADD r13,r13,r10
  ST r12,r13,0
  ADDI r10,r10,1
  JMP @dx2_dy
dx2_dy_done:

  ; Page base and layer-2 weight offsets.
  LD r10,r0,@dx2_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  ST r10,r0,@dx2_page

  ; dH = W2^T dY (128 -> 384)
  LD r1,r0,@dx2_page
  MOVI r11,0x6000
  MOVHI r11,0x0003
  ADD r1,r1,r11
  MOVI r2,0x5000
  MOVHI r2,0x00D0
  MOVI r3,0x5100
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,384
  CALL @hrv_mv_t
  ; dZ = dH * (1 - H^2)
  MOVI r10,0
dx2_dz:
  MOVI r12,384
  CMP r10,r12
  JMP[GE] @dx2_dz_done
  MOVI r12,0x5100
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,0x0300
  MOVHI r14,0x00D1
  ADD r14,r14,r10
  LD r14,r14,0
  FMUL r15,r14,r14
  MOVI r11,0
  MOVHI r11,0x3F80
  FSUB r11,r11,r15
  FMUL r13,r13,r11
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @dx2_dz
dx2_dz_done:
  ; dXN2 = W1^T dZ (384 -> 128)
  LD r1,r0,@dx2_page
  MOVI r11,0x0000
  MOVHI r11,0x0003
  ADD r1,r1,r11
  MOVI r2,0x5100
  MOVHI r2,0x00D0
  MOVI r3,0x5700
  MOVHI r3,0x00D0
  MOVI r4,384
  MOVI r5,128
  CALL @hrv_mv_t
  ; dX1 = dY + LN_bwd(A2, dXN2, inv2)
  MOVI r1,0x1100
  MOVHI r1,0x00D1
  MOVI r2,0x5700
  MOVHI r2,0x00D0
  MOVI r3,0x5800
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,0x7800
  MOVHI r5,0x00D2
  LD r5,r5,0
  CALL @hrv_ln_bwd
  MOVI r10,0
dx2_add_dy:
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @dx2_add_dy_done
  MOVI r12,0x5800
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,0x5000
  MOVHI r14,0x00D0
  ADD r14,r14,r10
  LD r14,r14,0
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @dx2_add_dy
dx2_add_dy_done:
  ; dC = Wo^T dX1
  LD r1,r0,@dx2_page
  MOVI r11,0xE000
  MOVHI r11,0x0002
  ADD r1,r1,r11
  MOVI r2,0x5800
  MOVHI r2,0x00D0
  MOVI r3,0x5900
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  ; dXN1 = Wv^T dC (attention with one token: dV=dC)
  LD r1,r0,@dx2_page
  MOVI r11,0xC000
  MOVHI r11,0x0002
  ADD r1,r1,r11
  MOVI r2,0x5900
  MOVHI r2,0x00D0
  MOVI r3,0x5A00
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  ; dx2 = LN_bwd(A1,dXN1,inv1) + dX1
  MOVI r1,0x5800
  MOVHI r1,0x00D2
  MOVI r2,0x5A00
  MOVHI r2,0x00D0
  MOVI r3,0x5B00
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,0x6800
  MOVHI r5,0x00D2
  LD r5,r5,0
  CALL @hrv_ln_bwd
  MOVI r10,0
dx2_finish:
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @dx2_ok
  MOVI r12,0x5B00
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,0x5800
  MOVHI r14,0x00D0
  ADD r14,r14,r10
  LD r14,r14,0
  FADD r13,r13,r14
  LD r14,r0,@dx2_out
  ADD r14,r14,r10
  ST r13,r14,0
  MOVI r14,0
  FMUL r13,r13,r13
  FADD r14,r14,r13
  MOVI r12,@dx2_norm
  LD r15,r12,0
  FADD r15,r15,r13
  ST r15,r12,0
  ADDI r10,r10,1
  JMP @dx2_finish
dx2_ok:
  MOVI r1,1
  MOVI r2,@dx2_norm
  LD r2,r2,0
  LD r3,r0,@dx2_t
  MOVI r4,0
  LD r15,r0,@dx2_link
  RET
dx2_t_bad:
  MOVI r4,2
  JMP @dx2_reject
dx2_forward_bad:
  MOVI r4,3
  JMP @dx2_reject
dx2_bad:
  MOVI r4,1
dx2_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@dx2_link
  RET

; ---------------------------------------------------------------------------
; T=2 exact reverse of the block6 layer-2 forward. mth_head_block6 uses an
; unmasked per-query softmax over all keys, so dK/dV include both key columns.
; dY is zero for the first token because the loss is last-token only.
; ---------------------------------------------------------------------------
dx2_t2:
  ; Page base = slot*0x40000 words + 0x00800000.
  LD r10,r0,@dx2_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  ST r10,r0,@dx2_page
  ; dY[0..T*128) = 0, then dY[last] = output[last] - target.
  LD r10,r0,@dx2_t
  MOVI r11,128
  MUL r10,r10,r11
  ST r10,r0,@dx2_t2_n
  MOVI r10,0
dx2_t2_dy_zero:
  LD r11,r0,@dx2_t2_n
  CMP r10,r11
  JMP[GE] @dx2_t2_dy_last
  LD r12,r0,@dx2_t2_dy
  ADD r12,r12,r10
  ST r0,r12,0
  ADDI r10,r10,1
  JMP @dx2_t2_dy_zero
dx2_t2_dy_last:
  LD r11,r0,@dx2_t2_n
  MOVI r12,128
  SUB r11,r11,r12
  ST r11,r0,@dx2_t2_last
  MOVI r10,0
dx2_t2_dy_diff:
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @dx2_t2_mlp_begin
  LD r12,r0,@dx2_output
  LD r13,r0,@dx2_t2_last
  ADD r12,r12,r13
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@dx2_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r12,r12,r13
  LD r13,r0,@dx2_t2_dy
  LD r14,r0,@dx2_t2_last
  ADD r13,r13,r14
  ADD r13,r13,r10
  ST r12,r13,0
  ADDI r10,r10,1
  JMP @dx2_t2_dy_diff

  ; Per-token MLP reverse and dctx = Wo^T dR1.
dx2_t2_mlp_begin:
  MOVI r10,0
  ST r10,r0,@dx2_t2_i
dx2_t2_mlp_loop:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t
  CMP r10,r11
  JMP[GE] @dx2_t2_attn_begin
  MOVI r12,128
  MUL r12,r10,r12
  ST r12,r0,@dx2_t2_off128
  MOVI r12,384
  MUL r12,r10,r12
  ST r12,r0,@dx2_t2_off384
  ; dH = W2^T dY[t]
  LD r1,r0,@dx2_page
  MOVI r11,0x6000
  MOVHI r11,0x0003
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_dy
  LD r11,r0,@dx2_t2_off128
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_dh
  LD r11,r0,@dx2_t2_off384
  ADD r3,r3,r11
  MOVI r4,128
  MOVI r5,384
  CALL @hrv_mv_t
  ; dZ = dH*(1-H^2), in place over dH.
  MOVI r10,0
dx2_t2_dz_loop:
  MOVI r11,384
  CMP r10,r11
  JMP[GE] @dx2_t2_dz_done
  LD r12,r0,@dx2_t2_dh
  LD r11,r0,@dx2_t2_off384
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r13,r12,0
  LD r14,r0,@dx2_t2_h
  ADD r14,r14,r11
  ADD r14,r14,r10
  LD r14,r14,0
  FMUL r15,r14,r14
  MOVI r11,0
  MOVHI r11,0x3F80
  FSUB r11,r11,r15
  FMUL r13,r13,r11
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @dx2_t2_dz_loop
dx2_t2_dz_done:
  ; dXN2 = W1^T dZ
  LD r1,r0,@dx2_page
  MOVI r11,0x0000
  MOVHI r11,0x0003
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_dh
  LD r11,r0,@dx2_t2_off384
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_dxn2
  LD r11,r0,@dx2_t2_off128
  ADD r3,r3,r11
  MOVI r4,384
  MOVI r5,128
  CALL @hrv_mv_t
  ; dR1[t] = LN_bwd(A2[t], dXN2[t], inv2[t])
  LD r1,r0,@dx2_t2_a2
  LD r11,r0,@dx2_t2_off128
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_dxn2
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_dr1
  ADD r3,r3,r11
  MOVI r4,128
  LD r5,r0,@dx2_t2_inv2
  LD r10,r0,@dx2_t2_i
  ADD r5,r5,r10
  LD r5,r5,0
  CALL @hrv_ln_bwd
  ; dR1[t] += dY[t]
  MOVI r10,0
dx2_t2_dr1_add:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @dx2_t2_dr1_done
  LD r12,r0,@dx2_t2_dr1
  LD r11,r0,@dx2_t2_off128
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r13,r12,0
  LD r14,r0,@dx2_t2_dy
  ADD r14,r14,r11
  ADD r14,r14,r10
  LD r14,r14,0
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @dx2_t2_dr1_add
dx2_t2_dr1_done:
  ; dctx[t] = Wo^T dR1[t]
  LD r1,r0,@dx2_page
  MOVI r11,0xE000
  MOVHI r11,0x0002
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_dr1
  LD r11,r0,@dx2_t2_off128
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_dctx
  ADD r3,r3,r11
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r10,r0,@dx2_t2_i
  ADDI r10,r10,1
  ST r10,r0,@dx2_t2_i
  JMP @dx2_t2_mlp_loop

  ; dP[i][j] = dctx[i] . V[j]
dx2_t2_attn_begin:
  LD r1,r0,@dx2_t2_dq
  LD r2,r0,@dx2_t2_n
  CALL @dx2_zero
  LD r1,r0,@dx2_t2_dk
  LD r2,r0,@dx2_t2_n
  CALL @dx2_zero
  LD r1,r0,@dx2_t2_dv
  LD r2,r0,@dx2_t2_n
  CALL @dx2_zero
  MOVI r10,0
  ST r10,r0,@dx2_t2_i
dx2_t2_dp_i:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t
  CMP r10,r11
  JMP[GE] @dx2_t2_ds_begin
  MOVI r10,0
  ST r10,r0,@dx2_t2_j
dx2_t2_dp_j:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r11,r12
  JMP[GE] @dx2_t2_dp_next_i
  LD r1,r0,@dx2_t2_dctx
  MOVI r12,128
  MUL r12,r10,r12
  ADD r1,r1,r12
  LD r2,r0,@dx2_t2_v
  MOVI r12,128
  MUL r12,r11,r12
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hrv_dot
  LD r13,r0,@hrv_dot_value
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t2_dp
  MOVI r14,8
  MUL r14,r10,r14
  ADD r12,r12,r14
  ADD r12,r12,r11
  ST r13,r12,0
  LD r11,r0,@dx2_t2_j
  ADDI r11,r11,1
  ST r11,r0,@dx2_t2_j
  JMP @dx2_t2_dp_j
dx2_t2_dp_next_i:
  LD r10,r0,@dx2_t2_i
  ADDI r10,r10,1
  ST r10,r0,@dx2_t2_i
  JMP @dx2_t2_dp_i

  ; ds[i][j] = p[i][j]*(dP[i][j]-mean_i), in place over dP.
dx2_t2_ds_begin:
  MOVI r10,0
  ST r10,r0,@dx2_t2_i
dx2_t2_ds_i:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t
  CMP r10,r11
  JMP[GE] @dx2_t2_dq_begin
  MOVI r12,0
  ST r12,r0,@dx2_t2_sum
  MOVI r12,0
  ST r12,r0,@dx2_t2_j
dx2_t2_mean_j:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r11,r12
  JMP[GE] @dx2_t2_mean_done
  LD r12,r0,@dx2_t2_p
  MOVI r14,8
  MUL r14,r10,r14
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r13,r12,0
  LD r12,r0,@dx2_t2_dp
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r14,r12,0
  FMUL r13,r13,r14
  MOVI r14,@dx2_t2_sum
  LD r15,r14,0
  FADD r15,r15,r13
  ST r15,r14,0
  LD r11,r0,@dx2_t2_j
  ADDI r11,r11,1
  ST r11,r0,@dx2_t2_j
  JMP @dx2_t2_mean_j
dx2_t2_mean_done:
  LD r12,r0,@dx2_t2_mean
  LD r10,r0,@dx2_t2_i
  ADD r12,r12,r10
  MOVI r13,@dx2_t2_sum
  LD r13,r13,0
  ST r13,r12,0
  MOVI r12,0
  ST r12,r0,@dx2_t2_j
dx2_t2_ds_j:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r11,r12
  JMP[GE] @dx2_t2_ds_next_i
  LD r12,r0,@dx2_t2_p
  MOVI r14,8
  MUL r14,r10,r14
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r13,r12,0
  LD r12,r0,@dx2_t2_dp
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r14,r12,0
  LD r15,r0,@dx2_t2_mean
  ADD r15,r15,r10
  LD r15,r15,0
  FSUB r14,r14,r15
  FMUL r13,r13,r14
  ST r13,r12,0
  LD r11,r0,@dx2_t2_j
  ADDI r11,r11,1
  ST r11,r0,@dx2_t2_j
  JMP @dx2_t2_ds_j
dx2_t2_ds_next_i:
  LD r10,r0,@dx2_t2_i
  ADDI r10,r10,1
  ST r10,r0,@dx2_t2_i
  JMP @dx2_t2_ds_i

  ; dQ[i] = sum_j ds[i][j]*K[j]/sqrt(128)
dx2_t2_dq_begin:
  MOVI r10,0
  ST r10,r0,@dx2_t2_i
dx2_t2_dq_i:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t
  CMP r10,r11
  JMP[GE] @dx2_t2_dk_begin
  MOVI r12,0
  ST r12,r0,@dx2_t2_j
dx2_t2_dq_j:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r11,r12
  JMP[GE] @dx2_t2_dq_next_i
  LD r12,r0,@dx2_t2_dp
  MOVI r14,8
  MUL r14,r10,r14
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r13,r12,0
  MOVI r12,@hw6_scale
  LD r12,r12,0
  FDIV r13,r13,r12
  ADD r3,r13,r0
  LD r1,r0,@dx2_t2_dq
  MOVI r14,128
  MUL r14,r10,r14
  ADD r1,r1,r14
  LD r2,r0,@dx2_t2_k
  MOVI r14,128
  MUL r14,r11,r14
  ADD r2,r2,r14
  MOVI r4,128
  CALL @dx2_axpy
  LD r11,r0,@dx2_t2_j
  ADDI r11,r11,1
  ST r11,r0,@dx2_t2_j
  JMP @dx2_t2_dq_j
dx2_t2_dq_next_i:
  LD r10,r0,@dx2_t2_i
  ADDI r10,r10,1
  ST r10,r0,@dx2_t2_i
  JMP @dx2_t2_dq_i

  ; dK[j] = sum_i ds[i][j]*Q[i]/sqrt(128)
dx2_t2_dk_begin:
  MOVI r10,0
  ST r10,r0,@dx2_t2_j
dx2_t2_dk_j:
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r11,r12
  JMP[GE] @dx2_t2_dv_begin
  MOVI r12,0
  ST r12,r0,@dx2_t2_i
dx2_t2_dk_i:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r10,r12
  JMP[GE] @dx2_t2_dk_next_j
  LD r12,r0,@dx2_t2_dp
  MOVI r14,8
  MUL r14,r10,r14
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r13,r12,0
  MOVI r12,@hw6_scale
  LD r12,r12,0
  FDIV r13,r13,r12
  ADD r3,r13,r0
  LD r1,r0,@dx2_t2_dk
  MOVI r14,128
  MUL r14,r11,r14
  ADD r1,r1,r14
  LD r2,r0,@dx2_t2_q
  MOVI r14,128
  MUL r14,r10,r14
  ADD r2,r2,r14
  MOVI r4,128
  CALL @dx2_axpy
  LD r10,r0,@dx2_t2_i
  ADDI r10,r10,1
  ST r10,r0,@dx2_t2_i
  JMP @dx2_t2_dk_i
dx2_t2_dk_next_j:
  LD r11,r0,@dx2_t2_j
  ADDI r11,r11,1
  ST r11,r0,@dx2_t2_j
  JMP @dx2_t2_dk_j

  ; dV[j] = sum_i p[i][j]*dctx[i]
dx2_t2_dv_begin:
  MOVI r10,0
  ST r10,r0,@dx2_t2_j
dx2_t2_dv_j:
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r11,r12
  JMP[GE] @dx2_t2_da1_begin
  MOVI r12,0
  ST r12,r0,@dx2_t2_i
dx2_t2_dv_i:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t2_j
  LD r12,r0,@dx2_t
  CMP r10,r12
  JMP[GE] @dx2_t2_dv_next_j
  LD r12,r0,@dx2_t2_p
  MOVI r14,8
  MUL r14,r10,r14
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r3,r12,0
  LD r1,r0,@dx2_t2_dv
  MOVI r14,128
  MUL r14,r11,r14
  ADD r1,r1,r14
  LD r2,r0,@dx2_t2_dctx
  MOVI r14,128
  MUL r14,r10,r14
  ADD r2,r2,r14
  MOVI r4,128
  CALL @dx2_axpy
  LD r10,r0,@dx2_t2_i
  ADDI r10,r10,1
  ST r10,r0,@dx2_t2_i
  JMP @dx2_t2_dv_i
dx2_t2_dv_next_j:
  LD r11,r0,@dx2_t2_j
  ADDI r11,r11,1
  ST r11,r0,@dx2_t2_j
  JMP @dx2_t2_dv_j

  ; dA1[t] = Wq^T dQ[t] + Wk^T dK[t] + Wv^T dV[t]
  ; dX2[t] = dR1[t] + LN_bwd(A1[t], dA1[t], inv1[t])
dx2_t2_da1_begin:
  MOVI r10,0
  ST r10,r0,@dx2_t2_i
dx2_t2_da1_i:
  LD r10,r0,@dx2_t2_i
  LD r11,r0,@dx2_t
  CMP r10,r11
  JMP[GE] @dx2_t2_done
  MOVI r12,128
  MUL r12,r10,r12
  ST r12,r0,@dx2_t2_off128
  LD r1,r0,@dx2_t2_da1
  ADD r1,r1,r12
  MOVI r2,128
  CALL @dx2_zero
  ; Wq^T dQ[t]
  LD r1,r0,@dx2_page
  MOVI r11,0x8000
  MOVHI r11,0x0002
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_dq
  LD r11,r0,@dx2_t2_off128
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_tmp
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r1,r0,@dx2_t2_da1
  LD r11,r0,@dx2_t2_off128
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_tmp
  MOVI r3,@hw6_one
  LD r3,r3,0
  MOVI r4,128
  CALL @dx2_axpy
  ; Wk^T dK[t]
  LD r1,r0,@dx2_page
  MOVI r11,0xA000
  MOVHI r11,0x0002
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_dk
  LD r11,r0,@dx2_t2_off128
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_tmp
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r1,r0,@dx2_t2_da1
  LD r11,r0,@dx2_t2_off128
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_tmp
  MOVI r3,@hw6_one
  LD r3,r3,0
  MOVI r4,128
  CALL @dx2_axpy
  ; Wv^T dV[t]
  LD r1,r0,@dx2_page
  MOVI r11,0xC000
  MOVHI r11,0x0002
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_dv
  LD r11,r0,@dx2_t2_off128
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_tmp
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r1,r0,@dx2_t2_da1
  LD r11,r0,@dx2_t2_off128
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_tmp
  MOVI r3,@hw6_one
  LD r3,r3,0
  MOVI r4,128
  CALL @dx2_axpy
  ; dX2 = LN_bwd(A1[t], dA1[t], inv1[t])
  LD r1,r0,@dx2_t2_a1
  LD r11,r0,@dx2_t2_off128
  ADD r1,r1,r11
  LD r2,r0,@dx2_t2_da1
  ADD r2,r2,r11
  LD r3,r0,@dx2_t2_dx
  ADD r3,r3,r11
  MOVI r4,128
  LD r5,r0,@dx2_t2_inv1
  LD r10,r0,@dx2_t2_i
  ADD r5,r5,r10
  LD r5,r5,0
  CALL @hrv_ln_bwd
  ; write dX2[t] and accumulate squared norm
  LD r11,r0,@dx2_t2_off128
  MOVI r10,0
dx2_t2_finish_d:
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @dx2_t2_next_i
  LD r12,r0,@dx2_t2_dr1
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r13,r12,0
  LD r12,r0,@dx2_t2_dx
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r14,r12,0
  FADD r13,r13,r14
  LD r14,r0,@dx2_out
  ADD r14,r14,r11
  ADD r14,r14,r10
  ST r13,r14,0
  FMUL r13,r13,r13
  MOVI r12,@dx2_norm
  LD r15,r12,0
  FADD r15,r15,r13
  ST r15,r12,0
  ADDI r10,r10,1
  JMP @dx2_t2_finish_d
dx2_t2_next_i:
  LD r10,r0,@dx2_t2_i
  ADDI r10,r10,1
  ST r10,r0,@dx2_t2_i
  JMP @dx2_t2_da1_i
dx2_t2_done:
  JMP @dx2_ok

; dx2_zero: r1=base, r2=count.
dx2_zero:
  MOVI r0,0
  ST r15,r0,@dx2_zero_link
  MOVI r10,0
dx2_zero_loop:
  CMP r10,r2
  JMP[GE] @dx2_zero_done
  ADD r11,r1,r10
  ST r0,r11,0
  ADDI r10,r10,1
  JMP @dx2_zero_loop
dx2_zero_done:
  LD r15,r0,@dx2_zero_link
  RET

; dx2_axpy: dest r1 += coeff r3 * src r2, D=r4.
dx2_axpy:
  MOVI r0,0
  ST r15,r0,@dx2_axpy_link
  MOVI r10,0
dx2_axpy_loop:
  CMP r10,r4
  JMP[GE] @dx2_axpy_done
  ADD r11,r2,r10
  LD r11,r11,0
  FMUL r11,r11,r3
  ADD r12,r1,r10
  LD r13,r12,0
  FADD r13,r13,r11
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @dx2_axpy_loop
dx2_axpy_done:
  LD r15,r0,@dx2_axpy_link
  RET

dx2_link:
  .word 0
dx2_context:
  .word 0
dx2_output:
  .word 0
dx2_slot:
  .word 0
dx2_t:
  .word 0
dx2_target:
  .word 0
dx2_out:
  .word 0
dx2_page:
  .word 0
dx2_norm:
  .word 0

; T=2 reverse working vectors (guest scratch above the forward captures).
dx2_t2_dy:
  .word 0x00D30000
dx2_t2_dh:
  .word 0x00D30200
dx2_t2_dxn2:
  .word 0x00D30600
dx2_t2_dr1:
  .word 0x00D30800
dx2_t2_dctx:
  .word 0x00D30A00
dx2_t2_dv:
  .word 0x00D30C00
dx2_t2_dk:
  .word 0x00D30E00
dx2_t2_dq:
  .word 0x00D31000
dx2_t2_dp:
  .word 0x00D31200
dx2_t2_da1:
  .word 0x00D31400
dx2_t2_dx:
  .word 0x00D31600
dx2_t2_tmp:
  .word 0x00D31800
dx2_t2_mean:
  .word 0x00D31900
; Layer-2 captures.
dx2_t2_q:
  .word 0x00D20800
dx2_t2_k:
  .word 0x00D21800
dx2_t2_v:
  .word 0x00D22800
dx2_t2_a1:
  .word 0x00D25800
dx2_t2_inv1:
  .word 0x00D26800
dx2_t2_inv2:
  .word 0x00D27800
dx2_t2_a2:
  .word 0x00D2A000
dx2_t2_h:
  .word 0x00D2D000
dx2_t2_p:
  .word 0x00D2E080
dx2_t2_i:
  .word 0
dx2_t2_j:
  .word 0
dx2_t2_n:
  .word 0
dx2_t2_last:
  .word 0
dx2_t2_sum:
  .word 0
dx2_t2_off128:
  .word 0
dx2_t2_off384:
  .word 0
dx2_zero_link:
  .word 0
dx2_axpy_link:
  .word 0
