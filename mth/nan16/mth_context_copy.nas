; Raw NaN16 context memory with a copy/induction soft-gate route.
;
; Two sparse 16x16 class tables are trained on every sample:
;   memory    : exact 4-byte top contexts, 3-byte hash backoff (host-built map)
;   induction : 2-byte suffix continuation copy (hash bucket, raw guest routing)
;
; The memory bucket is resolved here from the raw four context bytes and a
; guest-resident exact-key map.  The induction bucket is a raw FNV hash of the
; last two bytes.  Scoring combines the two class logit tables:
;
;   score(c) = mem_hi[h] + w*ind_hi[h] + mem_lo[h,l] + w*ind_lo[h,l]
;
; over the two best combined high-nibble groups.  The gate weight w is a
; float32 value transported unchanged by the host.
;
; Fixed memory:
;   0x60000  exact-key map, 16384 slots x 3 words (occupied, key, bucket)
;   0x80000  induction table, 16*C high + 16*16*C low scores
;   0x100000 memory table, 16*B high + 16*16*B low scores
;   0x2800   scratch high/combined scores (16 words each)
;   0x2820   scratch low scores (16 words each)
;
; ABI:
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits (0 disables updates)
;   r3 = packed context bytes line[4]..line[7] (line[4] in bits 31..24)
;   r4 = memory bucket count B
;   r5 = exact context count E (0 < E < B)
;   r6 = induction bucket count C
;   r7 = gate weight float32 bits
; Returns:
;   r1 = 1 when the combined prediction is correct
;   r2 = memory high+true-low cross entropy bits
;   r3 = combined predicted class 0..255
mth_context_copy:
  MOVI r12,@mth_cc_link
  ST r15,r12,0
  MOVI r12,@mth_cc_target
  ST r1,r12,0
  MOVI r12,@mth_cc_lr
  ST r2,r12,0
  MOVI r12,@mth_cc_key
  ST r3,r12,0
  MOVI r12,@mth_cc_buckets
  ST r4,r12,0
  MOVI r12,@mth_cc_exact
  ST r5,r12,0
  MOVI r12,@mth_cc_aux
  ST r6,r12,0
  MOVI r12,@mth_cc_weight
  ST r7,r12,0

  ; target nibbles
  MOVI r12,@mth_cc_target
  LD r1,r12,0
  SHR r4,r1,4
  MOVI r12,@mth_cc_high
  ST r4,r12,0
  SHL r4,r1,28
  SHR r4,r4,28
  MOVI r12,@mth_cc_low
  ST r4,r12,0

  ; FNV prime in r13.
  MOVI r13,0x0193
  MOVHI r13,0x0100
  MOVI r6,256

  ; Exact-key hash: FNV1a over line[4],line[5],line[6],line[7].
  MOVI r4,0x9DC5
  MOVHI r4,0x811C
  MOVI r12,@mth_cc_key
  LD r3,r12,0
  SHR r5,r3,24
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  SHR r5,r3,16
  MODU r5,r5,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  SHR r5,r3,8
  MODU r5,r5,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  MODU r5,r3,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  MOVI r12,@mth_cc_hash
  ST r4,r12,0

  ; Guest-side exact map lookup.  Only this path chooses exact vs 3-byte
  ; backoff; the host supplies the map but no per-sample routing decision.
  MOVI r6,0x0000
  MOVHI r6,0x0006
  MOVI r7,0x4000
  MODU r4,r4,r7
  MOVI r12,@mth_cc_slot
  ST r4,r12,0
  MOVI r8,3
  MUL r5,r4,r8
  ADD r5,r5,r6
mth_cc_map_loop:
  LD r8,r5,0
  CMP r8,r0
  JMP[EQ] @mth_cc_map_miss
  LD r9,r5,1
  MOVI r12,@mth_cc_key
  LD r10,r12,0
  CMP r9,r10
  JMP[EQ] @mth_cc_map_hit
  ADDI r5,r5,3
  MOVI r12,@mth_cc_slot
  LD r4,r12,0
  ADDI r4,r4,1
  CMP r4,r7
  JMP[LT] @mth_cc_map_nowrap
  MOVI r4,0
mth_cc_map_nowrap:
  ST r4,r12,0
  JMP @mth_cc_map_loop
mth_cc_map_hit:
  LD r4,r5,2
  MOVI r12,@mth_cc_mem_bucket
  ST r4,r12,0
  JMP @mth_cc_aux_hash

mth_cc_map_miss:
  ; 3-byte backoff hash over line[7],line[6],line[5] (same byte order as the
  ; host baseline used for its fallback buckets).
  MOVI r4,0x9DC5
  MOVHI r4,0x811C
  MOVI r12,@mth_cc_key
  LD r3,r12,0
  MOVI r6,256
  MODU r5,r3,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  SHR r5,r3,8
  MODU r5,r5,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  SHR r5,r3,16
  MODU r5,r5,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  MOVI r12,@mth_cc_buckets
  LD r6,r12,0
  MOVI r12,@mth_cc_exact
  LD r7,r12,0
  SUB r6,r6,r7
  CMP r6,r0
  JMP[EQ] @mth_cc_map_zero_fallback
  MODU r4,r4,r6
  ADD r4,r4,r7
  JMP @mth_cc_map_store
mth_cc_map_zero_fallback:
  ADD r4,r7,r0
mth_cc_map_store:
  MOVI r12,@mth_cc_mem_bucket
  ST r4,r12,0

mth_cc_aux_hash:
  ; Induction/copy bucket: FNV1a over line[6],line[7].
  MOVI r6,256
  MOVI r4,0x9DC5
  MOVHI r4,0x811C
  MOVI r12,@mth_cc_key
  LD r3,r12,0
  SHR r5,r3,8
  MODU r5,r5,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  MODU r5,r3,r6
  BOOL.6 r4,r4,r5
  MUL r4,r4,r13
  MOVI r12,@mth_cc_aux
  LD r6,r12,0
  MODU r4,r4,r6
  MOVI r12,@mth_cc_aux_bucket
  ST r4,r12,0

  ; Memory high head.
  MOVI r1,0x0000
  MOVHI r1,0x0010
  MOVI r12,@mth_cc_buckets
  LD r2,r12,0
  MOVI r12,@mth_cc_mem_bucket
  LD r3,r12,0
  MOVI r12,@mth_cc_high
  LD r4,r12,0
  MOVI r12,@mth_cc_lr
  LD r5,r12,0
  CALL @mth_softmax16_table
  MOVI r12,@mth_cc_loss_high_mem
  ST r2,r12,0
  MOVI r2,16
  MOVI r12,@mth_cc_buckets
  LD r10,r12,0
  MUL r10,r10,r2
  MOVI r2,0x0000
  MOVHI r2,0x0010
  ADD r2,r2,r10
  MOVI r12,@mth_cc_high
  LD r4,r12,0
  MOVI r11,16
  MUL r4,r4,r11
  MOVI r12,@mth_cc_buckets
  LD r10,r12,0
  MUL r4,r4,r10
  ADD r2,r2,r4
  ADD r1,r2,r0
  MOVI r12,@mth_cc_buckets
  LD r2,r12,0
  MOVI r12,@mth_cc_mem_bucket
  LD r3,r12,0
  MOVI r12,@mth_cc_low
  LD r4,r12,0
  MOVI r12,@mth_cc_lr
  LD r5,r12,0
  CALL @mth_softmax16_table
  MOVI r12,@mth_cc_loss_low_mem
  ST r2,r12,0

  ; Induction high head.
  MOVI r1,0x0000
  MOVHI r1,0x0008
  MOVI r12,@mth_cc_aux
  LD r2,r12,0
  MOVI r12,@mth_cc_aux_bucket
  LD r3,r12,0
  MOVI r12,@mth_cc_high
  LD r4,r12,0
  MOVI r12,@mth_cc_lr
  LD r5,r12,0
  CALL @mth_softmax16_table
  MOVI r2,16
  MOVI r12,@mth_cc_aux
  LD r10,r12,0
  MUL r10,r10,r2
  MOVI r2,0x0000
  MOVHI r2,0x0008
  ADD r2,r2,r10
  MOVI r12,@mth_cc_high
  LD r4,r12,0
  MOVI r11,16
  MUL r4,r4,r11
  MOVI r12,@mth_cc_aux
  LD r10,r12,0
  MUL r4,r4,r10
  ADD r2,r2,r4
  ADD r1,r2,r0
  MOVI r12,@mth_cc_aux
  LD r2,r12,0
  MOVI r12,@mth_cc_aux_bucket
  LD r3,r12,0
  MOVI r12,@mth_cc_low
  LD r4,r12,0
  MOVI r12,@mth_cc_lr
  LD r5,r12,0
  CALL @mth_softmax16_table

  ; High scores and combined high scores.
  MOVI r5,0
mth_cc_hi_loop:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_cc_hi_done
  MOVI r6,0x0000
  MOVHI r6,0x0010
  MOVI r12,@mth_cc_buckets
  LD r7,r12,0
  MUL r7,r5,r7
  ADD r7,r7,r6
  MOVI r12,@mth_cc_mem_bucket
  LD r8,r12,0
  ADD r7,r7,r8
  LD r7,r7,0
  MOVI r9,0x2800
  ADD r9,r9,r5
  ST r7,r9,0
  MOVI r6,0x0000
  MOVHI r6,0x0008
  MOVI r12,@mth_cc_aux
  LD r7,r12,0
  MUL r7,r5,r7
  ADD r7,r7,r6
  MOVI r12,@mth_cc_aux_bucket
  LD r8,r12,0
  ADD r7,r7,r8
  LD r7,r7,0
  MOVI r9,0x2810
  ADD r9,r9,r5
  ST r7,r9,0
  MOVI r12,@mth_cc_weight
  LD r8,r12,0
  FMUL r7,r7,r8
  MOVI r9,0x2800
  ADD r9,r9,r5
  LD r9,r9,0
  FADD r7,r7,r9
  MOVI r9,0x2840
  ADD r9,r9,r5
  ST r7,r9,0
  ADDI r5,r5,1
  JMP @mth_cc_hi_loop
mth_cc_hi_done:

  ; Top two combined high groups.
  MOVI r8,0
  MOVHI r8,0xFF80
  ADD r9,r8,r0
  MOVI r10,0
  MOVI r11,0
  MOVI r5,0
mth_cc_top_loop:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_cc_top_done
  MOVI r6,0x2840
  ADD r6,r6,r5
  LD r7,r6,0
  FCMP r7,r8
  JMP[LE] @mth_cc_top_second
  ADD r9,r8,r0
  ADD r11,r10,r0
  ADD r8,r7,r0
  ADD r10,r5,r0
  JMP @mth_cc_top_next
mth_cc_top_second:
  FCMP r7,r9
  JMP[LE] @mth_cc_top_next
  ADD r9,r7,r0
  ADD r11,r5,r0
mth_cc_top_next:
  ADDI r5,r5,1
  JMP @mth_cc_top_loop
mth_cc_top_done:
  MOVI r12,@mth_cc_idx1
  ST r10,r12,0
  MOVI r12,@mth_cc_idx2
  ST r11,r12,0

  MOVI r4,0
  MOVHI r4,0xFF80
  MOVI r12,@mth_cc_best_score
  ST r4,r12,0
  MOVI r4,0
  MOVI r12,@mth_cc_best_class
  ST r4,r12,0
  MOVI r12,@mth_cc_idx1
  LD r1,r12,0
  CALL @mth_cc_group
  MOVI r12,@mth_cc_idx2
  LD r1,r12,0
  CALL @mth_cc_group

  ; Correctness against the final combined argmax.
  MOVI r12,@mth_cc_best_class
  LD r3,r12,0
  MOVI r12,@mth_cc_target
  LD r1,r12,0
  CMP r3,r1
  JMP[NE] @mth_cc_wrong
  MOVI r1,1
  JMP @mth_cc_correct
mth_cc_wrong:
  MOVI r1,0
mth_cc_correct:
  MOVI r12,@mth_cc_loss_high_mem
  LD r2,r12,0
  MOVI r12,@mth_cc_loss_low_mem
  LD r4,r12,0
  FADD r2,r2,r4
  MOVI r12,@mth_cc_best_class
  LD r3,r12,0
  MOVI r12,@mth_cc_link
  LD r15,r12,0
  RET

; Score the 16 low classes under one high group for both tables.
; Input r1 = high group.  Updates global best score/class.
mth_cc_group:
  MOVI r12,@mth_cc_g_link
  ST r15,r12,0
  MOVI r12,@mth_cc_g_h
  ST r1,r12,0
  MOVI r6,0x2800
  ADD r6,r6,r1
  LD r7,r6,0
  MOVI r12,@mth_cc_g_mh
  ST r7,r12,0
  MOVI r6,0x2810
  ADD r6,r6,r1
  LD r7,r6,0
  MOVI r12,@mth_cc_g_ih
  ST r7,r12,0

  ; Memory low base = 0x100000 + (1 + h)*16*B + bucket.
  MOVI r12,@mth_cc_buckets
  LD r10,r12,0
  MOVI r11,16
  MUL r10,r10,r11
  MOVI r9,0x0000
  MOVHI r9,0x0010
  ADD r9,r9,r10
  MOVI r12,@mth_cc_g_h
  LD r7,r12,0
  MUL r7,r7,r10
  ADD r9,r9,r7
  MOVI r12,@mth_cc_mem_bucket
  LD r7,r12,0
  ADD r9,r9,r7
  MOVI r5,0
mth_cc_g_ml_loop:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_cc_g_ml_done
  MOVI r12,@mth_cc_buckets
  LD r10,r12,0
  MUL r11,r5,r10
  ADD r11,r11,r9
  LD r7,r11,0
  MOVI r6,0x2820
  ADD r6,r6,r5
  ST r7,r6,0
  ADDI r5,r5,1
  JMP @mth_cc_g_ml_loop
mth_cc_g_ml_done:

  ; Induction low base = 0x80000 + (1 + h)*16*C + aux bucket.
  MOVI r12,@mth_cc_aux
  LD r10,r12,0
  MOVI r11,16
  MUL r10,r10,r11
  MOVI r9,0x0000
  MOVHI r9,0x0008
  ADD r9,r9,r10
  MOVI r12,@mth_cc_g_h
  LD r7,r12,0
  MUL r7,r7,r10
  ADD r9,r9,r7
  MOVI r12,@mth_cc_aux_bucket
  LD r7,r12,0
  ADD r9,r9,r7
  MOVI r5,0
mth_cc_g_il_loop:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_cc_g_il_done
  MOVI r12,@mth_cc_aux
  LD r10,r12,0
  MUL r11,r5,r10
  ADD r11,r11,r9
  LD r7,r11,0
  MOVI r6,0x2830
  ADD r6,r6,r5
  ST r7,r6,0
  ADDI r5,r5,1
  JMP @mth_cc_g_il_loop
mth_cc_g_il_done:

  ; base = mh + w*ih
  MOVI r12,@mth_cc_weight
  LD r8,r12,0
  MOVI r12,@mth_cc_g_ih
  LD r7,r12,0
  FMUL r7,r7,r8
  MOVI r12,@mth_cc_g_mh
  LD r9,r12,0
  FADD r9,r9,r7
  MOVI r12,@mth_cc_g_base
  ST r9,r12,0

  ; l = 0..15: score = base + mem_low + w*ind_low
  MOVI r5,0
mth_cc_g_score_loop:
  MOVI r12,16
  CMP r5,r12
  JMP[GE] @mth_cc_g_score_done
  MOVI r12,@mth_cc_g_base
  LD r9,r12,0
  MOVI r6,0x2820
  ADD r6,r6,r5
  LD r7,r6,0
  FADD r9,r9,r7
  MOVI r6,0x2830
  ADD r6,r6,r5
  LD r7,r6,0
  MOVI r12,@mth_cc_weight
  LD r8,r12,0
  FMUL r7,r7,r8
  FADD r9,r9,r7
  MOVI r12,@mth_cc_best_score
  LD r10,r12,0
  FCMP r9,r10
  JMP[LE] @mth_cc_g_score_next
  ST r9,r12,0
  MOVI r12,@mth_cc_g_h
  LD r7,r12,0
  MOVI r11,16
  MUL r7,r7,r11
  ADD r7,r7,r5
  MOVI r12,@mth_cc_best_class
  ST r7,r12,0
mth_cc_g_score_next:
  ADDI r5,r5,1
  JMP @mth_cc_g_score_loop
mth_cc_g_score_done:
  MOVI r12,@mth_cc_g_link
  LD r15,r12,0
  RET

mth_cc_link:
  .word 0
mth_cc_target:
  .word 0
mth_cc_lr:
  .word 0
mth_cc_key:
  .word 0
mth_cc_buckets:
  .word 0
mth_cc_exact:
  .word 0
mth_cc_aux:
  .word 0
mth_cc_weight:
  .word 0
mth_cc_high:
  .word 0
mth_cc_low:
  .word 0
mth_cc_hash:
  .word 0
mth_cc_slot:
  .word 0
mth_cc_mem_bucket:
  .word 0
mth_cc_aux_bucket:
  .word 0
mth_cc_idx1:
  .word 0
mth_cc_idx2:
  .word 0
mth_cc_best_score:
  .word 0
mth_cc_best_class:
  .word 0
mth_cc_loss_high_mem:
  .word 0
mth_cc_loss_low_mem:
  .word 0
mth_cc_g_link:
  .word 0
mth_cc_g_h:
  .word 0
mth_cc_g_mh:
  .word 0
mth_cc_g_ih:
  .word 0
mth_cc_g_base:
  .word 0
