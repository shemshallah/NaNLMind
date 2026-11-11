; Raw NaN16 semantic-triangle -> simplicial pair-flow builder.
; ABI:
;   r1 = triads[16][3] (a,b,c), r2=count 0..16, r3=pair_flow[32640] f32,
;   r4 = weight bits (f32)
; Returns r1=1 success, r9=0; r1=0,r9=1 on invalid triangle.
; Head 255 is void and is rejected. It only builds flows; Hodge consumes them.

mth_triangle_flow_build:
  MOVI r0,0
  ST r15,r0,@mth_tf_link
  MOVI r10,0
mth_tf_clear:
  MOVI r12,32640
  CMP r10,r12
  JMP[GE] @mth_tf_start
  ADD r11,r3,r10
  ST r0,r11,0
  ADDI r10,r10,1
  JMP @mth_tf_clear
mth_tf_start:
  MOVI r12,@mth_tf_i
  ST r0,r12,0
mth_tf_tri_loop:
  MOVI r12,@mth_tf_i
  LD r5,r12,0
  CMP r5,r2
  JMP[GE] @mth_tf_ok
  MOVI r6,3
  MUL r6,r5,r6
  ADD r6,r1,r6
  LD r7,r6,0
  LD r8,r6,1
  LD r9,r6,2
  MOVI r12,@mth_tf_a
  ST r7,r12,0
  MOVI r12,@mth_tf_b
  ST r8,r12,0
  MOVI r12,@mth_tf_c
  ST r9,r12,0
  MOVI r12,255
  CMP r7,r12
  JMP[EQ] @mth_tf_reject
  CMP r8,r12
  JMP[EQ] @mth_tf_reject
  CMP r9,r12
  JMP[EQ] @mth_tf_reject
  CMP r7,r8
  JMP[EQ] @mth_tf_reject
  CMP r7,r9
  JMP[EQ] @mth_tf_reject
  CMP r8,r9
  JMP[EQ] @mth_tf_reject
  ; edge (a,b), then (b,c), (c,a)
  MOVI r12,@mth_tf_a
  LD r10,r12,0
  MOVI r12,@mth_tf_b
  LD r11,r12,0
  CALL @mth_tf_edge
  MOVI r12,@mth_tf_b
  LD r10,r12,0
  MOVI r12,@mth_tf_c
  LD r11,r12,0
  CALL @mth_tf_edge
  MOVI r12,@mth_tf_c
  LD r10,r12,0
  MOVI r12,@mth_tf_a
  LD r11,r12,0
  CALL @mth_tf_edge
  MOVI r12,@mth_tf_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_tf_tri_loop
mth_tf_ok:
  MOVI r1,1
  ST r1,r0,@mth_tf_status
  LD r15,r0,@mth_tf_link
  RET
mth_tf_reject:
  MOVI r1,0
  MOVI r9,1
  ST r9,r0,@mth_tf_status
  LD r15,r0,@mth_tf_link
  RET

; r10=u, r11=v, r4=weight; adds oriented flow into r3.
mth_tf_edge:
  MOVI r5,0
  CMP r10,r11
  JMP[LT] @mth_tf_edge_sorted
  ADD r6,r10,r0
  ADD r10,r11,r0
  ADD r11,r6,r0
  MOVI r5,1
mth_tf_edge_sorted:
  MOVI r6,511
  SUB r6,r6,r10
  MUL r6,r6,r10
  SHR r6,r6,1
  SUB r7,r11,r10
  ADDI r7,r7,-1
  ADD r6,r6,r7
  ; pair_flow is one word per pair in this footprint
  ADD r6,r3,r6
  ; r4 is float weight bits
  LD r7,r6,0
  CMP r5,r0
  JMP[EQ] @mth_tf_add
  FSUB r7,r7,r4
  JMP @mth_tf_store
mth_tf_add:
  FADD r7,r7,r4
mth_tf_store:
  ST r7,r6,0
  RET

mth_tf_link:
  .word 0
mth_tf_i:
  .word 0
mth_tf_status:
  .word 0
mth_tf_a:
  .word 0
mth_tf_b:
  .word 0
mth_tf_c:
  .word 0
