; Native palindromic-anchor/mirror-pair triangle CURL field.
; Reuses SAME canonical C(256,2) directed mirror-pair index as Hodge.
; Each source float is signed g[lo->hi]. Reverse edge is -g[lo->hi],
; never a second unrelated tensor. The endpoint anchors have physical
; bit-palindromic addresses pal16(i)=(reverse8(i)<<8)|i, with oriented
; edge mirror addr(u,v)=(reverse8(u)<<8)|v, rev16(addr(u,v))=addr(v,u).
; Stable boot sample: 255 local ring + 255 seeded long range triangles.
; VOID255 has no edge source, no HOT/COLD vote and no writer identity.
;
; ABI r1=pair_flow[32640] f32, r2=triangles[510][3] U32,
;     r3=count 1..510, r4=PRIVATE staging scratch[510][32] U32,
;     r5=published records[510][32] U32, r6=expected_epoch,r7=actual_epoch
; return r1=1,r2=count,r3=hot-majority-count,r4=0.
; reject r1=r2=r3=0,r4=1 invalid/2 stale/3 bad source/4 triangle.
; Neither published records nor ACTIVE tensor are changed on failure.
;
; Per record [0..31]:
; [0..2] i,j,k, [3] kind 0 local or 1 long (index>=255);
; [4] HOT mask, [5] COLD mask, [6] HOT count, [7] COLD count;
; [8] HOT/COLD majority sign +1/-1/0, [9] 3/3 HOT, [10] 3/3 COLD;
; [11] oriented LOOP SUM L=gij+gjk+gki F32 (discrete curl);
; [12..14] directed edge gradients gij,gjk,gki F32;
; [15] reconstructed gij=L-gjk-gki F32 (roundoff bounded, not independent);
; [16] directed reconstruction residual gij-reconstructed F32;
; [17..19] palindrome addresses of i,j,k (16-bit);
; [20..25] addr(i,j),addr(j,i),addr(j,k),addr(k,j),addr(k,i),addr(i,k);
; [26] source generation, [27] NOW255, [28..31] reserved (0).
;
; L is discrete exterior derivative of the sourced edge 1-form.
; Nonzero L is NOT the intrinsic sectional curvature of the Poincare ball.
; A second native Poincare128 hyperedge guest consumes L and vectors
; from measured heads, keeping those geometric concepts distinct.
; Error correction requires RETAINED L and trusted other two edges;
; use mth_mirror_triangle_recover to obtain candidate repair, not commit.
mth_mirror_triangle_field:
  MOVI r0,0
  ST r15,r0,@mpf_link
  ST r1,r0,@mpf_flows
  ST r2,r0,@mpf_tris
  ST r3,r0,@mpf_count
  ST r4,r0,@mpf_stage
  ST r5,r0,@mpf_publish
  ST r6,r0,@mpf_epoch
  CMP r1,r0
  JMP[EQ] @mpf_bad
  CMP r2,r0
  JMP[EQ] @mpf_bad
  CMP r4,r0
  JMP[EQ] @mpf_bad
  CMP r5,r0
  JMP[EQ] @mpf_bad
  CMP r4,r5
  JMP[EQ] @mpf_bad
  CMP r6,r7
  JMP[NE] @mpf_stale
  CMP r3,r0
  JMP[LE] @mpf_bad
  MOVI r10,510
  CMP r3,r10
  JMP[GT] @mpf_bad

  ; First reject every NaN/Inf/|g|>8.0 in the entire C(256,2) graph.
  ; Source for any pair ending at VOID255 MUST be float32 zero.
  MOVI r8,0
mpf_validate_flows:
  MOVI r10,32640
  CMP r8,r10
  JMP[GE] @mpf_validate_void
  LD r9,r0,@mpf_flows
  ADD r9,r9,r8
  LD r11,r9,0
  MOVI r12,0xFFFF
  MOVHI r12,0x7FFF
  BOOL.8 r11,r11,r12
  MOVI r12,0
  MOVHI r12,0x7F80
  BOOL.8 r14,r11,r12
  CMP r14,r12
  JMP[EQ] @mpf_bad_source
  MOVI r12,0
  MOVHI r12,0x4100
  CMP r11,r12
  JMP[GT] @mpf_bad_source
  ADDI r8,r8,1
  JMP @mpf_validate_flows

mpf_validate_void:
  MOVI r8,0
mpf_void_loop:
  MOVI r11,255
  CMP r8,r11
  JMP[GE] @mpf_validate_triangles
  ; Pair index(u,255)=u*(511-u)/2 + 254-u.
  MOVI r10,511
  SUB r10,r10,r8
  MUL r10,r10,r8
  SHR r10,r10,1
  MOVI r11,254
  SUB r11,r11,r8
  ADD r10,r10,r11
  LD r9,r0,@mpf_flows
  ADD r9,r9,r10
  LD r10,r9,0
  FCMP r10,r0
  JMP[NE] @mpf_bad_source
  ADDI r8,r8,1
  JMP @mpf_void_loop

mpf_validate_triangles:
  MOVI r8,0
mpf_check_triangle:
  LD r9,r0,@mpf_count
  CMP r8,r9
  JMP[GE] @mpf_measure_begin
  MOVI r10,3
  MUL r11,r8,r10
  LD r10,r0,@mpf_tris
  ADD r10,r10,r11
  LD r11,r10,0
  LD r12,r10,1
  LD r14,r10,2
  MOVI r9,255
  CMP r11,r9
  JMP[GE] @mpf_bad_triangle
  CMP r12,r9
  JMP[GE] @mpf_bad_triangle
  CMP r14,r9
  JMP[GE] @mpf_bad_triangle
  CMPS r11,r0
  JMP[LT] @mpf_bad_triangle
  CMPS r12,r0
  JMP[LT] @mpf_bad_triangle
  CMPS r14,r0
  JMP[LT] @mpf_bad_triangle
  CMP r11,r12
  JMP[EQ] @mpf_bad_triangle
  CMP r11,r14
  JMP[EQ] @mpf_bad_triangle
  CMP r12,r14
  JMP[EQ] @mpf_bad_triangle
  ADDI r8,r8,1
  JMP @mpf_check_triangle

mpf_measure_begin:
  ST r0,r0,@mpf_index
  ST r0,r0,@mpf_hot_major
mpf_measure:
  LD r8,r0,@mpf_index
  LD r9,r0,@mpf_count
  CMP r8,r9
  JMP[GE] @mpf_publish_begin
  ; Reserve and clear independent 32-word private record.
  LD r10,r0,@mpf_stage
  SHL r11,r8,5
  ADD r10,r10,r11
  ST r10,r0,@mpf_record
  MOVI r12,0
mpf_zero:
  MOVI r9,32
  CMP r12,r9
  JMP[GE] @mpf_fetch_triangle
  ADD r9,r10,r12
  ST r0,r9,0
  ADDI r12,r12,1
  JMP @mpf_zero

mpf_fetch_triangle:
  LD r8,r0,@mpf_index
  MOVI r11,3
  MUL r11,r11,r8
  LD r10,r0,@mpf_tris
  ADD r10,r10,r11
  LD r11,r10,0
  LD r12,r10,1
  LD r14,r10,2
  LD r10,r0,@mpf_record
  ST r11,r10,0
  ST r12,r10,1
  ST r14,r10,2
  MOVI r9,255
  CMP r8,r9
  JMP[LT] @mpf_local
  MOVI r9,1
  ST r9,r10,3
mpf_local:
  LD r10,r0,@mpf_record
  LD r8,r10,0
  LD r9,r10,1
  CALL @mpf_edge
  LD r11,r0,@mpf_record
  ST r10,r11,12
  LD r8,r11,1
  LD r9,r11,2
  CALL @mpf_edge
  LD r11,r0,@mpf_record
  ST r10,r11,13
  LD r8,r11,2
  LD r9,r11,0
  CALL @mpf_edge
  LD r11,r0,@mpf_record
  ST r10,r11,14

  LD r8,r11,12
  LD r9,r11,13
  FADD r8,r8,r9
  LD r9,r11,14
  FADD r8,r8,r9
  ST r8,r11,11

  ; Exact loop identity and independent recovery candidate.
  FSUB r8,r8,r9
  LD r9,r11,13
  FSUB r8,r8,r9
  ST r8,r11,15
  LD r9,r11,12
  FSUB r8,r9,r8
  ST r8,r11,16

  ; HOT/COLD pattern is attached to directed edges, not to whether
  ; a vertex happened to be declared a hot head.
  ST r0,r0,@mpf_hot
  ST r0,r0,@mpf_cold
  ST r0,r0,@mpf_hot_mask
  ST r0,r0,@mpf_cold_mask
  MOVI r8,0
mpf_edge_votes:
  MOVI r9,3
  CMP r8,r9
  JMP[GE] @mpf_pattern
  LD r11,r0,@mpf_record
  ADDI r11,r11,12
  ADD r11,r11,r8
  LD r10,r11,0
  FCMP r10,r0
  JMP[GT] @mpf_vote_hot
  JMP[LT] @mpf_vote_cold
  JMP @mpf_vote_next
mpf_vote_hot:
  LD r10,r0,@mpf_hot
  ADDI r10,r10,1
  ST r10,r0,@mpf_hot
  MOVI r10,@mpf_bits
  ADD r10,r10,r8
  LD r10,r10,0
  LD r11,r0,@mpf_hot_mask
  BOOL.14 r11,r11,r10
  ST r11,r0,@mpf_hot_mask
  JMP @mpf_vote_next
mpf_vote_cold:
  LD r10,r0,@mpf_cold
  ADDI r10,r10,1
  ST r10,r0,@mpf_cold
  MOVI r10,@mpf_bits
  ADD r10,r10,r8
  LD r10,r10,0
  LD r11,r0,@mpf_cold_mask
  BOOL.14 r11,r11,r10
  ST r11,r0,@mpf_cold_mask
mpf_vote_next:
  ADDI r8,r8,1
  JMP @mpf_edge_votes

mpf_pattern:
  LD r10,r0,@mpf_record
  LD r11,r0,@mpf_hot_mask
  ST r11,r10,4
  LD r11,r0,@mpf_cold_mask
  ST r11,r10,5
  LD r8,r0,@mpf_hot
  ST r8,r10,6
  LD r9,r0,@mpf_cold
  ST r9,r10,7
  MOVI r11,2
  CMP r8,r11
  JMP[LT] @mpf_check_cold
  MOVI r11,1
  ST r11,r10,8
  LD r12,r0,@mpf_hot_major
  ADDI r12,r12,1
  ST r12,r0,@mpf_hot_major
  MOVI r11,3
  CMP r8,r11
  JMP[NE] @mpf_addresses
  MOVI r11,1
  ST r11,r10,9
  JMP @mpf_addresses
mpf_check_cold:
  MOVI r11,2
  CMP r9,r11
  JMP[LT] @mpf_addresses
  MOVI r11,0xFFFF
  MOVHI r11,0xFFFF
  ST r11,r10,8
  MOVI r11,3
  CMP r9,r11
  JMP[NE] @mpf_addresses
  MOVI r11,1
  ST r11,r10,10

mpf_addresses:
  ; Actual bit-palindromic endpoint addresses, then both mirror rails
  ; for each oriented edge. No hand-waved adjacency coordinates.
  MOVI r8,0
mpf_pal_loop:
  MOVI r9,3
  CMP r8,r9
  JMP[GE] @mpf_pair_addresses
  LD r11,r0,@mpf_record
  ADD r11,r11,r8
  LD r9,r11,0
  ADD r11,r9,r0
  CALL @mpf_pal16
  LD r12,r0,@mpf_record
  ADDI r12,r12,17
  ADD r12,r12,r8
  ST r10,r12,0
  ADDI r8,r8,1
  JMP @mpf_pal_loop
mpf_pair_addresses:
  ST r0,r0,@mpf_pair_index
mpf_pair_loop:
  LD r14,r0,@mpf_pair_index
  MOVI r12,6
  CMP r14,r12
  JMP[GE] @mpf_record_epoch
  SHL r12,r14,1
  MOVI r11,@mpf_edge_indices
  ADD r11,r11,r12
  LD r8,r11,0
  LD r9,r11,1
  LD r11,r0,@mpf_record
  ADD r8,r8,r11
  LD r8,r8,0
  ADD r9,r9,r11
  LD r9,r9,0
  CALL @mpf_addr
  LD r11,r0,@mpf_record
  ADDI r11,r11,20
  LD r14,r0,@mpf_pair_index
  ADD r11,r11,r14
  ST r10,r11,0
  ADDI r14,r14,1
  ST r14,r0,@mpf_pair_index
  JMP @mpf_pair_loop

mpf_record_epoch:
  LD r10,r0,@mpf_record
  LD r11,r0,@mpf_epoch
  ST r11,r10,26
  MOVI r11,255
  ST r11,r10,27
  LD r8,r0,@mpf_index
  ADDI r8,r8,1
  ST r8,r0,@mpf_index
  JMP @mpf_measure

mpf_publish_begin:
  ; Scan all staged values for finite curls and finite recovery residuals
  ; before publishing a SINGLE record. NaN16 float arithmetic only.
  MOVI r8,0
mpf_verify_stage:
  LD r9,r0,@mpf_count
  CMP r8,r9
  JMP[GE] @mpf_publish_records
  LD r10,r0,@mpf_stage
  SHL r11,r8,5
  ADD r10,r10,r11
  MOVI r11,11
mpf_verify_floats:
  MOVI r12,17
  CMP r11,r12
  JMP[GE] @mpf_verified_next
  ADD r12,r10,r11
  LD r12,r12,0
  MOVI r14,0xFFFF
  MOVHI r14,0x7FFF
  BOOL.8 r12,r12,r14
  MOVI r14,0
  MOVHI r14,0x7F80
  BOOL.8 r12,r12,r14
  CMP r12,r14
  JMP[EQ] @mpf_bad_source
  ADDI r11,r11,1
  JMP @mpf_verify_floats
mpf_verified_next:
  ADDI r8,r8,1
  JMP @mpf_verify_stage

mpf_publish_records:
  MOVI r8,0
mpf_publish_loop:
  LD r9,r0,@mpf_count
  SHL r9,r9,5
  CMP r8,r9
  JMP[GE] @mpf_success
  LD r10,r0,@mpf_stage
  ADD r10,r10,r8
  LD r11,r10,0
  LD r10,r0,@mpf_publish
  ADD r10,r10,r8
  ST r11,r10,0
  ADDI r8,r8,1
  JMP @mpf_publish_loop
mpf_success:
  MOVI r1,1
  LD r2,r0,@mpf_count
  LD r3,r0,@mpf_hot_major
  MOVI r4,0
  JMP @mpf_return

; r8=u, r9=v, r10=directed scalar float32.
; Same canonical pair-index expression as native Hodge B1/B2^T.
mpf_edge:
  MOVI r11,0
  CMP r8,r9
  JMP[LT] @mpf_edge_sorted
  ADD r12,r8,r0
  ADD r8,r9,r0
  ADD r9,r12,r0
  MOVI r11,1
mpf_edge_sorted:
  MOVI r12,511
  SUB r12,r12,r8
  MUL r12,r12,r8
  SHR r12,r12,1
  SUB r14,r9,r8
  ADDI r14,r14,-1
  ADD r12,r12,r14
  LD r14,r0,@mpf_flows
  ADD r14,r14,r12
  LD r10,r14,0
  CMP r11,r0
  JMP[EQ] @mpf_edge_done
  FSUB r10,r0,r10
mpf_edge_done:
  RET

; r8=u,r9=v; physical 16-bit directed address in r10.
mpf_addr:
  ST r9,r0,@mpf_v
  ADD r9,r8,r0
  CALL @mpf_pal16
  MOVI r11,0xFF00
  BOOL.8 r10,r10,r11
  LD r11,r0,@mpf_v
  ADD r10,r10,r11
  RET
; r9=anchor 0..254, return pal16(anchor) in r10.
mpf_pal16:
  ADD r11,r9,r0
  MOVI r12,0
  MOVI r14,0
mpf_pal_bit:
  MOVI r10,8
  CMP r14,r10
  JMP[GE] @mpf_pal_done
  SHL r12,r12,1
  MOVI r10,1
  BOOL.8 r10,r10,r11
  BOOL.14 r12,r12,r10
  SHR r11,r11,1
  ADDI r14,r14,1
  JMP @mpf_pal_bit
mpf_pal_done:
  SHL r12,r12,8
  ADD r10,r12,r9
  RET

mpf_bad:
  MOVI r4,1
  JMP @mpf_reject
mpf_stale:
  MOVI r4,2
  JMP @mpf_reject
mpf_bad_source:
  MOVI r4,3
  JMP @mpf_reject
mpf_bad_triangle:
  MOVI r4,4
mpf_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
mpf_return:
  MOVI r13,1
  LD r15,r0,@mpf_link
  RET
mpf_link:
  .word 0
mpf_flows:
  .word 0
mpf_tris:
  .word 0
mpf_count:
  .word 0
mpf_stage:
  .word 0
mpf_publish:
  .word 0
mpf_epoch:
  .word 0
mpf_record:
  .word 0
mpf_index:
  .word 0
mpf_hot:
  .word 0
mpf_cold:
  .word 0
mpf_hot_mask:
  .word 0
mpf_cold_mask:
  .word 0
mpf_hot_major:
  .word 0
mpf_bits:
  .word 1,2,4
mpf_edge_indices:
  .word 0,1,1,0,1,2,2,1,2,0,0,2
mpf_v:
  .word 0
mpf_pair_index:
  .word 0
