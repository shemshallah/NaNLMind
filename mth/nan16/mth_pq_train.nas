; Raw NaN16 product-quantizer codebook trainer.
;
; ABI:
;   r1 = sample bank N*D, Q16.16, at a host-selected address
;   r2 = N samples (1..1024)
;   r3 = D values per sample (1..128)
;   r4 = C codewords (1..256)
;   r5 = training iterations (0..8)
;   r6 = output codebook C*D
;
; Samples are staged by the host. Initialization, assignment, accumulation,
; centroid division and the iteration count all execute in the guest. The
; scratch layout is:
;   0x10000 = samples
;   0x50000 = codebook
;   0x60000 = centroid sums
;   0x70000 = centroid counts
mth_pq_train:
  MOVI r12,@mth_pqt_link
  ST r15,r12,0
  MOVI r12,@mth_pqt_r10
  ST r10,r12,0
  MOVI r12,@mth_pqt_r11
  ST r11,r12,0
  MOVI r12,@mth_pqt_r12
  ST r12,r12,0
  MOVI r12,@mth_pqt_r13
  ST r13,r12,0
  MOVI r12,@mth_pqt_r14
  ST r14,r12,0
  MOVI r12,@mth_pqt_r15
  ST r15,r12,0
  MOVI r12,@mth_pqt_samples
  ST r1,r12,0
  MOVI r12,@mth_pqt_n
  ST r2,r12,0
  MOVI r12,@mth_pqt_d
  ST r3,r12,0
  MOVI r12,@mth_pqt_c
  ST r4,r12,0
  MOVI r12,@mth_pqt_iters
  ST r5,r12,0
  MOVI r12,@mth_pqt_out
  ST r6,r12,0

  ; initialize codebook from the first C samples, wrapping if N < C
  MOVI r12,@mth_pqt_ci
  ST r0,r12,0
mth_pqt_init_ci:
  MOVI r12,@mth_pqt_ci
  LD r5,r12,0
  MOVI r12,@mth_pqt_c
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqt_init_done
  MOVI r12,@mth_pqt_n
  LD r6,r12,0
  MODU r7,r5,r6
  MOVI r12,@mth_pqt_d
  LD r8,r12,0
  MUL r7,r7,r8
  MOVI r12,@mth_pqt_samples
  LD r9,r12,0
  ADD r9,r9,r7
  MUL r7,r5,r8
  MOVI r12,@mth_pqt_out
  LD r10,r12,0
  ADD r10,r10,r7
  MOVI r12,@mth_pqt_di
  ST r0,r12,0
mth_pqt_init_di:
  MOVI r12,@mth_pqt_di
  LD r7,r12,0
  MOVI r12,@mth_pqt_d
  LD r8,r12,0
  CMP r7,r8
  JMP[GE] @mth_pqt_init_next
  ADD r11,r9,r7
  LD r11,r11,0
  ADD r12,r10,r7
  ST r11,r12,0
  ADDI r7,r7,1
  MOVI r12,@mth_pqt_di
  ST r7,r12,0
  JMP @mth_pqt_init_di
mth_pqt_init_next:
  MOVI r12,@mth_pqt_ci
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pqt_init_ci
mth_pqt_init_done:

  MOVI r12,@mth_pqt_iter
  ST r0,r12,0
mth_pqt_iter_loop:
  MOVI r12,@mth_pqt_iter
  LD r5,r12,0
  MOVI r12,@mth_pqt_iters
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqt_done

  ; clear sums and counts
  MOVI r10,0x0000
  MOVHI r10,0x0006
  MOVI r11,0
  MOVI r12,@mth_pqt_c
  LD r12,r12,0
  MOVI r13,@mth_pqt_d
  LD r13,r13,0
  MUL r12,r12,r13
mth_pqt_clear_sums:
  CMP r11,r12
  JMP[GE] @mth_pqt_clear_counts
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  JMP @mth_pqt_clear_sums
mth_pqt_clear_counts:
  MOVI r10,0x0000
  MOVHI r10,0x0007
  MOVI r11,0
  MOVI r12,@mth_pqt_c
  LD r12,r12,0
mth_pqt_clear_counts_loop:
  CMP r11,r12
  JMP[GE] @mth_pqt_assign_start
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  JMP @mth_pqt_clear_counts_loop

mth_pqt_assign_start:
  MOVI r12,@mth_pqt_ni
  ST r0,r12,0
mth_pqt_assign_n:
  MOVI r12,@mth_pqt_ni
  LD r5,r12,0
  MOVI r12,@mth_pqt_n
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqt_update_start
  MOVI r12,@mth_pqt_best
  MOVI r7,0xFFFF
  MOVHI r7,0x7FFF
  ST r7,r12,0
  MOVI r12,@mth_pqt_best_c
  ST r0,r12,0
  MOVI r12,@mth_pqt_ci
  ST r0,r12,0
mth_pqt_dist_c:
  MOVI r12,@mth_pqt_ci
  LD r5,r12,0
  MOVI r12,@mth_pqt_c
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqt_assign_done
  MOVI r12,@mth_pqt_di
  ST r0,r12,0
  MOVI r12,@mth_pqt_dist
  ST r0,r12,0
mth_pqt_dist_d:
  MOVI r12,@mth_pqt_di
  LD r6,r12,0
  MOVI r12,@mth_pqt_d
  LD r7,r12,0
  CMP r6,r7
  JMP[GE] @mth_pqt_dist_done
  ; sample offset = ni*D + di
  MOVI r12,@mth_pqt_d
  LD r8,r12,0
  MOVI r12,@mth_pqt_ni
  LD r7,r12,0
  MUL r7,r7,r8
  ADD r7,r7,r6
  MOVI r12,@mth_pqt_samples
  LD r9,r12,0
  ADD r9,r9,r7
  LD r9,r9,0
  ; codeword offset = ci*D + di
  MOVI r12,@mth_pqt_ci
  LD r10,r12,0
  MUL r10,r10,r8
  ADD r10,r10,r6
  MOVI r12,@mth_pqt_out
  LD r11,r12,0
  ADD r11,r11,r10
  LD r11,r11,0
  SUB r9,r9,r11
  CMPS r9,r0
  JMP[GE] @mth_pqt_abs_done
  SUB r9,r0,r9
mth_pqt_abs_done:
  MOVI r12,@mth_pqt_dist
  LD r11,r12,0
  ADD r11,r11,r9
  ST r11,r12,0
  ADDI r6,r6,1
  MOVI r12,@mth_pqt_di
  ST r6,r12,0
  JMP @mth_pqt_dist_d
mth_pqt_dist_done:
  MOVI r12,@mth_pqt_dist
  LD r6,r12,0
  MOVI r12,@mth_pqt_best
  LD r7,r12,0
  CMP r6,r7
  JMP[GE] @mth_pqt_dist_next
  ST r6,r12,0
  MOVI r12,@mth_pqt_best_c
  MOVI r7,@mth_pqt_ci
  LD r7,r7,0
  ST r7,r12,0
mth_pqt_dist_next:
  MOVI r12,@mth_pqt_ci
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pqt_dist_c

mth_pqt_assign_done:
  ; accumulate sample into sums[best_c] and count[best_c]
  MOVI r12,@mth_pqt_best_c
  LD r5,r12,0
  MOVI r12,@mth_pqt_d
  LD r6,r12,0
  MUL r5,r5,r6
  MOVI r12,@mth_pqt_ni
  LD r7,r12,0
  MUL r7,r7,r6
  MOVI r12,@mth_pqt_samples
  LD r8,r12,0
  ADD r8,r8,r7
  MOVI r10,0x0000
  MOVHI r10,0x0006
  ADD r10,r10,r5
  MOVI r12,@mth_pqt_di
  ST r0,r12,0
mth_pqt_accum_d:
  MOVI r12,@mth_pqt_di
  LD r5,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqt_accum_done
  ADD r7,r8,r5
  LD r7,r7,0
  ADD r9,r10,r5
  LD r11,r9,0
  ADD r11,r11,r7
  ST r11,r9,0
  ADDI r5,r5,1
  MOVI r12,@mth_pqt_di
  ST r5,r12,0
  JMP @mth_pqt_accum_d
mth_pqt_accum_done:
  MOVI r12,@mth_pqt_best_c
  LD r5,r12,0
  MOVI r10,0x0000
  MOVHI r10,0x0007
  ADD r10,r10,r5
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  MOVI r12,@mth_pqt_ni
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pqt_assign_n

mth_pqt_update_start:
  MOVI r12,@mth_pqt_ci
  ST r0,r12,0
mth_pqt_update_c:
  MOVI r12,@mth_pqt_ci
  LD r5,r12,0
  MOVI r12,@mth_pqt_c
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqt_iter_next
  MOVI r10,0x0000
  MOVHI r10,0x0007
  ADD r10,r10,r5
  LD r11,r10,0
  CMP r11,r0
  JMP[EQ] @mth_pqt_update_next
  MOVI r12,@mth_pqt_d
  LD r6,r12,0
  MUL r5,r5,r6
  MOVI r12,@mth_pqt_out
  LD r7,r12,0
  ADD r7,r7,r5
  MOVI r10,0x0000
  MOVHI r10,0x0006
  ADD r10,r10,r5
  MOVI r12,@mth_pqt_di
  ST r0,r12,0
mth_pqt_update_d:
  MOVI r12,@mth_pqt_di
  LD r5,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqt_update_next
  ADD r8,r10,r5
  LD r8,r8,0
  MOVI r12,@mth_pqt_ci
  LD r9,r12,0
  MOVI r11,0x0000
  MOVHI r11,0x0007
  ADD r11,r11,r9
  LD r9,r11,0
  DIV r8,r8,r9
  ADD r9,r7,r5
  ST r8,r9,0
  ADDI r5,r5,1
  MOVI r12,@mth_pqt_di
  ST r5,r12,0
  JMP @mth_pqt_update_d
mth_pqt_update_next:
  MOVI r12,@mth_pqt_ci
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pqt_update_c
mth_pqt_iter_next:
  MOVI r12,@mth_pqt_iter
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pqt_iter_loop
mth_pqt_done:
  MOVI r12,@mth_pqt_iters
  LD r1,r12,0
  MOVI r12,@mth_pqt_r10
  LD r10,r12,0
  MOVI r12,@mth_pqt_r11
  LD r11,r12,0
  MOVI r12,@mth_pqt_r12
  LD r12,r12,0
  MOVI r12,@mth_pqt_r13
  LD r13,r12,0
  MOVI r12,@mth_pqt_r14
  LD r14,r12,0
  MOVI r12,@mth_pqt_r15
  LD r15,r12,0
  MOVI r12,@mth_pqt_link
  LD r15,r12,0
  RET

mth_pqt_r10:
  .word 0
mth_pqt_r11:
  .word 0
mth_pqt_r12:
  .word 0
mth_pqt_r13:
  .word 0
mth_pqt_r14:
  .word 0
mth_pqt_r15:
  .word 0
mth_pqt_link:
  .word 0
mth_pqt_samples:
  .word 0
mth_pqt_n:
  .word 0
mth_pqt_d:
  .word 0
mth_pqt_c:
  .word 0
mth_pqt_iters:
  .word 0
mth_pqt_out:
  .word 0
mth_pqt_ci:
  .word 0
mth_pqt_di:
  .word 0
mth_pqt_ni:
  .word 0
mth_pqt_iter:
  .word 0
mth_pqt_best:
  .word 0
mth_pqt_best_c:
  .word 0
mth_pqt_dist:
  .word 0
