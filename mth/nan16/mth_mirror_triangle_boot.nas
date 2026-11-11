; Native boot-frozen topology sampler for mirror-pair curvature.
; Physical 256 addresses include 255=NOW/VOID, so the 255 active
; palindromic fixed-point anchors 0..254 form the trainable ring.
; For the conceptual 256-node atlas C(256,3)=2,763,520; measuring
; all triples is infeasible. We select 255 LOCAL ring triples and
; 255 deterministic seeded LONG-RANGE triples (510 total).
; Frozen seed + epoch guarantee stable recall and no silent resampling.
;
; Physical address mapping for anchor i: pal16(i)=(rev8(i)<<8)|i.
; Directed mirrored pair address: addr(i,j)=(rev8(i)<<8)|j,
; mirror bit-reversal: rev16(addr(i,j))=addr(j,i).
; Each (i,j) flow is an oriented signed measurement of the real S+/S-
; mirror-pair rail, supplied separately; these addresses are NOT an
; alternative universe.
;
; Bootstrap r1=seed !=0, r2=epoch, r3=table[510][3] U32.
; r4=flag storage[3] U32 initialized zero, returns r1=1,r2=510,r3=0.
; Reject r1=0,r2=0,r3=1 invalid/2 already booted. Never overwrites
; frozen topology after successful boot; caller persists and hashes it.
; Not cryptographic RNG: xorshift32 is a reproducible topology sampler.
; Long triangles: a=t, b=a+32+(x&63), c=a+128+(x'&63), modulo 255.
; Each long edge spans at least 32 circular active-anchor intervals.
mth_mirror_triangle_boot:
  MOVI r0,0
  ST r15,r0,@mtb_link
  ST r1,r0,@mtb_seed
  ST r2,r0,@mtb_epoch
  ST r3,r0,@mtb_table
  ST r4,r0,@mtb_flag
  CMP r1,r0
  JMP[EQ] @mtb_bad
  CMP r3,r0
  JMP[EQ] @mtb_bad
  CMP r4,r0
  JMP[EQ] @mtb_bad
  LD r9,r4,0
  CMP r9,r0
  JMP[NE] @mtb_already
  ST r0,r0,@mtb_index

mtb_local:
  LD r8,r0,@mtb_index
  MOVI r10,255
  CMP r8,r10
  JMP[GE] @mtb_long_init
  LD r9,r0,@mtb_table
  MOVI r10,3
  MUL r11,r8,r10
  ADD r9,r9,r11
  ST r8,r9,0
  ADDI r11,r8,1
  MOVI r12,255
  CMP r11,r12
  JMP[LT] @mtb_local_b
  SUB r11,r11,r12
mtb_local_b:
  ST r11,r9,1
  ADDI r11,r8,2
  MOVI r12,255
  CMP r11,r12
  JMP[LT] @mtb_local_c
  SUB r11,r11,r12
mtb_local_c:
  ST r11,r9,2
  ADDI r8,r8,1
  ST r8,r0,@mtb_index
  JMP @mtb_local

mtb_long_init:
  ST r0,r0,@mtb_index
  LD r10,r0,@mtb_seed
  ST r10,r0,@mtb_rng
mtb_long:
  LD r8,r0,@mtb_index
  MOVI r10,255
  CMP r8,r10
  JMP[GE] @mtb_publish
  LD r9,r0,@mtb_table
  MOVI r10,255
  ADD r11,r8,r10
  MOVI r10,3
  MUL r11,r11,r10
  ADD r9,r9,r11
  ST r8,r9,0
  CALL @mtb_next
  MOVI r12,63
  BOOL.8 r10,r10,r12
  ADDI r10,r10,32
  ADD r10,r10,r8
  MOVI r11,255
  CMP r10,r11
  JMP[LT] @mtb_long_b
  SUB r10,r10,r11
mtb_long_b:
  ST r10,r9,1
  CALL @mtb_next
  MOVI r12,63
  BOOL.8 r10,r10,r12
  ADDI r10,r10,128
  ADD r10,r10,r8
  MOVI r11,255
  CMP r10,r11
  JMP[LT] @mtb_long_c
  SUB r10,r10,r11
mtb_long_c:
  ST r10,r9,2
  LD r8,r0,@mtb_index
  ADDI r8,r8,1
  ST r8,r0,@mtb_index
  JMP @mtb_long

; r10=next xorshift32, other registers r9/r8 remain unchanged.
mtb_next:
  LD r10,r0,@mtb_rng
  SHL r11,r10,13
  BOOL.6 r10,r10,r11
  SHR r11,r10,17
  BOOL.6 r10,r10,r11
  SHL r11,r10,5
  BOOL.6 r10,r10,r11
  ST r10,r0,@mtb_rng
  RET

mtb_publish:
  LD r9,r0,@mtb_flag
  MOVI r10,1
  ST r10,r9,0
  LD r10,r0,@mtb_seed
  ST r10,r9,1
  LD r10,r0,@mtb_epoch
  ST r10,r9,2
  MOVI r1,1
  MOVI r2,510
  MOVI r3,0
  JMP @mtb_return
mtb_already:
  MOVI r3,2
  JMP @mtb_reject
mtb_bad:
  MOVI r3,1
mtb_reject:
  MOVI r1,0
  MOVI r2,0
mtb_return:
  MOVI r13,1
  LD r15,r0,@mtb_link
  RET
mtb_link:
  .word 0
mtb_seed:
  .word 0
mtb_epoch:
  .word 0
mtb_table:
  .word 0
mtb_flag:
  .word 0
mtb_index:
  .word 0
mtb_rng:
  .word 0
