; NaN16 seven-credit bundle derived from raw local state.
;
; Fixed state:
;   CFT   Eab,Ebc,Eca,error,rate at 0x8000..0x8004
;   TRAIL 11 args at 0x8010..0x801A
;   HOLO  phases at 0x8020..0x8022
;   RING  shift at 0x8030; phases pointer fixed at 0x7500
;   LEAF  row,mask,counter at 0x8040..0x8042
;   TCA   local,peerA,peerB at 0x8050..0x8052
;   FLUX  phi_u,phi_v,weight,source at 0x8060..0x8063
; Output credits at 0x7200..0x7206.
;
; Calls each raw kernel and stores its local credit.  No host arithmetic.
mth_credit_bundle:
  MOVI r12,@mth_cb_link
  ST r15,r12,0

  ; TRAIL
  MOVI r10,0x8010
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  LD r7,r10,6
  LD r8,r10,7
  LD r9,r10,8
  LD r10,r10,9
  MOVI r11,0x801A
  LD r11,r11,0
  CALL @mth_trail_credit
  MOVI r10,0x7200
  ST r3,r10,0

  ; CFT
  MOVI r10,0x8000
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  CALL @mth_cft_credit
  MOVI r10,0x7201
  ST r4,r10,0

  ; HOLO
  MOVI r10,0x8020
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_holo_credit
  MOVI r10,0x7202
  ST r2,r10,0

  ; RING
  MOVI r1,0x7500
  MOVI r10,0x8030
  LD r2,r10,0
  CALL @mth_ring_credit
  MOVI r10,0x7203
  ST r1,r10,0

  ; LEAF
  MOVI r10,0x8040
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_leaf_credit
  MOVI r10,0x7204
  ST r2,r10,0

  ; TCA
  MOVI r10,0x8050
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_tca_credit
  MOVI r10,0x7205
  ST r1,r10,0

  ; FLUX
  MOVI r10,0x8060
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_flux_credit
  MOVI r10,0x7206
  ST r3,r10,0

  MOVI r1,7
  MOVI r13,1
  MOVI r12,@mth_cb_link
  LD r15,r12,0
  RET
mth_cb_link:
  .word 0
