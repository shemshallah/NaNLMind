; NaN16 HOLO cycle-holonomy credit.
; ABI: r1,r2,r3 = three 16-bit-turn phases.
; Returns r1 = wrapped holonomy, r2 = Q16.16 defect (1-cos).
mth_holo_credit:
  MOVI r12,@mth_holo_link
  ST r15,r12,0
  ADD r10,r1,r2
  ADD r10,r10,r3
  MOVI r5,0
  MOVHI r5,0x0001
  MODU r10,r10,r5
  ADD r1,r10,r0
  CALL @mth_q16_sin_cos
  MOVI r3,0
  MOVHI r3,0x0001
  SUB r2,r3,r1
  ADD r1,r10,r0
  MOVI r13,1
  MOVI r12,@mth_holo_link
  LD r15,r12,0
  RET
mth_holo_link:
  .word 0
