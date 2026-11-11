; Native NaN16 weighted-spectral -> trihead -> mirrored hypertensor proposal.
; Produces NO active tensor writes and NO external arena writes.
; An authenticated native arena controller must validate generation and writer
; capability again before applying any record to the CANDIDATE bank.
;
; Input to this kernel is a VERIFIED weighted-CSR-v2 Laplacian result:
; signed I64 Q16.16 words (low,high) for each of 256 physical heads.
; It deliberately does not reimplement spectral mathematics in host code.
;
; ABI: r1 = pointer to 12-word request (r0=0,r13=1):
;   [0] spectral_i64[256][2]      [1] trihead_vote_masks[85]
;   [2] target_pairs[255][2]      [3] writer_authority[255] (0/1)
;   [4] scratch_records[255][5]   [5] output_records[255][5]
;   [6] expected_generation      [7] current_generation
;   [8] global_hodge_gate (0/1)  [9] MC0_meta_gate (0/1)
;  [10] reserved=0               [11] reserved=0
; r1=1 success / 0 reject, r2=approved triheads, r3=records, r4=reason.
; No output_records bytes are touched on ANY rejection.
;
; Output record: [head, a, b, absolute_candidate_byte_offset, signed_Q16_credit].
; Offsets are computed by mth_hypertensor256_mirror_dual_map with bank=1:
; 64MiB active + 64MiB candidate; mirror (a,b) and (b,a) stay independent.
; Every recorded head was authorized, voted, non-void and nonzero.
; Triad quorum >=43 of 85, each approved triad >=2 actual member bits.
; 0..254 are candidate mathematical coordinates; 255 is physical ZERO/VOID.
; Head 0 is not implicitly authorized: only explicit permissions allow it.
; The caller owns disjoint bounded input/scratch/output RAM spans, and must
; check authentication/provenance/finite 48M NLL/persistence outside this guest.
; One guest invocation at a time (non-reentrant scratch bookkeeping).
;
; Depends on mth_hypertensor256_mirror_arena_map.nas and
; mth_hypertensor256_mirror_dual_map.nas in the containing image.
mth_spectral_trihead_tensor_proposal:
  MOVI r0,0
  ST r15,r0,@sp_link
  ST r1,r0,@sp_request
  MOVI r2,0
  MOVI r3,0
  CMP r1,r0
  JMP[EQ] @sp_bad_contract
  MOVI r12,0
sp_gate_pointers:
  LD r10,r1,0
  CMP r10,r0
  JMP[EQ] @sp_bad_contract
  ADDI r1,r1,1
  ADDI r12,r12,1
  MOVI r11,6
  CMP r12,r11
  JMP[LT] @sp_gate_pointers
  LD r1,r0,@sp_request
  LD r10,r1,4
  LD r11,r1,5
  CMP r10,r11
  JMP[EQ] @sp_bad_contract
  LD r10,r1,6
  LD r11,r1,7
  CMP r10,r11
  JMP[NE] @sp_bad_contract
  LD r10,r1,8
  CMP r10,r13
  JMP[NE] @sp_bad_contract
  LD r10,r1,9
  CMP r10,r13
  JMP[NE] @sp_bad_contract
  LD r10,r1,10
  CMP r10,r0
  JMP[NE] @sp_bad_contract
  LD r10,r1,11
  CMP r10,r0
  JMP[NE] @sp_bad_contract

  ; Full validation first. No output or ACTIVE bank is ever touched here.
  MOVI r9,0
sp_validate_spectral:
  LD r1,r0,@sp_request
  LD r1,r1,0
  SHL r10,r9,1
  ADD r1,r1,r10
  LD r10,r1,0
  LD r11,r1,1
  MOVI r12,255
  CMP r9,r12
  JMP[NE] @sp_validate_signed
  CMP r10,r0
  JMP[NE] @sp_bad_numeric
  CMP r11,r0
  JMP[NE] @sp_bad_numeric
  JMP @sp_validate_next
sp_validate_signed:
  CMPS r10,r0
  JMP[LT] @sp_validate_negative
  CMP r11,r0
  JMP[NE] @sp_bad_numeric
  MOVI r12,0
  MOVHI r12,0x0001
  CMPS r10,r12
  JMP[GT] @sp_bad_numeric
  JMP @sp_validate_pair
sp_validate_negative:
  MOVI r12,0xFFFF
  MOVHI r12,0xFFFF
  CMP r11,r12
  JMP[NE] @sp_bad_numeric
  MOVI r12,0
  MOVHI r12,0xFFFF
  CMPS r10,r12
  JMP[LT] @sp_bad_numeric
sp_validate_pair:
  LD r1,r0,@sp_request
  LD r1,r1,3
  ADD r1,r1,r9
  LD r10,r1,0
  MOVI r11,1
  CMP r10,r11
  JMP[GT] @sp_bad_numeric
  LD r1,r0,@sp_request
  LD r1,r1,2
  SHL r12,r9,1
  ADD r1,r1,r12
  LD r10,r1,0
  LD r11,r1,1
  MOVI r12,254
  CMP r10,r12
  JMP[GT] @sp_bad_numeric
  CMP r11,r12
  JMP[GT] @sp_bad_numeric
sp_validate_next:
  ADDI r9,r9,1
  MOVI r12,256
  CMP r9,r12
  JMP[LT] @sp_validate_spectral

  ; Validate all 85 masks before counting a field quorum.
  MOVI r9,0
  ST r0,r0,@sp_approved
sp_vote_loop:
  LD r1,r0,@sp_request
  LD r1,r1,1
  ADD r1,r1,r9
  LD r10,r1,0
  MOVI r11,7
  CMP r10,r11
  JMP[GT] @sp_bad_votes
  MOVI r11,3
  CMP r10,r11
  JMP[EQ] @sp_vote_approve
  MOVI r11,5
  CMP r10,r11
  JMP[EQ] @sp_vote_approve
  MOVI r11,6
  CMP r10,r11
  JMP[EQ] @sp_vote_approve
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @sp_vote_next
sp_vote_approve:
  LD r11,r0,@sp_approved
  ADDI r11,r11,1
  ST r11,r0,@sp_approved
sp_vote_next:
  ADDI r9,r9,1
  MOVI r11,85
  CMP r9,r11
  JMP[LT] @sp_vote_loop
  LD r11,r0,@sp_approved
  MOVI r12,43
  CMP r11,r12
  JMP[LT] @sp_bad_votes

  ; Stage only authorized member-voters from approving triheads.
  ST r0,r0,@sp_count
  MOVI r9,0
sp_stage_loop:
  MOVI r12,255
  CMP r9,r12
  JMP[GE] @sp_finish_stage
  LD r1,r0,@sp_request
  LD r1,r1,3
  ADD r1,r1,r9
  LD r10,r1,0
  CMP r10,r13
  JMP[NE] @sp_stage_next
  MOVI r8,3
  DIV r10,r9,r8
  MUL r11,r10,r8
  SUB r11,r9,r11
  MOVI r12,@sp_member_bits
  ADD r12,r12,r11
  LD r12,r12,0
  LD r1,r0,@sp_request
  LD r1,r1,1
  ADD r1,r1,r10
  LD r10,r1,0
  BOOL.8 r11,r10,r12
  CMP r11,r0
  JMP[EQ] @sp_stage_next
  ; All masks with fewer than two bits were counted as non-quorum;
  ; no member of those groups may propose tensor updates.
  MOVI r11,3
  CMP r10,r11
  JMP[EQ] @sp_stage_map
  MOVI r11,5
  CMP r10,r11
  JMP[EQ] @sp_stage_map
  MOVI r11,6
  CMP r10,r11
  JMP[EQ] @sp_stage_map
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @sp_stage_next
sp_stage_map:
  LD r1,r0,@sp_request
  LD r1,r1,2
  SHL r10,r9,1
  ADD r1,r1,r10
  LD r2,r1,0
  LD r3,r1,1
  ST r2,r0,@sp_a
  ST r3,r0,@sp_b
  ADD r1,r9,r0
  ST r9,r0,@sp_index
  MOVI r8,1
  CALL @mth_hypertensor256_mirror_dual_map
  LD r9,r0,@sp_index
  CMP r1,r13
  JMP[NE] @sp_bad_map
  ST r6,r0,@sp_offset
  LD r1,r0,@sp_request
  LD r1,r1,4
  LD r10,r0,@sp_count
  MOVI r11,5
  MUL r10,r10,r11
  ADD r1,r1,r10
  ST r9,r1,0
  LD r10,r0,@sp_a
  ST r10,r1,1
  LD r10,r0,@sp_b
  ST r10,r1,2
  LD r10,r0,@sp_offset
  ST r10,r1,3
  LD r10,r0,@sp_request
  LD r10,r10,0
  SHL r11,r9,1
  ADD r10,r10,r11
  LD r11,r10,0
  ST r11,r1,4
  LD r10,r0,@sp_count
  ADDI r10,r10,1
  ST r10,r0,@sp_count
sp_stage_next:
  ADDI r9,r9,1
  JMP @sp_stage_loop

sp_finish_stage:
  LD r2,r0,@sp_count
  CMP r2,r0
  JMP[EQ] @sp_bad_empty
  ; Publication occurs only after all validation and stage mapping succeed.
  LD r1,r0,@sp_request
  LD r10,r1,4
  LD r11,r1,5
  MOVI r12,5
  MUL r3,r2,r12
  MOVI r9,0
sp_publish:
  CMP r9,r3
  JMP[GE] @sp_success
  LD r12,r10,0
  ST r12,r11,0
  ADDI r10,r10,1
  ADDI r11,r11,1
  ADDI r9,r9,1
  JMP @sp_publish
sp_success:
  MOVI r1,1
  LD r2,r0,@sp_approved
  LD r3,r0,@sp_count
  MOVI r4,0
  JMP @sp_return

sp_bad_contract:
  MOVI r4,1
  JMP @sp_reject
sp_bad_votes:
  MOVI r4,2
  JMP @sp_reject
sp_bad_numeric:
  MOVI r4,3
  JMP @sp_reject
sp_bad_map:
  MOVI r4,4
  JMP @sp_reject
sp_bad_empty:
  MOVI r4,5
sp_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
sp_return:
  LD r15,r0,@sp_link
  RET

sp_link:
  .word 0
sp_request:
  .word 0
sp_a:
  .word 0
sp_b:
  .word 0
sp_offset:
  .word 0
sp_count:
  .word 0
sp_approved:
  .word 0
sp_index:
  .word 0
sp_member_bits:
  .word 1,2,4
