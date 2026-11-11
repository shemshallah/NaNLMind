; Raw NaN16 rotation-invariant hyperbolic measure for complex phase vectors.
;
; ABI:
;   r1 = complex phase vector [cos,sin] pairs
;   r2 = lane count L
; Returns:
;   r1 = mean complex energy Q16
;   r2 = radial proxy Q16
;
; For each lane:
;   energy = Q16(cos*cos) + Q16(sin*sin)
; The energy is invariant under a common phase rotation. The radial proxy is
; energy / (energy + 65536), so larger energy moves a vector outward along its
; ray while a common rotation leaves its position unchanged.

mth_phase_hyperbolic:
  MOVI r12,@mth_ph_link
  ST r15,r12,0
  MOVI r12,@mth_ph_ptr
  ST r1,r12,0
  MOVI r12,@mth_ph_lanes
  ST r2,r12,0
  MOVI r5,0
  MOVI r6,0
mth_ph_loop:
  CMP r5,r2
  JMP[GE] @mth_ph_done
  MOVI r7,2
  MUL r7,r5,r7
  MOVI r12,@mth_ph_ptr
  LD r8,r12,0
  ADD r7,r8,r7
  LD r9,r7,0
  ADDI r7,r7,1
  LD r10,r7,0
  ; q16 cos^2
  MUL r11,r9,r9
  MULH r12,r9,r9
  SHL r12,r12,16
  SHR r11,r11,16
  ADD r11,r11,r12
  ; q16 sin^2
  MUL r12,r10,r10
  MULH r13,r10,r10
  SHL r13,r13,16
  SHR r12,r12,16
  ADD r12,r12,r13
  ADD r6,r6,r11
  ADD r6,r6,r12
  ADDI r5,r5,1
  JMP @mth_ph_loop
mth_ph_done:
  DIV r6,r6,r2
  MOVI r7,0
  MOVHI r7,0x0001
  ADD r8,r6,r7
  ; mean*65536/(mean+65536), saturating
  MOVI r9,32767
  CMP r6,r9
  JMP[GT] @mth_ph_sat
  MOVI r9,0
  MOVHI r9,0x0001
  MUL r9,r6,r9
  DIV r9,r9,r8
  ADD r2,r9,r0
  ADD r1,r6,r0
  MOVI r12,@mth_ph_link
  LD r15,r12,0
  RET
mth_ph_sat:
  MOVI r2,0
  MOVHI r2,0x0001
  ADD r1,r6,r0
  MOVI r12,@mth_ph_link
  LD r15,r12,0
  RET

mth_ph_link:
  .word 0
mth_ph_ptr:
  .word 0
mth_ph_lanes:
  .word 0
