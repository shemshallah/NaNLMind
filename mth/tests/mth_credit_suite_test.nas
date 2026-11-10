.org 0
JMP @mth_cs_main
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_holo_credit.nas"
.include "../nan16/mth_ring_credit.nas"
.include "../nan16/mth_leaf_credit.nas"
.include "../nan16/mth_tca_credit.nas"
.include "../nan16/mth_flux_credit.nas"
.include "../nan16/mth_credit_combine.nas"

mth_cs_main:
  MOVI r13,1
  ; HOLO: zero holonomy, zero defect.
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  CALL @mth_holo_credit
  CMP r1,r0
  JMP[NE] @mth_cs_fail
  MOVI r10,64
  CMP r2,r10
  JMP[GT] @mth_cs_fail

  ; RING: zero phases, zero shift -> average cos ~ 1.0.
  MOVI r1,@mth_cs_phases
  MOVI r2,0
  CALL @mth_ring_credit
  MOVI r10,65000
  CMP r1,r10
  JMP[LT] @mth_cs_fail

  ; LEAF: bits 0xF & 0x3 = 2, counter=100 -> 200.
  MOVI r1,0xF
  MOVI r2,0x3
  MOVI r3,100
  CALL @mth_leaf_credit
  MOVI r10,2
  CMP r1,r10
  JMP[NE] @mth_cs_fail
  MOVI r10,200
  CMP r2,r10
  JMP[NE] @mth_cs_fail

  ; TCA: local 100, peers 50/50 -> advantage 50.
  MOVI r1,100
  MOVI r2,50
  MOVI r3,50
  CALL @mth_tca_credit
  MOVI r10,50
  CMP r1,r10
  JMP[NE] @mth_cs_fail

  ; FLUX: phi_u=0, phi_v=1.0, weight=.5 -> J=.5, source=0 -> D=.5,
  ; credit=.25.  Q16 values are 65536/32768/16384.
  MOVI r1,0
  MOVI r2,0
  MOVHI r2,0x0001
  MOVI r3,0x8000
  MOVI r4,0
  CALL @mth_flux_credit
  MOVI r10,0x8000
  CMP r1,r10
  JMP[NE] @mth_cs_fail
  CMP r2,r10
  JMP[NE] @mth_cs_fail
  MOVI r10,0x4000
  CMP r3,r10
  JMP[NE] @mth_cs_fail

  ; Combined credit: one unit credit at coefficient 1.0 -> one unit.
  MOVI r1,@mth_cs_credits
  MOVI r2,@mth_cs_coeffs
  CALL @mth_credit_combine
  MOVI r10,0
  MOVHI r10,0x0001
  CMP r1,r10
  JMP[NE] @mth_cs_fail

  MOVI r1,@mth_cs_pass
  CALL @mth_cs_puts
  HALT
mth_cs_fail:
  MOVI r1,@mth_cs_bad
  CALL @mth_cs_puts
  HALT
mth_cs_puts:
  MOVI r4,255
mth_cs_word:
  LD r2,r1,0
  MOVI r3,4
mth_cs_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_cs_byte
  ADD r1,r1,r13
  JMP @mth_cs_word
mth_cs_phases:
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
  .word 0,0,0,0,0,0,0,0
mth_cs_credits:
  .word 65536,0,0,0,0,0,0
mth_cs_coeffs:
  .word 65536,0,0,0,0,0,0
mth_cs_pass:
.str "MTH CREDIT SUITE PASS\n"
mth_cs_bad:
.str "MTH CREDIT SUITE FAIL\n"
