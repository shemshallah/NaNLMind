; Raw NaN16 product-quantizer residual builder.
;
; ABI:
;   r1 = samples[N][D] address
;   r2 = codebook[C][D] address
;   r3 = codes[N] address
;   r4 = N (1..1024)
;   r5 = D (1..128)
;   r6 = residuals[N][D] output address
;
; For each sample: residual[n][d] = sample[n][d] - codebook[codes[n]][d].
; The host only stages the arrays and reads the residual payload.
mth_pq_residual:
  MOVI r12,@mth_pqr_link
  ST r15,r12,0
  MOVI r12,@mth_pqr_r10
  ST r10,r12,0
  MOVI r12,@mth_pqr_r11
  ST r11,r12,0
  MOVI r12,@mth_pqr_r12
  ST r12,r12,0
  MOVI r12,@mth_pqr_r13
  ST r13,r12,0
  MOVI r12,@mth_pqr_r14
  ST r14,r12,0
  MOVI r12,@mth_pqr_r15
  ST r15,r12,0
  MOVI r12,@mth_pqr_samples
  ST r1,r12,0
  MOVI r12,@mth_pqr_book
  ST r2,r12,0
  MOVI r12,@mth_pqr_codes
  ST r3,r12,0
  MOVI r12,@mth_pqr_n
  ST r4,r12,0
  MOVI r12,@mth_pqr_d
  ST r5,r12,0
  MOVI r12,@mth_pqr_out
  ST r6,r12,0
  MOVI r12,@mth_pqr_ni
  ST r0,r12,0
mth_pqr_n_loop:
  MOVI r12,@mth_pqr_ni
  LD r5,r12,0
  MOVI r12,@mth_pqr_n
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pqr_done
  MOVI r12,@mth_pqr_codes
  LD r7,r12,0
  ADD r7,r7,r5
  LD r7,r7,0
  MOVI r12,@mth_pqr_d
  LD r8,r12,0
  MUL r7,r7,r8
  MOVI r12,@mth_pqr_book
  LD r9,r12,0
  ADD r9,r9,r7
  MOVI r12,@mth_pqr_samples
  LD r10,r12,0
  MUL r11,r5,r8
  ADD r10,r10,r11
  MOVI r12,@mth_pqr_out
  LD r11,r12,0
  MOVI r12,@mth_pqr_d
  LD r8,r12,0
  MUL r12,r5,r8
  ADD r11,r11,r12
  MOVI r12,@mth_pqr_di
  ST r0,r12,0
mth_pqr_d_loop:
  MOVI r12,@mth_pqr_di
  LD r5,r12,0
  MOVI r12,@mth_pqr_d
  LD r8,r12,0
  CMP r5,r8
  JMP[GE] @mth_pqr_n_next
  ADD r12,r10,r5
  LD r12,r12,0
  ADD r13,r9,r5
  LD r13,r13,0
  SUB r12,r12,r13
  ADD r13,r11,r5
  ST r12,r13,0
  ADDI r5,r5,1
  MOVI r12,@mth_pqr_di
  ST r5,r12,0
  JMP @mth_pqr_d_loop
mth_pqr_n_next:
  MOVI r12,@mth_pqr_ni
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pqr_n_loop
mth_pqr_done:
  MOVI r12,@mth_pqr_n
  LD r1,r12,0
  MOVI r12,@mth_pqr_r10
  LD r10,r12,0
  MOVI r12,@mth_pqr_r11
  LD r11,r12,0
  MOVI r12,@mth_pqr_r12
  LD r12,r12,0
  MOVI r12,@mth_pqr_r13
  LD r13,r12,0
  MOVI r12,@mth_pqr_r14
  LD r14,r12,0
  MOVI r12,@mth_pqr_r15
  LD r15,r12,0
  MOVI r12,@mth_pqr_link
  LD r15,r12,0
  RET

mth_pqr_r10:
  .word 0
mth_pqr_r11:
  .word 0
mth_pqr_r12:
  .word 0
mth_pqr_r13:
  .word 0
mth_pqr_r14:
  .word 0
mth_pqr_r15:
  .word 0
mth_pqr_link:
  .word 0
mth_pqr_samples:
  .word 0
mth_pqr_book:
  .word 0
mth_pqr_codes:
  .word 0
mth_pqr_n:
  .word 0
mth_pqr_d:
  .word 0
mth_pqr_out:
  .word 0
mth_pqr_ni:
  .word 0
mth_pqr_di:
  .word 0
