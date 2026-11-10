; Raw NaN16 FNV-1a context hashing plus hierarchical context readout.
;
; The guest owns the hash arithmetic and bucket selection. The host supplies
; only raw context bytes packed little-endian (the first byte to hash is in
; bits 0..7), the byte count, target, learning rate and bucket count.
;
; ABI:
;   r1 = target byte 0..254
;   r2 = learning-rate float32 bits
;   r3 = packed context bytes, first hashed byte in bits 0..7
;   r4 = context byte count 1..4
;   r5 = bucket count B (1..16384)
; Returns:
;   r1 = 1 when both high and low predictions are correct
;   r2 = high CE + low CE (training target group)
;   r3 = predicted high class
;   r4 = predicted low class
;   r5 = FNV-1a bucket (hash % B)
;
; FNV-1a 32-bit: h = 0x811C9DC5; for each byte b: h = (h XOR b) * 0x01000193.
; MUL keeps the low 32 bits, matching uint32 wrap, and MODU is unsigned.
mth_context_hash:
  MOVI r12,@mth_ctxh_link
  ST r15,r12,0
  MOVI r12,@mth_ctxh_target
  ST r1,r12,0
  MOVI r12,@mth_ctxh_lr
  ST r2,r12,0
  MOVI r12,@mth_ctxh_packed
  ST r3,r12,0
  MOVI r12,@mth_ctxh_count
  ST r4,r12,0
  MOVI r12,@mth_ctxh_buckets
  ST r5,r12,0

  ; hash = FNV offset basis 0x811C9DC5
  MOVI r6,0x9DC5
  MOVHI r6,0x811C
  ; prime = FNV prime 0x01000193
  MOVI r7,0x0193
  MOVHI r7,0x0100
  MOVI r12,@mth_ctxh_packed
  LD r4,r12,0
  MOVI r5,0
mth_ctxh_loop:
  MOVI r12,@mth_ctxh_count
  LD r12,r12,0
  CMP r5,r12
  JMP[GE] @mth_ctxh_loop_done
  ; b = packed & 0xFF
  SHL r9,r4,24
  SHR r9,r9,24
  ; hash = (hash XOR b) * prime
  BOOL.6 r6,r6,r9
  MUL r6,r6,r7
  SHR r4,r4,8
  ADDI r5,r5,1
  JMP @mth_ctxh_loop
mth_ctxh_loop_done:
  ; bucket = hash % B
  MOVI r12,@mth_ctxh_buckets
  LD r5,r12,0
  MODU r6,r6,r5
  MOVI r12,@mth_ctxh_bucket
  ST r6,r12,0

  ; Run the existing context-hierarchical readout on the guest-selected bucket.
  MOVI r12,@mth_ctxh_target
  LD r1,r12,0
  MOVI r12,@mth_ctxh_lr
  LD r2,r12,0
  MOVI r12,@mth_ctxh_bucket
  LD r3,r12,0
  MOVI r12,@mth_ctxh_buckets
  LD r4,r12,0
  CALL @mth_context_hier

  MOVI r12,@mth_ctxh_bucket
  LD r5,r12,0
  MOVI r12,@mth_ctxh_link
  LD r15,r12,0
  RET

mth_ctxh_link:
  .word 0
mth_ctxh_target:
  .word 0
mth_ctxh_lr:
  .word 0
mth_ctxh_packed:
  .word 0
mth_ctxh_count:
  .word 0
mth_ctxh_buckets:
  .word 0
mth_ctxh_bucket:
  .word 0
