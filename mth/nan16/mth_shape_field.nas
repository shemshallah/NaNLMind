; Raw NaN16 shape-gated trihead field.
;
; Tables:
;   0x2F0000  85 triad vote masks
;   0x2F0100  85 triad tightness/quality Q16
;   0x2F0200  stats [triangles, positive, negative]
;
; A semantic word triangle is observed with:
;   r1=triad 0..84, r2=tightness, r3=orientation, r4=area
; It sets the triad's 2-of-3 vote and keeps its best shape quality.
;
; The final gate:
;   r1=path closure, r2=path length, r3=quality threshold (0 => mean)
; Returns r1=accepted triads, r2=field hot, r3=mean quality.

mth_tri_field_reset:
  MOVI r10,0x0000
  MOVHI r10,0x002F
  MOVI r11,0
  MOVI r12,85
mth_tf_reset_votes:
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_tf_reset_votes
  MOVI r10,0x0100
  MOVHI r10,0x002F
  MOVI r11,0
mth_tf_reset_quality:
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_tf_reset_quality
  MOVI r10,0x0200
  MOVHI r10,0x002F
  MOVI r11,0
  MOVI r12,3
mth_tf_reset_stats:
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_tf_reset_stats
  MOVI r1,0
  RET

mth_tri_field_observe:
  MOVI r10,0x0000
  MOVHI r10,0x002F
  ADD r11,r10,r1
  MOVI r12,7
  ST r12,r11,0
  MOVI r10,0x0100
  MOVHI r10,0x002F
  ADD r11,r10,r1
  LD r12,r11,0
  CMP r2,r12
  JMP[LE] @mth_tf_quality_done
  ST r2,r11,0
mth_tf_quality_done:
  MOVI r10,0x0200
  MOVHI r10,0x002F
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  CMPS r3,r0
  JMP[EQ] @mth_tf_stats_done
  MOVI r11,1
  JMP[GT] @mth_tf_pos
  LD r11,r10,2
  ADDI r11,r11,1
  ST r11,r10,2
  JMP @mth_tf_stats_done
mth_tf_pos:
  LD r11,r10,1
  ADDI r11,r11,1
  ST r11,r10,1
mth_tf_stats_done:
  MOVI r1,0
  RET

mth_shape_field_gate:
  MOVI r12,@mth_sf_link
  ST r15,r12,0
  MOVI r10,0x0100
  MOVHI r10,0x002F
  MOVI r11,0
  MOVI r12,85
  MOVI r13,0
  MOVI r14,0
mth_sf_mean_loop:
  CMP r11,r12
  JMP[GE] @mth_sf_mean_done
  ADD r15,r10,r11
  LD r15,r15,0
  CMP r15,r0
  JMP[EQ] @mth_sf_mean_next
  ADD r13,r13,r15
  ADDI r14,r14,1
mth_sf_mean_next:
  ADDI r11,r11,1
  JMP @mth_sf_mean_loop
mth_sf_mean_done:
  CMP r14,r0
  JMP[EQ] @mth_sf_empty
  DIV r13,r13,r14
  ; threshold r3==0 => mean
  CMP r3,r0
  JMP[NE] @mth_sf_threshold_ready
  ADD r3,r13,r0
mth_sf_threshold_ready:
  MOVI r10,0x0000
  MOVHI r10,0x002F
  MOVI r11,0
  MOVI r12,85
  MOVI r14,0
mth_sf_count_loop:
  CMP r11,r12
  JMP[GE] @mth_sf_count_done
  MOVI r10,0x0000
  MOVHI r10,0x002F
  ADD r15,r10,r11
  LD r15,r15,0
  ; vote mask must have at least two of three bits
  MOVI r9,7
  BOOL.3 r15,r15,r9
  MOVI r9,0
  MOVI r8,1
  BOOL.3 r9,r15,r8
  ADD r8,r9,r0
  MOVI r9,2
  BOOL.3 r9,r15,r9
  ADD r8,r8,r9
  MOVI r9,4
  BOOL.3 r9,r15,r9
  ADD r8,r8,r9
  MOVI r9,2
  CMP r8,r9
  JMP[LT] @mth_sf_count_next
  MOVI r10,0x0100
  MOVHI r10,0x002F
  ADD r15,r10,r11
  LD r15,r15,0
  CMP r15,r3
  JMP[LT] @mth_sf_count_next
  ADDI r14,r14,1
mth_sf_count_next:
  ADDI r11,r11,1
  JMP @mth_sf_count_loop
mth_sf_count_done:
  ; closure gate: closure*2 <= path length (when path exists)
  CMP r2,r0
  JMP[EQ] @mth_sf_no_closure
  MOVI r9,2
  MUL r1,r1,r9
  CMP r1,r2
  JMP[GT] @mth_sf_no_field
mth_sf_no_closure:
  MOVI r9,43
  CMP r14,r9
  JMP[LT] @mth_sf_no_field
  MOVI r2,1
  ADD r1,r14,r0
  ADD r3,r13,r0
  MOVI r12,@mth_sf_link
  LD r15,r12,0
  RET
mth_sf_no_field:
  MOVI r1,0
  MOVI r2,0
  ADD r3,r13,r0
  MOVI r12,@mth_sf_link
  LD r15,r12,0
  RET
mth_sf_empty:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r12,@mth_sf_link
  LD r15,r12,0
  RET

mth_sf_link:
  .word 0
