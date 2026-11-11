; Raw NaN16 meta-tokenizer -> trihead bridge.
;
; A three-word context is hashed in the guest to one of 85 triads. The selected
; triad gets a 2-of-3 vote mask (7) and its three member heads receive Q16
; credit. These are the same 85-triad/255-head objects used by the hot-trihead
; and 43/85 field layers; no host triad arithmetic is performed.
;
; Tables:
;   0x220000 = 85 triad vote masks
;   0x220100 = 255 signed head credits

mth_meta_hash3:
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

mth_meta_trihead_reset:
  MOVI r10,0x0000
  MOVHI r10,0x0022
  MOVI r11,0
  MOVI r12,85
mth_mt_reset_votes:
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_mt_reset_votes
  MOVI r10,0x0100
  MOVHI r10,0x0022
  MOVI r11,0
  MOVI r12,255
mth_mt_reset_credits:
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_mt_reset_credits
  MOVI r1,85
  ; r13 is the shared NaN16 unity / gate sentinel, not a scratch pointer.
  MOVI r13,1
  RET

; r1=w0,r2=w1,r3=w2 -> r1=triad, r2=context hash
mth_meta_trihead_observe:
  MOVI r12,@mth_mt_link
  ST r15,r12,0
  MOVI r12,@mth_mt_w0
  ST r1,r12,0
  MOVI r12,@mth_mt_w1
  ST r2,r12,0
  MOVI r12,@mth_mt_w2
  ST r3,r12,0
  CALL @mth_meta_hash3
  MOVI r12,@mth_mt_hash
  ST r1,r12,0
  MOVI r9,85
  MODU r7,r1,r9
  MOVI r12,@mth_mt_triad
  ST r7,r12,0
  ; OR 7 into votes[triad]
  MOVI r10,0x0000
  MOVHI r10,0x0022
  ADD r10,r10,r7
  MOVI r11,7
  ST r11,r10,0
  ; add 65536 to each of the three member-head credits
  MOVI r8,3
  MUL r7,r7,r8
  MOVI r10,0x0100
  MOVHI r10,0x0022
  ADD r10,r10,r7
  ; Only the three members of this selected triad receive credit.
  ; r9 was 85 for the modulo above and must not become a loop bound.
  MOVI r9,3
  MOVI r8,0
mth_mt_credit_loop:
  CMP r8,r9
  JMP[GE] @mth_mt_observe_done
  ADD r11,r10,r8
  LD r12,r11,0
  MOVI r13,0
  MOVHI r13,0x0001
  ADD r12,r12,r13
  ST r12,r11,0
  ADDI r8,r8,1
  JMP @mth_mt_credit_loop
mth_mt_observe_done:
  MOVI r12,@mth_mt_triad
  LD r1,r12,0
  MOVI r12,@mth_mt_hash
  LD r2,r12,0
  MOVI r12,@mth_mt_link
  LD r15,r12,0
  ; Q16 credit accumulation used r13=65536; restore the native ABI.
  MOVI r13,1
  RET

; r1=word IDs, r2=count -> r1=contexts observed
mth_meta_trihead_observe_batch:
  MOVI r12,@mth_mt_batch_link
  ST r15,r12,0
  MOVI r12,@mth_mt_words
  ST r1,r12,0
  MOVI r12,@mth_mt_count
  ST r2,r12,0
  MOVI r12,@mth_mt_i
  ST r0,r12,0
  MOVI r12,@mth_mt_contexts
  ST r0,r12,0
mth_mt_batch_loop:
  MOVI r12,@mth_mt_i
  LD r5,r12,0
  MOVI r12,@mth_mt_count
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_mt_batch_done
  MOVI r12,@mth_mt_words
  LD r7,r12,0
  ; context = previous three words, not the current word
  MOVI r1,0
  MOVI r8,3
  CMP r5,r8
  JMP[LT] @mth_mt_batch_has_two
  SUB r8,r5,r8
  ADD r8,r7,r8
  LD r1,r8,0
mth_mt_batch_has_two:
  MOVI r2,0
  MOVI r8,2
  CMP r5,r8
  JMP[LT] @mth_mt_batch_has_one
  SUB r8,r5,r8
  ADD r8,r7,r8
  LD r2,r8,0
mth_mt_batch_has_one:
  MOVI r3,0
  MOVI r8,1
  CMP r5,r8
  JMP[LT] @mth_mt_batch_context_ready
  SUB r8,r5,r8
  ADD r8,r7,r8
  LD r3,r8,0
mth_mt_batch_context_ready:
  CALL @mth_meta_trihead_observe
  MOVI r12,@mth_mt_contexts
  LD r8,r12,0
  ADDI r8,r8,1
  ST r8,r12,0
  MOVI r12,@mth_mt_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_mt_batch_loop
mth_mt_batch_done:
  MOVI r12,@mth_mt_contexts
  LD r1,r12,0
  MOVI r12,@mth_mt_batch_link
  LD r15,r12,0
  MOVI r13,1
  RET

mth_mt_link:
  .word 0
mth_mt_batch_link:
  .word 0
mth_mt_w0:
  .word 0
mth_mt_w1:
  .word 0
mth_mt_w2:
  .word 0
mth_mt_hash:
  .word 0
mth_mt_triad:
  .word 0
mth_mt_words:
  .word 0
mth_mt_count:
  .word 0
mth_mt_i:
  .word 0
mth_mt_contexts:
  .word 0
