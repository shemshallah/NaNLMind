; Native NaN16 symbiotic candidate-and-data-leaf proof, one global brain.
; Takes REAL per-head opcode110 and per-triad opcode111 measurements already
; present in the SAME VM, and emits five typed candidate-only descriptors:
;   three independent HEAD diagonal curl/scalar + vector leaf references,
;   trihead gradient scalar + 128D TRIHEAD vector reference,
;   trihead radial depth scalar + oriented HYPEREDGE provenance reference.
; Each destination is mapped by the ORIGINAL full 128MiB mirror mapper.
; Candidate descriptors are NOT an active write, and are NOT promotions.
; The host may only transport/persist them after verifying signatures/leases.
; No 48M decoder mathematics is implemented in the host or this kernel.
;
; r1=request[12] U32:
; [0] triad t[0..84], [1] expected generation, [2] current generation,
; [3] Hodge/global gate=1, [4] MC0/meta gate=1,
; [5] 85 triad vote masks [0..7], [6] 255-member complete permutation,
; [7] 255 writer capabilities, [8] scratch[60] for 5 records,
; [9] output[60] for 5 records, [10] source digest pointer (not proof),
; [11] stable logical base leaf ID.
; all buffers nonzero and scratch/output disjoint. Input tables are read-only.
; Output record[12]:
; [0] proposer HEAD h, [1] tensor h, [2] tensor a, [3] tensor b,
; [4] absolute candidate-bank byte offset (>=67108864),
; [5] native F32 scalar bits, [6] leaf-kind (1=head128,2=trihead128,
;       3=hyperedge relation), [7] native 128D vector/edge data pointer,
; [8] data length in words, [9] generation,
; [10] source digest pointer, [11] logical_leaf_id.
;
; Accept requires ALL 85 vote masks valid, >=43 accepted triads (2/3),
; selected triad has 2/3 vote, exactly matching actual three HEAD Boolean
; votes produced by native opcode110, all 3 head-private writer caps,
; valid native 128D trihead projection and hot/cold classifications, matching
; same generation, Hodge/MC0 gates and a nonzero source digest reference.
; Return r1=1,r2=quorum_count,r3=5,r4=0.
; On ANY rejection r1=r2=r3=0,r4=1 contract/2 vote/3 member/
;     4 guest-math/5 candidate-map; output[60] remains UNMODIFIED.
;
; Dependencies: mth_hypertensor256_mirror_arena_map.nas,
; mth_hypertensor256_mirror_dual_map.nas.
; One serialized VM field cycle: static bookkeeping is not reentrant.
mth_native_symbiotic_leaf_feedback:
  MOVI r0,0
  ST r15,r0,@slf_link
  ST r1,r0,@slf_request
  CMP r1,r0
  JMP[EQ] @slf_bad_contract
  MOVI r9,5
slf_check_ptrs:
  MOVI r10,10
  CMP r9,r10
  JMP[GE] @slf_header
  LD r11,r1,r9
  CMP r11,r0
  JMP[EQ] @slf_bad_contract
  ADDI r9,r9,1
  JMP @slf_check_ptrs
slf_header:
  LD r10,r1,0
  MOVI r11,85
  CMP r10,r11
  JMP[GE] @slf_bad_contract
  CMPS r10,r0
  JMP[LT] @slf_bad_contract
  ST r10,r0,@slf_t
  LD r10,r1,1
  ST r10,r0,@slf_generation
  LD r11,r1,2
  CMP r10,r11
  JMP[NE] @slf_bad_contract
  LD r10,r1,3
  CMP r10,r13
  JMP[NE] @slf_bad_contract
  LD r10,r1,4
  CMP r10,r13
  JMP[NE] @slf_bad_contract
  LD r10,r1,8
  LD r11,r1,9
  CMP r10,r11
  JMP[EQ] @slf_bad_contract
  LD r10,r1,11
  CMP r10,r0
  JMP[EQ] @slf_bad_contract

  ; Validate ALL 85 triads and count 2-of-3 field majority.
  ST r0,r0,@slf_quorum
  MOVI r9,0
slf_validate_all:
  MOVI r10,85
  CMP r9,r10
  JMP[GE] @slf_check_quorum
  LD r11,r0,@slf_request
  LD r11,r11,5
  ADD r11,r11,r9
  LD r10,r11,0
  MOVI r12,7
  CMP r10,r12
  JMP[GT] @slf_bad_votes
  MOVI r11,3
  CMP r10,r11
  JMP[EQ] @slf_add_quorum
  MOVI r11,5
  CMP r10,r11
  JMP[EQ] @slf_add_quorum
  MOVI r11,6
  CMP r10,r11
  JMP[EQ] @slf_add_quorum
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @slf_next_vote
slf_add_quorum:
  LD r12,r0,@slf_quorum
  ADDI r12,r12,1
  ST r12,r0,@slf_quorum
slf_next_vote:
  ADDI r9,r9,1
  JMP @slf_validate_all
slf_check_quorum:
  LD r10,r0,@slf_quorum
  MOVI r11,43
  CMP r10,r11
  JMP[LT] @slf_bad_votes
  LD r10,r0,@slf_request
  LD r10,r10,5
  LD r11,r0,@slf_t
  ADD r10,r10,r11
  LD r10,r10,0
  ST r10,r0,@slf_vote
  MOVI r11,3
  CMP r10,r11
  JMP[EQ] @slf_check_members
  MOVI r11,5
  CMP r10,r11
  JMP[EQ] @slf_check_members
  MOVI r11,6
  CMP r10,r11
  JMP[EQ] @slf_check_members
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @slf_bad_votes

slf_check_members:
  ST r0,r0,@slf_member_vote
  ; Confirm all 255 map IDs are a UNIQUE permutation, not just 3 heads.
  MOVI r10,0x6000
  MOVHI r10,0x003C
  ST r10,r0,@slf_seen
  MOVI r9,0
slf_clear_seen:
  MOVI r10,255
  CMP r9,r10
  JMP[GE] @slf_map_validate
  LD r11,r0,@slf_seen
  ADD r11,r11,r9
  ST r0,r11,0
  ADDI r9,r9,1
  JMP @slf_clear_seen
slf_map_validate:
  MOVI r9,0
slf_each_map:
  MOVI r10,255
  CMP r9,r10
  JMP[GE] @slf_selected
  LD r11,r0,@slf_request
  LD r11,r11,6
  ADD r11,r11,r9
  LD r10,r11,0
  MOVI r12,255
  CMP r10,r12
  JMP[GE] @slf_bad_member
  CMPS r10,r0
  JMP[LT] @slf_bad_member
  LD r11,r0,@slf_seen
  ADD r11,r11,r10
  LD r12,r11,0
  CMP r12,r0
  JMP[NE] @slf_bad_member
  MOVI r12,1
  ST r12,r11,0
  ADDI r9,r9,1
  JMP @slf_each_map

slf_selected:
  MOVI r9,0
  ST r9,r0,@slf_hot
slf_member_loop:
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @slf_triad_meta
  LD r10,r0,@slf_t
  MOVI r11,3
  MUL r10,r10,r11
  ADD r10,r10,r9
  LD r11,r0,@slf_request
  LD r11,r11,6
  ADD r10,r11,r10
  LD r11,r10,0
  MOVI r10,@slf_members
  ADD r10,r10,r9
  ST r11,r10,0

  LD r10,r0,@slf_request
  LD r10,r10,7
  ADD r10,r10,r11
  LD r10,r10,0
  CMP r10,r13
  JMP[NE] @slf_bad_member

  MOVI r10,0
  MOVHI r10,0x003B
  SHL r12,r11,8
  ADD r10,r10,r12
  LD r12,r10,132
  CMP r12,r13
  JMP[NE] @slf_bad_member
  LD r12,r10,147
  CMP r12,r13
  JMP[NE] @slf_bad_member
  LD r12,r10,133
  LD r11,r0,@slf_generation
  CMP r12,r11
  JMP[NE] @slf_bad_member
  LD r12,r10,134
  CMP r12,r11
  JMP[NE] @slf_bad_member
  LD r12,r10,140
  CMP r12,r0
  JMP[EQ] @slf_cold_member
  CMP r12,r13
  JMP[NE] @slf_bad_member
  LD r11,r0,@slf_hot
  ADDI r11,r11,1
  ST r11,r0,@slf_hot
slf_cold_member:
  LD r12,r10,140
  MOVI r11,@slf_bit
  ADD r11,r11,r9
  LD r11,r11,0
  MUL r12,r12,r11
  LD r10,r0,@slf_member_vote
  BOOL.14 r10,r10,r12
  ST r10,r0,@slf_member_vote
  ADDI r9,r9,1
  JMP @slf_member_loop

slf_triad_meta:
  LD r10,r0,@slf_member_vote
  LD r11,r0,@slf_vote
  CMP r10,r11
  JMP[NE] @slf_bad_votes
  LD r10,r0,@slf_t
  SHL r10,r10,4
  MOVI r11,0xE000
  MOVHI r11,0x003E
  ADD r10,r10,r11
  ST r10,r0,@slf_meta
  LD r11,r10,12
  CMP r11,r13
  JMP[NE] @slf_bad_math
  LD r11,r10,13
  LD r12,r0,@slf_t
  CMP r11,r12
  JMP[NE] @slf_bad_math
  LD r11,r10,4
  MOVI r12,255
  CMP r11,r12
  JMP[NE] @slf_bad_math
  LD r11,r10,5
  LD r12,r0,@slf_hot
  CMP r11,r12
  JMP[NE] @slf_bad_math
  MOVI r12,3
  LD r11,r10,6
  LD r9,r0,@slf_hot
  ADD r9,r9,r11
  CMP r9,r12
  JMP[NE] @slf_bad_math
  ; Validate ball, signed credit and depth are finite and bounded.
  LD r10,r0,@slf_meta
  LD r11,r10,0
  LD r12,r10,1
  MOVI r8,0
  MOVHI r8,0x3F80
  FCMP r11,r8
  JMP[GE] @slf_bad_math
  FCMP r11,r0
  JMP[LT] @slf_bad_math
  FCMP r12,r0
  JMP[LT] @slf_bad_math
  LD r12,r10,10
  MOVI r8,0
  MOVHI r8,0x7F80
  MOVI r9,0xFFFF
  MOVHI r9,0x7FFF
  BOOL.8 r9,r9,r12
  BOOL.8 r9,r9,r8
  CMP r9,r8
  JMP[EQ] @slf_bad_math

  ; All five records use ORIGINAL native rank3 tensor mapper.
  MOVI r9,0
slf_stage_loop:
  MOVI r10,5
  CMP r9,r10
  JMP[GE] @slf_publish
  ST r9,r0,@slf_index
  ; first 3 are head diagonals; last two are distinct trihead scalars
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @slf_triad_record
  MOVI r10,@slf_members
  ADD r10,r10,r9
  LD r1,r10,0
  ADD r2,r1,r0
  ADD r3,r1,r0
  ST r1,r0,@slf_proposer
  MOVI r10,0
  MOVHI r10,0x003B
  SHL r11,r1,8
  ADD r10,r10,r11
  LD r11,r10,143
  ST r11,r0,@slf_value
  MOVI r11,1
  ST r11,r0,@slf_kind
  MOVI r10,0
  MOVHI r10,0x003F
  SHL r11,r1,8
  ADD r10,r10,r11
  ST r10,r0,@slf_leafptr
  MOVI r11,128
  ST r11,r0,@slf_leaflen
  JMP @slf_mapped
slf_triad_record:
  MOVI r10,@slf_members
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  ST r1,r0,@slf_proposer
  MOVI r11,4
  CMP r9,r11
  JMP[EQ] @slf_depth
  ADD r3,r2,r0
  LD r10,r0,@slf_meta
  LD r11,r10,10
  ST r11,r0,@slf_value
  MOVI r11,2
  ST r11,r0,@slf_kind
  LD r11,r0,@slf_t
  SHL r11,r11,7
  MOVI r10,0xB000
  MOVHI r10,0x003E
  ADD r10,r10,r11
  ST r10,r0,@slf_leafptr
  MOVI r11,128
  ST r11,r0,@slf_leaflen
  JMP @slf_mapped
slf_depth:
  ADD r2,r3,r0
  LD r10,r0,@slf_meta
  LD r11,r10,1
  ST r11,r0,@slf_value
  MOVI r11,3
  ST r11,r0,@slf_kind
  LD r11,r0,@slf_t
  SHL r11,r11,3
  MOVI r10,0xE600
  MOVHI r10,0x003E
  ADD r10,r10,r11
  ST r10,r0,@slf_leafptr
  MOVI r11,8
  ST r11,r0,@slf_leaflen
slf_mapped:
  ST r1,r0,@slf_h
  ST r2,r0,@slf_a
  ST r3,r0,@slf_b
  MOVI r8,1
  CALL @mth_hypertensor256_mirror_dual_map
  CMP r1,r13
  JMP[NE] @slf_bad_map
  LD r9,r0,@slf_index
  LD r10,r0,@slf_request
  LD r10,r10,8
  MOVI r11,12
  MUL r11,r11,r9
  ADD r10,r10,r11
  LD r11,r0,@slf_proposer
  ST r11,r10,0
  LD r11,r0,@slf_h
  ST r11,r10,1
  LD r11,r0,@slf_a
  ST r11,r10,2
  LD r11,r0,@slf_b
  ST r11,r10,3
  ST r6,r10,4
  LD r11,r0,@slf_value
  ST r11,r10,5
  LD r11,r0,@slf_kind
  ST r11,r10,6
  LD r11,r0,@slf_leafptr
  ST r11,r10,7
  LD r11,r0,@slf_leaflen
  ST r11,r10,8
  LD r11,r0,@slf_generation
  ST r11,r10,9
  LD r11,r0,@slf_request
  LD r11,r11,10
  ST r11,r10,10
  LD r11,r0,@slf_request
  LD r11,r11,11
  ADD r11,r11,r9
  ST r11,r10,11
  ADDI r9,r9,1
  JMP @slf_stage_loop
slf_publish:
  LD r10,r0,@slf_request
  LD r10,r10,8
  LD r11,r0,@slf_request
  LD r11,r11,9
  MOVI r9,0
slf_copy:
  MOVI r12,60
  CMP r9,r12
  JMP[GE] @slf_success
  LD r12,r10,0
  ST r12,r11,0
  ADDI r10,r10,1
  ADDI r11,r11,1
  ADDI r9,r9,1
  JMP @slf_copy
slf_success:
  MOVI r1,1
  LD r2,r0,@slf_quorum
  MOVI r3,5
  MOVI r4,0
  JMP @slf_return
slf_bad_contract:
  MOVI r4,1
  JMP @slf_reject
slf_bad_votes:
  MOVI r4,2
  JMP @slf_reject
slf_bad_member:
  MOVI r4,3
  JMP @slf_reject
slf_bad_math:
  MOVI r4,4
  JMP @slf_reject
slf_bad_map:
  MOVI r4,5
slf_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
slf_return:
  LD r15,r0,@slf_link
  MOVI r13,1
  RET
slf_link:
  .word 0
slf_request:
  .word 0
slf_quorum:
  .word 0
slf_t:
  .word 0
slf_vote:
  .word 0
slf_member_vote:
  .word 0
slf_hot:
  .word 0
slf_members:
  .word 0,0,0
slf_seen:
  .word 0
slf_meta:
  .word 0
slf_generation:
  .word 0
slf_index:
  .word 0
slf_proposer:
  .word 0
slf_h:
  .word 0
slf_a:
  .word 0
slf_b:
  .word 0
slf_value:
  .word 0
slf_kind:
  .word 0
slf_leafptr:
  .word 0
slf_leaflen:
  .word 0
