; NaN16 TCA leave-one-out triad advantage.
; ABI: r1=local log-prob, r2=peer A, r3=peer B (Q16.16).
; Returns r1=advantage, r2=advantage.
mth_tca_credit:
  ADD r10,r2,r3
  SAR r10,r10,1
  SUB r11,r1,r10
  ADD r1,r11,r0
  ADD r2,r11,r0
  RET
