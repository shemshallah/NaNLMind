; Canonical NaN16 P2 geometry: ONE block of 255 local two-rail TRAIL
; eligibility updates, 85 triad sign-votes and 43/85 field commit.
; Uses the existing mth_trail_credit (Q16.16) and NO BPTT tape.
;
; Command 41 on the consolidated field driver:
; 0x4001 threshold |credit| Q16.16, >=0
; 0x4002 positive learning rate Q16.16
; 0x4003 expected generation, 0x4004 current generation
; 0xD000 255 x 9 input words:
;   reward, V-(next), V+(now), V+(prev), V-(now),
;   local g+, local g-, gamma, lambda
; 0xE600 255 persistent e+ traces
; 0xE700 255 persistent e- traces
; 0xE800 255 persistent signed Q16.16 coefficients
; 0xE000 staged new e+, 0xE100 staged new e-, 0xE200 credit
; 0xF000 triad majority masks, 0xF100 majority polarity;
; 0xF200/F300 positive/negative counts, 0xF400/F500 masks
; 0x4010..0x4013: accepted_triads, committed, updated_heads, generation
;
; Scratch writes are candidate-guest registers, not canonical chart commits. No coefficient or eligibility
; trace changes unless (a) 2 of 3 heads in each voting triad agree in
; credit sign, (b) 43 of 85 triads approve, and (c) generation is fresh.
; A rejected block leaves 0xE600..0xE8FE and generation unchanged.
mth_geometric_trail_field:
  MOVI r12,@mth_gt_link
  ST r15,r12,0
  MOVI r10,0
  MOVI r12,@mth_gt_index
  ST r10,r12,0
  MOVI r12,@mth_gt_accepted
  ST r10,r12,0
  MOVI r12,@mth_gt_updated
  ST r10,r12,0
  MOVI r12,@mth_gt_committed
  ST r10,r12,0
  MOVI r12,0x4001
  LD r10,r12,0
  MOVI r12,@mth_gt_threshold
  ST r10,r12,0
  MOVI r12,0x4002
  LD r10,r12,0
  MOVI r12,@mth_gt_rate
  ST r10,r12,0

  ; Compute every head's local TRAIL credit, stage but do not commit.
mth_gt_stage:
  MOVI r12,@mth_gt_index
  LD r10,r12,0
  MOVI r11,255
  CMP r10,r11
  JMP[GE] @mth_gt_clear
  MOVI r11,9
  MUL r10,r10,r11
  MOVI r11,0xD000
  ADD r10,r10,r11
  MOVI r12,@mth_gt_ptr
  ST r10,r12,0

  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  MOVI r12,@mth_gt_index
  LD r12,r12,0
  MOVI r11,0xE600
  ADD r11,r11,r12
  LD r6,r11,0
  MOVI r11,0xE700
  ADD r11,r11,r12
  LD r7,r11,0
  MOVI r10,@mth_gt_ptr
  LD r10,r10,0
  LD r8,r10,5
  LD r9,r10,6
  LD r11,r10,8
  LD r10,r10,7
  CALL @mth_trail_credit

  MOVI r12,@mth_gt_index
  LD r12,r12,0
  MOVI r10,0xE000
  ADD r10,r10,r12
  ST r1,r10,0
  MOVI r10,0xE100
  ADD r10,r10,r12
  ST r2,r10,0
  MOVI r10,0xE200
  ADD r10,r10,r12
  ST r3,r10,0
  MOVI r10,@mth_gt_index
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  JMP @mth_gt_stage

mth_gt_clear:
  MOVI r12,@mth_gt_index
  ST r0,r12,0
mth_gt_clear_loop:
  MOVI r12,@mth_gt_index
  LD r9,r12,0
  MOVI r10,85
  CMP r9,r10
  JMP[GE] @mth_gt_count_heads
  MOVI r10,0xF000
  ADD r10,r10,r9
  ST r0,r10,0
  MOVI r10,0xF100
  ADD r10,r10,r9
  ST r0,r10,0
  MOVI r10,0xF200
  ADD r10,r10,r9
  ST r0,r10,0
  MOVI r10,0xF300
  ADD r10,r10,r9
  ST r0,r10,0
  MOVI r10,0xF400
  ADD r10,r10,r9
  ST r0,r10,0
  MOVI r10,0xF500
  ADD r10,r10,r9
  ST r0,r10,0
  ADDI r9,r9,1
  ST r9,r12,0
  JMP @mth_gt_clear_loop

mth_gt_count_heads:
  MOVI r12,@mth_gt_index
  ST r0,r12,0
mth_gt_vote_loop:
  MOVI r12,@mth_gt_index
  LD r8,r12,0
  MOVI r9,255
  CMP r8,r9
  JMP[GE] @mth_gt_finish_votes
  MOVI r9,3
  DIV r3,r8,r9
  MUL r4,r3,r9
  SUB r4,r8,r4
  MOVI r5,@mth_gt_bits
  ADD r5,r5,r4
  LD r6,r5,0
  MOVI r5,0xE200
  ADD r5,r5,r8
  LD r7,r5,0
  MOVI r5,@mth_gt_threshold
  LD r5,r5,0
  CMPS r7,r5
  JMP[GT] @mth_gt_positive
  SUB r5,r0,r5
  CMPS r7,r5
  JMP[LT] @mth_gt_negative
  JMP @mth_gt_vote_next

mth_gt_positive:
  MOVI r10,0xF200
  ADD r10,r10,r3
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  MOVI r10,0xF400
  ADD r10,r10,r3
  LD r11,r10,0
  ADD r11,r11,r6
  ST r11,r10,0
  JMP @mth_gt_vote_next

mth_gt_negative:
  MOVI r10,0xF300
  ADD r10,r10,r3
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  MOVI r10,0xF500
  ADD r10,r10,r3
  LD r11,r10,0
  ADD r11,r11,r6
  ST r11,r10,0

mth_gt_vote_next:
  MOVI r12,@mth_gt_index
  LD r8,r12,0
  ADDI r8,r8,1
  ST r8,r12,0
  JMP @mth_gt_vote_loop

mth_gt_finish_votes:
  MOVI r12,@mth_gt_index
  ST r0,r12,0
mth_gt_group_loop:
  MOVI r12,@mth_gt_index
  LD r9,r12,0
  MOVI r10,85
  CMP r9,r10
  JMP[GE] @mth_gt_gate
  MOVI r10,0xF200
  ADD r10,r10,r9
  LD r11,r10,0
  MOVI r10,2
  CMP r11,r10
  JMP[GE] @mth_gt_accept_positive
  MOVI r10,0xF300
  ADD r10,r10,r9
  LD r11,r10,0
  MOVI r10,2
  CMP r11,r10
  JMP[GE] @mth_gt_accept_negative
  JMP @mth_gt_group_next

mth_gt_accept_positive:
  MOVI r10,0xF400
  ADD r10,r10,r9
  LD r11,r10,0
  MOVI r10,0xF000
  ADD r10,r10,r9
  ST r11,r10,0
  MOVI r10,0xF100
  ADD r10,r10,r9
  MOVI r11,1
  ST r11,r10,0
  JMP @mth_gt_group_approved

mth_gt_accept_negative:
  MOVI r10,0xF500
  ADD r10,r10,r9
  LD r11,r10,0
  MOVI r10,0xF000
  ADD r10,r10,r9
  ST r11,r10,0
  MOVI r10,0xF100
  ADD r10,r10,r9
  MOVI r11,1
  SUB r11,r0,r11
  ST r11,r10,0

mth_gt_group_approved:
  MOVI r12,@mth_gt_accepted
  LD r11,r12,0
  ADDI r11,r11,1
  ST r11,r12,0

mth_gt_group_next:
  MOVI r12,@mth_gt_index
  LD r9,r12,0
  ADDI r9,r9,1
  ST r9,r12,0
  JMP @mth_gt_group_loop

mth_gt_gate:
  MOVI r12,@mth_gt_threshold
  LD r10,r12,0
  CMPS r10,r0
  JMP[LT] @mth_gt_end
  MOVI r12,@mth_gt_rate
  LD r10,r12,0
  CMPS r10,r0
  JMP[LT] @mth_gt_end
  MOVI r12,@mth_gt_accepted
  LD r10,r12,0
  MOVI r11,43
  CMP r10,r11
  JMP[LT] @mth_gt_end
  MOVI r12,0x4003
  LD r10,r12,0
  MOVI r12,0x4004
  LD r11,r12,0
  CMP r10,r11
  JMP[NE] @mth_gt_end

  ; The global field accepted. Only the winning-sign voters in
  ; accepted triads may modify their individual rails and coefficients.
  MOVI r12,@mth_gt_committed
  MOVI r11,1
  ST r11,r12,0
  MOVI r12,@mth_gt_index
  ST r0,r12,0
mth_gt_commit_loop:
  MOVI r12,@mth_gt_index
  LD r8,r12,0
  MOVI r9,255
  CMP r8,r9
  JMP[GE] @mth_gt_advance_generation
  MOVI r9,3
  DIV r3,r8,r9
  MUL r4,r3,r9
  SUB r4,r8,r4
  MOVI r5,@mth_gt_bits
  ADD r5,r5,r4
  LD r6,r5,0
  MOVI r5,0xF000
  ADD r5,r5,r3
  LD r7,r5,0
  BOOL.8 r7,r7,r6
  CMP r7,r0
  JMP[EQ] @mth_gt_commit_next
  MOVI r10,0xE200
  ADD r10,r10,r8
  LD r1,r10,0
  MOVI r10,@mth_gt_rate
  LD r2,r10,0
  CALL @mth_q16_mul
  MOVI r12,@mth_gt_index
  LD r8,r12,0
  MOVI r10,0xE800
  ADD r10,r10,r8
  LD r9,r10,0
  ADD r9,r9,r1
  ST r9,r10,0
  MOVI r10,0xE000
  ADD r10,r10,r8
  LD r9,r10,0
  MOVI r10,0xE600
  ADD r10,r10,r8
  ST r9,r10,0
  MOVI r10,0xE100
  ADD r10,r10,r8
  LD r9,r10,0
  MOVI r10,0xE700
  ADD r10,r10,r8
  ST r9,r10,0
  MOVI r12,@mth_gt_updated
  LD r11,r12,0
  ADDI r11,r11,1
  ST r11,r12,0

mth_gt_commit_next:
  MOVI r12,@mth_gt_index
  LD r8,r12,0
  ADDI r8,r8,1
  ST r8,r12,0
  JMP @mth_gt_commit_loop

mth_gt_advance_generation:
  MOVI r12,0x4004
  LD r11,r12,0
  ADDI r11,r11,1
  ST r11,r12,0

mth_gt_end:
  MOVI r10,0x4010
  MOVI r12,@mth_gt_accepted
  LD r11,r12,0
  ST r11,r10,0
  MOVI r12,@mth_gt_committed
  LD r11,r12,0
  ST r11,r10,1
  MOVI r12,@mth_gt_updated
  LD r11,r12,0
  ST r11,r10,2
  MOVI r12,0x4004
  LD r11,r12,0
  ST r11,r10,3
  MOVI r12,@mth_gt_link
  LD r15,r12,0
  RET

mth_gt_link:
  .word 0
mth_gt_ptr:
  .word 0
mth_gt_index:
  .word 0
mth_gt_threshold:
  .word 0
mth_gt_rate:
  .word 0
mth_gt_accepted:
  .word 0
mth_gt_committed:
  .word 0
mth_gt_updated:
  .word 0
mth_gt_bits:
  .word 1
  .word 2
  .word 4
