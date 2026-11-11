; Raw NaN16 temporally split context slots.
;
; For every current word:
;   S+ (past/preceding)      = hash(w[i-3],w[i-2],w[i-1])
;   C  (current / head 255)  = w[i]
;   S- (future/anticipatory) = hash(w[i+1],w[i+2],w[i+3])
;
; Tables:
;   0x230000  S+ votes[85]
;   0x230100  S+ head credits[255]
;   0x231000  S- votes[85]
;   0x231100  S- head credits[255]
;   0x232000  current word per position
;   0x233000  current-context slot [word,255,count,0] (255 is not an incidence endpoint)
;   0x234000  temporal slot records: [preceding_hash,current_word,future_hash]
;
; The raw project step merges S+ and S- into the standard meta-trihead tables
; at 0x220000/0x220100. The current slot remains the non-triad head 255 field.

mth_ts_hash3:
  MOVI r4,0x9DC5
  MOVHI r4,0x811C
  MOVI r5,0x0193
  MOVHI r5,0x0100
  BOOL.6 r4,r4,r1
  MUL r4,r4,r5
  BOOL.6 r4,r4,r2
  MUL r4,r4,r5
  BOOL.6 r4,r4,r3
  MUL r4,r4,r5
  ADD r1,r4,r0
  RET

mth_temporal_reset:
  MOVI r10,0x0000
  MOVHI r10,0x0023
  MOVI r11,85
  MOVI r12,0
mth_ts_reset_sp:
  ADD r13,r10,r12
  ST r0,r13,0
  ADDI r12,r12,1
  CMP r12,r11
  JMP[LT] @mth_ts_reset_sp
  MOVI r10,0x0100
  MOVHI r10,0x0023
  MOVI r11,255
  MOVI r12,0
mth_ts_reset_spc:
  ADD r13,r10,r12
  ST r0,r13,0
  ADDI r12,r12,1
  CMP r12,r11
  JMP[LT] @mth_ts_reset_spc
  MOVI r10,0x1000
  MOVHI r10,0x0023
  MOVI r11,85
  MOVI r12,0
mth_ts_reset_sm:
  ADD r13,r10,r12
  ST r0,r13,0
  ADDI r12,r12,1
  CMP r12,r11
  JMP[LT] @mth_ts_reset_sm
  MOVI r10,0x1100
  MOVHI r10,0x0023
  MOVI r11,255
  MOVI r12,0
mth_ts_reset_smc:
  ADD r13,r10,r12
  ST r0,r13,0
  ADDI r12,r12,1
  CMP r12,r11
  JMP[LT] @mth_ts_reset_smc
  MOVI r10,0x3000
  MOVHI r10,0x0023
  MOVI r11,4
  MOVI r12,0
mth_ts_reset_head:
  ADD r13,r10,r12
  ST r0,r13,0
  ADDI r12,r12,1
  CMP r12,r11
  JMP[LT] @mth_ts_reset_head
  MOVI r1,85
  RET

; r1=word IDs, r2=count -> r1=context count
mth_temporal_observe_batch:
  MOVI r12,@mth_ts_link
  ST r15,r12,0
  MOVI r12,@mth_ts_words
  ST r1,r12,0
  MOVI r12,@mth_ts_count
  ST r2,r12,0
  MOVI r12,@mth_ts_i
  ST r0,r12,0
  MOVI r12,@mth_ts_contexts
  ST r0,r12,0
mth_ts_loop:
  MOVI r12,@mth_ts_i
  LD r5,r12,0
  MOVI r12,@mth_ts_count
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_ts_done
  MOVI r12,@mth_ts_words
  LD r7,r12,0

  ; preceding context words w[i-3],w[i-2],w[i-1]
  MOVI r1,0
  MOVI r8,3
  CMP r5,r8
  JMP[LT] @mth_ts_pre2
  SUB r8,r5,r8
  ADD r8,r7,r8
  LD r1,r8,0
mth_ts_pre2:
  MOVI r2,0
  MOVI r8,2
  CMP r5,r8
  JMP[LT] @mth_ts_pre1
  SUB r8,r5,r8
  ADD r8,r7,r8
  LD r2,r8,0
mth_ts_pre1:
  MOVI r3,0
  MOVI r8,1
  CMP r5,r8
  JMP[LT] @mth_ts_pre_ready
  SUB r8,r5,r8
  ADD r8,r7,r8
  LD r3,r8,0
mth_ts_pre_ready:
  CALL @mth_ts_hash3
  MOVI r12,@mth_ts_pre
  ST r1,r12,0
  ; hash3 clobbers r5; recover the loop index
  MOVI r12,@mth_ts_i
  LD r5,r12,0

  ; current word
  ADD r8,r7,r5
  LD r8,r8,0
  MOVI r12,@mth_ts_current
  ST r8,r12,0
  ; current array and separate field slot (255 is void)
  MOVI r9,0x0000
  MOVHI r9,0x0023
  MOVI r10,0x2000
  ADD r9,r9,r10
  ADD r9,r9,r5
  ST r8,r9,0
  MOVI r9,0x3000
  MOVHI r9,0x0023
  ST r8,r9,0
  MOVI r10,255
  ST r10,r9,1
  ST r5,r9,2
  ST r0,r9,3

  ; anticipatory context w[i+1],w[i+2],w[i+3]
  MOVI r1,0
  MOVI r8,1
  ADD r8,r5,r8
  CMP r8,r6
  JMP[GE] @mth_ts_fut2
  ADD r8,r7,r8
  LD r1,r8,0
mth_ts_fut2:
  MOVI r2,0
  MOVI r8,2
  ADD r8,r5,r8
  CMP r8,r6
  JMP[GE] @mth_ts_fut1
  ADD r8,r7,r8
  LD r2,r8,0
mth_ts_fut1:
  MOVI r3,0
  MOVI r8,3
  ADD r8,r5,r8
  CMP r8,r6
  JMP[GE] @mth_ts_fut_ready
  ADD r8,r7,r8
  LD r3,r8,0
mth_ts_fut_ready:
  CALL @mth_ts_hash3
  MOVI r12,@mth_ts_future
  ST r1,r12,0
  MOVI r12,@mth_ts_i
  LD r5,r12,0

  ; temporal slot record [preceding,current,future]
  MOVI r9,0x4000
  MOVHI r9,0x0023
  MOVI r10,3
  MUL r10,r5,r10
  ADD r9,r9,r10
  MOVI r12,@mth_ts_pre
  LD r10,r12,0
  ST r10,r9,0
  MOVI r12,@mth_ts_current
  LD r10,r12,0
  ST r10,r9,1
  MOVI r12,@mth_ts_future
  LD r10,r12,0
  ST r10,r9,2

  ; S+ update
  MOVI r12,@mth_ts_pre
  LD r1,r12,0
  MOVI r10,85
  MODU r1,r1,r10
  MOVI r9,0x0000
  MOVHI r9,0x0023
  ADD r9,r9,r1
  MOVI r10,7
  ST r10,r9,0
  MOVI r9,0x0100
  MOVHI r9,0x0023
  MOVI r10,3
  MUL r1,r1,r10
  ADD r9,r9,r1
  MOVI r3,0
  MOVI r4,0
  MOVHI r4,0x0001
mth_ts_sp_credit:
  MOVI r10,3
  CMP r3,r10
  JMP[GE] @mth_ts_sm_update
  ADD r11,r9,r3
  LD r10,r11,0
  ADD r10,r10,r4
  ST r10,r11,0
  ADDI r3,r3,1
  JMP @mth_ts_sp_credit

mth_ts_sm_update:
  MOVI r12,@mth_ts_future
  LD r1,r12,0
  MOVI r10,85
  MODU r1,r1,r10
  MOVI r9,0x1000
  MOVHI r9,0x0023
  ADD r9,r9,r1
  MOVI r10,7
  ST r10,r9,0
  MOVI r9,0x1100
  MOVHI r9,0x0023
  MOVI r10,3
  MUL r1,r1,r10
  ADD r9,r9,r1
  MOVI r3,0
  MOVI r4,0
  MOVHI r4,0x0001
mth_ts_sm_credit:
  MOVI r10,3
  CMP r3,r10
  JMP[GE] @mth_ts_next
  ADD r11,r9,r3
  LD r10,r11,0
  ADD r10,r10,r4
  ST r10,r11,0
  ADDI r3,r3,1
  JMP @mth_ts_sm_credit
mth_ts_next:
  MOVI r12,@mth_ts_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  MOVI r12,@mth_ts_contexts
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_ts_loop
mth_ts_done:
  MOVI r12,@mth_ts_contexts
  LD r1,r12,0
  MOVI r12,@mth_ts_link
  LD r15,r12,0
  RET

; Merge S+ and S- into the standard meta-trihead tables.
mth_temporal_project:
  MOVI r10,0x0000
  MOVHI r10,0x0022
  MOVI r11,0
  MOVI r12,85
mth_ts_proj_votes:
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_ts_proj_votes
  MOVI r10,0x0100
  MOVHI r10,0x0022
  MOVI r11,0
  MOVI r12,255
mth_ts_proj_credits:
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_ts_proj_credits
  MOVI r10,0x0000
  MOVHI r10,0x0023
  MOVI r11,0
  MOVI r12,85
mth_ts_proj_slots:
  CMP r11,r12
  JMP[GE] @mth_ts_proj_credits_loop
  ADD r13,r10,r11
  LD r5,r13,0
  MOVI r9,0x1000
  MOVHI r9,0x0023
  ADD r9,r9,r11
  LD r6,r9,0
  ADD r7,r5,r6
  CMP r7,r0
  JMP[EQ] @mth_ts_proj_next
  MOVI r8,0x0000
  MOVHI r8,0x0022
  ADD r8,r8,r11
  MOVI r7,7
  ST r7,r8,0
mth_ts_proj_next:
  ADDI r11,r11,1
  JMP @mth_ts_proj_slots
mth_ts_proj_credits_loop:
  MOVI r10,0x0100
  MOVHI r10,0x0023
  MOVI r11,0
  MOVI r12,255
mth_ts_proj_credit_loop:
  CMP r11,r12
  JMP[GE] @mth_ts_proj_done
  ADD r13,r10,r11
  LD r5,r13,0
  MOVI r9,0x1100
  MOVHI r9,0x0023
  ADD r9,r9,r11
  LD r6,r9,0
  ADD r7,r5,r6
  MOVI r8,0x0100
  MOVHI r8,0x0022
  ADD r8,r8,r11
  ST r7,r8,0
  ADDI r11,r11,1
  JMP @mth_ts_proj_credit_loop
mth_ts_proj_done:
  MOVI r1,85
  RET

mth_ts_link:
  .word 0
mth_ts_words:
  .word 0
mth_ts_count:
  .word 0
mth_ts_i:
  .word 0
mth_ts_contexts:
  .word 0
mth_ts_pre:
  .word 0
mth_ts_future:
  .word 0
mth_ts_current:
  .word 0
