; Native NaN16 Hodge-linked 128D Poincare hyperedge projection.
; Exactly ONE 128D vector and ONE ordered (a,b,c) hyperedge. No host math.
; Input r1=src[128] F32, r2=dst[128] F32, r3=record[8] U32,
;       r4=meta[5] F32/U32, r13=1.
; record: [a,b,c, signed_Hodge_curl_F32, expected_gen, current_gen,
;          now_head=255, supplied_source_type=1].
; The source_type is an APPLICATION CLAIM, not independent cryptographic proof.
; The coordinator MUST verify that curl came from the native Hodge field,
; face orientation and the correct dataset/epoch, not an invented scalar.
;
; Output on success:
;    dst[i]=src[i]/(1+||src||_2), i=0..127.
;    meta=[radius, hyperbolic_origin_distance, curl*radius,
;          curl_sign(-1,0,+1), now_head255].
;    radius=||src||/(1+||src||), always strictly inside unit ball.
;    hyperbolic origin distance = log((1+r)/(1-r)) = 2 atanh r.
;    Signed feedback retains oriented curl; opposite face orientation
;    reverses feedback sign, NOT geometric depth or source norm.
;    return r1=1, r2=128, r3=sign, r4=0.
; Reject: r1=r2=r3=0, r4=1 envelope /2 stale /3 bad vector
;                 /4 nonfinite curl.
; Rejected calls modify neither dst nor meta, active tensor, model or root.
; Caller MUST supply nonoverlapping src/dst/record/meta bounded memory spans.
; 128D is actual geometry, not a claim that concept hierarchy is already learned.
;
; Numeric envelope: abs(src[i]) <=8, abs(curl)<=8, no NaN/Inf.
; This keeps 128-term float32 sum of squares bounded at 8192.

mth_hyperedge_poincare128_curl:
  MOVI r0,0
  ST r15,r0,@hp128_link
  ST r1,r0,@hp128_src
  ST r2,r0,@hp128_dst
  ST r3,r0,@hp128_record
  ST r4,r0,@hp128_meta
  CMP r1,r0
  JMP[EQ] @hp128_bad_envelope
  CMP r2,r0
  JMP[EQ] @hp128_bad_envelope
  CMP r3,r0
  JMP[EQ] @hp128_bad_envelope
  CMP r4,r0
  JMP[EQ] @hp128_bad_envelope
  CMP r1,r2
  JMP[EQ] @hp128_bad_envelope
  CMP r1,r3
  JMP[EQ] @hp128_bad_envelope
  CMP r1,r4
  JMP[EQ] @hp128_bad_envelope
  CMP r2,r3
  JMP[EQ] @hp128_bad_envelope
  CMP r2,r4
  JMP[EQ] @hp128_bad_envelope
  CMP r3,r4
  JMP[EQ] @hp128_bad_envelope

  LD r3,r0,@hp128_record
  LD r5,r3,0
  LD r6,r3,1
  LD r7,r3,2
  MOVI r8,255
  CMP r5,r8
  JMP[GE] @hp128_bad_envelope
  CMP r6,r8
  JMP[GE] @hp128_bad_envelope
  CMP r7,r8
  JMP[GE] @hp128_bad_envelope
  CMP r5,r6
  JMP[EQ] @hp128_bad_envelope
  CMP r5,r7
  JMP[EQ] @hp128_bad_envelope
  CMP r6,r7
  JMP[EQ] @hp128_bad_envelope
  LD r5,r3,4
  LD r6,r3,5
  CMP r5,r6
  JMP[NE] @hp128_bad_stale
  LD r5,r3,6
  CMP r5,r8
  JMP[NE] @hp128_bad_envelope
  LD r5,r3,7
  CMP r5,r13
  JMP[NE] @hp128_bad_envelope

  ; Hodge curl finite check and signed fixed admissible magnitude bound.
  LD r5,r3,3
  MOVI r6,0xFFFF
  MOVHI r6,0x7FFF
  BOOL.8 r7,r5,r6
  MOVI r8,0
  MOVHI r8,0x7F80
  BOOL.8 r9,r7,r8
  CMP r9,r8
  JMP[EQ] @hp128_bad_curl
  MOVI r8,0
  MOVHI r8,0x4100
  CMP r7,r8
  JMP[GT] @hp128_bad_curl
  ST r5,r0,@hp128_curl

  MOVI r9,0
  MOVI r10,0
  MOVI r11,0xFFFF
  MOVHI r11,0x7FFF
  MOVI r12,0
  MOVHI r12,0x4100
hp128_preflight:
  MOVI r8,128
  CMP r9,r8
  JMP[GE] @hp128_normalize
  LD r1,r0,@hp128_src
  ADD r1,r1,r9
  LD r5,r1,0
  BOOL.8 r6,r5,r11
  MOVI r8,0
  MOVHI r8,0x7F80
  BOOL.8 r7,r6,r8
  CMP r7,r8
  JMP[EQ] @hp128_bad_vector
  CMP r6,r12
  JMP[GT] @hp128_bad_vector
  FMUL r6,r5,r5
  FADD r10,r10,r6
  ADDI r9,r9,1
  JMP @hp128_preflight

hp128_normalize:
  FSQRT r10,r10
  MOVI r11,0
  MOVHI r11,0x3F80
  FADD r12,r10,r11            ; denom 1+norm
  FDIV r5,r10,r12             ; radius in [0,1)
  ST r5,r0,@hp128_radius
  FADD r6,r11,r5
  FSUB r7,r11,r5
  FDIV r6,r6,r7
  FLOG r6,r6
  ST r6,r0,@hp128_depth
  LD r8,r0,@hp128_curl
  FMUL r8,r8,r5
  ST r8,r0,@hp128_signed
  MOVI r9,0
  FCMP r8,r9
  JMP[GT] @hp128_positive
  JMP[LT] @hp128_negative
  ST r9,r0,@hp128_sign
  JMP @hp128_commit
hp128_positive:
  MOVI r9,1
  ST r9,r0,@hp128_sign
  JMP @hp128_commit
hp128_negative:
  MOVI r9,0xFFFF
  MOVHI r9,0xFFFF
  ST r9,r0,@hp128_sign

hp128_commit:
  ; Only now that ALL inputs have passed validation may outputs be written.
  MOVI r9,0
  LD r1,r0,@hp128_src
  LD r2,r0,@hp128_dst
hp128_copy_loop:
  MOVI r8,128
  CMP r9,r8
  JMP[GE] @hp128_meta_write
  ADD r5,r1,r9
  LD r5,r5,0
  FDIV r5,r5,r12
  ADD r6,r2,r9
  ST r5,r6,0
  ADDI r9,r9,1
  JMP @hp128_copy_loop
hp128_meta_write:
  LD r8,r0,@hp128_meta
  LD r5,r0,@hp128_radius
  ST r5,r8,0
  LD r5,r0,@hp128_depth
  ST r5,r8,1
  LD r5,r0,@hp128_signed
  ST r5,r8,2
  LD r5,r0,@hp128_sign
  ST r5,r8,3
  MOVI r5,255
  ST r5,r8,4
  MOVI r1,1
  MOVI r2,128
  LD r3,r0,@hp128_sign
  MOVI r4,0
  JMP @hp128_return

hp128_bad_envelope:
  MOVI r4,1
  JMP @hp128_reject
hp128_bad_stale:
  MOVI r4,2
  JMP @hp128_reject
hp128_bad_vector:
  MOVI r4,3
  JMP @hp128_reject
hp128_bad_curl:
  MOVI r4,4
hp128_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
hp128_return:
  MOVI r13,1
  LD r15,r0,@hp128_link
  RET

hp128_link:
  .word 0
hp128_src:
  .word 0
hp128_dst:
  .word 0
hp128_record:
  .word 0
hp128_meta:
  .word 0
hp128_curl:
  .word 0
hp128_radius:
  .word 0
hp128_depth:
  .word 0
hp128_signed:
  .word 0
hp128_sign:
  .word 0
