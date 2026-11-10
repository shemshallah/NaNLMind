; NaN16 geometric-credit gate.
;
; ABI (Q16.16):
;   r1 = signed credit
;   r2 = base learning rate
;   r3 = acceptance threshold
; Returns:
;   r1 = gated learning rate (0 when credit <= threshold)
;
; The credit is clamped to [0,1] before multiplying the base rate, so a large
; CFT/TRAIL credit cannot amplify a local update without bound.
mth_credit_gate:
  MOVI r12,@mth_cg_link
  ST r15,r12,0
  CMPS r1,r3
  JMP[LE] @mth_cg_zero
  MOVI r4,0
  MOVHI r4,0x0001              ; Q16.16 1.0
  CMPS r1,r4
  JMP[LE] @mth_cg_scale
  ADD r1,r4,r0
mth_cg_scale:
  ADD r2,r2,r0
  CALL @mth_q16_mul
  JMP @mth_cg_out
mth_cg_zero:
  MOVI r1,0
mth_cg_out:
  MOVI r13,1
  MOVI r12,@mth_cg_link
  LD r15,r12,0
  RET
mth_cg_link:
  .word 0
