; Raw NaN16 reverse helpers: transposed bf16 matvec, dot product,
; LayerNorm backward, zero-fill and scaled add.
;
; transposed matvec: r1=matrix[rows][cols] bf16 words, r2=f32[rows],
;                    r3=f32 output[cols], r4=rows, r5=cols.
; dot product: r1=a f32[D], r2=b f32[D], r3=D -> hrv_dot_value.
; LN backward: r1=XN f32[D], r2=dy f32[D], r3=dx f32[D], r4=D, r5=invstd.
; zero: r1=base, r2=count.
; axpy: r1=dest += r3 * r2, r4=D.
; All return via r15; helper scratch is static and non-reentrant.
hrv_zero:
  MOVI r0,0
  ST r15,r0,@hrv_zero_link
  MOVI r10,0
hrv_zero_loop:
  CMP r10,r2
  JMP[GE] @hrv_zero_done
  ADD r11,r1,r10
  ST r0,r11,0
  ADDI r10,r10,1
  JMP @hrv_zero_loop
hrv_zero_done:
  LD r15,r0,@hrv_zero_link
  RET

hrv_axpy:
  MOVI r0,0
  ST r15,r0,@hrv_axpy_link
  MOVI r10,0
hrv_axpy_loop:
  CMP r10,r4
  JMP[GE] @hrv_axpy_done
  ADD r11,r2,r10
  LD r11,r11,0
  FMUL r11,r11,r3
  ADD r12,r1,r10
  LD r13,r12,0
  FADD r13,r13,r11
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hrv_axpy_loop
hrv_axpy_done:
  LD r15,r0,@hrv_axpy_link
  RET

hrv_dot:
  MOVI r0,0
  ST r15,r0,@hrv_dot_link
  MOVI r10,0
  MOVI r14,0
hrv_dot_loop:
  CMP r10,r3
  JMP[GE] @hrv_dot_done
  ADD r11,r1,r10
  LD r11,r11,0
  ADD r12,r2,r10
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r10,r10,1
  JMP @hrv_dot_loop
hrv_dot_done:
  ST r14,r0,@hrv_dot_value
  LD r15,r0,@hrv_dot_link
  RET

hrv_mv_t:
  MOVI r0,0
  ST r15,r0,@hrv_mt_link
  ST r1,r0,@hrv_mt_mat
  ST r2,r0,@hrv_mt_vec
  ST r3,r0,@hrv_mt_out
  ST r4,r0,@hrv_mt_rows
  ST r5,r0,@hrv_mt_cols
  MOVI r10,0
hrv_mt_col:
  LD r5,r0,@hrv_mt_cols
  CMP r10,r5
  JMP[GE] @hrv_mt_done
  MOVI r14,0
  MOVI r11,0
hrv_mt_row:
  LD r5,r0,@hrv_mt_rows
  CMP r11,r5
  JMP[GE] @hrv_mt_store
  LD r5,r0,@hrv_mt_cols
  SHR r6,r5,1
  MUL r6,r11,r6
  SHR r7,r10,1
  ADD r6,r6,r7
  LD r1,r0,@hrv_mt_mat
  ADD r6,r6,r1
  LD r7,r6,0
  MOVI r8,1
  SHL r8,r10,31
  SHR r8,r8,31
  CMP r8,r0
  JMP[EQ] @hrv_mt_low
  SHR r7,r7,16
  SHL r7,r7,16
  JMP @hrv_mt_have
hrv_mt_low:
  SHL r7,r7,16
hrv_mt_have:
  LD r2,r0,@hrv_mt_vec
  ADD r2,r2,r11
  LD r2,r2,0
  FMUL r7,r7,r2
  FADD r14,r14,r7
  ADDI r11,r11,1
  JMP @hrv_mt_row
hrv_mt_store:
  LD r3,r0,@hrv_mt_out
  ADD r3,r3,r10
  ST r14,r3,0
  ADDI r10,r10,1
  JMP @hrv_mt_col
hrv_mt_done:
  LD r15,r0,@hrv_mt_link
  RET

hrv_ln_bwd:
  MOVI r0,0
  ST r15,r0,@hrv_ln_link
  ST r1,r0,@hrv_ln_xn
  ST r2,r0,@hrv_ln_dy
  ST r3,r0,@hrv_ln_dx
  ST r4,r0,@hrv_ln_d
  ST r5,r0,@hrv_ln_inv
  MOVI r10,0
  MOVI r11,0
hrv_ln_sum1:
  LD r12,r0,@hrv_ln_d
  CMP r10,r12
  JMP[GE] @hrv_ln_sum1_done
  LD r12,r0,@hrv_ln_dy
  ADD r12,r12,r10
  LD r12,r12,0
  FADD r11,r11,r12
  ADDI r10,r10,1
  JMP @hrv_ln_sum1
hrv_ln_sum1_done:
  LD r12,r0,@hrv_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  ST r11,r0,@hrv_ln_mean1
  MOVI r10,0
  MOVI r11,0
hrv_ln_sum2:
  LD r12,r0,@hrv_ln_d
  CMP r10,r12
  JMP[GE] @hrv_ln_sum2_done
  LD r12,r0,@hrv_ln_dy
  ADD r12,r12,r10
  LD r12,r12,0
  LD r13,r0,@hrv_ln_xn
  ADD r13,r13,r10
  LD r13,r13,0
  FMUL r12,r12,r13
  FADD r11,r11,r12
  ADDI r10,r10,1
  JMP @hrv_ln_sum2
hrv_ln_sum2_done:
  LD r12,r0,@hrv_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  ST r11,r0,@hrv_ln_mean2
  MOVI r10,0
hrv_ln_out:
  LD r12,r0,@hrv_ln_d
  CMP r10,r12
  JMP[GE] @hrv_ln_done
  LD r12,r0,@hrv_ln_dy
  ADD r12,r12,r10
  LD r12,r12,0
  MOVI r13,@hrv_ln_mean1
  LD r13,r13,0
  FSUB r12,r12,r13
  LD r13,r0,@hrv_ln_xn
  ADD r13,r13,r10
  LD r13,r13,0
  MOVI r14,@hrv_ln_mean2
  LD r14,r14,0
  FMUL r13,r13,r14
  FSUB r12,r12,r13
  LD r13,r0,@hrv_ln_inv
  FMUL r12,r12,r13
  LD r13,r0,@hrv_ln_dx
  ADD r13,r13,r10
  ST r12,r13,0
  ADDI r10,r10,1
  JMP @hrv_ln_out
hrv_ln_done:
  LD r15,r0,@hrv_ln_link
  RET

hrv_zero_link:
  .word 0
hrv_axpy_link:
  .word 0
hrv_dot_link:
  .word 0
hrv_dot_value:
  .word 0
hrv_mt_link:
  .word 0
hrv_mt_mat:
  .word 0
hrv_mt_vec:
  .word 0
hrv_mt_out:
  .word 0
hrv_mt_rows:
  .word 0
hrv_mt_cols:
  .word 0
hrv_ln_link:
  .word 0
hrv_ln_xn:
  .word 0
hrv_ln_dy:
  .word 0
hrv_ln_dx:
  .word 0
hrv_ln_d:
  .word 0
hrv_ln_inv:
  .word 0
hrv_ln_mean1:
  .word 0
hrv_ln_mean2:
  .word 0
