; NaN16 cycle-flux credit for one triangle.
;
; ABI:
;   r1 = E(a,b), r2 = E(b,c), r3 = E(c,a) in Q16.16
;   r4 = local error in Q16.16 (non-negative in this first slice)
;   r5 = rate in Q16.16 (non-negative in this first slice)
; Returns:
;   r1,r2,r3 = updated edge energies
;   r4 = signed residual E(a,b)+E(b,c)+E(c,a)
;
; The three edge updates change the triangle circulation by the proposed
; delta: +delta, +delta, -delta. This is local credit, not a BPTT tape.
mth_cft_credit:
  MOVI r7,0
  MOVHI r7,1              ; 65536 = Q16.16 one
  MUL r6,r4,r5
  DIVU r6,r6,r7           ; positive Q16 product; unsigned scale
  MOVI r7,3
  DIVU r6,r6,r7           ; delta /= 3
  ADD r1,r1,r6
  ADD r2,r2,r6
  SUB r3,r3,r6
  ADD r4,r1,r2
  ADD r4,r4,r3
  RET
