; Native coupling: mirror-pair triangle loop curl -> SAME 128D Poincare
; hyperedge math used by independently measured HEAD / TRIHEAD layers.
; Discrete curl L is NOT the intrinsic constant-negative sectional curvature;
; it is an oriented observed field 2-form, transported into that geometry.
; The Poincare ball's radial depth and sign-symmetric 128D vector are
; independent from L; curl*radius is an oriented signed eligibility signal.
;
; ABI r1=measured triangle record[32], r2=guest measured heads[255][256],
;     r3=private source-average128, r4=private Poincare dest128,
;     r5=hyperedge source record[8],r6=meta[5],r7=source epoch.
; return r1=1,r2=128,r3=curl sign(-1/0/1),r4=0; reject 1 malformed/
;        2 stale /3 missing head measurement/4 hyperbolic failure.
; On success measured record[28..31] gains radius,depth,curl*radius,1.
; No tensor ACTIVE writes or model changes. Guest vector dst is PRIVATE.
mth_mirror_triangle_poincare128:
  MOVI r0,0
  ST r15,r0,@mtp_link
  ST r1,r0,@mtp_record
  ST r2,r0,@mtp_heads
  ST r3,r0,@mtp_src
  ST r4,r0,@mtp_dst
  ST r5,r0,@mtp_hyper
  ST r6,r0,@mtp_meta
  ST r7,r0,@mtp_epoch
  CMP r1,r0
  JMP[EQ] @mtp_bad
  CMP r2,r0
  JMP[EQ] @mtp_bad
  CMP r3,r0
  JMP[EQ] @mtp_bad
  CMP r4,r0
  JMP[EQ] @mtp_bad
  CMP r5,r0
  JMP[EQ] @mtp_bad
  CMP r6,r0
  JMP[EQ] @mtp_bad
  CMP r3,r4
  JMP[EQ] @mtp_bad
  CMP r3,r5
  JMP[EQ] @mtp_bad
  CMP r3,r6
  JMP[EQ] @mtp_bad
  CMP r4,r5
  JMP[EQ] @mtp_bad
  CMP r4,r6
  JMP[EQ] @mtp_bad
  CMP r5,r6
  JMP[EQ] @mtp_bad
  LD r10,r1,26
  CMP r10,r7
  JMP[NE] @mtp_stale

  MOVI r8,0
mtp_check_heads:
  MOVI r9,3
  CMP r8,r9
  JMP[GE] @mtp_average
  LD r10,r0,@mtp_record
  ADD r10,r10,r8
  LD r11,r10,0
  MOVI r12,255
  CMP r11,r12
  JMP[GE] @mtp_bad
  CMPS r11,r0
  JMP[LT] @mtp_bad
  ; Existing independently measured 128D HEADs require native stamp and
  ; matching epoch. No guest head phase or Boolean rule is invented here.
  ; Respect the caller's measured-head bank instead of assuming 0x3B0000.
  ; Production keeps that address, while isolated guest tests may relocate it.
  LD r12,r0,@mtp_heads
  SHL r10,r11,8
  ADD r12,r12,r10
  LD r10,r12,147
  MOVI r11,1
  CMP r10,r11
  JMP[NE] @mtp_bad_head
  LD r10,r12,133
  LD r11,r0,@mtp_epoch
  CMP r10,r11
  JMP[NE] @mtp_stale
  ADDI r8,r8,1
  JMP @mtp_check_heads

mtp_average:
  MOVI r8,0
mtp_dimension:
  MOVI r10,128
  CMP r8,r10
  JMP[GE] @mtp_hyperedge_record
  MOVI r10,0
  ST r10,r0,@mtp_acc
  MOVI r9,0
mtp_member_dimension:
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @mtp_avg_done
  LD r10,r0,@mtp_record
  ADD r10,r10,r9
  LD r11,r10,0
  SHL r11,r11,8
  LD r10,r0,@mtp_heads
  ADD r10,r10,r11
  ADD r10,r10,r8
  LD r11,r10,0
  LD r12,r0,@mtp_acc
  FADD r12,r12,r11
  ST r12,r0,@mtp_acc
  ADDI r9,r9,1
  JMP @mtp_member_dimension
mtp_avg_done:
  LD r10,r0,@mtp_acc
  MOVI r12,0
  MOVHI r12,0x4040   ; 3.0 float32
  FDIV r10,r10,r12
  LD r11,r0,@mtp_src
  ADD r11,r11,r8
  ST r10,r11,0
  ADDI r8,r8,1
  JMP @mtp_dimension

mtp_hyperedge_record:
  LD r8,r0,@mtp_record
  LD r9,r0,@mtp_hyper
  LD r10,r8,0
  ST r10,r9,0
  LD r10,r8,1
  ST r10,r9,1
  LD r10,r8,2
  ST r10,r9,2
  LD r10,r8,11
  ST r10,r9,3      ; actual, native measured oriented loop curl
  LD r10,r0,@mtp_epoch
  ST r10,r9,4
  ST r10,r9,5
  MOVI r10,255
  ST r10,r9,6
  MOVI r10,1
  ST r10,r9,7
  LD r1,r0,@mtp_src
  LD r2,r0,@mtp_dst
  LD r3,r0,@mtp_hyper
  LD r4,r0,@mtp_meta
  MOVI r13,1
  CALL @mth_hyperedge_poincare128_curl
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @mtp_bad_geometry
  LD r8,r0,@mtp_record
  LD r9,r0,@mtp_meta
  LD r10,r9,0
  ST r10,r8,28      ; Poincare radius, not L
  LD r10,r9,1
  ST r10,r8,29      ; hyperbolic origin depth
  LD r10,r9,2
  ST r10,r8,30      ; signed L * radius, not intrinsic curvature
  ST r13,r8,31      ; native geometric coupling acceptance
  MOVI r1,1
  MOVI r2,128
  LD r3,r9,3
  MOVI r4,0
  JMP @mtp_return
mtp_bad:
  MOVI r4,1
  JMP @mtp_reject
mtp_stale:
  MOVI r4,2
  JMP @mtp_reject
mtp_bad_head:
  MOVI r4,3
  JMP @mtp_reject
mtp_bad_geometry:
  MOVI r4,4
mtp_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
mtp_return:
  MOVI r13,1
  LD r15,r0,@mtp_link
  RET
mtp_link:
  .word 0
mtp_record:
  .word 0
mtp_heads:
  .word 0
mtp_src:
  .word 0
mtp_dst:
  .word 0
mtp_hyper:
  .word 0
mtp_meta:
  .word 0
mtp_epoch:
  .word 0
mtp_acc:
  .word 0
