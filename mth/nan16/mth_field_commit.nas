; NaN16 CFT-credit -> triad -> field commit gate.
;
; ABI:
;   r1 = pointer to 85 signed Q16.16 triad credits
;   r2 = signed Q16.16 acceptance threshold
;   r3 = pointer to 85 output vote bytes (may be the caller's chart scratch)
; Returns:
;   r1 = number of accepted triads (0..85)
;   r2 = 1 when at least 43 triads accept, else 0
;
; The local CFT/TRAIL credit is not a global tape. A triad accepts when its
; aggregate credit clears the threshold; the field commits only at 43/85.
mth_field_commit:
  ADD r10,r1,r0
  ADD r11,r3,r0
  MOVI r12,0
  MOVI r13,1
  MOVI r14,85

mth_fcommit_loop:
  LD r5,r10,0
  CMPS r5,r2
  JMP[LE] @mth_fcommit_reject
  MOVI r6,1
  ST r6,r11,0
  ADDI r12,r12,1
  JMP @mth_fcommit_next
mth_fcommit_reject:
  ST r0,r11,0
mth_fcommit_next:
  ADDI r10,r10,1
  ADDI r11,r11,1
  SUB r14,r14,r13
  CMP r14,r0
  JMP[NE] @mth_fcommit_loop

  MOVI r4,43
  CMP r12,r4
  JMP[LT] @mth_fcommit_no
  MOVI r2,1
  JMP @mth_fcommit_out
mth_fcommit_no:
  MOVI r2,0
mth_fcommit_out:
  ADD r1,r12,r0
  RET
