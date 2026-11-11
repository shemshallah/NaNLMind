.org 0
JMP @mth_tc_main
.include "../nan16/mth_triangle_model.nas"

; Native contrastive triangle-bank fixture.
; Covers reset, positive/negative observation, contrastive scoring,
; positive-only fallback and the negative-only zero score.
mth_tc_main:
  MOVI r13,1
  CALL @mth_tri_model_reset

  ; Both banks start empty.
  MOVI r10,0x0200
  MOVHI r10,0x002E
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_tc_fail
  MOVI r10,0x0210
  MOVHI r10,0x002E
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_tc_fail

  ; Positive-like shape: sides 100,110,105 area 105 tightness 50000.
  MOVI r1,100
  MOVI r2,110
  MOVI r3,105
  MOVI r4,105
  MOVI r5,0xC350
  MOVHI r5,0x0000
  MOVI r6,1
  CALL @mth_tri_model_observe
  MOVI r12,1
  CMP r1,r12
  JMP[NE] @mth_tc_fail

  ; Negative-like shape: sides 300,310,305 area 305 tightness 20000.
  MOVI r1,300
  MOVI r2,310
  MOVI r3,305
  MOVI r4,305
  MOVI r5,20000
  MOVI r6,0xFFFF
  MOVHI r6,0xFFFF
  CALL @mth_tri_model_observe_negative
  MOVI r12,1
  CMP r1,r12
  JMP[NE] @mth_tc_fail

  ; A positive-like query must score above 60000.
  MOVI r4,105
  MOVI r5,0xC350
  MOVHI r5,0x0000
  CALL @mth_tri_model_score_contrast
  MOVI r12,0xEA60
  MOVHI r12,0x0000
  CMP r1,r12
  JMP[LE] @mth_tc_fail

  ; A negative-like query must score below 5000.
  MOVI r4,305
  MOVI r5,20000
  CALL @mth_tri_model_score_contrast
  MOVI r12,5000
  CMP r1,r12
  JMP[GE] @mth_tc_fail

  ; Reset must clear both banks.
  CALL @mth_tri_model_reset
  MOVI r10,0x0200
  MOVHI r10,0x002E
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_tc_fail
  MOVI r10,0x0210
  MOVHI r10,0x002E
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_tc_fail

  ; With no negative bank, contrastive scoring falls back to the
  ; positive-only shape score.
  MOVI r1,100
  MOVI r2,110
  MOVI r3,105
  MOVI r4,105
  MOVI r5,0xC350
  MOVHI r5,0x0000
  MOVI r6,1
  CALL @mth_tri_model_observe
  MOVI r4,105
  MOVI r5,0xC350
  MOVHI r5,0x0000
  CALL @mth_tri_model_score_contrast
  MOVI r12,0xEA60
  MOVHI r12,0x0000
  CMP r1,r12
  JMP[LE] @mth_tc_fail

  ; A negative-only bank cannot produce a positive contrastive score.
  CALL @mth_tri_model_reset
  MOVI r1,300
  MOVI r2,310
  MOVI r3,305
  MOVI r4,305
  MOVI r5,20000
  MOVI r6,0xFFFF
  MOVHI r6,0xFFFF
  CALL @mth_tri_model_observe_negative
  MOVI r4,305
  MOVI r5,20000
  CALL @mth_tri_model_score_contrast
  CMP r1,r0
  JMP[NE] @mth_tc_fail

  MOVI r1,@mth_tc_pass
  CALL @mth_tc_puts
  HALT

mth_tc_fail:
  MOVI r1,@mth_tc_bad
  CALL @mth_tc_puts
  HALT

mth_tc_puts:
  MOVI r13,1
  MOVI r4,255
mth_tc_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_tc_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_tc_puts_byte
  ADD r1,r1,r13
  JMP @mth_tc_puts_word

mth_tc_pass:
.str "MTH TRIANGLE CONTRAST PASS"
mth_tc_bad:
.str "MTH TRIANGLE CONTRAST FAIL"
