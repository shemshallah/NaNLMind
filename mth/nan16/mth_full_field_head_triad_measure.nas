; One canonical NaN16 full-field measurement cycle: 255 independent heads,
; 85 genuine 128D triheads, no fabricated 84-triad quorum.
;
; Source/provenance boundary: input head[h] 128D source vectors, Boolean16
; masks/operands, writer leases, oriented hyperedge IDs, sourced Hodge curls
; and generation MUST be prepared by an authenticated controller. Trihead
; curl[85] and seven_credit[85] MUST come from sourced native kernels.
; THIS ROUTINE DOES NOT FABRICATE THESE SOURCES OR PROMOTE ACTIVE WEIGHTS.
;
; ABI (r0=0, r13=1):
;   r1 mapping[255] unique permutation of 0..254
;   r2 trihead_hodge_curl_f32[85] (oriented, sourced; may be zero)
;   r3 trihead_seven_credit_q16[85] (sourced; each within [-8,+8])
;   r4 expected_epoch, r5 observed_epoch
;   r6 output_votes[85], r7 output_report[10] (disjoint buffers)
; Return r1=1 when ALL HEAD and TRIHEAD native math was measured;
;   r2 = number of 2/3 HOT triheads (0..85)
;   r3 = measured head count (255), r4=0
; Rejection r1=r2=r3=0, r4=1 contract/2 stale/3 bad mapping, 
;                            4 head geometry/5 trihead geometry.
; No votes/report are published on rejection. All intermediate vectors are
; still independent in head and triad scratch; a late failure can leave
; partially measured scratch, but never a published field or tensor update.
;
; output_report: [0] 255 heads measured, [1] 85 triheads measured,
; [2] HOT heads, [3] 2/3 HOT triheads, [4] 2/3 COLD triheads,
; [5] unanimous 3/3 HOT, [6] unanimous 3/3 COLD,
; [7] 43/85 HOT field gate, [8] NOW VOID=255, [9] epoch.
; Every mask comes from actual per-head Boolean output, not provided masks.
; The 3/3 HOT/COLD gradient vector and depth remain in native triad scratch
; 0x3EB000+t*128 and 0x3EE000+t*16 respectively. Nothing is reduced to
; a fake scalar "tensor vector". Trihead eligibility is NOT exact BPTT.
;
; The outer caller MUST re-check leases, generation and native global/meta
; gates before candidate-only typed tensor leaves are staged. This is one
; serialized field cycle; shared BOOL opcode patching is not reentrant.
mth_full_field_head_triad_measure:
  MOVI r0,0
  ST r15,r0,@ff_link
  ST r1,r0,@ff_map
  ST r2,r0,@ff_curls
  ST r3,r0,@ff_credits
  ST r4,r0,@ff_epoch
  ST r6,r0,@ff_votes_out
  ST r7,r0,@ff_report_out
  CMP r1,r0
  JMP[EQ] @ff_bad_contract
  CMP r2,r0
  JMP[EQ] @ff_bad_contract
  CMP r3,r0
  JMP[EQ] @ff_bad_contract
  CMP r6,r0
  JMP[EQ] @ff_bad_contract
  CMP r7,r0
  JMP[EQ] @ff_bad_contract
  CMP r6,r7
  JMP[EQ] @ff_bad_contract
  CMP r4,r5
  JMP[NE] @ff_bad_stale

  ; Validate full permutation and EVERY head's writer + current epoch
  ; before running a single mutable Boolean guest instruction.
  MOVI r8,0
ff_clear_seen:
  MOVI r10,255
  CMP r8,r10
  JMP[GE] @ff_preflight
  MOVI r10,0xF400
  MOVHI r10,0x003E
  ADD r10,r10,r8
  ST r0,r10,0
  ADDI r8,r8,1
  JMP @ff_clear_seen

ff_preflight:
  MOVI r8,0
ff_each_head:
  MOVI r10,255
  CMP r8,r10
  JMP[GE] @ff_measure_heads
  LD r9,r0,@ff_map
  ADD r9,r9,r8
  LD r11,r9,0
  MOVI r10,255
  CMP r11,r10
  JMP[GE] @ff_bad_map
  CMPS r11,r0
  JMP[LT] @ff_bad_map
  MOVI r10,0xF400
  MOVHI r10,0x003E
  ADD r10,r10,r11
  LD r9,r10,0
  CMP r9,r0
  JMP[NE] @ff_bad_map
  MOVI r9,1
  ST r9,r10,0
  ; Independently owned scratch at 0x3B0000+h*256.
  MOVI r10,0
  MOVHI r10,0x003B
  SHL r12,r11,8
  ADD r10,r10,r12
  LD r9,r10,132
  MOVI r12,1
  CMP r9,r12
  JMP[NE] @ff_bad_map
  LD r9,r10,133
  LD r12,r0,@ff_epoch
  CMP r9,r12
  JMP[NE] @ff_bad_stale
  LD r9,r10,134
  CMP r9,r12
  JMP[NE] @ff_bad_stale
  ADDI r8,r8,1
  JMP @ff_each_head

ff_measure_heads:
  ST r0,r0,@ff_index
  ST r0,r0,@ff_hot_heads
ff_measure_head_loop:
  LD r8,r0,@ff_index
  MOVI r10,255
  CMP r8,r10
  JMP[GE] @ff_measure_triads
  LD r9,r0,@ff_map
  ADD r9,r9,r8
  LD r1,r9,0
  CALL @mth_head16_poincare_measure
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @ff_bad_head
  CMP r3,r0
  JMP[EQ] @ff_head_done
  MOVI r10,1
  CMP r3,r10
  JMP[NE] @ff_bad_head
  LD r10,r0,@ff_hot_heads
  ADDI r10,r10,1
  ST r10,r0,@ff_hot_heads
ff_head_done:
  LD r8,r0,@ff_index
  ADDI r8,r8,1
  ST r8,r0,@ff_index
  JMP @ff_measure_head_loop

ff_measure_triads:
  ST r0,r0,@ff_index
  ST r0,r0,@ff_accepted
  ST r0,r0,@ff_cold_major
  ST r0,r0,@ff_allhot
  ST r0,r0,@ff_allcold
ff_measure_triad_loop:
  LD r8,r0,@ff_index
  MOVI r10,85
  CMP r8,r10
  JMP[GE] @ff_publish
  LD r9,r0,@ff_curls
  ADD r9,r9,r8
  LD r3,r9,0
  LD r9,r0,@ff_credits
  ADD r9,r9,r8
  LD r6,r9,0
  ADD r1,r8,r0
  LD r2,r0,@ff_map
  LD r4,r0,@ff_epoch
  ADD r5,r4,r0
  CALL @mth_triad_hotcold_poincare128
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @ff_bad_triad
  ST r2,r0,@ff_triad_hot
  ; Independently confirm raw Boolean votes of ALL THREE members.
  ST r0,r0,@ff_mask
  ST r0,r0,@ff_member
ff_each_member:
  LD r8,r0,@ff_member
  MOVI r10,3
  CMP r8,r10
  JMP[GE] @ff_triad_vote_done
  LD r9,r0,@ff_index
  MOVI r10,3
  MUL r9,r9,r10
  ADD r9,r9,r8
  LD r10,r0,@ff_map
  ADD r9,r9,r10
  LD r11,r9,0
  MOVI r10,0
  MOVHI r10,0x003B
  SHL r12,r11,8
  ADD r10,r10,r12
  LD r11,r10,140
  CMP r11,r0
  JMP[EQ] @ff_next_member
  MOVI r10,1
  CMP r11,r10
  JMP[NE] @ff_bad_triad
  MOVI r10,@ff_bits
  ADD r10,r10,r8
  LD r10,r10,0
  LD r12,r0,@ff_mask
  BOOL.14 r12,r12,r10
  ST r12,r0,@ff_mask
ff_next_member:
  LD r8,r0,@ff_member
  ADDI r8,r8,1
  ST r8,r0,@ff_member
  JMP @ff_each_member

ff_triad_vote_done:
  LD r8,r0,@ff_index
  MOVI r10,0xF500
  MOVHI r10,0x003E
  ADD r10,r10,r8
  LD r11,r0,@ff_mask
  ST r11,r10,0       ; staged votes, never client supplied
  LD r10,r0,@ff_triad_hot
  MOVI r9,3
  CMP r10,r9
  JMP[EQ] @ff_unanimous_hot
  MOVI r9,2
  CMP r10,r9
  JMP[EQ] @ff_hot_majority
  MOVI r9,1
  CMP r10,r9
  JMP[EQ] @ff_cold_majority
  CMP r10,r0
  JMP[EQ] @ff_unanimous_cold
  JMP @ff_bad_triad
ff_unanimous_hot:
  MOVI r10,@ff_allhot
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  JMP @ff_hot_majority
ff_unanimous_cold:
  MOVI r10,@ff_allcold
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  JMP @ff_cold_majority
ff_hot_majority:
  MOVI r10,@ff_accepted
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  JMP @ff_next_triad
ff_cold_majority:
  MOVI r10,@ff_cold_major
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
ff_next_triad:
  LD r8,r0,@ff_index
  ADDI r8,r8,1
  ST r8,r0,@ff_index
  JMP @ff_measure_triad_loop

ff_publish:
  ; All 255 head and 85 trihead measurements succeeded.
  ; Staging the report is safe now; no ACTIVE tensor writes exist here.
  MOVI r10,0xF500
  MOVHI r10,0x003E
  LD r11,r0,@ff_votes_out
  MOVI r8,0
ff_publish_votes:
  MOVI r9,85
  CMP r8,r9
  JMP[GE] @ff_publish_report
  LD r12,r10,0
  ST r12,r11,0
  ADDI r10,r10,1
  ADDI r11,r11,1
  ADDI r8,r8,1
  JMP @ff_publish_votes
ff_publish_report:
  LD r10,r0,@ff_report_out
  MOVI r11,255
  ST r11,r10,0
  MOVI r11,85
  ST r11,r10,1
  LD r11,r0,@ff_hot_heads
  ST r11,r10,2
  LD r11,r0,@ff_accepted
  ST r11,r10,3
  LD r11,r0,@ff_cold_major
  ST r11,r10,4
  LD r11,r0,@ff_allhot
  ST r11,r10,5
  LD r11,r0,@ff_allcold
  ST r11,r10,6
  MOVI r12,0
  MOVI r9,43
  LD r11,r0,@ff_accepted
  CMP r11,r9
  JMP[LT] @ff_field_rejected
  MOVI r12,1
ff_field_rejected:
  ST r12,r10,7
  MOVI r11,255
  ST r11,r10,8
  LD r11,r0,@ff_epoch
  ST r11,r10,9
  MOVI r1,1
  LD r2,r0,@ff_accepted
  MOVI r3,255
  MOVI r4,0
  JMP @ff_return
ff_bad_contract:
  MOVI r4,1
  JMP @ff_reject
ff_bad_stale:
  MOVI r4,2
  JMP @ff_reject
ff_bad_map:
  MOVI r4,3
  JMP @ff_reject
ff_bad_head:
  MOVI r4,4
  JMP @ff_reject
ff_bad_triad:
  MOVI r4,5
ff_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
ff_return:
  MOVI r13,1
  LD r15,r0,@ff_link
  RET
ff_link:
  .word 0
ff_map:
  .word 0
ff_curls:
  .word 0
ff_credits:
  .word 0
ff_epoch:
  .word 0
ff_votes_out:
  .word 0
ff_report_out:
  .word 0
ff_index:
  .word 0
ff_hot_heads:
  .word 0
ff_triad_hot:
  .word 0
ff_member:
  .word 0
ff_mask:
  .word 0
ff_accepted:
  .word 0
ff_cold_major:
  .word 0
ff_allhot:
  .word 0
ff_allcold:
  .word 0
ff_bits:
  .word 1,2,4
