; Raw NaN16 geometry for the 256-dimensional phase-vector layer.
;
; mth_geom_hyperbolic:
;   r1=vector[D], r2=D -> r1=mean L1 radius Q16, r2=Poincare radial proxy Q16.
;   The radial proxy is monotone: larger mean -> further out along the ray.
;
; mth_geom_path:
;   r1=vector bank N*D, r2=N, r3=D
;   -> r1=path length Q16, r2=closure Q16,
;      r3=turn/second-difference Q16, r4=curvature proxy Q16.
;
; mth_geom_triangle:
;   r1=three vectors [v0,v1,v2], r2=D
;   -> r1..r3 side L1 distances, r4=area proxy, r5=tightness Q16,
;      r6=orientation sign (first two coordinate deltas).
;
; mth_geom_field_perturb:
;   r1=vector, r2=D -> credits[255] at 0x2E0000, triad votes[85] at 0x2E0100.
;   Returns the head-255/current component.

mth_geom_hyperbolic:
  MOVI r12,@mth_g_ptr
  ST r1,r12,0
  MOVI r12,@mth_g_dim
  ST r2,r12,0
  MOVI r5,0
  MOVI r6,0
mth_g_hyp_loop:
  CMP r5,r2
  JMP[GE] @mth_g_hyp_done
  ADD r7,r1,r5
  LD r7,r7,0
  CMPS r7,r0
  JMP[GE] @mth_g_hyp_abs
  SUB r7,r0,r7
mth_g_hyp_abs:
  ADD r6,r6,r7
  ADDI r5,r5,1
  JMP @mth_g_hyp_loop
mth_g_hyp_done:
  DIV r6,r6,r2
  MOVI r7,0
  MOVHI r7,0x0001
  MOVI r8,32767
  CMP r6,r8
  JMP[GT] @mth_g_hyp_sat
  MUL r7,r6,r7
  MOVI r8,0
  MOVHI r8,0x0001
  ADD r8,r6,r8
  DIV r7,r7,r8
  ADD r2,r7,r0
  ADD r1,r6,r0
  RET
mth_g_hyp_sat:
  MOVI r2,0
  MOVHI r2,0x0001
  ADD r1,r6,r0
  RET

mth_geom_path:
  MOVI r12,@mth_g_path_link
  ST r15,r12,0
  MOVI r12,@mth_g_ptr
  ST r1,r12,0
  MOVI r12,@mth_g_n
  ST r2,r12,0
  MOVI r12,@mth_g_dim
  ST r3,r12,0
  MOVI r5,0
  MOVI r6,0
mth_g_path_step:
  ADDI r8,r2,-1
  CMP r5,r8
  JMP[GE] @mth_g_path_length
  MOVI r11,0
  MUL r9,r5,r3
  ADDI r10,r5,1
  MUL r10,r10,r3
mth_g_path_d:
  CMP r11,r3
  JMP[GE] @mth_g_path_next
  ADD r12,r9,r11
  ADD r12,r1,r12
  LD r12,r12,0
  ADD r13,r10,r11
  ADD r13,r1,r13
  LD r13,r13,0
  SUB r13,r13,r12
  CMPS r13,r0
  JMP[GE] @mth_g_path_abs
  SUB r13,r0,r13
mth_g_path_abs:
  ADD r6,r6,r13
  ADDI r11,r11,1
  JMP @mth_g_path_d
mth_g_path_next:
  ADDI r5,r5,1
  JMP @mth_g_path_step
mth_g_path_length:
  DIV r1,r6,r3
  ; closure on first/last vectors
  MOVI r12,@mth_g_ptr
  LD r10,r12,0
  MOVI r12,@mth_g_n
  LD r7,r12,0
  ADDI r7,r7,-1
  MUL r7,r7,r3
  MOVI r5,0
  MOVI r6,0
mth_g_close_d:
  CMP r5,r3
  JMP[GE] @mth_g_close_done
  ADD r8,r10,r5
  LD r8,r8,0
  ADD r9,r7,r5
  ADD r9,r10,r9
  LD r9,r9,0
  SUB r9,r9,r8
  CMPS r9,r0
  JMP[GE] @mth_g_close_abs
  SUB r9,r0,r9
mth_g_close_abs:
  ADD r6,r6,r9
  ADDI r5,r5,1
  JMP @mth_g_close_d
mth_g_close_done:
  DIV r2,r6,r3
  ; turn proxy: sum |v[i+1] - 2*v[i] + v[i-1]|
  MOVI r5,1
  MOVI r6,0
  MOVI r12,@mth_g_ptr
  LD r10,r12,0
mth_g_turn_step:
  MOVI r12,@mth_g_n
  LD r7,r12,0
  ADDI r7,r7,-1
  CMP r5,r7
  JMP[GE] @mth_g_turn_done
  MOVI r12,@mth_g_ptr
  LD r9,r12,0
  MOVI r11,0
  MUL r10,r5,r3
mth_g_turn_d:
  CMP r11,r3
  JMP[GE] @mth_g_turn_next
  ADD r12,r10,r11
  ADD r12,r9,r12
  LD r12,r12,0
  SHL r12,r12,1
  ADDI r13,r10,-1
  ADD r13,r13,r11
  ADD r13,r9,r13
  LD r13,r13,0
  SUB r12,r12,r13
  ADDI r13,r10,1
  ADD r13,r13,r11
  ADD r13,r9,r13
  LD r13,r13,0
  ADD r12,r12,r13
  CMPS r12,r0
  JMP[GE] @mth_g_turn_abs
  SUB r12,r0,r12
mth_g_turn_abs:
  ADD r6,r6,r12
  ADDI r11,r11,1
  JMP @mth_g_turn_d
mth_g_turn_next:
  ADDI r5,r5,1
  JMP @mth_g_turn_step
mth_g_turn_done:
  DIV r3,r6,r3
  MOVI r7,1
  ADD r7,r1,r7
  DIV r4,r3,r7
  MOVI r12,@mth_g_path_link
  LD r15,r12,0
  RET

mth_geom_triangle:
  MOVI r12,@mth_g_tri_link
  ST r15,r12,0
  MOVI r12,@mth_g_ptr
  ST r1,r12,0
  MOVI r12,@mth_g_dim
  ST r2,r12,0
  ; data side sums in mth_g_side[0..2]
  MOVI r5,0
mth_g_tri_pair:
  MOVI r8,3
  CMP r5,r8
  JMP[GE] @mth_g_tri_sides
  MOVI r6,0
  MOVI r7,0
  MUL r9,r5,r2
  ADDI r10,r5,1
  MOVI r8,3
  MODU r10,r10,r8
  MUL r10,r10,r2
mth_g_tri_d:
  CMP r7,r2
  JMP[GE] @mth_g_tri_store
  ADD r11,r9,r7
  ADD r11,r1,r11
  LD r11,r11,0
  ADD r12,r10,r7
  ADD r12,r1,r12
  LD r12,r12,0
  SUB r12,r12,r11
  CMPS r12,r0
  JMP[GE] @mth_g_tri_abs
  SUB r12,r0,r12
mth_g_tri_abs:
  ADD r6,r6,r12
  ADDI r7,r7,1
  JMP @mth_g_tri_d
mth_g_tri_store:
  DIV r6,r6,r2
  MOVI r11,@mth_g_side
  ADD r11,r11,r5
  ST r6,r11,0
  ADDI r5,r5,1
  JMP @mth_g_tri_pair
mth_g_tri_sides:
  MOVI r11,@mth_g_side
  LD r1,r11,0
  LD r2,r11,1
  LD r3,r11,2
  ; tightness = min(side)/max(side)
  MOVI r4,0xFFFF
  MOVHI r4,0x7FFF
  MOVI r5,0
  MOVI r6,0
mth_g_tri_mm:
  MOVI r8,3
  CMP r6,r8
  JMP[GE] @mth_g_tri_tight
  ADD r9,r11,r6
  LD r9,r9,0
  CMP r9,r4
  JMP[GE] @mth_g_tri_mm_skipmin
  ADD r4,r9,r0
mth_g_tri_mm_skipmin:
  CMP r9,r5
  JMP[LE] @mth_g_tri_mm_skipmax
  ADD r5,r9,r0
mth_g_tri_mm_skipmax:
  ADDI r6,r6,1
  JMP @mth_g_tri_mm
mth_g_tri_tight:
  ; r4 currently min side; r5 currently max side
  MOVI r7,0
  CMP r5,r7
  JMP[EQ] @mth_g_tri_zero
  MOVI r6,0
  MOVHI r6,0x0001
  MUL r6,r4,r6
  DIV r6,r6,r5
  ADD r5,r6,r0
  ; area proxy = min side scaled by tightness; r4 stays min side
  JMP @mth_g_tri_orientation
mth_g_tri_zero:
  MOVI r4,0
  MOVI r5,0
mth_g_tri_orientation:
  MOVI r12,@mth_g_ptr
  LD r9,r12,0
  MOVI r12,@mth_g_dim
  LD r8,r12,0
  ADDI r8,r8,-1
  MOVI r10,0
  MOVI r12,@mth_g_osum
  ST r0,r12,0
mth_g_orient_d:
  CMP r10,r8
  JMP[GE] @mth_g_orient_done_sum
  MOVI r12,@mth_g_dim
  LD r6,r12,0
  ; v0d / v0d+1
  ADD r11,r9,r10
  LD r7,r11,0
  MOVI r12,@mth_g_a
  ST r7,r12,0
  ADDI r11,r11,1
  LD r7,r11,0
  MOVI r12,@mth_g_b
  ST r7,r12,0
  ; v1d / v1d+1
  ADD r11,r9,r6
  ADD r11,r11,r10
  LD r11,r11,0
  ADDI r11,r11,0
  ; reload v1d+1 separately
  ADD r12,r9,r6
  ADD r12,r12,r10
  LD r12,r12,0          ; v1d
  ; store v1d in data
  MOVI r7,@mth_g_c
  ST r12,r7,0
  MOVI r7,@mth_g_dim
  LD r7,r7,0
  ADD r12,r9,r7
  ADD r12,r12,r10
  ADDI r12,r12,1
  LD r12,r12,0          ; v1d+1
  ; v2d / v2d+1
  MOVI r7,@mth_g_dim
  LD r7,r7,0
  ADD r13,r9,r7
  ADD r13,r13,r7
  ADD r13,r13,r10
  LD r13,r13,0          ; v2d
  ADDI r13,r13,1
  ; reload v2d+1
  MOVI r7,@mth_g_dim
  LD r7,r7,0
  ADD r14,r9,r7
  ADD r14,r14,r7
  ADD r14,r14,r10
  ADDI r14,r14,1
  LD r14,r14,0          ; v2d+1
  ; term = (v1d-a)*(v2d1-b) - (v1d1-b)*(v2d-a)
  MOVI r7,@mth_g_a
  LD r15,r7,0
  SUB r11,r11,r15       ; v1d - a (r11 currently v1d? loaded then overwritten)
  ; r11 may be v1d from above; ensure
  MOVI r7,@mth_g_dim
  LD r7,r7,0
  ADD r11,r9,r7
  ADD r11,r11,r10
  LD r11,r11,0
  MOVI r7,@mth_g_a
  LD r15,r7,0
  SUB r11,r11,r15
  MOVI r7,@mth_g_b
  LD r15,r7,0
  SUB r14,r14,r15
  MUL r11,r11,r14
  ; term2
  MOVI r7,@mth_g_b
  LD r15,r7,0
  SUB r12,r12,r15
  MOVI r7,@mth_g_dim
  LD r7,r7,0
  ADD r13,r9,r7
  ADD r13,r13,r7
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r7,@mth_g_a
  LD r15,r7,0
  SUB r13,r13,r15
  MUL r12,r12,r13
  SUB r11,r11,r12
  MOVI r7,@mth_g_osum
  LD r12,r7,0
  ADD r12,r12,r11
  ST r12,r7,0
  ADDI r10,r10,1
  JMP @mth_g_orient_d
mth_g_orient_done_sum:
  MOVI r7,@mth_g_osum
  LD r11,r7,0
  MOVI r6,0
  CMP r11,r0
  JMP[EQ] @mth_g_tri_orient_done
  MOVI r6,1
  JMP[GT] @mth_g_tri_orient_done
  MOVI r6,-1
mth_g_tri_orient_done:
  MOVI r12,@mth_g_tri_link
  LD r15,r12,0
  RET

mth_geom_field_perturb:
  MOVI r12,@mth_g_field_link
  ST r15,r12,0
  MOVI r12,@mth_g_ptr
  ST r1,r12,0
  MOVI r12,@mth_g_dim
  ST r2,r12,0
  MOVI r10,0x0000
  MOVHI r10,0x002E
  MOVI r5,0
  MOVI r6,0
mth_g_field_loop:
  CMP r5,r2
  JMP[GE] @mth_g_field_votes
  MOVI r8,255
  CMP r5,r8
  JMP[GE] @mth_g_field_next
  ADD r7,r1,r5
  LD r7,r7,0
  CMPS r7,r0
  JMP[GE] @mth_g_field_abs
  SUB r7,r0,r7
mth_g_field_abs:
  ADD r6,r6,r7
  ADD r9,r10,r5
  ST r7,r9,0
mth_g_field_next:
  ADDI r5,r5,1
  JMP @mth_g_field_loop
mth_g_field_votes:
  MOVI r12,@mth_g_energy
  ST r6,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x002E
  MOVI r5,0
  MOVI r10,0x0000
  MOVHI r10,0x002E
mth_g_vote_loop:
  MOVI r8,85
  CMP r5,r8
  JMP[GE] @mth_g_field_return
  MOVI r8,3
  MUL r9,r5,r8
  MOVI r6,0
  MOVI r7,0
mth_g_vote_member:
  CMP r7,r8
  JMP[GE] @mth_g_vote_store
  ADD r11,r9,r7
  ADD r11,r10,r11
  LD r11,r11,0
  CMP r11,r0
  JMP[EQ] @mth_g_vote_skip
  ADDI r6,r6,1
mth_g_vote_skip:
  ADDI r7,r7,1
  JMP @mth_g_vote_member
mth_g_vote_store:
  MOVI r7,0
  MOVI r8,3
  CMP r6,r8
  JMP[LT] @mth_g_vote_put
  MOVI r7,7
mth_g_vote_put:
  ADD r11,r12,r5
  ST r7,r11,0
  ADDI r5,r5,1
  JMP @mth_g_vote_loop
mth_g_field_return:
  MOVI r1,0
  MOVI r9,255
  MOVI r12,@mth_g_dim
  LD r8,r12,0
  CMP r8,r9
  JMP[LE] @mth_g_field_mean
  MOVI r12,@mth_g_ptr
  LD r8,r12,0
  ADD r8,r8,r9
  LD r1,r8,0
  CMP r1,r0
  JMP[NE] @mth_g_field_out
mth_g_field_mean:
  MOVI r12,@mth_g_energy
  LD r1,r12,0
  MOVI r12,@mth_g_dim
  LD r8,r12,0
  DIV r1,r1,r8
mth_g_field_out:
  MOVI r12,@mth_g_field_link
  LD r15,r12,0
  RET

mth_g_path_link:
  .word 0
mth_g_tri_link:
  .word 0
mth_g_field_link:
  .word 0
mth_g_ptr:
  .word 0
mth_g_dim:
  .word 0
mth_g_n:
  .word 0
mth_g_iside:
  .word 0
mth_g_v0x:
  .word 0
mth_g_v0y:
  .word 0
mth_g_v1x:
  .word 0
mth_g_v1y:
  .word 0
mth_g_v2x:
  .word 0
mth_g_v2y:
  .word 0
mth_g_a:
  .word 0
mth_g_b:
  .word 0
mth_g_c:
  .word 0
mth_g_osum:
  .word 0
mth_g_side:
  .word 0
mth_g_energy:
  .word 0
