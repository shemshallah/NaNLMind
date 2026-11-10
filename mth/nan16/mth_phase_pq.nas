; Raw NaN16 product quantizer and graph spectral embedding helpers.
;
; Both kernels operate on Q16.16 vectors. The host may marshal a codebook or
; adjacency matrix, but every comparison, dot product, rotation and iteration
; below runs in the guest.

; Product quantizer: nearest codeword by L1 distance.
; ABI:
;   r1 = query[D] address
;   r2 = codebook[C][D] address
;   r3 = C
;   r4 = D
;   r5 = output address: [code, distance]
; Returns:
;   r1 = code, r2 = distance
mth_pq_encode:
  MOVI r12,@mth_pq_link
  ST r15,r12,0
  MOVI r12,@mth_pq_query
  ST r1,r12,0
  MOVI r12,@mth_pq_book
  ST r2,r12,0
  MOVI r12,@mth_pq_c
  ST r3,r12,0
  MOVI r12,@mth_pq_d
  ST r4,r12,0
  MOVI r12,@mth_pq_out
  ST r5,r12,0
  MOVI r12,@mth_pq_best
  MOVI r6,0x7FFF
  MOVHI r6,0x7FFF
  ST r6,r12,0
  MOVI r12,@mth_pq_best_idx
  ST r0,r12,0

  MOVI r12,@mth_pq_i
  ST r0,r12,0
mth_pq_ci:
  MOVI r12,@mth_pq_i
  LD r5,r12,0
  MOVI r12,@mth_pq_c
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pq_done

  MOVI r12,@mth_pq_d
  LD r6,r12,0
  MUL r7,r5,r6
  MOVI r12,@mth_pq_book
  LD r6,r12,0
  ADD r7,r7,r6
  MOVI r12,@mth_pq_d
  LD r6,r12,0
  MOVI r12,@mth_pq_j
  ST r0,r12,0
  MOVI r12,@mth_pq_dist
  ST r0,r12,0
mth_pq_dj:
  MOVI r12,@mth_pq_j
  LD r6,r12,0
  MOVI r12,@mth_pq_d
  LD r8,r12,0
  CMP r6,r8
  JMP[GE] @mth_pq_row_done
  ADD r8,r7,r6
  LD r8,r8,0
  MOVI r12,@mth_pq_query
  LD r9,r12,0
  ADD r9,r9,r6
  LD r9,r9,0
  SUB r8,r8,r9
  CMPS r8,r0
  JMP[GE] @mth_pq_abs_done
  SUB r8,r0,r8
mth_pq_abs_done:
  MOVI r12,@mth_pq_dist
  LD r9,r12,0
  ADD r9,r9,r8
  ST r9,r12,0
  ADDI r6,r6,1
  MOVI r12,@mth_pq_j
  ST r6,r12,0
  JMP @mth_pq_dj
mth_pq_row_done:
  MOVI r12,@mth_pq_dist
  LD r6,r12,0
  MOVI r12,@mth_pq_best
  LD r7,r12,0
  CMP r6,r7
  JMP[GE] @mth_pq_next
  ST r6,r12,0
  MOVI r12,@mth_pq_best_idx
  MOVI r6,@mth_pq_i
  LD r6,r6,0
  ST r6,r12,0
mth_pq_next:
  MOVI r12,@mth_pq_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pq_ci
mth_pq_done:
  MOVI r12,@mth_pq_best_idx
  LD r1,r12,0
  MOVI r12,@mth_pq_best
  LD r2,r12,0
  MOVI r12,@mth_pq_out
  LD r6,r12,0
  ST r1,r6,0
  ST r2,r6,1
  MOVI r12,@mth_pq_link
  LD r15,r12,0
  RET

mth_pq_link:
  .word 0
mth_pq_query:
  .word 0
mth_pq_book:
  .word 0
mth_pq_c:
  .word 0
mth_pq_d:
  .word 0
mth_pq_out:
  .word 0
mth_pq_i:
  .word 0
mth_pq_j:
  .word 0
mth_pq_dist:
  .word 0
mth_pq_best:
  .word 0
mth_pq_best_idx:
  .word 0

; One graph power iteration for an 8x8 Q16 adjacency matrix.
; ABI:
;   r1 = A[8][8] address
;   r2 = input vector[8] address
;   r3 = output vector[8] address
; Returns:
;   r1 = output address (unchanged)
mth_spectral_iter:
  MOVI r12,@mth_sp_link
  ST r15,r12,0
  MOVI r12,@mth_sp_a
  ST r1,r12,0
  MOVI r12,@mth_sp_in
  ST r2,r12,0
  MOVI r12,@mth_sp_out
  ST r3,r12,0
  MOVI r12,@mth_sp_i
  ST r0,r12,0
mth_sp_row:
  MOVI r12,@mth_sp_i
  LD r5,r12,0
  MOVI r12,8
  CMP r5,r12
  JMP[GE] @mth_sp_done
  MOVI r12,@mth_sp_i
  LD r5,r12,0
  MOVI r12,8
  MUL r5,r5,r12
  MOVI r12,@mth_sp_a
  LD r6,r12,0
  ADD r6,r6,r5
  MOVI r12,@mth_sp_j
  ST r0,r12,0
  MOVI r12,@mth_sp_sum
  ST r0,r12,0
mth_sp_dot:
  MOVI r12,@mth_sp_j
  LD r5,r12,0
  MOVI r12,8
  CMP r5,r12
  JMP[GE] @mth_sp_store
  ADD r6,r6,r5
  LD r1,r6,0
  MOVI r12,@mth_sp_in
  LD r7,r12,0
  ADD r7,r7,r5
  LD r2,r7,0
  CALL @mth_q16_mul
  MOVI r12,@mth_sp_sum
  LD r5,r12,0
  ADD r5,r5,r1
  ST r5,r12,0
  MOVI r12,@mth_sp_j
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_sp_dot
mth_sp_store:
  MOVI r12,@mth_sp_i
  LD r5,r12,0
  MOVI r12,@mth_sp_out
  LD r6,r12,0
  ADD r6,r6,r5
  MOVI r12,@mth_sp_sum
  LD r5,r12,0
  ST r5,r6,0
  MOVI r12,@mth_sp_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_sp_row
mth_sp_done:
  MOVI r12,@mth_sp_out
  LD r1,r12,0
  MOVI r12,@mth_sp_link
  LD r15,r12,0
  RET

mth_sp_link:
  .word 0
mth_sp_a:
  .word 0
mth_sp_in:
  .word 0
mth_sp_out:
  .word 0
mth_sp_i:
  .word 0
mth_sp_j:
  .word 0
mth_sp_sum:
  .word 0

; Rotate an 8-lane complex phase hypervector by a Q16.16 turn.
; ABI:
;   r1 = input complex[8] address
;   r2 = output complex[8] address
;   r3 = turn (16-bit turn units)
;   r4 = lane count (normally 8)
mth_phase_rotate:
  MOVI r12,@mth_pr_link
  ST r15,r12,0
  MOVI r12,@mth_pr_in
  ST r1,r12,0
  MOVI r12,@mth_pr_out
  ST r2,r12,0
  MOVI r12,@mth_pr_lanes
  ST r4,r12,0
  ADD r1,r3,r0
  CALL @mth_q16_sin_cos
  MOVI r12,@mth_pr_cos
  ST r1,r12,0
  MOVI r12,@mth_pr_sin
  ST r2,r12,0
  MOVI r12,@mth_pr_l
  ST r0,r12,0
mth_pr_loop:
  MOVI r12,@mth_pr_l
  LD r5,r12,0
  MOVI r12,@mth_pr_lanes
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pr_done
  MOVI r12,@mth_pr_in
  LD r6,r12,0
  MOVI r12,2
  MUL r7,r5,r12
  ADD r6,r6,r7
  LD r8,r6,0
  LD r9,r6,1
  ; out_cos = c*cos - s*sin
  MOVI r12,@mth_pr_cos
  LD r1,r12,0
  MOVI r12,@mth_pr_sin
  LD r2,r12,0
  MOVI r12,@mth_pr_fc
  ST r1,r12,0
  MOVI r12,@mth_pr_fs
  ST r2,r12,0
  MOVI r12,@mth_pr_xc
  ST r8,r12,0
  MOVI r12,@mth_pr_xs
  ST r9,r12,0
  ADD r1,r8,r0
  ADD r2,r1,r0
  MOVI r12,@mth_pr_cos
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_pr_a
  ST r1,r12,0
  MOVI r12,@mth_pr_xs
  LD r1,r12,0
  MOVI r12,@mth_pr_sin
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_pr_a
  LD r8,r12,0
  SUB r8,r8,r1
  ; out_sin = x_c*sin + x_s*cos
  MOVI r12,@mth_pr_xc
  LD r1,r12,0
  MOVI r12,@mth_pr_sin
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_pr_b
  ST r1,r12,0
  MOVI r12,@mth_pr_xs
  LD r1,r12,0
  MOVI r12,@mth_pr_cos
  LD r2,r12,0
  CALL @mth_q16_mul
  MOVI r12,@mth_pr_b
  LD r9,r12,0
  ADD r9,r9,r1
  MOVI r12,@mth_pr_out
  LD r6,r12,0
  MOVI r12,2
  MUL r7,r5,r12
  ADD r6,r6,r7
  ST r8,r6,0
  ST r9,r6,1
  MOVI r12,@mth_pr_l
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pr_loop
mth_pr_done:
  MOVI r12,@mth_pr_link
  LD r15,r12,0
  RET

mth_pr_link:
  .word 0
mth_pr_in:
  .word 0
mth_pr_out:
  .word 0
mth_pr_lanes:
  .word 0
mth_pr_cos:
  .word 0
mth_pr_sin:
  .word 0
mth_pr_l:
  .word 0
mth_pr_fc:
  .word 0
mth_pr_fs:
  .word 0
mth_pr_xc:
  .word 0
mth_pr_xs:
  .word 0
mth_pr_a:
  .word 0
mth_pr_b:
  .word 0
