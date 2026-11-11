; NaN16 native causal three-future-word prefix window: one step per generated word.
; This is the NaN-side context gate for the EXISTING frozen 48M decoder.
; No new decoder, no host math, no ground-truth future, no ACTIVE tensor write.
;
; Input r1=observed word IDs[1..4096] (read only), r2=observed count,
;       r3=generated prefix[0..2] (read only), r4=generated_count (0..2),
;       r5=expected generation, r6=current generation, r7=request[12].
; r13=1. The caller must use each actual decoder-selected generated word as
; the NEXT step's prefix; external source/provenance validation is mandatory.
; IMPORTANT: generated[g..2] are NEVER read; they may contain poison/gold.
; Output request matches mth_six_context_poincare_attention:
; [anchor, -3,-2,-1, 0,0,0, causal_mask, 0, gen,gen, NOW=255].
; r1=accepted (1/0), r2=mask (or zero), r3=horizon 1..3 (or zero),
; r4=0 success/1 malformed/2 stale. Rejection does not publish request.
; Uses isolated static scratch and must be called serially in one NaN0S VM.
mth_future3_causal_window:
  MOVI r0,0
  ST r15,r0,@f3_link
  ST r1,r0,@f3_observed
  ST r2,r0,@f3_count
  ST r3,r0,@f3_generated
  ST r4,r0,@f3_gcount
  ST r5,r0,@f3_epoch
  ST r7,r0,@f3_output
  CMP r1,r0
  JMP[EQ] @f3_bad
  CMP r3,r0
  JMP[EQ] @f3_bad
  CMP r7,r0
  JMP[EQ] @f3_bad
  CMP r1,r7
  JMP[EQ] @f3_bad
  CMP r3,r7
  JMP[EQ] @f3_bad
  CMP r2,r0
  JMP[LE] @f3_bad
  MOVI r10,4096
  CMP r2,r10
  JMP[GT] @f3_bad
  CMPS r4,r0
  JMP[LT] @f3_bad
  MOVI r10,2
  CMP r4,r10
  JMP[GT] @f3_bad
  CMP r5,r6
  JMP[NE] @f3_stale

  ; Stage a fresh request: never inherit another horizon's future slots.
  MOVI r8,0
f3_clear:
  MOVI r10,12
  CMP r8,r10
  JMP[GE] @f3_collect
  MOVI r10,@f3_request
  ADD r10,r10,r8
  ST r0,r10,0
  ADDI r8,r8,1
  JMP @f3_clear

f3_collect:
  MOVI r8,0
f3_slot:
  MOVI r10,3
  CMP r8,r10
  JMP[GE] @f3_publish
  LD r9,r0,@f3_count
  LD r10,r0,@f3_gcount
  ADD r9,r9,r10
  MOVI r10,3
  SUB r9,r9,r10
  ADD r9,r9,r8
  CMPS r9,r0
  JMP[LT] @f3_next
  LD r10,r0,@f3_count
  CMP r9,r10
  JMP[GE] @f3_generated_word
  LD r11,r0,@f3_observed
  ADD r11,r11,r9
  LD r12,r11,0
  JMP @f3_store
f3_generated_word:
  SUB r9,r9,r10
  LD r10,r0,@f3_gcount
  CMP r9,r10
  JMP[GE] @f3_bad
  LD r11,r0,@f3_generated
  ADD r11,r11,r9
  LD r12,r11,0
f3_store:
  CMP r12,r0
  JMP[EQ] @f3_bad
  MOVI r11,@f3_request
  ADD r11,r11,r8
  ST r12,r11,1
  MOVI r11,@f3_bits
  ADD r11,r11,r8
  LD r11,r11,0
  LD r10,r0,@f3_mask
  BOOL.14 r10,r10,r11
  ST r10,r0,@f3_mask
f3_next:
  ADDI r8,r8,1
  JMP @f3_slot

f3_publish:
  LD r10,r0,@f3_mask
  CMP r10,r0
  JMP[EQ] @f3_bad
  ; Index 3 is always the most recent OBSERVED or GENERATED word.
  MOVI r10,@f3_request
  LD r11,r10,3
  CMP r11,r0
  JMP[EQ] @f3_bad
  ST r11,r10,0
  LD r11,r0,@f3_mask
  ST r11,r10,7
  LD r11,r0,@f3_epoch
  ST r11,r10,9
  ST r11,r10,10
  MOVI r11,255
  ST r11,r10,11
  ; Publish only after the whole three-past causal request passed.
  MOVI r8,0
f3_copy:
  MOVI r10,12
  CMP r8,r10
  JMP[GE] @f3_success
  MOVI r10,@f3_request
  ADD r10,r10,r8
  LD r11,r10,0
  LD r10,r0,@f3_output
  ADD r10,r10,r8
  ST r11,r10,0
  ADDI r8,r8,1
  JMP @f3_copy
f3_success:
  MOVI r1,1
  LD r2,r0,@f3_mask
  LD r3,r0,@f3_gcount
  ADDI r3,r3,1
  MOVI r4,0
  JMP @f3_return
f3_bad:
  MOVI r4,1
  JMP @f3_reject
f3_stale:
  MOVI r4,2
f3_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
f3_return:
  ST r0,r0,@f3_mask
  MOVI r13,1
  LD r15,r0,@f3_link
  RET
f3_link:      .word 0
f3_observed:  .word 0
f3_count:     .word 0
f3_generated: .word 0
f3_gcount:    .word 0
f3_epoch:     .word 0
f3_output:    .word 0
f3_mask:      .word 0
f3_bits:      .word 1,2,4
f3_request:   .word 0,0,0,0,0,0,0,0,0,0,0,0
