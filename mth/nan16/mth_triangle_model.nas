; Raw NaN16 triangle-shape model.
;
; Stats at 0x2E0200:
;   [tightness_mean_q8, area_mean_q8, count,
;    positive_orientation, negative_orientation]
;
; The banks keep Q8 running means rather than 32-bit sums.  A full N16TRI
; train pass has more than 100k rows; tightness/area sums overflow int32 long
; before that and silently corrupt every score.  Q8 means stay bounded, and
; rounded division removes the large freeze bias of integer Q0 means.
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

; r5=value, r11=old count, r12=new count, r13=mean_q8 address.
; Updates the Q8 mean in place.  Division is rounded to nearest so a large
; stream does not drift toward its first observations.
mth_tri_mean_q8_add:
  SHL r14,r5,8
  CMP r11,r0
  JMP[NE] @mth_tm_mean_update
  ST r14,r13,0
  RET
mth_tm_mean_update:
  LD r7,r13,0
  SUB r1,r14,r7
  CMPS r1,r0
  JMP[GE] @mth_tm_mean_abs
  SUB r1,r0,r1
mth_tm_mean_abs:
  DIV r8,r1,r12
  MOD r9,r1,r12
  SHL r9,r9,1
  CMP r9,r12
  JMP[LT] @mth_tm_mean_rounded
  ADDI r8,r8,1
mth_tm_mean_rounded:
  CMP r14,r7
  JMP[GE] @mth_tm_mean_inc
  SUB r7,r7,r8
  ST r7,r13,0
  RET
mth_tm_mean_inc:
  ADD r7,r7,r8
  ST r7,r13,0
  RET

mth_tri_model_observe:
  ; NaN16 CALL has no stack: save the caller's r15 before the helper calls.
  ADD r3,r15,r0
  MOVI r10,0x0200
  MOVHI r10,0x002E
  LD r11,r10,2
  ADDI r12,r11,1
  ADDI r13,r10,0
  CALL @mth_tri_mean_q8_add
  ADD r5,r4,r0
  ADDI r13,r10,1
  CALL @mth_tri_mean_q8_add
  ST r12,r10,2
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
  ADD r15,r3,r0
  RET

mth_tri_model_score:
  ; stored Q8 means: tightness at [0], area at [1]
  MOVI r10,0x0200
  MOVHI r10,0x002E
  LD r6,r10,2
  CMP r6,r0
  JMP[EQ] @mth_tm_score_empty
  LD r7,r10,0
  LD r8,r10,1
  ; deviation tightness (query and mean in Q8, then back to Q0)
  SHL r9,r5,8
  SUB r9,r9,r7
  CMPS r9,r0
  JMP[GE] @mth_tm_dt_abs
  SUB r9,r0,r9
mth_tm_dt_abs:
  SHR r9,r9,8
  ; deviation area
  SHL r11,r4,8
  SUB r11,r11,r8
  CMPS r11,r0
  JMP[GE] @mth_tm_da_abs
  SUB r11,r0,r11
mth_tm_da_abs:
  SHR r11,r11,8
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
  ADD r3,r15,r0
  MOVI r10,0x0210
  MOVHI r10,0x002E
  LD r11,r10,2
  ADDI r12,r11,1
  ADDI r13,r10,0
  CALL @mth_tri_mean_q8_add
  ADD r5,r4,r0
  ADDI r13,r10,1
  CALL @mth_tri_mean_q8_add
  ST r12,r10,2
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
  ADD r15,r3,r0
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

  ; positive Q8 means
  LD r8,r10,0
  LD r9,r10,1
  ; positive deviation
  SHL r12,r5,8
  SUB r12,r12,r8
  CMPS r12,r0
  JMP[GE] @mth_tmc_pd_t
  SUB r12,r0,r12
mth_tmc_pd_t:
  SHL r13,r4,8
  SUB r13,r13,r9
  CMPS r13,r0
  JMP[GE] @mth_tmc_pd_a
  SUB r13,r0,r13
mth_tmc_pd_a:
  ADD r12,r12,r13
  SHR r12,r12,8

  ; negative Q8 means
  LD r8,r11,0
  LD r9,r11,1
  SHL r13,r5,8
  SUB r13,r13,r8
  CMPS r13,r0
  JMP[GE] @mth_tmc_nd_t
  SUB r13,r0,r13
mth_tmc_nd_t:
  SHL r14,r4,8
  SUB r14,r14,r9
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
