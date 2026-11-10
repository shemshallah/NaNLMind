; Raw NaN16 checkpoint payload digest.
; ABI:
;   r1 = base word address
;   r2 = word count (0..65535)
; Returns:
;   r1 = FNV-1a 32-bit digest over the payload words
;
; This is an integrity check for persisted codebook/matrix state. The host only
; pages the payload; the digest is computed by the guest.
mth_ckpt_hash:
  ; FNV offset basis 2166136261 = 0x811C9DC5
  MOVI r3,0x9DC5
  MOVHI r3,0x811C
  MOVI r5,0
mth_ck_hash_loop:
  CMP r5,r2
  JMP[GE] @mth_ck_hash_done
  ADD r6,r1,r5
  LD r6,r6,0
  ; hash ^= word
  BOOL.6 r3,r3,r6
  ; hash *= 16777619 (0x01000193)
  MOVI r6,0x0193
  MOVHI r6,0x0100
  MUL r3,r3,r6
  ADDI r5,r5,1
  JMP @mth_ck_hash_loop
mth_ck_hash_done:
  ADD r1,r3,r0
  RET
