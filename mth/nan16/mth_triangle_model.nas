; Raw NaN16 triangle-shape model.
;
; Stats at 0x2E0200:
;   [tightness_sum, area_sum, count, positive_orientation, negative_orientation]
;
; observe: r1=side0,r2=side1,r3=side2,r4=area,r5=tightness,r6=orientation
; score:   r1=side0,r2=side1,r3=side2,r4=area,r5=tightness -> r1=score Q16

mth_tri_model_reset:
  MOVI r10,0x0200
  MOVHI r10,0x002E
  MOVI r11,0
  MOVI r12,5
mth_tm_reset_loop:
  CMP r11,r12
  JMP[GE] @mth_tm_reset_done
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  JMP @mth_tm_reset_loop
mth_tm_reset_done:
  MOVI r1,0
  RET

mth_tri_model_observe:
  MOVI r10,0x0200
  MOVHI r10,0x002E
  ; tightness sum
  LD r11,r10,0
  ADD r11,r11,r5
  ST r11,r10,0
  ; area sum
  LD r11,r10,1
  ADD r11,r11,r4
  ST r11,r10,1
  ; count
  LD r11,r10,2
  ADDI r11,r11,1
  ST r11,r10,2
  ; orientation
  CMP r6,r0
  JMP[EQ] @mth_tm_obs_done
  MOVI r12,1
  JMP[GT] @mth_tm_obs_pos
  LD r11,r10,4
  ADDI r11,r11,1
  ST r11,r10,4
  JMP @mth_tm_obs_done
mth_tm_obs_pos:
  LD r11,r10,3
  ADDI r11,r11,1
  ST r11,r10,3
mth_tm_obs_done:
  LD r1,r10,2
  RET

mth_tri_model_score:
  ; mean tightness/area
  MOVI r10,0x0200
  MOVHI r10,0x002E
  LD r6,r10,2
  CMP r6,r0
  JMP[EQ] @mth_tm_score_empty
  LD r7,r10,0
  DIV r7,r7,r6
  LD r8,r10,1
  DIV r8,r8,r6
  ; deviation tightness
  SUB r9,r5,r7
  CMPS r9,r0
  JMP[GE] @mth_tm_dt_abs
  SUB r9,r0,r9
mth_tm_dt_abs:
  ; deviation area
  SUB r11,r4,r8
  CMPS r11,r0
  JMP[GE] @mth_tm_da_abs
  SUB r11,r0,r11
mth_tm_da_abs:
  ; score = 65536 / (1 + dt + da)
  ADD r12,r9,r11
  ADDI r12,r12,1
  MOVI r13,0
  MOVHI r13,0x0001
  DIV r1,r13,r12
  RET
mth_tm_score_empty:
  MOVI r1,0
  RET
