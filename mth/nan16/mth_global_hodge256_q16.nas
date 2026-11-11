; Q16 pair-flow adapter for the global 256-head Hodge kernel.
; Converts 32,640 Q16.16 flows to float32 in guest scratch, then executes
; mth_global_hodge256_f32. All conversion and Hodge arithmetic stay native.
;
; Fixed staging:
;   Q16 flows      0x360000[32640]
;   triangles      0x368000[16][3] U32
;   divergence     0x369000[256] float32
;   curl           0x369400[16]  float32
;   Hodge scratch  0x36A000[256], 0x36B000[24]
;   float flows    0x36C000[32640]
; count 0x4001.
mth_global_hodge256_q16:
  MOVI r12,@mth_ghq_link
  ST r15,r12,0
  MOVI r10,0x0000
  MOVHI r10,0x0036          ; Q16 flows
  MOVI r11,0xC000
  MOVHI r11,0x0036          ; float flows
  MOVI r8,0
  MOVI r9,32640
mth_ghq_convert:
  CMP r8,r9
  JMP[GE] @mth_ghq_call
  ADD r6,r10,r8
  LD r6,r6,0
  CVTIF r6,r6
  MOVI r7,0
  MOVHI r7,0x4780          ; 65536.0
  FDIV r6,r6,r7
  ADD r7,r11,r8
  ST r6,r7,0
  ADDI r8,r8,1
  JMP @mth_ghq_convert
mth_ghq_call:
  ADD r1,r11,r0
  MOVI r2,0x8000
  MOVHI r2,0x0036
  MOVI r10,0x4001
  LD r3,r10,0
  MOVI r4,0x9000
  MOVHI r4,0x0036
  MOVI r5,0x9400
  MOVHI r5,0x0036
  MOVI r6,0xA000
  MOVHI r6,0x0036
  MOVI r7,0xB000
  MOVHI r7,0x0036
  CALL @mth_global_hodge256_f32
  MOVI r12,@mth_ghq_link
  LD r15,r12,0
  RET
mth_ghq_link:
  .word 0
