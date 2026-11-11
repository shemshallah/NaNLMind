; Native NaN16 six-word source-window builder. NO TARGET LEAKAGE.
; The builder feeds mth_six_context_poincare_attention (opcode107).
;
; r1=source word IDs[0..n-1] (read-only)
; r2=n (1..4096)
; r3=target position
; r4=task: 0 predict NEXT word (MUST target==n), 1 masked infill (target<n)
; r5=masked-query anchor ID for infill (NEVER target ID).
; r6=expected generation, r7=current generation
; r8=12-word request output;  r13=1.
; output request [observed_anchor, past[-3,-2,-1], future[+1,+2,+3],
;                 valid_mask, task, expected_generation, current_gen, NOW=255]
; Return r1=1 success, r2=valid mask, r3=observed neighbors, r4=0.
; Reject r1=r2=r3=0, r4=1 invalid /2 stale; no output writes.
;
; Task0 never reads the target (it lies beyond the observed source);
; no future words or future mask bits may appear. Task1 deliberately
; NEVER loads word[target], even when the corpus buffer still contains it.
; Caller must supply actual masked targets, train/dev provenance and epochs.
; This is a read-only source filter; no model or hypertensor writes.
; Non-reentrant small static scratch, native serialized driver calls only.
mth_context6_window_stream:
  MOVI r0,0
  ST r15,r0,@c6s_link
  ST r1,r0,@c6s_source
  ST r2,r0,@c6s_count
  ST r3,r0,@c6s_target
  ST r4,r0,@c6s_task
  ST r5,r0,@c6s_anchor
  ST r6,r0,@c6s_generation
  ST r7,r0,@c6s_current_gen
  ST r8,r0,@c6s_output
  CMP r1,r0
  JMP[EQ] @c6s_bad
  CMP r8,r0
  JMP[EQ] @c6s_bad
  CMP r1,r8
  JMP[EQ] @c6s_bad
  CMP r2,r0
  JMP[LE] @c6s_bad
  MOVI r9,4096
  CMP r2,r9
  JMP[GT] @c6s_bad
  MOVI r9,1
  CMP r4,r9
  JMP[GT] @c6s_bad
  CMPS r3,r0
  JMP[LT] @c6s_bad
  CMP r4,r0
  JMP[NE] @c6s_infill
  CMP r3,r2
  JMP[NE] @c6s_bad
  JMP @c6s_generation_gate
c6s_infill:
  CMP r3,r2
  JMP[GE] @c6s_bad
  CMP r5,r0
  JMP[EQ] @c6s_bad
c6s_generation_gate:
  CMP r6,r7
  JMP[NE] @c6s_stale
  ST r0,r0,@c6s_mask
  ST r0,r0,@c6s_valid
  MOVI r9,0
c6s_zero_slots:
  MOVI r10,6
  CMP r9,r10
  JMP[GE] @c6s_collect
  MOVI r10,@c6s_slots
  ADD r10,r10,r9
  ST r0,r10,0
  ADDI r9,r9,1
  JMP @c6s_zero_slots

c6s_collect:
  MOVI r9,0
c6s_loop:
  MOVI r10,6
  CMP r9,r10
  JMP[GE] @c6s_commit
  LD r10,r0,@c6s_task
  CMP r10,r0
  JMP[NE] @c6s_candidate
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @c6s_next
c6s_candidate:
  MOVI r10,@c6s_offsets
  ADD r10,r10,r9
  LD r11,r10,0
  LD r10,r0,@c6s_target
  ADD r11,r11,r10
  CMPS r11,r0
  JMP[LT] @c6s_next
  LD r10,r0,@c6s_count
  CMP r11,r10
  JMP[GE] @c6s_next
  LD r10,r0,@c6s_source
  ADD r10,r10,r11
  LD r12,r10,0
  CMP r12,r0
  JMP[EQ] @c6s_bad
  MOVI r10,@c6s_slots
  ADD r10,r10,r9
  ST r12,r10,0
  MOVI r10,@c6s_mask_bits
  ADD r10,r10,r9
  LD r12,r10,0
  LD r10,r0,@c6s_mask
  BOOL.14 r10,r10,r12
  ST r10,r0,@c6s_mask
  LD r10,r0,@c6s_valid
  ADDI r10,r10,1
  ST r10,r0,@c6s_valid
c6s_next:
  ADDI r9,r9,1
  JMP @c6s_loop

c6s_commit:
  LD r11,r0,@c6s_valid
  CMP r11,r0
  JMP[EQ] @c6s_bad
  LD r11,r0,@c6s_task
  CMP r11,r0
  JMP[NE] @c6s_use_explicit_anchor
  LD r10,r0,@c6s_source
  LD r12,r0,@c6s_count
  SUB r12,r12,r13
  ADD r10,r10,r12
  LD r11,r10,0
  JMP @c6s_have_anchor
c6s_use_explicit_anchor:
  LD r11,r0,@c6s_anchor
c6s_have_anchor:
  CMP r11,r0
  JMP[EQ] @c6s_bad
  LD r8,r0,@c6s_output
  ST r11,r8,0
  MOVI r9,0
c6s_copy:
  MOVI r10,6
  CMP r9,r10
  JMP[GE] @c6s_copy_done
  MOVI r10,@c6s_slots
  ADD r10,r10,r9
  LD r11,r10,0
  ADD r10,r8,r9
  ST r11,r10,1
  ADDI r9,r9,1
  JMP @c6s_copy
c6s_copy_done:
  LD r11,r0,@c6s_mask
  ST r11,r8,7
  LD r11,r0,@c6s_task
  ST r11,r8,8
  LD r11,r0,@c6s_generation
  ST r11,r8,9
  ST r11,r8,10
  MOVI r11,255
  ST r11,r8,11
  MOVI r1,1
  LD r2,r0,@c6s_mask
  LD r3,r0,@c6s_valid
  MOVI r4,0
  JMP @c6s_return
c6s_bad:
  MOVI r4,1
  JMP @c6s_reject
c6s_stale:
  MOVI r4,2
c6s_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
c6s_return:
  MOVI r13,1
  LD r15,r0,@c6s_link
  RET

c6s_link:
  .word 0
c6s_source:
  .word 0
c6s_count:
  .word 0
c6s_target:
  .word 0
c6s_task:
  .word 0
c6s_anchor:
  .word 0
c6s_generation:
  .word 0
c6s_current_gen:
  .word 0
c6s_output:
  .word 0
c6s_mask:
  .word 0
c6s_valid:
  .word 0
c6s_slots:
  .word 0,0,0,0,0,0
c6s_offsets:
  .word 4294967293,4294967294,4294967295,1,2,3
c6s_mask_bits:
  .word 1,2,4,8,16,32
