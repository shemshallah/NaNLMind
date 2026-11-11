; Native NaN16 measured TRIHEAD vectors, hot/cold votes and gradients.
; Exactly one shared global state; each of 85 triheads has independent
; measured 128D scratch in guest RAM, not an independent model instance.
; Head input vectors are actual individual native head16 Poincare outputs:
;    head[h] p[128] at 0x3F0000+h*256;
;    private head scratch at 0x3B0000+h*256.
; Triad t scratch (85 distinct slabs):
;    source[128] at 0x3E8000+t*128,
;    Poincare dst[128] at 0x3EB000+t*128,
;    meta[16] at 0x3EE000+t*16,
;    oriented hyperedge record[8] at 0x3EE600+t*8.
; Uses mth_hyperedge_poincare128_curl: native 128D projection and actual
; oriented Hodge curl; no host trigonometry or geometry.
;
; ABI: r1=triad t[0..84],r2=mapping 85*3 U32,
;      r3=sourced Hodge curl F32,r4=expected gen,r5=current gen,
;      r6=native seven-credit Q16 [-8,8],r13=1.
; On success r1=1,r2=hot[0..3],r3=cold[0..3],r4=0.
; Reject r1=0,r2=r3=0,r4=1 invalid slot/2 stale/3 head invalid/
;                            4 denied or head not measured/5 credit/geometry.
; Meta:
;   [0] Poincare radius F32, [1] radial depth F32, [2] curl*radius F32,
;   [3] orientation (-1/0/+1), [4] NOW VOID255;
;   [5] hot_count, [6] cold_count, [7] majority sign (+1 hot / -1 cold),
;   [8] unanimous 3/3 HOT flag, [9] unanimous 3/3 COLD flag,
;   [10] signed native candidate-credit/gradient-proposal F32,
;   [11] input native 7-credit Q16, [12] triad 2/3 vote accepted=1,
;   [13] t, [14] gradient kind=1 (eligibility, NOT exact BPTT), [15] link.
; Credit proposal = native_hodge_curl*Poincare_radius *
;     native_seven_credit * (hot3:+1; hot2:+0.5; cold2:-0.5; cold3:-1).
; Hot 3/3 and cold 3/3 are independently retained as distinct channels.
; Do not describe this signed eligibility as a loss derivative unless a
; verified differentiable reference proves that connection.
; No active tensor, weight, or chart writes: controller still needs per-head
; writer permissions, field(43/85), provenance, meta and held-out 48M NLL.
;
; Requires mth_hyperedge_poincare128_curl.nas.
mth_triad_hotcold_poincare128:
  MOVI r0,0
  MOVI r10,85
  CMP r1,r10
  JMP[GE] @thc_bad_slot
  CMPS r1,r0
  JMP[LT] @thc_bad_slot
  CMP r2,r0
  JMP[EQ] @thc_bad_slot
  ST r15,r0,@thc_link
  ST r1,r0,@thc_t
  ST r2,r0,@thc_map
  ST r3,r0,@thc_curl
  ST r4,r0,@thc_expected
  ST r5,r0,@thc_current
  ST r6,r0,@thc_credit
  CMP r4,r5
  JMP[NE] @thc_bad_stale
  ; Native Q16 credit within [-8,+8].
  ADD r8,r6,r0
  CMPS r8,r0
  JMP[GE] @thc_credit_positive
  SUB r8,r0,r8
thc_credit_positive:
  MOVI r10,0
  MOVHI r10,8
  CMP r8,r10
  JMP[GT] @thc_bad_credit
  MOVI r9,0
  ST r9,r0,@thc_i
  ST r9,r0,@thc_hot

thc_preflight_heads:
  LD r9,r0,@thc_i
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @thc_compute
  LD r10,r0,@thc_t
  MOVI r11,3
  MUL r10,r10,r11
  ADD r10,r10,r9
  LD r11,r0,@thc_map
  ADD r10,r10,r11
  LD r11,r10,0
  MOVI r12,255
  CMP r11,r12
  JMP[GE] @thc_bad_head
  CMPS r11,r0
  JMP[LT] @thc_bad_head
  ; No repeated heads within any oriented triple.
  MOVI r10,@thc_ids
  ADD r10,r10,r9
  ST r11,r10,0
  MOVI r12,0
thc_dup_loop:
  CMP r12,r9
  JMP[GE] @thc_head_data
  MOVI r10,@thc_ids
  ADD r10,r10,r12
  LD r10,r10,0
  CMP r10,r11
  JMP[EQ] @thc_bad_head
  ADDI r12,r12,1
  JMP @thc_dup_loop
thc_head_data:
  MOVI r10,0
  MOVHI r10,0x003B
  SHL r12,r11,8
  ADD r10,r10,r12
  LD r12,r10,132
  MOVI r11,1
  CMP r12,r11
  JMP[NE] @thc_bad_writer
  LD r12,r10,147
  CMP r12,r11
  JMP[NE] @thc_bad_writer
  LD r12,r10,133
  LD r11,r0,@thc_expected
  CMP r12,r11
  JMP[NE] @thc_bad_stale
  LD r12,r10,134
  CMP r12,r11
  JMP[NE] @thc_bad_stale
  LD r12,r10,140
  CMP r12,r0
  JMP[EQ] @thc_next_head
  MOVI r11,1
  CMP r12,r11
  JMP[NE] @thc_bad_head
  LD r11,r0,@thc_hot
  ADDI r11,r11,1
  ST r11,r0,@thc_hot
thc_next_head:
  LD r9,r0,@thc_i
  ADDI r9,r9,1
  ST r9,r0,@thc_i
  JMP @thc_preflight_heads

thc_compute:
  LD r9,r0,@thc_t
  SHL r10,r9,7
  MOVI r11,0x8000
  MOVHI r11,0x003E
  ADD r10,r10,r11
  ST r10,r0,@thc_src
  MOVI r11,0xB000
  MOVHI r11,0x003E
  SHL r12,r9,7
  ADD r11,r11,r12
  ST r11,r0,@thc_dst
  MOVI r11,0xE000
  MOVHI r11,0x003E
  SHL r12,r9,4
  ADD r11,r11,r12
  ST r11,r0,@thc_meta
  MOVI r11,0xE600
  MOVHI r11,0x003E
  SHL r12,r9,3
  ADD r11,r11,r12
  ST r11,r0,@thc_rec
  ; Each independent HEAD vector contributes to each trihead dimension.
  MOVI r9,0
thc_dim_loop:
  MOVI r10,128
  CMP r9,r10
  JMP[GE] @thc_hyperedge
  MOVI r7,0                 ; float32 zero
  MOVI r8,0
thc_sum_loop:
  MOVI r10,3
  CMP r8,r10
  JMP[GE] @thc_sum_done
  MOVI r10,@thc_ids
  ADD r10,r10,r8
  LD r11,r10,0
  SHL r11,r11,8
  MOVI r10,0
  MOVHI r10,0x003F
  ADD r11,r11,r10
  ADD r11,r11,r9
  LD r11,r11,0
  FADD r7,r7,r11
  ADDI r8,r8,1
  JMP @thc_sum_loop
thc_sum_done:
  MOVI r10,0
  MOVHI r10,0x4040         ; exactly 3.0f
  FDIV r7,r7,r10
  LD r11,r0,@thc_src
  ADD r11,r11,r9
  ST r7,r11,0
  ADDI r9,r9,1
  JMP @thc_dim_loop

thc_hyperedge:
  LD r10,r0,@thc_rec
  LD r11,r0,@thc_ids
  ST r11,r10,0
  LD r11,r0,@thc_ids+1
  ST r11,r10,1
  LD r11,r0,@thc_ids+2
  ST r11,r10,2
  LD r11,r0,@thc_curl
  ST r11,r10,3
  LD r11,r0,@thc_expected
  ST r11,r10,4
  ST r11,r10,5
  MOVI r11,255
  ST r11,r10,6
  MOVI r11,1
  ST r11,r10,7
  LD r1,r0,@thc_src
  LD r2,r0,@thc_dst
  LD r3,r0,@thc_rec
  LD r4,r0,@thc_meta
  LD r9,r0,@thc_t
  ST r15,r4,15
  CALL @mth_hyperedge_poincare128_curl
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @thc_bad_credit
  LD r10,r0,@thc_meta
  LD r9,r0,@thc_hot
  ST r9,r10,5
  MOVI r11,3
  SUB r11,r11,r9
  ST r11,r10,6
  MOVI r12,0
  MOVI r11,2
  CMP r9,r11
  JMP[LT] @thc_cold_majority
  MOVI r12,1
  JMP @thc_majority_ready
thc_cold_majority:
  MOVI r12,0xFFFF
  MOVHI r12,0xFFFF
thc_majority_ready:
  ST r12,r10,7
  MOVI r11,0
  MOVI r12,3
  CMP r9,r12
  JMP[NE] @thc_not_all_hot
  MOVI r11,1
thc_not_all_hot:
  ST r11,r10,8
  MOVI r11,0
  CMP r9,r0
  JMP[NE] @thc_not_all_cold
  MOVI r11,1
thc_not_all_cold:
  ST r11,r10,9
  ; A sourced native 7-credit value, not a fabricated gradient.
  LD r11,r0,@thc_credit
  ST r11,r10,11
  CVTIF r12,r11
  MOVI r11,0
  MOVHI r11,0x4780          ; 65536.0f
  FDIV r12,r12,r11
  LD r11,r10,2              ; signed Hodge curl * Poincare radius
  FMUL r12,r12,r11
  MOVI r11,1
  CMP r9,r11
  JMP[EQ] @thc_negative_half
  MOVI r11,0
  CMP r9,r11
  JMP[EQ] @thc_negative_full
  MOVI r11,2
  CMP r9,r11
  JMP[EQ] @thc_positive_half
  JMP @thc_gradient_ready   ; 3/3 hot
thc_negative_full:
  MOVI r11,0
  FSUB r12,r11,r12
  JMP @thc_gradient_ready
thc_negative_half:
  MOVI r11,0
  FSUB r12,r11,r12
thc_positive_half:
  MOVI r11,0
  MOVHI r11,0x3F00          ; 0.5f
  FMUL r12,r12,r11
thc_gradient_ready:
  ST r12,r10,10
  MOVI r11,1
  ST r11,r10,12
  LD r11,r0,@thc_t
  ST r11,r10,13
  MOVI r11,1
  ST r11,r10,14             ; native eligibility gradient, not BPTT
  LD r15,r0,@thc_link
  MOVI r1,1
  LD r2,r0,@thc_hot
  MOVI r3,3
  SUB r3,r3,r2
  MOVI r4,0
  RET
thc_bad_slot:
  MOVI r4,1
  JMP @thc_reject_no_link
thc_bad_stale:
  MOVI r4,2
  JMP @thc_reject
thc_bad_head:
  MOVI r4,3
  JMP @thc_reject
thc_bad_writer:
  MOVI r4,4
  JMP @thc_reject
thc_bad_credit:
  MOVI r4,5
thc_reject:
  ; Always restore this invocation's return link even when preflight
  ; rejected before meta scratch was assigned. Never use stale trihead meta.
  LD r15,r0,@thc_link
thc_reject_no_link:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  RET
thc_link:
  .word 0
thc_t:
  .word 0
thc_map:
  .word 0
thc_expected:
  .word 0
thc_current:
  .word 0
thc_curl:
  .word 0
thc_credit:
  .word 0
thc_i:
  .word 0
thc_hot:
  .word 0
thc_ids:
  .word 0,0,0
thc_src:
  .word 0
thc_dst:
  .word 0
thc_meta:
  .word 0
thc_rec:
  .word 0
