; Raw NaN16 context 16x16 class -> canonical 255-head/85-triad/43 field link.
;
; This is the physical bridge from the context-memory class table to the
; canonical topology in spec/unified-build.v1.json:
;
;   class head = high_class * 16 + low_class       (0..255)
;   class triad = class head / 3                   (0..84)
;   class member = class head % 3                  (0..2)
;   field head = 255                               (not a triad member)
;
; The high/low classes are either read directly from the context table or
; supplied as predictions. All argmax, mapping, credit, 2-of-3 triad vote and
; 43/85 field arithmetic below runs in the guest. The host only writes inputs
; and reads results.

; ---------------------------------------------------------------------------
; mth_context_pick
;
; ABI:
;   r1 = high table base word address
;   r2 = bucket count B
;   r3 = context bucket (0..B-1)
;   r4 = low table base word address (0 => r1 + 16*B)
;   r5 = mode (0 = table scores, 1 = direct predictions)
;   r6 = direct high class (mode 1)
;   r7 = direct low class (mode 1)
; Returns:
;   r1 = class head = high*16 + low (0..255)
;   r2 = triad = head/3, or 0xFFFF for field head 255
;   r3 = member = head%3, or 0xFFFF for field head 255
;   r4 = 1 when the class maps to field head 255, else 0
;   r5 = high class (0..15)
;   r6 = low class (0..15)
;
; The context table layout is the one used by mth_context_hier.nas:
;   high[h] = high_base[h*B + bucket]
;   low[h][l] = low_base[h*16*B + l*B + bucket]
; The default low_base is high_base + 16*B (high table followed by the
; sixteen 16-row low tables).
; ---------------------------------------------------------------------------
mth_context_pick:
  MOVI r12,@mth_ccp_link
  ST r15,r12,0
  MOVI r12,@mth_ccp_highbase
  ST r1,r12,0
  MOVI r12,@mth_ccp_buckets
  ST r2,r12,0
  MOVI r12,@mth_ccp_bucket
  ST r3,r12,0
  MOVI r12,@mth_ccp_lowbase
  ST r4,r12,0
  MOVI r12,@mth_ccp_mode
  ST r5,r12,0
  MOVI r12,@mth_ccp_dhigh
  ST r6,r12,0
  MOVI r12,@mth_ccp_dlow
  ST r7,r12,0

  CMP r5,r0
  JMP[NE] @mth_ccp_direct

  ; High argmax over the 16 class rows at this bucket.
  MOVI r9,0
  MOVHI r9,0xFF80          ; -infinity
  MOVI r8,0
  MOVI r5,0
mth_ccp_high_loop:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_ccp_high_done
  MOVI r12,@mth_ccp_buckets
  LD r12,r12,0
  MUL r14,r5,r12
  MOVI r12,@mth_ccp_bucket
  LD r12,r12,0
  ADD r14,r14,r12
  MOVI r12,@mth_ccp_highbase
  LD r12,r12,0
  ADD r14,r14,r12
  LD r7,r14,0
  FCMP r7,r9
  JMP[LE] @mth_ccp_high_next
  ADD r9,r7,r0
  ADD r8,r5,r0
mth_ccp_high_next:
  ADDI r5,r5,1
  JMP @mth_ccp_high_loop
mth_ccp_high_done:
  MOVI r12,@mth_ccp_high
  ST r8,r12,0

  ; Low table base = explicit pointer or high_base + 16*B.
  MOVI r12,@mth_ccp_lowbase
  LD r10,r12,0
  CMP r10,r0
  JMP[NE] @mth_ccp_lowbase_ok
  MOVI r12,@mth_ccp_buckets
  LD r10,r12,0
  MOVI r12,16
  MUL r10,r10,r12
  MOVI r12,@mth_ccp_highbase
  LD r12,r12,0
  ADD r10,r10,r12
mth_ccp_lowbase_ok:
  MOVI r12,@mth_ccp_lowbase_computed
  ST r10,r12,0

  ; Group base for the selected high nibble: low_base + high*16*B.
  MOVI r12,@mth_ccp_high
  LD r11,r12,0
  MOVI r12,16
  MUL r11,r11,r12
  MOVI r12,@mth_ccp_buckets
  LD r12,r12,0
  MUL r11,r11,r12
  MOVI r12,@mth_ccp_lowbase_computed
  LD r10,r12,0
  ADD r11,r11,r10

  ; Low argmax over the conditional 16-class group.
  MOVI r9,0
  MOVHI r9,0xFF80          ; -infinity
  MOVI r6,0
  MOVI r5,0
mth_ccp_low_loop:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_ccp_low_done
  MOVI r12,@mth_ccp_buckets
  LD r12,r12,0
  MUL r14,r5,r12
  MOVI r12,@mth_ccp_bucket
  LD r12,r12,0
  ADD r14,r14,r12
  ADD r14,r14,r11
  LD r7,r14,0
  FCMP r7,r9
  JMP[LE] @mth_ccp_low_next
  ADD r9,r7,r0
  ADD r6,r5,r0
mth_ccp_low_next:
  ADDI r5,r5,1
  JMP @mth_ccp_low_loop
mth_ccp_low_done:
  JMP @mth_ccp_map

mth_ccp_direct:
  MOVI r12,@mth_ccp_dhigh
  LD r8,r12,0
  MOVI r12,15
  BOOL.8 r8,r8,r12
  MOVI r12,@mth_ccp_dlow
  LD r6,r12,0
  MOVI r12,15
  BOOL.8 r6,r6,r12

mth_ccp_map:
  ; class head = high * 16 + low
  MOVI r12,16
  MUL r1,r8,r12
  ADD r1,r1,r6
  MOVI r12,255
  CMP r1,r12
  JMP[EQ] @mth_ccp_field_head
  MOVI r12,3
  DIV r2,r1,r12           ; triad = head / 3
  MOD r3,r1,r12           ; member = head % 3
  MOVI r4,0
  JMP @mth_ccp_out
mth_ccp_field_head:
  MOVI r2,0xFFFF
  MOVI r3,0xFFFF
  MOVI r4,1
mth_ccp_out:
  ADD r5,r8,r0
  MOVI r13,1
  MOVI r12,@mth_ccp_link
  LD r15,r12,0
  RET

mth_ccp_link:
  .word 0
mth_ccp_highbase:
  .word 0
mth_ccp_buckets:
  .word 0
mth_ccp_bucket:
  .word 0
mth_ccp_lowbase:
  .word 0
mth_ccp_mode:
  .word 0
mth_ccp_dhigh:
  .word 0
mth_ccp_dlow:
  .word 0
mth_ccp_lowbase_computed:
  .word 0
mth_ccp_high:
  .word 0

; ---------------------------------------------------------------------------
; mth_context_field
;
; ABI:
;   r1 = pointer to 255 signed int32 head credits
;   r2 = signed int32 head-credit threshold
;   r3 = pointer to 85 output triad votes (one word each)
;   r4 = selected class head (0..255)
;   r5 = signed credit delta added to the selected head before voting
; Returns:
;   r1 = accepted triad count (2-of-3, 0..85)
;   r2 = 1 when at least 43 triads accept, else 0
;   r3 = selected triad vote (0 for field head 255)
;   r4 = selected head credit before the delta
;   r5 = selected head credit after the delta (also written to credits[head])
;
; The canonical partition is fixed: triad t uses heads 3t, 3t+1, 3t+2.
; Head 255 is the field head and is never inserted into a triad.
; ---------------------------------------------------------------------------
mth_context_field:
  MOVI r12,@mth_ccf_link
  ST r15,r12,0
  MOVI r12,@mth_ccf_credits
  ST r1,r12,0
  MOVI r12,@mth_ccf_threshold
  ST r2,r12,0
  MOVI r12,@mth_ccf_votes
  ST r3,r12,0

  MOVI r12,255
  CMP r4,r12
  JMP[EQ] @mth_ccf_field_head

  ; Apply the native credit delta to the selected class head.
  ADD r10,r1,r4
  LD r8,r10,0
  MOVI r12,@mth_ccf_before
  ST r8,r12,0
  ADD r9,r8,r5
  ST r9,r10,0
  MOVI r12,@mth_ccf_after
  ST r9,r12,0
  MOVI r12,3
  DIV r7,r4,r12
  MOVI r12,@mth_ccf_seltriad
  ST r7,r12,0
  JMP @mth_ccf_scan

mth_ccf_field_head:
  MOVI r12,@mth_ccf_before
  ST r0,r12,0
  MOVI r12,@mth_ccf_after
  ST r0,r12,0
  MOVI r12,@mth_ccf_seltriad
  MOVI r7,0xFFFF
  ST r7,r12,0
  MOVI r12,@mth_ccf_selvote
  ST r0,r12,0

mth_ccf_scan:
  MOVI r7,0               ; accepted triads
  MOVI r6,0               ; triad index
mth_ccf_triad:
  MOVI r12,85
  CMP r6,r12
  JMP[GE] @mth_ccf_done
  MOVI r12,@mth_ccf_credits
  LD r10,r12,0
  MOVI r12,3
  MUL r9,r6,r12
  ADD r10,r10,r9
  MOVI r8,0               ; member votes
  MOVI r12,@mth_ccf_threshold
  LD r11,r12,0

  LD r13,r10,0
  CMPS r13,r11
  JMP[LE] @mth_ccf_m1
  ADDI r8,r8,1
mth_ccf_m1:
  ADDI r10,r10,1
  LD r13,r10,0
  CMPS r13,r11
  JMP[LE] @mth_ccf_m2
  ADDI r8,r8,1
mth_ccf_m2:
  ADDI r10,r10,1
  LD r13,r10,0
  CMPS r13,r11
  JMP[LE] @mth_ccf_vote
  ADDI r8,r8,1
mth_ccf_vote:
  MOVI r13,0
  MOVI r12,2
  CMPS r8,r12
  JMP[LT] @mth_ccf_store
  MOVI r13,1
  ADDI r7,r7,1
mth_ccf_store:
  MOVI r12,@mth_ccf_votes
  LD r10,r12,0
  ADD r10,r10,r6
  ST r13,r10,0
  MOVI r12,@mth_ccf_seltriad
  LD r10,r12,0
  CMP r6,r10
  JMP[NE] @mth_ccf_next
  MOVI r12,@mth_ccf_selvote
  ST r13,r12,0
mth_ccf_next:
  ADDI r6,r6,1
  JMP @mth_ccf_triad

mth_ccf_done:
  MOVI r10,43
  CMPS r7,r10
  MOVI r2,0
  JMP[LT] @mth_ccf_field_no
  MOVI r2,1
mth_ccf_field_no:
  ADD r1,r7,r0
  MOVI r12,@mth_ccf_before
  LD r4,r12,0
  MOVI r12,@mth_ccf_after
  LD r5,r12,0
  MOVI r12,@mth_ccf_selvote
  LD r3,r12,0
  MOVI r13,1
  MOVI r12,@mth_ccf_link
  LD r15,r12,0
  RET

mth_ccf_link:
  .word 0
mth_ccf_credits:
  .word 0
mth_ccf_threshold:
  .word 0
mth_ccf_votes:
  .word 0
mth_ccf_before:
  .word 0
mth_ccf_after:
  .word 0
mth_ccf_seltriad:
  .word 0xFFFF
mth_ccf_selvote:
  .word 0
