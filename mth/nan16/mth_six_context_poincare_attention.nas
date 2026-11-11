; Raw NaN16 six-neighbor TEMPORAL self-attention with trigonometric
; word-phase keys, one NOW/VOID point, and actual 2D Poincare ball projection.
;
; Positions: 0=-3,1=-2,2=-1,3=+1,4=+2,5=+3; now is NOT a learner.
; r1 -> request U32[12]:
;   [0] observed anchor word ID/explicit public mask symbol (NOT target label)
;   [1..6] context word IDs, zeroed exactly when missing
;   [7] valid mask 6 bits
;   [8] task 0 causal next-word / 1 bidirectional masked infill
;   [9] expected generation [10] actual generation [11] NOW head=255
; r2 -> output[8] (unmodified on any rejection):
;   [0] Poincare x F32, [1] Poincare y F32, [2] radius F32,
;   [3] EXACT radial Poincare distance F32=log((1+r)/(1-r)),
;   [4] mask, [5] task, [6] VOID head=255, [7] anchor ID.
; return r1=1 accepted, r2=count, r3=task, r4=0.
; reject r1=r2=r3=0, r4=1 malformed /2 causality /3 stale/4 guest.
;
; Query and content-dependent masked softmax use the EXISTING native
; mth_meta_attention16_f32 kernel (6 slots, D=2), not a host substitute.
; Keys/values are native 16-iteration CORDIC phasors for each word ID,
; with positional offsets of 1024-turn units per distance. "Temporal NOW"
; is an observation anchor at physical 255, never a candidate writer.
; Radius is strictly <1 by contract, including when phasors align.
; This is a genuine 2D Poincare-ball feature, NOT an unproven 128D
; hyperbolic geodesic or semantic concept representation.
;
; IMPORTANT: Future words are NEVER accepted in task 0 even if caller
; supplied them; masks and IDs are jointly validated before processing.
; Task 1 uses future words ONLY when the target word was truly masked.
; The host must enforce provenance and the latter target masking.
; Static scratch: one invocation at a time; caller must supply disjoint buffers.
; Requires mth_q16_sin_cos.nas + mth_meta_attention16_f32.nas.

mth_six_context_poincare_attention:
  MOVI r0,0
  ST r15,r0,@scpa_link
  ST r1,r0,@scpa_request
  ST r2,r0,@scpa_output
  CMP r1,r0
  JMP[EQ] @scpa_bad_input
  CMP r2,r0
  JMP[EQ] @scpa_bad_input
  CMP r1,r2
  JMP[EQ] @scpa_bad_input
  LD r10,r1,0
  CMP r10,r0
  JMP[EQ] @scpa_bad_input
  LD r8,r1,7
  CMP r8,r0
  JMP[EQ] @scpa_bad_input
  SHR r10,r8,6
  CMP r10,r0
  JMP[NE] @scpa_bad_input
  LD r9,r1,8
  MOVI r10,1
  CMP r9,r10
  JMP[GT] @scpa_bad_input
  CMP r9,r0
  JMP[NE] @scpa_infill
  MOVI r10,56
  BOOL.8 r11,r8,r10
  CMP r11,r0
  JMP[NE] @scpa_bad_causal
scpa_infill:
  LD r10,r1,9
  LD r11,r1,10
  CMP r10,r11
  JMP[NE] @scpa_bad_generation
  LD r10,r1,11
  MOVI r11,255
  CMP r10,r11
  JMP[NE] @scpa_bad_input
  MOVI r9,0
  ST r0,r0,@scpa_valid
scpa_validate_loop:
  MOVI r10,6
  CMP r9,r10
  JMP[GE] @scpa_prepare
  LD r1,r0,@scpa_request
  ADD r1,r1,r9
  LD r7,r1,1
  LD r1,r0,@scpa_request
  LD r8,r1,7
  MOVI r10,@scpa_mask_bits
  ADD r10,r10,r9
  LD r10,r10,0
  BOOL.8 r8,r8,r10
  CMP r8,r0
  JMP[EQ] @scpa_absent
  CMP r7,r0
  JMP[EQ] @scpa_bad_input
  LD r10,r0,@scpa_valid
  ADDI r10,r10,1
  ST r10,r0,@scpa_valid
  JMP @scpa_validate_next
scpa_absent:
  CMP r7,r0
  JMP[NE] @scpa_bad_input
scpa_validate_next:
  ADDI r9,r9,1
  JMP @scpa_validate_loop

scpa_prepare:
  ; query = CORDIC(canonical observed anchor phase)
  LD r10,r0,@scpa_request
  LD r1,r10,0
  MOVI r11,0xFFFF
  BOOL.8 r1,r1,r11
  CALL @mth_q16_sin_cos
  MOVI r10,0
  MOVHI r10,0x4780
  CVTIF r1,r1
  FDIV r1,r1,r10
  ST r1,r0,@scpa_query
  CVTIF r2,r2
  FDIV r2,r2,r10
  ST r2,r0,@scpa_query+1

  MOVI r9,0
  ST r9,r0,@scpa_i
scpa_encode_loop:
  LD r9,r0,@scpa_i
  MOVI r10,6
  CMP r9,r10
  JMP[GE] @scpa_attention
  LD r10,r0,@scpa_request
  ADD r10,r10,r9
  LD r11,r10,1
  MOVI r10,@scpa_word_slot
  ST r11,r10,0
  LD r10,r0,@scpa_request
  LD r8,r10,7
  MOVI r10,@scpa_mask_bits
  ADD r10,r10,r9
  LD r10,r10,0
  BOOL.8 r8,r8,r10
  MOVI r10,0
  CMP r8,r0
  JMP[EQ] @scpa_absent_slot
  MOVI r10,1
scpa_absent_slot:
  MOVI r11,@scpa_masks
  ADD r11,r11,r9
  ST r10,r11,0
  CMP r10,r0
  JMP[EQ] @scpa_zero_slot

  ; Word phase + time-offset phase. Native CORDIC Q16 -> native F32.
  LD r1,r0,@scpa_word_slot
  MOVI r10,@scpa_offsets
  ADD r10,r10,r9
  LD r10,r10,0
  ADD r1,r1,r10
  MOVI r10,0xFFFF
  BOOL.8 r1,r1,r10
  CALL @mth_q16_sin_cos
  MOVI r10,0
  MOVHI r10,0x4780
  CVTIF r1,r1
  FDIV r1,r1,r10
  CVTIF r2,r2
  FDIV r2,r2,r10
  JMP @scpa_write_slot
scpa_zero_slot:
  MOVI r1,0
  MOVI r2,0
scpa_write_slot:
  LD r9,r0,@scpa_i
  SHL r10,r9,1
  MOVI r11,@scpa_keys
  ADD r11,r11,r10
  ST r1,r11,0
  ST r2,r11,1
  MOVI r11,@scpa_values
  ADD r11,r11,r10
  ST r1,r11,0
  ST r2,r11,1
  ADDI r9,r9,1
  ST r9,r0,@scpa_i
  JMP @scpa_encode_loop

scpa_attention:
  MOVI r1,@scpa_query
  MOVI r2,@scpa_keys
  MOVI r3,@scpa_values
  MOVI r4,6
  MOVI r5,2
  MOVI r6,@scpa_masks
  MOVI r7,@scpa_attended
  CALL @mth_meta_attention16_f32
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @scpa_bad_guest

  ; Poincare disk projection of native normalized contextual vector:
  ; p = v/(1+||v||). Norm and hyperbolic radial distance are native F32.
  LD r5,r0,@scpa_attended
  LD r6,r0,@scpa_attended+1
  FMUL r7,r5,r5
  FMUL r8,r6,r6
  FADD r7,r7,r8
  FSQRT r7,r7
  MOVI r8,0
  MOVHI r8,0x3F80
  FADD r9,r7,r8
  FDIV r10,r5,r9
  FDIV r11,r6,r9
  FDIV r12,r7,r9
  ; d_hyp = log((1+r)/(1-r)) for r<1.
  FADD r1,r8,r12
  FSUB r2,r8,r12
  FDIV r3,r1,r2
  FLOG r3,r3

  LD r4,r0,@scpa_output
  ST r10,r4,0
  ST r11,r4,1
  ST r12,r4,2
  ST r3,r4,3
  LD r1,r0,@scpa_request
  LD r5,r1,7
  ST r5,r4,4
  LD r5,r1,8
  ST r5,r4,5
  LD r5,r1,11
  ST r5,r4,6
  LD r5,r1,0
  ST r5,r4,7
  MOVI r1,1
  LD r2,r0,@scpa_valid
  LD r3,r0,@scpa_request
  LD r3,r3,8
  MOVI r4,0
  JMP @scpa_return
scpa_bad_input:
  MOVI r4,1
  JMP @scpa_reject
scpa_bad_causal:
  MOVI r4,2
  JMP @scpa_reject
scpa_bad_generation:
  MOVI r4,3
  JMP @scpa_reject
scpa_bad_guest:
  MOVI r4,4
scpa_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
scpa_return:
  MOVI r13,1
  LD r15,r0,@scpa_link
  RET

scpa_link: .word 0
scpa_request: .word 0
scpa_output: .word 0
scpa_valid: .word 0
scpa_i: .word 0
scpa_word_slot: .word 0
scpa_mask_bits:
  .word 1,2,4,8,16,32
scpa_offsets:
  .word 62464,63488,64512,1024,2048,3072
scpa_query:
  .word 0,0
scpa_keys:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
scpa_values:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
scpa_masks:
  .word 0,0,0,0,0,0
scpa_attended:
  .word 0,0
