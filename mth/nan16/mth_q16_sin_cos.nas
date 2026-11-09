; NaN16 Q16.16 sine/cosine (CORDIC, 16 iterations).
;
; ABI:
;   r1 = angle in 16-bit turn units (0..65535)
; Returns:
;   r1 = cos(angle), Q16.16, approximately +/-65536
;   r2 = sin(angle), Q16.16
; Clobbers r3-r9. Preserves r0, r10-r15.
; Runtime arithmetic is integer shifts/adds/subtracts only.

mth_q16_sin_cos:
  MOVI r8,1
  MOVI r9,1
  MOVI r5,0x8000
  CMP r1,r5
  JMP[LT] @mth_q16_no_half
  SUB r1,r1,r5
  SUB r8,r0,r8
  SUB r9,r0,r9
mth_q16_no_half:
  MOVI r5,0x4000
  CMP r1,r5
  JMP[LT] @mth_q16_reduced
  MOVI r5,0x8000
  SUB r1,r5,r1
  SUB r9,r0,r9
mth_q16_reduced:
  MOVI r2,39797
  MOVI r3,0
  ADD r4,r1,r0
  SAR r5,r2,0
  SAR r6,r3,0
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_0
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,8192
  SUB r4,r4,r7
  JMP @mth_q16_done_0
mth_q16_neg_0:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,8192
  ADD r4,r4,r7
mth_q16_done_0:
  SAR r5,r2,1
  SAR r6,r3,1
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_1
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,4836
  SUB r4,r4,r7
  JMP @mth_q16_done_1
mth_q16_neg_1:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,4836
  ADD r4,r4,r7
mth_q16_done_1:
  SAR r5,r2,2
  SAR r6,r3,2
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_2
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,2555
  SUB r4,r4,r7
  JMP @mth_q16_done_2
mth_q16_neg_2:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,2555
  ADD r4,r4,r7
mth_q16_done_2:
  SAR r5,r2,3
  SAR r6,r3,3
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_3
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,1297
  SUB r4,r4,r7
  JMP @mth_q16_done_3
mth_q16_neg_3:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,1297
  ADD r4,r4,r7
mth_q16_done_3:
  SAR r5,r2,4
  SAR r6,r3,4
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_4
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,651
  SUB r4,r4,r7
  JMP @mth_q16_done_4
mth_q16_neg_4:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,651
  ADD r4,r4,r7
mth_q16_done_4:
  SAR r5,r2,5
  SAR r6,r3,5
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_5
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,326
  SUB r4,r4,r7
  JMP @mth_q16_done_5
mth_q16_neg_5:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,326
  ADD r4,r4,r7
mth_q16_done_5:
  SAR r5,r2,6
  SAR r6,r3,6
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_6
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,163
  SUB r4,r4,r7
  JMP @mth_q16_done_6
mth_q16_neg_6:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,163
  ADD r4,r4,r7
mth_q16_done_6:
  SAR r5,r2,7
  SAR r6,r3,7
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_7
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,81
  SUB r4,r4,r7
  JMP @mth_q16_done_7
mth_q16_neg_7:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,81
  ADD r4,r4,r7
mth_q16_done_7:
  SAR r5,r2,8
  SAR r6,r3,8
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_8
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,41
  SUB r4,r4,r7
  JMP @mth_q16_done_8
mth_q16_neg_8:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,41
  ADD r4,r4,r7
mth_q16_done_8:
  SAR r5,r2,9
  SAR r6,r3,9
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_9
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,20
  SUB r4,r4,r7
  JMP @mth_q16_done_9
mth_q16_neg_9:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,20
  ADD r4,r4,r7
mth_q16_done_9:
  SAR r5,r2,10
  SAR r6,r3,10
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_10
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,10
  SUB r4,r4,r7
  JMP @mth_q16_done_10
mth_q16_neg_10:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,10
  ADD r4,r4,r7
mth_q16_done_10:
  SAR r5,r2,11
  SAR r6,r3,11
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_11
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,5
  SUB r4,r4,r7
  JMP @mth_q16_done_11
mth_q16_neg_11:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,5
  ADD r4,r4,r7
mth_q16_done_11:
  SAR r5,r2,12
  SAR r6,r3,12
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_12
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,3
  SUB r4,r4,r7
  JMP @mth_q16_done_12
mth_q16_neg_12:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,3
  ADD r4,r4,r7
mth_q16_done_12:
  SAR r5,r2,13
  SAR r6,r3,13
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_13
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,1
  SUB r4,r4,r7
  JMP @mth_q16_done_13
mth_q16_neg_13:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,1
  ADD r4,r4,r7
mth_q16_done_13:
  SAR r5,r2,14
  SAR r6,r3,14
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_14
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,1
  SUB r4,r4,r7
  JMP @mth_q16_done_14
mth_q16_neg_14:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,1
  ADD r4,r4,r7
mth_q16_done_14:
  SAR r5,r2,15
  SAR r6,r3,15
  CMPS r4,r0
  JMP[LT] @mth_q16_neg_15
  SUB r2,r2,r6
  ADD r3,r3,r5
  MOVI r7,0
  SUB r4,r4,r7
  JMP @mth_q16_done_15
mth_q16_neg_15:
  ADD r2,r2,r6
  SUB r3,r3,r5
  MOVI r7,0
  ADD r4,r4,r7
mth_q16_done_15:
  CMPS r8,r0
  JMP[GE] @mth_q16_sin_positive
  SUB r3,r0,r3
mth_q16_sin_positive:
  CMPS r9,r0
  JMP[GE] @mth_q16_cos_positive
  SUB r2,r0,r2
mth_q16_cos_positive:
  ADD r1,r2,r0
  ADD r2,r3,r0
  RET
