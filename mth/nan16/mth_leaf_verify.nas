; Raw NaN16 remote-leaf reconstruction verifier.
;
; ABI:
;   r1 = expected phase vector[D] (Q16)
;   r2 = codebook[C][D] (Q16)
;   r3 = residual[D] (Q16)
;   r4 = code index
;   r5 = D (1..128)
;   r6 = tolerance (Q16)
; Returns:
;   r1 = 1 when sum |expected - (codebook[code] + residual)| <= tolerance
;   r2 = reconstruction L1 error
;
; The host only pages the expected vector, codebook, and residual leaf. The
; reconstruction, absolute error, and accept decision are guest-side.
mth_leaf_verify:
  MOVI r12,@mth_lv_link
  ST r15,r12,0
  MOVI r12,@mth_lv_code
  ST r4,r12,0
  MOVI r12,@mth_lv_d
  ST r5,r12,0
  MOVI r12,@mth_lv_tol
  ST r6,r12,0

  ; codebase = r2 + code*D
  MUL r7,r4,r5
  ADD r7,r2,r7
  MOVI r12,@mth_lv_book
  ST r7,r12,0
  MOVI r12,@mth_lv_i
  ST r0,r12,0
  MOVI r12,@mth_lv_err
  ST r0,r12,0
mth_lv_loop:
  MOVI r12,@mth_lv_i
  LD r7,r12,0
  MOVI r12,@mth_lv_d
  LD r8,r12,0
  CMP r7,r8
  JMP[GE] @mth_lv_done
  ADD r8,r1,r7
  LD r8,r8,0
  MOVI r12,@mth_lv_book
  LD r9,r12,0
  ADD r9,r9,r7
  LD r9,r9,0
  ADD r10,r3,r7
  LD r10,r10,0
  ADD r9,r9,r10
  SUB r8,r8,r9
  CMPS r8,r0
  JMP[GE] @mth_lv_abs_done
  SUB r8,r0,r8
mth_lv_abs_done:
  MOVI r12,@mth_lv_err
  LD r9,r12,0
  ADD r9,r9,r8
  ST r9,r12,0
  MOVI r12,@mth_lv_i
  LD r7,r12,0
  ADDI r7,r7,1
  ST r7,r12,0
  JMP @mth_lv_loop
mth_lv_done:
  MOVI r12,@mth_lv_err
  LD r2,r12,0
  MOVI r12,@mth_lv_tol
  LD r6,r12,0
  MOVI r1,1
  CMP r2,r6
  JMP[LE] @mth_lv_out
  MOVI r1,0
mth_lv_out:
  MOVI r12,@mth_lv_link
  LD r15,r12,0
  RET

mth_lv_link:
  .word 0
mth_lv_code:
  .word 0
mth_lv_d:
  .word 0
mth_lv_tol:
  .word 0
mth_lv_book:
  .word 0
mth_lv_i:
  .word 0
mth_lv_err:
  .word 0
