; Signed Q16.16 multiply: r1 = (r1*r2) >> 16.
; Uses the native 32x32 -> 64-bit MUL/MULH pair; no host floating point.
; Clobbers r3,r4 only.
mth_q16_mul:
  MUL r3,r1,r2
  MULH r4,r1,r2
  SHL r4,r4,16
  SHR r3,r3,16
  ADD r1,r3,r4
  RET
