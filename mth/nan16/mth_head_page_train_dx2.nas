; Raw NaN16 layer-2 dX2 reverse pass for T=1.
; Computes the exact gradient of 0.5*||Y_last-target||^2 with respect to the
; layer-2 input, using captured A1/A2, inverse-std, hidden, and layer-2 weights.
; No page mutation. T=2+ is rejected until full reverse attention is added.
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
  MOVI r7,1
  CMP r4,r7
  JMP[NE] @dx2_t_bad
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
  MOVI r3,1
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
