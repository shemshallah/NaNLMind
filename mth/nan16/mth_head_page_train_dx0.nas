; Raw NaN16 full input-gradient reverse for the T=1/T=2 three-layer block.
;
; Opcode 138 runs the same forward as mth_head_block6 (which captures A1/inv1,
; A2/inv2, hidden H, Q/K/V and normalized attention probabilities for every
; token and layer), then applies the exact layer reverse three times:
;
;   reverse layer 2 with dY -> dX2
;   reverse layer 1 with dX2 -> dX1
;   reverse layer 0 with dX1 -> dX0
;
; Each reverse uses that layer's own page weights (Wq/Wk/Wv/Wo/W1/W2) and its
; own captures. The attention reverse is the exact reverse of the unmasked
; per-query softmax implemented by mth_head_block6:
;
;   dP[i][j] = dctx[i] . V[j]
;   ds[i][j] = p[i][j] * (dP[i][j] - sum_k p[i][k]*dP[i][k])
;   dQ[i]    = sum_j ds[i][j] * K[j] / sqrt(128)
;   dK[j]    = sum_i ds[i][j] * Q[i] / sqrt(128)
;   dV[j]    = sum_i p[i][j] * dctx[i]
;
; No page mutation. T=1 and T=2 only; T>2 is rejected.
;
; ABI: r1=context, r2=output, r3=slot, r4=T, r5=target, r6=dx0.
; Returns r1=1,r2=dx0 norm^2,r3=T,r4=0; rejection r1=0,r4=reason.
mth_head_page_train_dx0:
  MOVI r0,0
  ST r15,r0,@dx0_link
  ST r1,r0,@dx0_context
  ST r2,r0,@dx0_output
  ST r3,r0,@dx0_slot
  ST r4,r0,@dx0_t
  ST r5,r0,@dx0_target
  ST r6,r0,@dx0_out
  CMP r1,r0
  JMP[EQ] @dx0_bad
  CMP r2,r0
  JMP[EQ] @dx0_bad
  CMP r5,r0
  JMP[EQ] @dx0_bad
  CMP r6,r0
  JMP[EQ] @dx0_bad
  CMP r4,r0
  JMP[EQ] @dx0_bad
  MOVI r7,2
  CMP r4,r7
  JMP[GT] @dx0_t_bad
  MOVI r7,16
  CMP r3,r7
  JMP[GE] @dx0_bad
  MOVI r10,0
  ST r10,r0,@dx0_norm

  ; Forward pass with all-token/all-layer captures.
  LD r1,r0,@dx0_context
  LD r2,r0,@dx0_output
  LD r3,r0,@dx0_slot
  LD r4,r0,@dx0_t
  CALL @mth_head_block6
  CMP r1,r0
  JMP[EQ] @dx0_forward_bad

  ; Page base = slot*0x40000 words + 0x00800000.
  LD r10,r0,@dx0_slot
  SHL r10,r10,18
  MOVI r11,0x0000
  MOVHI r11,0x0080
  ADD r10,r10,r11
  ST r10,r0,@dx0_page

  ; n = T*128.
  LD r10,r0,@dx0_t
  MOVI r11,128
  MUL r10,r10,r11
  ST r10,r0,@dx0_n

  ; dY = zero for all tokens, then output-target on the last token.
  LD r1,r0,@dx0_buf_dy
  LD r2,r0,@dx0_n
  CALL @hrv_zero
  LD r10,r0,@dx0_n
  MOVI r11,128
  SUB r10,r10,r11
  ST r10,r0,@dx0_last
  MOVI r10,0
dx0_dy_loop:
  MOVI r12,128
  CMP r10,r12
  JMP[GE] @dx0_dy_done
  LD r12,r0,@dx0_output
  LD r13,r0,@dx0_last
  ADD r12,r12,r13
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@dx0_target
  ADD r13,r13,r10
  LD r13,r13,0
  FSUB r12,r12,r13
  LD r13,r0,@dx0_buf_dy
  LD r14,r0,@dx0_last
  ADD r13,r13,r14
  ADD r13,r13,r10
  ST r12,r13,0
  ADDI r10,r10,1
  JMP @dx0_dy_loop
dx0_dy_done:

  ; dX2 = layer_rev(2, dY), dX1 = layer_rev(1, dX2),
  ; dX0 = layer_rev(0, dX1).
  MOVI r1,2
  LD r2,r0,@dx0_buf_dy
  LD r3,r0,@dx0_buf_1
  CALL @dx0_layer_rev
  MOVI r1,1
  LD r2,r0,@dx0_buf_1
  LD r3,r0,@dx0_buf_2
  CALL @dx0_layer_rev
  MOVI r1,0
  LD r2,r0,@dx0_buf_2
  LD r3,r0,@dx0_out
  CALL @dx0_layer_rev

  ; Accumulate ||dX0||^2 for the receipt.
  MOVI r10,0
dx0_norm_loop:
  LD r11,r0,@dx0_n
  CMP r10,r11
  JMP[GE] @dx0_ok
  LD r12,r0,@dx0_out
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r12,@dx0_norm
  LD r14,r12,0
  FMUL r15,r13,r13
  FADD r14,r14,r15
  ST r14,r12,0
  ADDI r10,r10,1
  JMP @dx0_norm_loop
dx0_ok:
  MOVI r1,1
  MOVI r2,@dx0_norm
  LD r2,r2,0
  LD r3,r0,@dx0_t
  MOVI r4,0
  LD r15,r0,@dx0_link
  RET
dx0_t_bad:
  MOVI r4,2
  JMP @dx0_reject
dx0_forward_bad:
  MOVI r4,3
  JMP @dx0_reject
dx0_bad:
  MOVI r4,1
dx0_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r15,r0,@dx0_link
  RET

; ---------------------------------------------------------------------------
; Generic exact reverse of one block6 layer.
;
; ABI: r1=layer index 0..2, r2=dOut f32[T*128], r3=dIn f32[T*128].
; Forward layer form:
;   A1=LN1(x); q=Wq A1; k=Wk A1; v=Wv A1
;   ctx_i=sum_j p_ij v_j; x+=Wo ctx
;   A2=LN2(x); H=tanh(W1 A2); x+=W2 H
; Reverse:
;   dH=W2^T dOut; dZ=dH*(1-H^2); dXN2=W1^T dZ
;   dR1=dOut+LNbwd(A2,dXN2,inv2); dctx=Wo^T dR1
;   attention reverse (unmasked full softmax)
;   dA1=Wq^T dQ+Wk^T dK+Wv^T dV
;   dIn=dR1+LNbwd(A1,dA1,inv1)
; ---------------------------------------------------------------------------
dx0_layer_rev:
  MOVI r0,0
  ST r15,r0,@dx0_lr_link
  ST r1,r0,@dx0_lr_layer
  ST r2,r0,@dx0_lr_dout
  ST r3,r0,@dx0_lr_din

  ; Layer page = page + layer*0x14000 words.
  LD r10,r0,@dx0_page
  LD r11,r0,@dx0_lr_layer
  MOVI r12,0x4000
  MOVHI r12,0x0001
  MUL r12,r11,r12
  ADD r10,r10,r12
  ST r10,r0,@dx0_lr_page

  ; Per-layer capture offsets: 0x400 words for token vectors and scalar
  ; inv captures, 0x1000 words for A2/H, 0x40 words for probabilities.
  LD r11,r0,@dx0_lr_layer
  MOVI r12,0x400
  MUL r11,r11,r12
  ST r11,r0,@dx0_offcap
  LD r11,r0,@dx0_lr_layer
  MOVI r12,0x1000
  MUL r11,r11,r12
  ST r11,r0,@dx0_off2
  LD r11,r0,@dx0_lr_layer
  MOVI r12,0x40
  MUL r11,r11,r12
  ST r11,r0,@dx0_offp

  ; Q/K/V/A1/inv1/inv2 capture bases.
  MOVI r10,0x0000
  MOVHI r10,0x00D2
  LD r11,r0,@dx0_offcap
  ADD r10,r10,r11
  ST r10,r0,@dx0_qbase
  MOVI r10,0x1000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_kbase
  MOVI r10,0x2000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_vbase
  MOVI r10,0x5000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_a1base
  MOVI r10,0x6000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_inv1base
  MOVI r10,0x7000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_inv2base
  ; A2/H capture bases.
  LD r11,r0,@dx0_off2
  MOVI r10,0x8000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_a2base
  MOVI r10,0xB000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_hbase
  ; Probability capture base.
  LD r11,r0,@dx0_offp
  MOVI r10,0xE000
  MOVHI r10,0x00D2
  ADD r10,r10,r11
  ST r10,r0,@dx0_pbase

  ; dH[t] = W2^T dOut[t]; dZ[t] = dH[t]*(1-H[t]^2) in place.
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_dh_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_dh_done
  MOVI r12,128
  MUL r12,r10,r12
  ST r12,r0,@dx0_off128
  MOVI r12,384
  MUL r12,r10,r12
  ST r12,r0,@dx0_off384
  LD r1,r0,@dx0_lr_page
  MOVI r11,0xE000
  ADD r1,r1,r11
  LD r2,r0,@dx0_lr_dout
  LD r11,r0,@dx0_off128
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_dh
  LD r11,r0,@dx0_off384
  ADD r3,r3,r11
  MOVI r4,128
  MOVI r5,384
  CALL @hrv_mv_t
  MOVI r10,0
dx0_lr_dz_d:
  MOVI r11,384
  CMP r10,r11
  JMP[GE] @dx0_lr_dz_done
  LD r12,r0,@dx0_buf_dh
  LD r11,r0,@dx0_off384
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r13,r12,0
  LD r14,r0,@dx0_hbase
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
  JMP @dx0_lr_dz_d
dx0_lr_dz_done:
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dh_i
dx0_lr_dh_done:

  ; dXN2[t] = W1^T dZ[t].
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_dxn2_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_dxn2_done
  MOVI r12,128
  MUL r12,r10,r12
  ST r12,r0,@dx0_off128
  MOVI r12,384
  MUL r12,r10,r12
  ST r12,r0,@dx0_off384
  LD r1,r0,@dx0_lr_page
  MOVI r11,0x8000
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_dh
  LD r11,r0,@dx0_off384
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_dxn2
  LD r11,r0,@dx0_off128
  ADD r3,r3,r11
  MOVI r4,384
  MOVI r5,128
  CALL @hrv_mv_t
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dxn2_i
dx0_lr_dxn2_done:

  ; dR1[t] = dOut[t] + LNbwd(A2[t], dXN2[t], inv2[t]).
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_dr1_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_dr1_done
  MOVI r12,128
  MUL r12,r10,r12
  ST r12,r0,@dx0_off128
  LD r1,r0,@dx0_a2base
  LD r11,r0,@dx0_off128
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_dxn2
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_dr1
  ADD r3,r3,r11
  MOVI r4,128
  LD r5,r0,@dx0_inv2base
  LD r10,r0,@dx0_i
  ADD r5,r5,r10
  LD r5,r5,0
  CALL @hrv_ln_bwd
  MOVI r10,0
dx0_lr_dr1_add:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @dx0_lr_dr1_add_done
  LD r12,r0,@dx0_buf_dr1
  LD r11,r0,@dx0_off128
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r13,r12,0
  LD r14,r0,@dx0_lr_dout
  ADD r14,r14,r11
  ADD r14,r14,r10
  LD r14,r14,0
  FADD r13,r13,r14
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @dx0_lr_dr1_add
dx0_lr_dr1_add_done:
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dr1_i
dx0_lr_dr1_done:

  ; dctx[t] = Wo^T dR1[t].
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_dctx_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_dctx_done
  MOVI r12,128
  MUL r12,r10,r12
  ST r12,r0,@dx0_off128
  LD r1,r0,@dx0_lr_page
  MOVI r11,0x6000
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_dr1
  LD r11,r0,@dx0_off128
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_dctx
  ADD r3,r3,r11
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dctx_i
dx0_lr_dctx_done:

  ; Attention reverse. Zero dQ/dK/dV first.
  LD r1,r0,@dx0_buf_dq
  LD r2,r0,@dx0_n
  CALL @hrv_zero
  LD r1,r0,@dx0_buf_dk
  LD r2,r0,@dx0_n
  CALL @hrv_zero
  LD r1,r0,@dx0_buf_dv
  LD r2,r0,@dx0_n
  CALL @hrv_zero

  ; dP[i][j] = dctx[i] . V[j].
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_dp_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_dp_done
  MOVI r10,0
  ST r10,r0,@dx0_j
dx0_lr_dp_j:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r11,r12
  JMP[GE] @dx0_lr_dp_next_i
  MOVI r12,128
  MUL r12,r10,r12
  LD r1,r0,@dx0_buf_dctx
  ADD r1,r1,r12
  MOVI r12,128
  MUL r12,r11,r12
  LD r2,r0,@dx0_vbase
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hrv_dot
  LD r13,r0,@hrv_dot_value
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_j
  MOVI r12,8
  MUL r12,r10,r12
  LD r14,r0,@dx0_buf_dp
  ADD r14,r14,r12
  ADD r14,r14,r11
  ST r13,r14,0
  LD r11,r0,@dx0_j
  ADDI r11,r11,1
  ST r11,r0,@dx0_j
  JMP @dx0_lr_dp_j
dx0_lr_dp_next_i:
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dp_i

  ; mean_i = sum_j p[i][j]*dP[i][j], stored in dx0_buf_mean[i].
dx0_lr_dp_done:
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_mean_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_mean_done
  MOVI r12,0
  ST r12,r0,@dx0_sum
  MOVI r12,0
  ST r12,r0,@dx0_j
dx0_lr_mean_j:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r11,r12
  JMP[GE] @dx0_lr_mean_next_i
  MOVI r14,8
  MUL r14,r10,r14
  LD r12,r0,@dx0_pbase
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r13,r12,0
  LD r12,r0,@dx0_buf_dp
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r14,r12,0
  FMUL r13,r13,r14
  MOVI r14,@dx0_sum
  LD r15,r14,0
  FADD r15,r15,r13
  ST r15,r14,0
  LD r11,r0,@dx0_j
  ADDI r11,r11,1
  ST r11,r0,@dx0_j
  JMP @dx0_lr_mean_j
dx0_lr_mean_next_i:
  LD r12,r0,@dx0_buf_mean
  LD r10,r0,@dx0_i
  ADD r12,r12,r10
  MOVI r13,@dx0_sum
  LD r13,r13,0
  ST r13,r12,0
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_mean_i

  ; ds[i][j] = p[i][j]*(dP[i][j]-mean_i), in place over dP.
dx0_lr_mean_done:
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_ds_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_ds_done
  MOVI r10,0
  ST r10,r0,@dx0_j
dx0_lr_ds_j:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r11,r12
  JMP[GE] @dx0_lr_ds_next_i
  MOVI r14,8
  MUL r14,r10,r14
  LD r12,r0,@dx0_pbase
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r13,r12,0
  LD r12,r0,@dx0_buf_dp
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r14,r12,0
  LD r15,r0,@dx0_buf_mean
  ADD r15,r15,r10
  LD r15,r15,0
  FSUB r14,r14,r15
  FMUL r13,r13,r14
  ST r13,r12,0
  LD r11,r0,@dx0_j
  ADDI r11,r11,1
  ST r11,r0,@dx0_j
  JMP @dx0_lr_ds_j
dx0_lr_ds_next_i:
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_ds_i

  ; dQ[i] += (ds[i][j]/scale) * K[j].
dx0_lr_ds_done:
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_dq_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_dq_done
  MOVI r10,0
  ST r10,r0,@dx0_j
dx0_lr_dq_j:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r11,r12
  JMP[GE] @dx0_lr_dq_next_i
  MOVI r14,8
  MUL r14,r10,r14
  LD r12,r0,@dx0_buf_dp
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r3,r12,0
  MOVI r12,@hw6_scale
  LD r12,r12,0
  FDIV r3,r3,r12
  MOVI r14,128
  MUL r14,r10,r14
  LD r1,r0,@dx0_buf_dq
  ADD r1,r1,r14
  MOVI r14,128
  MUL r14,r11,r14
  LD r2,r0,@dx0_kbase
  ADD r2,r2,r14
  MOVI r4,128
  CALL @hrv_axpy
  LD r11,r0,@dx0_j
  ADDI r11,r11,1
  ST r11,r0,@dx0_j
  JMP @dx0_lr_dq_j
dx0_lr_dq_next_i:
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dq_i

  ; dK[j] += (ds[i][j]/scale) * Q[i].
dx0_lr_dq_done:
  MOVI r10,0
  ST r10,r0,@dx0_j
dx0_lr_dk_j:
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r11,r12
  JMP[GE] @dx0_lr_dk_done
  MOVI r12,0
  ST r12,r0,@dx0_i
dx0_lr_dk_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r10,r12
  JMP[GE] @dx0_lr_dk_next_j
  MOVI r14,8
  MUL r14,r10,r14
  LD r12,r0,@dx0_buf_dp
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r3,r12,0
  MOVI r12,@hw6_scale
  LD r12,r12,0
  FDIV r3,r3,r12
  MOVI r14,128
  MUL r14,r11,r14
  LD r1,r0,@dx0_buf_dk
  ADD r1,r1,r14
  MOVI r14,128
  MUL r14,r10,r14
  LD r2,r0,@dx0_qbase
  ADD r2,r2,r14
  MOVI r4,128
  CALL @hrv_axpy
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dk_i
dx0_lr_dk_next_j:
  LD r11,r0,@dx0_j
  ADDI r11,r11,1
  ST r11,r0,@dx0_j
  JMP @dx0_lr_dk_j

  ; dV[j] += p[i][j] * dctx[i].
dx0_lr_dk_done:
  MOVI r10,0
  ST r10,r0,@dx0_j
dx0_lr_dv_j:
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r11,r12
  JMP[GE] @dx0_lr_dv_done
  MOVI r12,0
  ST r12,r0,@dx0_i
dx0_lr_dv_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_j
  LD r12,r0,@dx0_t
  CMP r10,r12
  JMP[GE] @dx0_lr_dv_next_j
  MOVI r14,8
  MUL r14,r10,r14
  LD r12,r0,@dx0_pbase
  ADD r12,r12,r14
  ADD r12,r12,r11
  LD r3,r12,0
  MOVI r14,128
  MUL r14,r11,r14
  LD r1,r0,@dx0_buf_dv
  ADD r1,r1,r14
  MOVI r14,128
  MUL r14,r10,r14
  LD r2,r0,@dx0_buf_dctx
  ADD r2,r2,r14
  MOVI r4,128
  CALL @hrv_axpy
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_dv_i
dx0_lr_dv_next_j:
  LD r11,r0,@dx0_j
  ADDI r11,r11,1
  ST r11,r0,@dx0_j
  JMP @dx0_lr_dv_j

  ; dA1[t] = Wq^T dQ[t] + Wk^T dK[t] + Wv^T dV[t]
  ; dIn[t] = dR1[t] + LNbwd(A1[t], dA1[t], inv1[t])
dx0_lr_dv_done:
  MOVI r10,0
  ST r10,r0,@dx0_i
dx0_lr_da1_i:
  LD r10,r0,@dx0_i
  LD r11,r0,@dx0_t
  CMP r10,r11
  JMP[GE] @dx0_lr_da1_done
  MOVI r12,128
  MUL r12,r10,r12
  ST r12,r0,@dx0_off128
  ; zero dA1[t]
  LD r1,r0,@dx0_buf_da1
  ADD r1,r1,r12
  MOVI r2,128
  CALL @hrv_zero
  ; Wq^T dQ[t]
  LD r1,r0,@dx0_lr_page
  MOVI r11,0x0000
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_dq
  LD r11,r0,@dx0_off128
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_tmp
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r1,r0,@dx0_buf_da1
  LD r11,r0,@dx0_off128
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_tmp
  MOVI r3,@hw6_one
  LD r3,r3,0
  MOVI r4,128
  CALL @hrv_axpy
  ; Wk^T dK[t]
  LD r1,r0,@dx0_lr_page
  MOVI r11,0x2000
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_dk
  LD r11,r0,@dx0_off128
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_tmp
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r1,r0,@dx0_buf_da1
  LD r11,r0,@dx0_off128
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_tmp
  MOVI r3,@hw6_one
  LD r3,r3,0
  MOVI r4,128
  CALL @hrv_axpy
  ; Wv^T dV[t]
  LD r1,r0,@dx0_lr_page
  MOVI r11,0x4000
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_dv
  LD r11,r0,@dx0_off128
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_tmp
  MOVI r4,128
  MOVI r5,128
  CALL @hrv_mv_t
  LD r1,r0,@dx0_buf_da1
  LD r11,r0,@dx0_off128
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_tmp
  MOVI r3,@hw6_one
  LD r3,r3,0
  MOVI r4,128
  CALL @hrv_axpy
  ; LNbwd(A1[t], dA1[t], inv1[t]), then add dR1[t].
  LD r1,r0,@dx0_a1base
  LD r11,r0,@dx0_off128
  ADD r1,r1,r11
  LD r2,r0,@dx0_buf_da1
  ADD r2,r2,r11
  LD r3,r0,@dx0_buf_dx
  ADD r3,r3,r11
  MOVI r4,128
  LD r5,r0,@dx0_inv1base
  LD r10,r0,@dx0_i
  ADD r5,r5,r10
  LD r5,r5,0
  CALL @hrv_ln_bwd
  MOVI r10,0
dx0_lr_finish_d:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @dx0_lr_finish_done
  LD r12,r0,@dx0_buf_dr1
  LD r11,r0,@dx0_off128
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r13,r12,0
  LD r12,r0,@dx0_buf_dx
  ADD r12,r12,r11
  ADD r12,r12,r10
  LD r14,r12,0
  FADD r13,r13,r14
  MOVI r12,@dx0_lr_din
  LD r12,r12,0
  ADD r12,r12,r11
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @dx0_lr_finish_d
dx0_lr_finish_done:
  LD r10,r0,@dx0_i
  ADDI r10,r10,1
  ST r10,r0,@dx0_i
  JMP @dx0_lr_da1_i
dx0_lr_da1_done:
  LD r15,r0,@dx0_lr_link
  RET

dx0_link:
  .word 0
dx0_context:
  .word 0
dx0_output:
  .word 0
dx0_slot:
  .word 0
dx0_t:
  .word 0
dx0_target:
  .word 0
dx0_out:
  .word 0
dx0_page:
  .word 0
dx0_norm:
  .word 0
dx0_n:
  .word 0
dx0_last:
  .word 0
dx0_i:
  .word 0
dx0_j:
  .word 0
dx0_sum:
  .word 0
dx0_off128:
  .word 0
dx0_off384:
  .word 0
dx0_offcap:
  .word 0
dx0_off2:
  .word 0
dx0_offp:
  .word 0
dx0_lr_link:
  .word 0
dx0_lr_layer:
  .word 0
dx0_lr_dout:
  .word 0
dx0_lr_din:
  .word 0
dx0_lr_page:
  .word 0
dx0_qbase:
  .word 0
dx0_kbase:
  .word 0
dx0_vbase:
  .word 0
dx0_a1base:
  .word 0
dx0_inv1base:
  .word 0
dx0_inv2base:
  .word 0
dx0_a2base:
  .word 0
dx0_hbase:
  .word 0
dx0_pbase:
  .word 0

; Reverse working vectors. Layer-2, layer-1 and layer-0 passes reuse the same
; buffers because each pass finishes before the next starts.
dx0_buf_dy:
  .word 0x00D30000
dx0_buf_1:
  .word 0x00D30200
dx0_buf_2:
  .word 0x00D30400
dx0_buf_dh:
  .word 0x00D30600
dx0_buf_dxn2:
  .word 0x00D30A00
dx0_buf_dr1:
  .word 0x00D30C00
dx0_buf_dctx:
  .word 0x00D30E00
dx0_buf_dv:
  .word 0x00D31000
dx0_buf_dk:
  .word 0x00D31200
dx0_buf_dq:
  .word 0x00D31400
dx0_buf_dp:
  .word 0x00D31600
dx0_buf_da1:
  .word 0x00D31800
dx0_buf_dx:
  .word 0x00D31A00
dx0_buf_tmp:
  .word 0x00D31C00
dx0_buf_mean:
  .word 0x00D31D00
