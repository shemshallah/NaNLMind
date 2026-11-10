; Raw NaN16 sparse k-NN over a vector bank.
;
; ABI:
;   r1 = query[D] Q16.16
;   r2 = bank[N][D] Q16.16
;   r3 = N
;   r4 = D
;   r5 = k (1..4)
;   r6 = output indices[k]
;   r7 = output scores[k]
; Returns r1 = returned k.
;
; This is an exact local top-k scan. It is used to select sparse codebook
; regions before any remote leaf fetch; no host arithmetic is involved.
mth_sparse_knn:
  MOVI r12,@mth_kn_link
  ST r15,r12,0
  MOVI r12,@mth_kn_query
  ST r1,r12,0
  MOVI r12,@mth_kn_bank
  ST r2,r12,0
  MOVI r12,@mth_kn_n
  ST r3,r12,0
  MOVI r12,@mth_kn_d
  ST r4,r12,0
  MOVI r12,@mth_kn_k
  ST r5,r12,0
  MOVI r12,@mth_kn_out_idx
  ST r6,r12,0
  MOVI r12,@mth_kn_out_score
  ST r7,r12,0

  ; scores[0..3] = -2^31, indices = 0
  MOVI r12,@mth_kn_i
  ST r0,r12,0
mth_kn_init:
  MOVI r12,@mth_kn_i
  LD r5,r12,0
  MOVI r12,4
  CMP r5,r12
  JMP[GE] @mth_kn_init_done
  MOVI r12,@mth_kn_scores
  ADD r6,r12,r5
  MOVI r7,0
  MOVHI r7,0x8000
  ST r7,r6,0
  MOVI r12,@mth_kn_idx
  ADD r6,r12,r5
  ST r0,r6,0
  ADDI r5,r5,1
  MOVI r12,@mth_kn_i
  ST r5,r12,0
  JMP @mth_kn_init
mth_kn_init_done:

  MOVI r12,@mth_kn_c
  ST r0,r12,0
mth_kn_c_loop:
  MOVI r12,@mth_kn_c
  LD r5,r12,0
  MOVI r12,@mth_kn_n
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_kn_done

  ; row = bank + c*D
  MOVI r12,@mth_kn_d
  LD r6,r12,0
  MUL r7,r5,r6
  MOVI r12,@mth_kn_bank
  LD r6,r12,0
  ADD r7,r7,r6
  MOVI r12,@mth_kn_row
  ST r7,r12,0
  MOVI r12,@mth_kn_di
  ST r0,r12,0
  MOVI r12,@mth_kn_sum
  ST r0,r12,0
mth_kn_d_loop:
  MOVI r12,@mth_kn_di
  LD r5,r12,0
  MOVI r12,@mth_kn_d
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_kn_dot_done
  MOVI r12,@mth_kn_row
  LD r6,r12,0
  ADD r6,r6,r5
  LD r1,r6,0
  MOVI r12,@mth_kn_query
  LD r6,r12,0
  ADD r6,r6,r5
  LD r2,r6,0
  CALL @mth_q16_mul
  MOVI r12,@mth_kn_sum
  LD r6,r12,0
  ADD r6,r6,r1
  ST r6,r12,0
  MOVI r12,@mth_kn_di
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_kn_d_loop
mth_kn_dot_done:
  MOVI r12,@mth_kn_pos
  ST r0,r12,0
mth_kn_find:
  MOVI r12,@mth_kn_pos
  LD r5,r12,0
  MOVI r12,@mth_kn_k
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_kn_next_c
  MOVI r12,@mth_kn_scores
  ADD r7,r12,r5
  LD r7,r7,0
  MOVI r12,@mth_kn_sum
  LD r8,r12,0
  CMPS r8,r7
  JMP[GT] @mth_kn_insert
  ADDI r5,r5,1
  MOVI r12,@mth_kn_pos
  ST r5,r12,0
  JMP @mth_kn_find
mth_kn_insert:
  ; shift entries down from k-1 to pos
  MOVI r12,@mth_kn_k
  LD r6,r12,0
  MOVI r12,4
  CMP r6,r12
  JMP[LE] @mth_kn_shift_start
  MOVI r6,4
mth_kn_shift_start:
  SUB r6,r6,r13
mth_kn_shift:
  CMP r6,r5
  JMP[LE] @mth_kn_shift_done
  MOVI r12,@mth_kn_scores
  ADD r7,r12,r6
  SUB r8,r6,r13
  ADD r9,r12,r8
  LD r10,r9,0
  ST r10,r7,0
  MOVI r12,@mth_kn_idx
  ADD r7,r12,r6
  ADD r9,r12,r8
  LD r10,r9,0
  ST r10,r7,0
  SUB r6,r6,r13
  JMP @mth_kn_shift
mth_kn_shift_done:
  MOVI r12,@mth_kn_scores
  ADD r7,r12,r5
  MOVI r12,@mth_kn_sum
  LD r8,r12,0
  ST r8,r7,0
  MOVI r12,@mth_kn_idx
  ADD r7,r12,r5
  MOVI r12,@mth_kn_c
  LD r8,r12,0
  ST r8,r7,0
mth_kn_next_c:
  MOVI r12,@mth_kn_c
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_kn_c_loop
mth_kn_done:
  MOVI r12,@mth_kn_i
  ST r0,r12,0
  MOVI r12,@mth_kn_k
  LD r6,r12,0
mth_kn_out:
  MOVI r12,@mth_kn_i
  LD r5,r12,0
  CMP r5,r6
  JMP[GE] @mth_kn_return
  MOVI r12,@mth_kn_out_idx
  LD r7,r12,0
  ADD r7,r7,r5
  MOVI r12,@mth_kn_idx
  ADD r8,r12,r5
  LD r9,r8,0
  ST r9,r7,0
  MOVI r12,@mth_kn_out_score
  LD r7,r12,0
  ADD r7,r7,r5
  MOVI r12,@mth_kn_scores
  ADD r8,r12,r5
  LD r9,r8,0
  ST r9,r7,0
  ADDI r5,r5,1
  MOVI r12,@mth_kn_i
  ST r5,r12,0
  JMP @mth_kn_out
mth_kn_return:
  MOVI r12,@mth_kn_k
  LD r1,r12,0
  MOVI r12,@mth_kn_link
  LD r15,r12,0
  RET

mth_kn_link:
  .word 0
mth_kn_query:
  .word 0
mth_kn_bank:
  .word 0
mth_kn_n:
  .word 0
mth_kn_d:
  .word 0
mth_kn_k:
  .word 0
mth_kn_out_idx:
  .word 0
mth_kn_out_score:
  .word 0
mth_kn_i:
  .word 0
mth_kn_c:
  .word 0
mth_kn_di:
  .word 0
mth_kn_row:
  .word 0
mth_kn_sum:
  .word 0
mth_kn_pos:
  .word 0
mth_kn_scores:
  .word 0
  .word 0
  .word 0
  .word 0
mth_kn_idx:
  .word 0
  .word 0
  .word 0
  .word 0
