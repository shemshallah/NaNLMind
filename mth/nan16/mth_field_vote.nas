; NaN16 field vote over 85 triads.
;
; ABI:
;   r1 = pointer to 85 32-bit words; low 3 bits of each word are the triad vote
;   r2 = number of triads (normally 85)
; Returns:
;   r1 = number of triads with at least two approving members
;   r2 = 1 when count >= 43 (the one-field majority), else 0

mth_field_vote:
  MOVI r9,@mth_field_vote_link
  ST r15,r9,0
  ADD r11,r1,r0
  ADD r10,r2,r0
  MOVI r12,0
  MOVI r13,1

mth_field_loop:
  CMP r10,r0
  JMP[EQ] @mth_field_done
  LD r3,r11,0
  MOVI r4,7
  BOOL.8 r3,r3,r4
  ADD r1,r3,r0
  CALL @mth_bool_popcount3
  MOVI r4,2
  CMP r2,r4
  JMP[LT] @mth_field_next
  ADDI r12,r12,1
mth_field_next:
  ADDI r11,r11,1
  SUB r10,r10,r13
  JMP @mth_field_loop

mth_field_done:
  MOVI r4,43
  CMP r12,r4
  JMP[LT] @mth_field_no
  MOVI r2,1
  JMP @mth_field_out
mth_field_no:
  MOVI r2,0
mth_field_out:
  ADD r1,r12,r0
  MOVI r9,@mth_field_vote_link
  LD r15,r9,0
  RET

mth_field_vote_link:
  .word 0
