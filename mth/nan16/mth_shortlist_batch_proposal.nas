; Native NaN16 shortlist batch proposal.
;
; One ABI call evaluates an entire bounded candidate shortlist through the
; existing six-position CORDIC attention + Poincare kernel.  The host supplies
; guest token IDs only; it performs no attention or trigonometry.
;
; ABI:
;   r1 -> request U32[12 + N]:
;     [0] N candidates (1..64)
;     [1..6] context word IDs in the order [-3,-2,-1,+1,+2,+3]
;     [7] 6-bit context mask
;     [8] task (1 for masked candidate probes)
;     [9] expected generation
;     [10] actual generation
;     [11] NOW/VOID head = 255
;     [12..12+N-1] candidate guest word IDs (nonzero)
;   r2 -> output U32[4 * N] as F32 lanes:
;     [4i+0] Poincare x, [4i+1] y, [4i+2] radius, [4i+3] radial distance
;
; Returns r1 = accepted candidate count, r2 = N, r3 = 0, r4 = reject reason.
; A rejected candidate is written as four zero words and does not abort the
; batch.  Candidate count bounds are rejected before side effects.

mth_shortlist_batch_proposal:
  MOVI r0,0
  ST r15,r0,@mth_sbp_link
  ST r1,r0,@mth_sbp_req
  ST r2,r0,@mth_sbp_out
  CMP r1,r0
  JMP[EQ] @mth_sbp_bad
  CMP r2,r0
  JMP[EQ] @mth_sbp_bad
  LD r3,r1,0
  CMP r3,r0
  JMP[EQ] @mth_sbp_bad
  MOVI r4,64
  CMP r3,r4
  JMP[GT] @mth_sbp_bad
  LD r4,r1,7
  CMP r4,r0
  JMP[EQ] @mth_sbp_bad
  LD r4,r1,11
  MOVI r5,255
  CMP r4,r5
  JMP[NE] @mth_sbp_bad
  MOVI r4,0
  ST r4,r0,@mth_sbp_i
  ST r4,r0,@mth_sbp_ok
mth_sbp_loop:
  LD r4,r0,@mth_sbp_i
  LD r3,r0,@mth_sbp_req
  LD r3,r3,0
  CMP r4,r3
  JMP[GE] @mth_sbp_done
  ; Copy the six context IDs and metadata into the per-candidate request.
  LD r3,r0,@mth_sbp_req
  MOVI r5,0
mth_sbp_copy_ctx:
  MOVI r6,6
  CMP r5,r6
  JMP[GE] @mth_sbp_copy_meta
  ADD r6,r3,r5
  LD r7,r6,1
  MOVI r6,@mth_sbp_one_req
  ADD r6,r6,r5
  ST r7,r6,1
  ADDI r5,r5,1
  JMP @mth_sbp_copy_ctx
mth_sbp_copy_meta:
  LD r7,r3,7
  MOVI r6,@mth_sbp_one_req
  ST r7,r6,7
  LD r7,r3,8
  ST r7,r6,8
  LD r7,r3,9
  ST r7,r6,9
  LD r7,r3,10
  ST r7,r6,10
  MOVI r7,255
  ST r7,r6,11
  ; Candidate anchor.
  LD r4,r0,@mth_sbp_i
  ADD r6,r3,r4
  LD r7,r6,12
  MOVI r6,@mth_sbp_one_req
  ST r7,r6,0
  CMP r7,r0
  JMP[EQ] @mth_sbp_reject_one
  MOVI r1,@mth_sbp_one_req
  MOVI r2,@mth_sbp_one_out
  CALL @mth_six_context_poincare_attention
  MOVI r3,1
  CMP r1,r3
  JMP[NE] @mth_sbp_reject_one
  ; Copy x,y,radius,distance to output slot 4*i.
  LD r3,r0,@mth_sbp_i
  SHL r3,r3,2
  LD r4,r0,@mth_sbp_out
  ADD r4,r4,r3
  MOVI r5,@mth_sbp_one_out
  LD r6,r5,0
  ST r6,r4,0
  LD r6,r5,1
  ST r6,r4,1
  LD r6,r5,2
  ST r6,r4,2
  LD r6,r5,3
  ST r6,r4,3
  LD r4,r0,@mth_sbp_ok
  ADDI r4,r4,1
  ST r4,r0,@mth_sbp_ok
  JMP @mth_sbp_next
mth_sbp_reject_one:
  LD r3,r0,@mth_sbp_i
  SHL r3,r3,2
  LD r4,r0,@mth_sbp_out
  ADD r4,r4,r3
  MOVI r5,0
  ST r5,r4,0
  ST r5,r4,1
  ST r5,r4,2
  ST r5,r4,3
mth_sbp_next:
  LD r4,r0,@mth_sbp_i
  ADDI r4,r4,1
  ST r4,r0,@mth_sbp_i
  JMP @mth_sbp_loop
mth_sbp_done:
  LD r1,r0,@mth_sbp_ok
  LD r2,r0,@mth_sbp_req
  LD r2,r2,0
  MOVI r3,0
  MOVI r4,0
  MOVI r12,@mth_sbp_link
  LD r15,r12,0
  RET
mth_sbp_bad:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r4,1
  MOVI r12,@mth_sbp_link
  LD r15,r12,0
  RET

mth_sbp_link:
  .word 0
mth_sbp_req:
  .word 0
mth_sbp_out:
  .word 0
mth_sbp_i:
  .word 0
mth_sbp_ok:
  .word 0
mth_sbp_one_req:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
mth_sbp_one_out:
  .word 0,0,0,0,0,0,0,0
