; NaN16 credit -> triad (2/3) -> field (43/85) vote.
;
; ABI:
;   r1 = pointer to 255 signed Q16.16 head credits
;   r2 = signed Q16.16 head threshold
;   r3 = pointer to 85 output triad votes (one word each)
; Returns:
;   r1 = accepted triad count
;   r2 = 1 when at least 43 triads accept
;
; Triad membership is the fixed 255-head partition 3t,3t+1,3t+2 in this
; primitive.  The adaptive Universe mapping remains the chart's authority; a
; later ABI adds the mapping pointer.  No host Boolean arithmetic is used.
mth_credit_field:
  MOVI r12,@mth_cf_link
  ST r15,r12,0
  MOVI r12,@mth_cf_credits
  ST r1,r12,0
  MOVI r12,@mth_cf_threshold
  ST r2,r12,0
  MOVI r12,@mth_cf_votes
  ST r3,r12,0

  MOVI r7,0               ; accepted triads
  MOVI r6,0               ; triad index
mth_cf_triad:
  MOVI r12,85
  CMP r6,r12
  JMP[GE] @mth_cf_done
  MOVI r12,3
  MUL r9,r6,r12
  MOVI r12,@mth_cf_credits
  LD r10,r12,0
  ADD r10,r10,r9
  MOVI r8,0               ; member votes
  MOVI r12,@mth_cf_threshold
  LD r11,r12,0

  LD r13,r10,0
  CMPS r13,r11
  JMP[LE] @mth_cf_m1
  ADDI r8,r8,1
mth_cf_m1:
  ADDI r10,r10,1
  LD r13,r10,0
  CMPS r13,r11
  JMP[LE] @mth_cf_m2
  ADDI r8,r8,1
mth_cf_m2:
  ADDI r10,r10,1
  LD r13,r10,0
  CMPS r13,r11
  JMP[LE] @mth_cf_vote
  ADDI r8,r8,1
mth_cf_vote:
  MOVI r12,0
  CMPS r8,r12
  MOVI r13,0
  JMP[EQ] @mth_cf_store
  MOVI r12,2
  CMPS r8,r12
  JMP[LT] @mth_cf_store
  MOVI r13,1
  ADDI r7,r7,1
mth_cf_store:
  MOVI r12,@mth_cf_votes
  LD r10,r12,0
  ADD r10,r10,r6
  ST r13,r10,0
  ADDI r6,r6,1
  JMP @mth_cf_triad
mth_cf_done:
  MOVI r12,43
  CMPS r7,r12
  MOVI r2,0
  JMP[LT] @mth_cf_out
  MOVI r2,1
mth_cf_out:
  ADD r1,r7,r0
  MOVI r13,1
  MOVI r12,@mth_cf_link
  LD r15,r12,0
  RET
mth_cf_link:
  .word 0
mth_cf_credits:
  .word 0
mth_cf_threshold:
  .word 0
mth_cf_votes:
  .word 0
