; Raw NaN16 multi-order context backoff route.
;
; This module is the authority for the compact k=4 context route.  The host
; only supplies packed context bytes and drives the passes; every key lookup,
; frequency count, slot assignment, fallback hash and table update below runs
; in guest code.
;
; Memory:
;   0x40000  exact hash table, 32768 entries x 3 words:
;            [0] packed k=4 key, [1] count, [2] compact slot / 0xFFFFFFFF
;   0x58000  count histogram, 4096 words (counts >= 4095 share the top bin)
;
; A selected key with slot < exact_count uses that exact compact bucket.
; Every other key (unseen, unselected, or not in the exact table) uses the
; raw FNV-1a hash of its k=3 suffix in buckets exact_count..buckets-1.
;
; ABI for mth_context_backoff (driver mode 3):
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits
;   r3 = packed k=4 key: b4<<24 | b5<<16 | b6<<8 | b7
;   r4 = bucket count B
; Returns:
;   r1 = 1 when both high and low predictions are correct
;   r2 = high CE + true-low CE
;   r3 = predicted high class
;   r4 = predicted low class
;   r5 = 1 when the exact k=4 slot was used, 0 for the k=3 fallback
;   r6 = routed bucket

; r1 = packed key. Returns r1 = 1 when the key was inserted, else 0.
mth_ctxb_build:
  MOVI r12,@mth_ctxb_build_link
  ST r15,r12,0
  MOVI r12,@mth_ctxb_build_key
  ST r1,r12,0

  ; linear probe entry pointer = 0x40000 + 3*((key*2654435761)&32767)
  MOVI r4,0x79B1
  MOVHI r4,0x9E37
  MUL r3,r1,r4
  SHL r3,r3,17
  SHR r3,r3,17
  MOVI r4,3
  MUL r3,r3,r4
  MOVI r2,0x0000
  MOVHI r2,0x0004
  ADD r2,r2,r3

  MOVI r4,32768
mth_ctxb_build_probe:
  LD r5,r2,1
  CMP r5,r0
  JMP[EQ] @mth_ctxb_build_insert
  LD r6,r2,0
  MOVI r12,@mth_ctxb_build_key
  LD r1,r12,0
  CMP r6,r1
  JMP[EQ] @mth_ctxb_build_hit

  ADDI r2,r2,3
  MOVI r6,0x8000
  MOVHI r6,0x0005
  CMP r2,r6
  JMP[LT] @mth_ctxb_build_nowrap
  MOVI r2,0x0000
  MOVHI r2,0x0004
mth_ctxb_build_nowrap:
  ADDI r4,r4,-1
  CMP r4,r0
  JMP[GT] @mth_ctxb_build_probe
  MOVI r1,0
  JMP @mth_ctxb_build_out

mth_ctxb_build_insert:
  MOVI r12,@mth_ctxb_build_key
  LD r1,r12,0
  ST r1,r2,0
  MOVI r5,1
  ST r5,r2,1
  MOVI r5,0xFFFF
  MOVHI r5,0xFFFF
  ST r5,r2,2
  MOVI r1,1
  JMP @mth_ctxb_build_out

mth_ctxb_build_hit:
  LD r5,r2,1
  ADDI r5,r5,1
  ST r5,r2,1
  MOVI r1,0
mth_ctxb_build_out:
  MOVI r12,@mth_ctxb_build_link
  LD r15,r12,0
  RET

; r1 = bucket count, r2 = exact slot limit.
; Returns r1 = exact_count, r2 = fallback buckets,
;         r3 = selected count threshold, r4 = unique k=4 keys.
mth_ctxb_select:
  MOVI r12,@mth_ctxb_select_link
  ST r15,r12,0
  MOVI r12,@mth_ctxb_buckets
  ST r1,r12,0
  MOVI r12,@mth_ctxb_exact_limit
  ST r2,r12,0

  ; clear the count histogram
  MOVI r1,0
  MOVI r2,0x8000
  MOVHI r2,0x0005
  MOVI r3,4096
mth_ctxb_select_clear:
  ST r0,r2,0
  ADDI r2,r2,1
  ADDI r1,r1,1
  CMP r1,r3
  JMP[LT] @mth_ctxb_select_clear

  ; count unique keys and histogram their occurrence counts
  MOVI r1,0
  MOVI r2,0x0000
  MOVHI r2,0x0004
  MOVI r3,0
  MOVI r7,32768
mth_ctxb_select_scan:
  LD r4,r2,1
  CMP r4,r0
  JMP[EQ] @mth_ctxb_select_scan_next
  ADDI r3,r3,1
  MOVI r5,4095
  CMP r4,r5
  JMP[LE] @mth_ctxb_select_hist
  MOVI r4,4095
mth_ctxb_select_hist:
  MOVI r5,0x8000
  MOVHI r5,0x0005
  ADD r5,r5,r4
  LD r6,r5,0
  ADDI r6,r6,1
  ST r6,r5,0
mth_ctxb_select_scan_next:
  ADDI r2,r2,3
  ADDI r1,r1,1
  CMP r1,r7
  JMP[LT] @mth_ctxb_select_scan
  MOVI r12,@mth_ctxb_unique
  ST r3,r12,0

  ; exact_count = min(exact_limit, buckets-1, unique)
  MOVI r12,@mth_ctxb_exact_limit
  LD r8,r12,0
  MOVI r12,@mth_ctxb_buckets
  LD r4,r12,0
  ADDI r4,r4,-1
  CMP r8,r4
  JMP[LE] @mth_ctxb_select_cap_unique
  ADD r8,r4,r0
mth_ctxb_select_cap_unique:
  CMP r8,r3
  JMP[LE] @mth_ctxb_select_exact_ready
  ADD r8,r3,r0
mth_ctxb_select_exact_ready:
  MOVI r12,@mth_ctxb_exact_count
  ST r8,r12,0
  MOVI r12,@mth_ctxb_buckets
  LD r4,r12,0
  SUB r9,r4,r8
  MOVI r12,@mth_ctxb_fallback
  ST r9,r12,0

  ; Find the count threshold of the top exact_count keys.
  CMP r8,r0
  JMP[EQ] @mth_ctxb_select_zero
  MOVI r10,0
  MOVI r11,0
  MOVI r4,4095
mth_ctxb_select_threshold:
  MOVI r5,0x8000
  MOVHI r5,0x0005
  ADD r5,r5,r4
  LD r6,r5,0
  ADD r11,r11,r6
  CMP r11,r8
  JMP[GE] @mth_ctxb_select_threshold_found
  CMP r4,r0
  JMP[EQ] @mth_ctxb_select_threshold_last
  ADDI r4,r4,-1
  JMP @mth_ctxb_select_threshold
mth_ctxb_select_threshold_found:
  ADD r10,r4,r0
  SUB r11,r11,r6
  SUB r11,r8,r11
  JMP @mth_ctxb_select_assign
mth_ctxb_select_threshold_last:
  MOVI r10,0
  ADD r11,r8,r0
  JMP @mth_ctxb_select_assign
mth_ctxb_select_zero:
  MOVI r10,0xFFFF
  MOVHI r10,0xFFFF
  MOVI r11,0

mth_ctxb_select_assign:
  MOVI r12,@mth_ctxb_threshold
  ST r10,r12,0
  MOVI r12,@mth_ctxb_remaining
  ST r11,r12,0

  ; First assign every key with count > threshold, sentinel the rest.
  MOVI r1,0
  MOVI r2,0x0000
  MOVHI r2,0x0004
  MOVI r3,0
  MOVI r7,32768
mth_ctxb_select_assign_high:
  LD r4,r2,1
  CMP r4,r10
  JMP[LE] @mth_ctxb_select_sentinel
  ST r3,r2,2
  ADDI r3,r3,1
  JMP @mth_ctxb_select_assign_high_next
mth_ctxb_select_sentinel:
  MOVI r5,0xFFFF
  MOVHI r5,0xFFFF
  ST r5,r2,2
mth_ctxb_select_assign_high_next:
  ADDI r2,r2,3
  ADDI r1,r1,1
  CMP r1,r7
  JMP[LT] @mth_ctxb_select_assign_high

  ; Then fill the remaining slots from keys tied at the threshold.
  MOVI r1,0
  MOVI r2,0x0000
  MOVHI r2,0x0004
  MOVI r7,32768
mth_ctxb_select_assign_tie:
  MOVI r12,@mth_ctxb_remaining
  LD r11,r12,0
  CMP r11,r0
  JMP[EQ] @mth_ctxb_select_done
  LD r4,r2,1
  CMP r4,r10
  JMP[NE] @mth_ctxb_select_assign_tie_next
  ST r3,r2,2
  ADDI r3,r3,1
  ADDI r11,r11,-1
  MOVI r12,@mth_ctxb_remaining
  ST r11,r12,0
mth_ctxb_select_assign_tie_next:
  ADDI r2,r2,3
  ADDI r1,r1,1
  CMP r1,r7
  JMP[LT] @mth_ctxb_select_assign_tie

mth_ctxb_select_done:
  MOVI r12,@mth_ctxb_exact_count
  LD r1,r12,0
  MOVI r12,@mth_ctxb_fallback
  LD r2,r12,0
  MOVI r12,@mth_ctxb_threshold
  LD r3,r12,0
  MOVI r12,@mth_ctxb_unique
  LD r4,r12,0
  MOVI r12,@mth_ctxb_select_link
  LD r15,r12,0
  RET

; r1 = packed key. Returns r1 = routed bucket, r2 = exact flag.
mth_ctxb_route:
  MOVI r3,0x79B1
  MOVHI r3,0x9E37
  MUL r2,r1,r3
  SHL r2,r2,17
  SHR r2,r2,17
  MOVI r3,3
  MUL r2,r2,r3
  MOVI r3,0x0000
  MOVHI r3,0x0004
  ADD r2,r2,r3
  MOVI r5,32768
mth_ctxb_route_probe:
  LD r6,r2,1
  CMP r6,r0
  JMP[EQ] @mth_ctxb_route_fallback
  LD r7,r2,0
  CMP r7,r1
  JMP[EQ] @mth_ctxb_route_found
  ADDI r2,r2,3
  MOVI r6,0x8000
  MOVHI r6,0x0005
  CMP r2,r6
  JMP[LT] @mth_ctxb_route_nowrap
  MOVI r2,0x0000
  MOVHI r2,0x0004
mth_ctxb_route_nowrap:
  ADDI r5,r5,-1
  CMP r5,r0
  JMP[GT] @mth_ctxb_route_probe
  JMP @mth_ctxb_route_fallback

mth_ctxb_route_found:
  LD r6,r2,2
  MOVI r12,@mth_ctxb_exact_count
  LD r7,r12,0
  CMP r6,r7
  JMP[LT] @mth_ctxb_route_exact
  JMP @mth_ctxb_route_fallback

mth_ctxb_route_exact:
  ADD r1,r6,r0
  MOVI r2,1
  RET

mth_ctxb_route_fallback:
  ; FNV-1a over the k=3 suffix, in the same newest-to-oldest order as the
  ; host baseline: b7, b6, b5.
  MOVI r6,0x9DC5
  MOVHI r6,0x811C
  MOVI r7,0x0193
  MOVHI r7,0x0100
  SHL r8,r1,24
  SHR r8,r8,24
  BOOL.6 r6,r6,r8
  MUL r6,r6,r7
  SHL r8,r1,16
  SHR r8,r8,24
  BOOL.6 r6,r6,r8
  MUL r6,r6,r7
  SHR r8,r1,16
  SHL r8,r8,24
  SHR r8,r8,24
  BOOL.6 r6,r6,r8
  MUL r6,r6,r7
  MOVI r12,@mth_ctxb_fallback
  LD r7,r12,0
  MODU r6,r6,r7
  MOVI r12,@mth_ctxb_exact_count
  LD r8,r12,0
  ADD r1,r8,r6
  MOVI r2,0
  RET

; Driver mode 3. Routes one raw k=4 key and updates the shared class memory.
mth_context_backoff:
  MOVI r12,@mth_ctxb_step_link
  ST r15,r12,0
  MOVI r12,@mth_ctxb_step_target
  ST r1,r12,0
  MOVI r12,@mth_ctxb_step_lr
  ST r2,r12,0
  MOVI r12,@mth_ctxb_step_key
  ST r3,r12,0
  MOVI r12,@mth_ctxb_step_buckets
  ST r4,r12,0

  MOVI r12,@mth_ctxb_step_key
  LD r1,r12,0
  CALL @mth_ctxb_route
  MOVI r12,@mth_ctxb_step_bucket
  ST r1,r12,0
  MOVI r12,@mth_ctxb_step_exact
  ST r2,r12,0

  MOVI r12,@mth_ctxb_step_target
  LD r1,r12,0
  MOVI r12,@mth_ctxb_step_lr
  LD r2,r12,0
  MOVI r12,@mth_ctxb_step_bucket
  LD r3,r12,0
  MOVI r12,@mth_ctxb_step_buckets
  LD r4,r12,0
  CALL @mth_context_hier

  MOVI r12,@mth_ctxb_step_exact
  LD r5,r12,0
  MOVI r12,@mth_ctxb_step_bucket
  LD r6,r12,0
  MOVI r12,@mth_ctxb_step_link
  LD r15,r12,0
  RET

mth_ctxb_build_link:
  .word 0
mth_ctxb_build_key:
  .word 0
mth_ctxb_select_link:
  .word 0
mth_ctxb_buckets:
  .word 0
mth_ctxb_exact_limit:
  .word 0
mth_ctxb_exact_count:
  .word 0
mth_ctxb_fallback:
  .word 0
mth_ctxb_threshold:
  .word 0
mth_ctxb_unique:
  .word 0
mth_ctxb_remaining:
  .word 0
mth_ctxb_step_link:
  .word 0
mth_ctxb_step_target:
  .word 0
mth_ctxb_step_lr:
  .word 0
mth_ctxb_step_key:
  .word 0
mth_ctxb_step_buckets:
  .word 0
mth_ctxb_step_bucket:
  .word 0
mth_ctxb_step_exact:
  .word 0
