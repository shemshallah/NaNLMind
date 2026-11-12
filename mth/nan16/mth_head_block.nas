.org 0x3E40
mth_hbd_link:
  .word 0
mth_hbd_in:
  .word 0
mth_hbd_out:
  .word 0
mth_hbd_slot:
  .word 0
mth_hbd_page:
  .word 0
mth_hbd_layer_page:
  .word 0
mth_hbd_layer:
  .word 0
mth_hbd_ln_link:
  .word 0
mth_hbd_ln_in:
  .word 0
mth_hbd_ln_out:
  .word 0
mth_hbd_ln_d:
  .word 0
mth_hbd_mean:
  .word 0
mth_hbd_inv:
  .word 0
mth_hbd_mv_link:
  .word 0
mth_hbd_one:
  .word 0x3F800000
mth_hbd_eps:
  .word 0x3727C5AC

.org 0x3E60
; Raw NaN16 128D three-layer bf16 head block.
;
; One head page (1 MiB packed weights, 2 MiB guest words) is consumed from
; one of the 16 paged slots.  The block is single-token: the local attention
; over one token is exactly V, so Q/K weights are evaluated but the context
; is V.  A later six-token wrapper can reuse the same page layout and the
; same matvec/LN primitives.
;
; Page layout (packed bf16, little-endian, two values per 32-bit word):
;   +0x00000  layer 0 Wq  128 x 128
;   +0x08000  layer 0 Wk  128 x 128
;   +0x10000  layer 0 Wv  128 x 128
;   +0x18000  layer 0 Wo  128 x 128
;   +0x20000  layer 0 W1  384 x 128
;   +0x38000  layer 0 W2  128 x 384
;   layer stride 0x50000, three layers
;   +0xF0000  Wemb 128 x 128 (reserved; not used by this block)
;   +0xFCC00  page header (magic 0x48315233)
;
; ABI:
;   r1 = input f32[128]
;   r2 = output f32[128]
;   r3 = slot 0..15
; Returns r1=1, r2=128, r3=slot, r4=0 on success; r1=0,r4=reason otherwise.
; All arithmetic, conversion, normalization and residual updates are guest.

; Scratch: 0xD00000..0xD00FFF, above the 16 page slots and below the
; high tensor/head addresses.  The page slots are 0x800000..0xC00000.
mth_head_block:
  MOVI r0,0
  ST r15,r0,@mth_hbd_link
  ST r1,r0,@mth_hbd_in
  ST r2,r0,@mth_hbd_out
  ST r3,r0,@mth_hbd_slot
  CMP r1,r0
  JMP[EQ] @mth_hb_bad
  CMP r2,r0
  JMP[EQ] @mth_hb_bad
  MOVI r4,16
  CMP r3,r4
  JMP[GE] @mth_hb_bad_slot
  SHL r4,r3,18
  MOVI r5,0x0000
  MOVHI r5,0x0080
  ADD r5,r5,r4
  ST r5,r0,@mth_hbd_page
  MOVI r6,0xF300
  MOVHI r6,0x0003
  ADD r6,r5,r6
  LD r7,r6,0
  MOVI r8,0x5233
  MOVHI r8,0x4831
  CMP r7,r8
  JMP[NE] @mth_hb_bad_header

  ; Copy the input into the working vector.
  MOVI r10,0
mth_hb_copy_in:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @mth_hb_copy_in_done
  MOVI r11,0x0000
  MOVHI r11,0x00D0
  ADD r11,r11,r10
  MOVI r12,@mth_hbd_in
  LD r12,r12,0
  ADD r12,r12,r10
  LD r13,r12,0
  ST r13,r11,0
  ADDI r10,r10,1
  JMP @mth_hb_copy_in
mth_hb_copy_in_done:
  MOVI r10,0
  ST r10,r0,@mth_hbd_layer
mth_hb_layer_loop:
  MOVI r10,3
  MOVI r11,@mth_hbd_layer
  LD r11,r11,0
  CMP r11,r10
  JMP[GE] @mth_hb_finish

  ; LayerNorm(x) -> xn.
  MOVI r1,0x0000
  MOVHI r1,0x00D0
  MOVI r2,0x0100
  MOVHI r2,0x00D0
  MOVI r3,128
  CALL @mth_hb_ln

  ; Compute the page base for this layer.
  MOVI r10,@mth_hbd_page
  LD r10,r10,0
  MOVI r11,@mth_hbd_layer
  LD r11,r11,0
  MOVI r12,0x4000
  MOVHI r12,0x0001
  MUL r12,r11,r12
  ADD r10,r10,r12
  ST r10,r0,@mth_hbd_layer_page

  ; q = Wq * xn
  MOVI r1,0x0000
  ADD r1,r10,r1
  MOVI r2,0x0100
  MOVHI r2,0x00D0
  MOVI r3,0x0200
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,128
  CALL @mth_hb_mv
  ; k = Wk * xn
  MOVI r10,@mth_hbd_layer_page
  LD r10,r10,0
  MOVI r1,0x2000
  ADD r1,r10,r1
  MOVI r2,0x0100
  MOVHI r2,0x00D0
  MOVI r3,0x0300
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,128
  CALL @mth_hb_mv
  ; v = Wv * xn
  MOVI r10,@mth_hbd_layer_page
  LD r10,r10,0
  MOVI r1,0x4000
  ADD r1,r10,r1
  MOVI r2,0x0100
  MOVHI r2,0x00D0
  MOVI r3,0x0400
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,128
  CALL @mth_hb_mv
  ; attn = Wo * v (single-token attention is exactly V).
  MOVI r10,@mth_hbd_layer_page
  LD r10,r10,0
  MOVI r1,0x6000
  ADD r1,r10,r1
  MOVI r2,0x0400
  MOVHI r2,0x00D0
  MOVI r3,0x0500
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,128
  CALL @mth_hb_mv

  ; x = x + attn
  MOVI r10,0
mth_hb_res1:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @mth_hb_res1_done
  MOVI r11,0x0000
  MOVHI r11,0x00D0
  ADD r11,r11,r10
  MOVI r12,0x0500
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r11,0
  LD r14,r12,0
  FADD r13,r13,r14
  ST r13,r11,0
  ADDI r10,r10,1
  JMP @mth_hb_res1
mth_hb_res1_done:

  ; LayerNorm again, then MLP.
  MOVI r1,0x0000
  MOVHI r1,0x00D0
  MOVI r2,0x0100
  MOVHI r2,0x00D0
  MOVI r3,128
  CALL @mth_hb_ln

  ; h = W1 * xn, rows=384, cols=128.
  MOVI r10,@mth_hbd_layer_page
  LD r10,r10,0
  MOVI r1,0x8000
  ADD r1,r10,r1
  MOVI r2,0x0100
  MOVHI r2,0x00D0
  MOVI r3,0x0600
  MOVHI r3,0x00D0
  MOVI r4,384
  MOVI r5,128
  CALL @mth_hb_mv
  ; h = tanh(h)
  MOVI r10,0
mth_hb_tanh:
  MOVI r11,384
  CMP r10,r11
  JMP[GE] @mth_hb_tanh_done
  MOVI r11,0x0600
  MOVHI r11,0x00D0
  ADD r11,r11,r10
  LD r12,r11,0
  FTANH r12,r12
  ST r12,r11,0
  ADDI r10,r10,1
  JMP @mth_hb_tanh
mth_hb_tanh_done:

  ; mlp = W2 * h, rows=128, cols=384.
  MOVI r10,@mth_hbd_layer_page
  LD r10,r10,0
  MOVI r1,0xE000
  ADD r1,r10,r1
  MOVI r2,0x0600
  MOVHI r2,0x00D0
  MOVI r3,0x0800
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,384
  CALL @mth_hb_mv

  ; x = x + mlp
  MOVI r10,0
mth_hb_res2:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @mth_hb_res2_done
  MOVI r11,0x0000
  MOVHI r11,0x00D0
  ADD r11,r11,r10
  MOVI r12,0x0800
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r11,0
  LD r14,r12,0
  FADD r13,r13,r14
  ST r13,r11,0
  ADDI r10,r10,1
  JMP @mth_hb_res2
mth_hb_res2_done:
  MOVI r10,@mth_hbd_layer
  LD r11,r10,0
  ADDI r11,r11,1
  ST r11,r10,0
  JMP @mth_hb_layer_loop

mth_hb_finish:
  ; Copy x to the caller's output.
  MOVI r10,0
mth_hb_copy_out:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @mth_hb_ok
  MOVI r11,0x0000
  MOVHI r11,0x00D0
  ADD r11,r11,r10
  LD r12,r11,0
  MOVI r13,@mth_hbd_out
  LD r13,r13,0
  ADD r13,r13,r10
  ST r12,r13,0
  ADDI r10,r10,1
  JMP @mth_hb_copy_out
mth_hb_ok:
  MOVI r1,1
  MOVI r2,128
  MOVI r3,@mth_hbd_slot
  LD r3,r3,0
  MOVI r4,0
  MOVI r10,@mth_hbd_link
  LD r15,r10,0
  RET
mth_hb_bad_slot:
  MOVI r4,1
  JMP @mth_hb_reject
mth_hb_bad_header:
  MOVI r4,2
  JMP @mth_hb_reject
mth_hb_bad:
  MOVI r4,3
mth_hb_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r10,@mth_hbd_link
  LD r15,r10,0
  RET

; LayerNorm over D words.  r1=input, r2=output, r3=D.
mth_hb_ln:
  MOVI r0,0
  ST r15,r0,@mth_hbd_ln_link
  ST r1,r0,@mth_hbd_ln_in
  ST r2,r0,@mth_hbd_ln_out
  ST r3,r0,@mth_hbd_ln_d
  ; sum
  MOVI r10,0
  MOVI r11,0
mth_hb_ln_sum:
  MOVI r12,@mth_hbd_ln_d
  LD r12,r12,0
  CMP r10,r12
  JMP[GE] @mth_hb_ln_sum_done
  MOVI r12,@mth_hbd_ln_in
  LD r12,r12,0
  ADD r12,r12,r10
  LD r13,r12,0
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @mth_hb_ln_sum
mth_hb_ln_sum_done:
  MOVI r12,@mth_hbd_ln_d
  LD r12,r12,0
  CVTIF r12,r12
  FDIV r11,r11,r12
  ST r11,r0,@mth_hbd_mean
  ; variance
  MOVI r10,0
  MOVI r11,0
mth_hb_ln_var:
  MOVI r12,@mth_hbd_ln_d
  LD r12,r12,0
  CMP r10,r12
  JMP[GE] @mth_hb_ln_var_done
  MOVI r12,@mth_hbd_ln_in
  LD r12,r12,0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@mth_hbd_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  FMUL r13,r13,r13
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @mth_hb_ln_var
mth_hb_ln_var_done:
  MOVI r12,@mth_hbd_ln_d
  LD r12,r12,0
  CVTIF r12,r12
  FDIV r11,r11,r12
  MOVI r12,@mth_hbd_eps
  LD r12,r12,0
  FADD r11,r11,r12
  FSQRT r11,r11
  MOVI r12,@mth_hbd_one
  LD r12,r12,0
  FDIV r11,r12,r11
  ST r11,r0,@mth_hbd_inv
  ; y = (x - mean) * inv
  MOVI r10,0
mth_hb_ln_out:
  MOVI r12,@mth_hbd_ln_d
  LD r12,r12,0
  CMP r10,r12
  JMP[GE] @mth_hb_ln_done
  MOVI r12,@mth_hbd_ln_in
  LD r12,r12,0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@mth_hbd_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  MOVI r14,@mth_hbd_inv
  LD r14,r14,0
  FMUL r13,r13,r14
  MOVI r12,@mth_hbd_ln_out
  LD r12,r12,0
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @mth_hb_ln_out
mth_hb_ln_done:
  MOVI r10,@mth_hbd_ln_link
  LD r15,r10,0
  RET

; bf16 matrix-vector: r1=matrix words, r2=f32 vector, r3=f32 output,
; r4=rows, r5=cols (even).
mth_hb_mv:
  MOVI r0,0
  ST r15,r0,@mth_hbd_mv_link
  MOVI r11,0
mth_hb_mv_row:
  CMP r11,r4
  JMP[GE] @mth_hb_mv_done
  MOVI r14,0
  MOVI r10,0
mth_hb_mv_col:
  CMP r10,r5
  JMP[GE] @mth_hb_mv_row_done
  SHR r6,r5,1
  MUL r6,r11,r6
  SHR r7,r10,1
  ADD r6,r6,r7
  ADD r6,r6,r1
  LD r7,r6,0
  SHL r8,r10,31
  SHR r8,r8,31
  CMP r8,r0
  JMP[EQ] @mth_hb_mv_low
  SHR r7,r7,16
mth_hb_mv_low:
  SHL r7,r7,16
  ADD r8,r2,r10
  LD r8,r8,0
  FMUL r7,r7,r8
  FADD r14,r14,r7
  ADDI r10,r10,1
  JMP @mth_hb_mv_col
mth_hb_mv_row_done:
  ADD r6,r3,r11
  ST r14,r6,0
  ADDI r11,r11,1
  JMP @mth_hb_mv_row
mth_hb_mv_done:
  MOVI r10,@mth_hbd_mv_link
  LD r15,r10,0
  RET

