; Native NaN16 dynamic Boolean-function helpers.
;
; The only place a rule number becomes an instruction is the BOOL slot below.
; The slot word is rewritten with STW; its class nibble is the truth table.
; This is raw NaN16 self-modification, not a host Boolean switch.

mth_bool_dynamic_slot:
  BOOL.0 r5,r6,r7
  RET

; r1 = rule 0..15, r6 = operand A, r7 = operand B
; returns r5 = 0/1. Clobbers r2,r3.
mth_bool_eval:
  MOVI r2,@mth_bool_eval_link
  ST r15,r2,0
  MOVI r2,0x0007
  MOVHI r2,0x0056
  MOVI r3,@mth_bool_dynamic_slot
  STW r2,r3,r1
  CALL @mth_bool_dynamic_slot
  MOVI r2,@mth_bool_eval_link
  LD r15,r2,0
  MOVI r2,1
  BOOL.8 r5,r5,r2
  RET

mth_bool_eval_link:
  .word 0

; r1 = 16-bit function mask, returns r2 = lowest enabled rule (0 if empty).
; Clobbers r3,r4.
mth_bool_lowbit:
  MOVI r2,0
  CMP r1,r0
  JMP[EQ] @mth_bool_lowbit_done
  MOVI r3,1
mth_bool_lowbit_loop:
  BOOL.8 r4,r1,r3
  CMP r4,r0
  JMP[NE] @mth_bool_lowbit_done
  SHR r1,r1,1
  ADDI r2,r2,1
  MOVI r4,16
  CMP r2,r4
  JMP[LT] @mth_bool_lowbit_loop
mth_bool_lowbit_done:
  RET

; r1 = 3-bit vote mask, returns r2 = count 0..3. Clobbers r3,r4.
mth_bool_popcount3:
  MOVI r2,0
  MOVI r3,1
  BOOL.8 r4,r1,r3
  ADD r2,r2,r4
  SHR r1,r1,1
  BOOL.8 r4,r1,r3
  ADD r2,r2,r4
  SHR r1,r1,1
  BOOL.8 r4,r1,r3
  ADD r2,r2,r4
  RET
