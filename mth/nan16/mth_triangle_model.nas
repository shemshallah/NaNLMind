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
  ; Clear both banks and the reserved gap between them:
  ; 0x2E0200..0x2E0204 positive, 0x2E0210..0x2E0214 negative.
  MOVI r12,21
  MOVI r14,0
mth_tm_reset_loop:
  CMP r11,r12
  JMP[GE] @mth_tm_reset_done
  ADD r13,r10,r11
  ST r14,r13,0
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
  ; orientation is signed: negative orientation is a real class.
  CMPS r6,r0
  JMP[EQ] @mth_tm_obs_done
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

; Negative-shape observer. ABI mirrors mth_tri_model_observe, but accumulates
; the negative bank at 0x2E0210.
mth_tri_model_observe_negative:
  MOVI r10,0x0210
  MOVHI r10,0x002E
  LD r11,r10,0
  ADD r11,r11,r5
  ST r11,r10,0
  LD r11,r10,1
  ADD r11,r11,r4
  ST r11,r10,1
  LD r11,r10,2
  ADDI r11,r11,1
  ST r11,r10,2
  CMPS r6,r0
  JMP[EQ] @mth_tmn_obs_done
  JMP[GT] @mth_tmn_obs_pos
  LD r11,r10,4
  ADDI r11,r11,1
  ST r11,r10,4
  JMP @mth_tmn_obs_done
mth_tmn_obs_pos:
  LD r11,r10,3
  ADDI r11,r11,1
  ST r11,r10,3
mth_tmn_obs_done:
  LD r1,r10,2
  RET

; Contrastive shape score: closer to positive shape than negative shape.
; ABI: r1..r3 sides (unused), r4 area, r5 tightness.
; Returns r1 = Q16 score, 65536 when strongly positive-like.
mth_tri_model_score_contrast:
  MOVI r10,0x0200
  MOVHI r10,0x002E
  MOVI r11,0x0210
  MOVHI r11,0x002E
  LD r6,r10,2
  LD r7,r11,2
  CMP r6,r0
  JMP[EQ] @mth_tmc_no_positive
  CMP r7,r0
  JMP[EQ] @mth_tmc_no_negative

  ; positive means
  LD r8,r10,0
  DIV r8,r8,r6
  LD r9,r10,1
  DIV r9,r9,r6
  ; positive deviation
  SUB r12,r5,r8
  CMPS r12,r0
  JMP[GE] @mth_tmc_pd_t
  SUB r12,r0,r12
mth_tmc_pd_t:
  SUB r13,r4,r9
  CMPS r13,r0
  JMP[GE] @mth_tmc_pd_a
  SUB r13,r0,r13
mth_tmc_pd_a:
  ADD r12,r12,r13
  SHR r12,r12,8

  ; negative means
  LD r8,r11,0
  DIV r8,r8,r7
  LD r9,r11,1
  DIV r9,r9,r7
  SUB r13,r5,r8
  CMPS r13,r0
  JMP[GE] @mth_tmc_nd_t
  SUB r13,r0,r13
mth_tmc_nd_t:
  SUB r14,r4,r9
  CMPS r14,r0
  JMP[GE] @mth_tmc_nd_a
  SUB r14,r0,r14
mth_tmc_nd_a:
  ADD r13,r13,r14
  SHR r13,r13,8

  ; score = 65536 * d_neg / (d_pos + d_neg + 1).
  ; Keep the denominator unscaled, then scale the numerator once.
  ADD r14,r12,r13
  ADDI r14,r14,1
  MOVI r8,0
  MOVHI r8,0x0001
  MUL r13,r13,r8
  DIV r1,r13,r14
  RET
mth_tmc_no_positive:
  MOVI r1,0
  RET
mth_tmc_no_negative:
  ; Until negatives exist, retain the positive-only shape score.
  JMP @mth_tri_model_score
