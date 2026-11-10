; NaN16 LEAF hypermatrix leaf support credit.
; ABI: r1=row_bits, r2=leaf_mask, r3=leaf_counter Q16.16.
; Returns r1=support bit count, r2=support*counter.
mth_leaf_credit:
  MOVI r12,@mth_leaf_link
  ST r15,r12,0
  ADD r10,r3,r0
  BOOL.8 r4,r1,r2
  MOVI r5,0
  MOVI r6,0
  MOVI r7,32
mth_leaf_loop:
  CMP r5,r7
  JMP[GE] @mth_leaf_done
  MOVI r8,1
  BOOL.8 r9,r4,r8
  ADD r6,r6,r9
  SHR r4,r4,1
  ADDI r5,r5,1
  JMP @mth_leaf_loop
mth_leaf_done:
  MUL r2,r6,r10
  ADD r1,r6,r0
  MOVI r13,1
  MOVI r12,@mth_leaf_link
  LD r15,r12,0
  RET
mth_leaf_link:
  .word 0
