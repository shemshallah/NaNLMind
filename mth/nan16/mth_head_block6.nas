; Raw NaN16 six-token 128D three-layer bf16 head block (head-worker image).
;
; This is the low-address standalone version.  It is assembled into
; mth/drivers/head_worker.nas at word 0, so every JMP/CALL is a normal 16-bit
; guest transfer and the 0x4000 command block leaves ample code room.
;
; ABI (worker dispatcher writes args at 0x4001..0x4004):
;   r1 = input f32[T][128]
;   r2 = output f32[T][128]
;   r3 = slot 0..15
;   r4 = T 1..6
; Returns r1=1, r2=T*128, r3=slot, r4=0 on success.
;
; Page layout is the same frozen 1 MiB layout as the single-token block:
;   +0x00000 Wq, +0x02000 Wk, +0x04000 Wv, +0x06000 Wo,
;   +0x08000 W1 (384x128), +0x0E000 W2 (128x384),
;   layer stride 0x14000 (guest words), header at +0x3F300.
; All page reads are bf16 pairs; all arithmetic is guest-side.

mth_head_block6:
  MOVI r0,0
  ST r15,r0,@hw6_link
  ST r1,r0,@hw6_in
  ST r2,r0,@hw6_out
  ST r3,r0,@hw6_slot
  ST r4,r0,@hw6_t
  CMP r1,r0
  JMP[EQ] @hw6_bad
  CMP r2,r0
  JMP[EQ] @hw6_bad
  CMP r4,r0
  JMP[EQ] @hw6_bad
  MOVI r5,6
  CMP r4,r5
  JMP[GT] @hw6_bad
  MOVI r5,16
  CMP r3,r5
  JMP[GE] @hw6_bad_slot
  SHL r5,r3,18
  MOVI r6,0x0000
  MOVHI r6,0x0080
  ADD r6,r6,r5
  ST r6,r0,@hw6_page
  MOVI r7,0xF300
  MOVHI r7,0x0003
  ADD r7,r6,r7
  LD r8,r7,0
  MOVI r9,0x5233
  MOVHI r9,0x4831
  CMP r8,r9
  JMP[NE] @hw6_bad_header

  ; Copy T*128 input floats to the working bank.
  MOVI r10,0
  MOVI r5,128
  LD r11,r0,@hw6_t
  MUL r11,r11,r5
  ST r11,r0,@hw6_n
hw6_copy_in:
  LD r11,r0,@hw6_n
  CMP r10,r11
  JMP[GE] @hw6_copy_in_done
  LD r12,r0,@hw6_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r12,0x0000
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hw6_copy_in
hw6_copy_in_done:
  MOVI r10,0
  ST r10,r0,@hw6_layer

hw6_layer_loop:
  LD r10,r0,@hw6_layer
  MOVI r11,3
  CMP r10,r11
  JMP[GE] @hw6_finish

  ; LayerNorm all tokens.
  MOVI r10,0
  ST r10,r0,@hw6_i
hw6_ln_tokens:
  LD r10,r0,@hw6_i
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_ln_tokens_done
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r1,0x0000
  MOVHI r1,0x00D0
  ADD r1,r1,r12
  MOVI r2,0x0300
  MOVHI r2,0x00D0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hw6_ln
  LD r10,r0,@hw6_i
  ADDI r10,r10,1
  ST r10,r0,@hw6_i
  JMP @hw6_ln_tokens
hw6_ln_tokens_done:

  ; Layer page = page + layer*0x14000 words.
  LD r10,r0,@hw6_page
  LD r11,r0,@hw6_layer
  MOVI r12,0x4000
  MOVHI r12,0x0001
  MUL r12,r11,r12
  ADD r10,r10,r12
  ST r10,r0,@hw6_layer_page

  ; Q, K, V for every token.
  MOVI r10,0
  ST r10,r0,@hw6_i
hw6_qkv_tokens:
  LD r10,r0,@hw6_i
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_qkv_done
  MOVI r12,128
  MUL r12,r10,r12
  ; q
  LD r1,r0,@hw6_layer_page
  ADD r1,r1,r0
  MOVI r2,0x0300
  MOVHI r2,0x00D0
  ADD r2,r2,r12
  MOVI r3,0x0600
  MOVHI r3,0x00D0
  ADD r3,r3,r12
  MOVI r4,128
  MOVI r5,128
  CALL @hw6_mv
  ; k
  LD r1,r0,@hw6_layer_page
  MOVI r13,0x2000
  ADD r1,r1,r13
  MOVI r2,0x0300
  MOVHI r2,0x00D0
  ADD r2,r2,r12
  MOVI r3,0x0900
  MOVHI r3,0x00D0
  ADD r3,r3,r12
  MOVI r4,128
  MOVI r5,128
  CALL @hw6_mv
  ; v
  LD r1,r0,@hw6_layer_page
  MOVI r13,0x4000
  ADD r1,r1,r13
  MOVI r2,0x0300
  MOVHI r2,0x00D0
  ADD r2,r2,r12
  MOVI r3,0x0C00
  MOVHI r3,0x00D0
  ADD r3,r3,r12
  MOVI r4,128
  MOVI r5,128
  CALL @hw6_mv
  LD r10,r0,@hw6_i
  ADDI r10,r10,1
  ST r10,r0,@hw6_i
  JMP @hw6_qkv_tokens
hw6_qkv_done:

  ; For each query token, score against all keys and mix values.
  MOVI r10,0
  ST r10,r0,@hw6_i
hw6_query_loop:
  LD r10,r0,@hw6_i
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_attention_done
  ; scores[j] = dot(q_i,k_j)/sqrt(128), max tracked
  MOVI r10,0
  ST r10,r0,@hw6_j
  MOVI r10,0
  MOVHI r10,0xFF80
  ST r10,r0,@hw6_max
hw6_score_loop:
  LD r10,r0,@hw6_j
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_score_done
  MOVI r12,128
  LD r13,r0,@hw6_i
  MUL r13,r13,r12
  MOVI r1,0x0600
  MOVHI r1,0x00D0
  ADD r1,r1,r13
  MUL r12,r10,r12
  MOVI r2,0x0900
  MOVHI r2,0x00D0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hw6_dot
  LD r10,r0,@hw6_dot_value
  MOVI r12,@hw6_scale
  LD r12,r12,0
  FDIV r10,r10,r12
  LD r11,r0,@hw6_j
  MOVI r12,0x1800
  MOVHI r12,0x00D0
  ADD r12,r12,r11
  ST r10,r12,0
  ; compare against max cell
  MOVI r12,@hw6_max
  LD r13,r12,0
  FCMP r10,r13
  JMP[LE] @hw6_score_next
  ST r10,r12,0
hw6_score_next:
  LD r10,r0,@hw6_j
  ADDI r10,r10,1
  ST r10,r0,@hw6_j
  JMP @hw6_score_loop
hw6_score_done:

  ; probs[j] = exp(score-max), sum
  MOVI r10,0
  ST r10,r0,@hw6_j
  MOVI r10,0
  ST r10,r0,@hw6_sum
hw6_prob_loop:
  LD r10,r0,@hw6_j
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_prob_done
  MOVI r12,0x1800
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hw6_max
  LD r14,r14,0
  FSUB r13,r13,r14
  FEXP r13,r13
  MOVI r14,0x1810
  MOVHI r14,0x00D0
  ADD r14,r14,r10
  ST r13,r14,0
  MOVI r14,@hw6_sum
  LD r15,r14,0
  FADD r15,r15,r13
  ST r15,r14,0
  ADDI r10,r10,1
  ST r10,r0,@hw6_j
  JMP @hw6_prob_loop
hw6_prob_done:
  ; normalize probs and clear context
  MOVI r10,0
  ST r10,r0,@hw6_j
hw6_norm_loop:
  LD r10,r0,@hw6_j
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_ctx_begin
  MOVI r12,0x1810
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hw6_sum
  LD r14,r14,0
  FDIV r13,r13,r14
  ST r13,r12,0
  ADDI r10,r10,1
  ST r10,r0,@hw6_j
  JMP @hw6_norm_loop
hw6_ctx_begin:
  MOVI r10,0
  ST r10,r0,@hw6_d
hw6_ctx_clear:
  LD r10,r0,@hw6_d
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hw6_ctx_clear_done
  MOVI r12,0x0F00
  MOVHI r12,0x00D0
  LD r13,r0,@hw6_i
  MOVI r14,128
  MUL r13,r13,r14
  ADD r12,r12,r13
  ADD r12,r12,r10
  ST r0,r12,0
  ADDI r10,r10,1
  ST r10,r0,@hw6_d
  JMP @hw6_ctx_clear
hw6_ctx_clear_done:
  MOVI r10,0
  ST r10,r0,@hw6_j
hw6_ctx_j:
  LD r10,r0,@hw6_j
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_ctx_done
  MOVI r12,0x1810
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r15,r12,0
  MOVI r13,0
  ST r13,r0,@hw6_d
hw6_ctx_d:
  LD r13,r0,@hw6_d
  MOVI r14,128
  CMP r13,r14
  JMP[GE] @hw6_ctx_next_j
  MOVI r12,128
  LD r14,r0,@hw6_j
  MUL r14,r14,r12
  MOVI r11,0x0C00
  MOVHI r11,0x00D0
  ADD r11,r11,r14
  ADD r11,r11,r13
  LD r11,r11,0
  FMUL r11,r11,r15
  MOVI r12,128
  LD r14,r0,@hw6_i
  MUL r14,r14,r12
  MOVI r12,0x0F00
  MOVHI r12,0x00D0
  ADD r12,r12,r14
  ADD r12,r12,r13
  LD r14,r12,0
  FADD r14,r14,r11
  ST r14,r12,0
  ADDI r13,r13,1
  ST r13,r0,@hw6_d
  JMP @hw6_ctx_d
hw6_ctx_next_j:
  LD r10,r0,@hw6_j
  ADDI r10,r10,1
  ST r10,r0,@hw6_j
  JMP @hw6_ctx_j
hw6_ctx_done:

  ; attn = Wo * ctx
  LD r10,r0,@hw6_layer_page
  MOVI r12,0x6000
  ADD r1,r10,r12
  MOVI r2,0x0F00
  MOVHI r2,0x00D0
  LD r13,r0,@hw6_i
  MOVI r12,128
  MUL r13,r13,r12
  ADD r2,r2,r13
  MOVI r3,0x1200
  MOVHI r3,0x00D0
  ADD r3,r3,r13
  MOVI r4,128
  MOVI r5,128
  CALL @hw6_mv
  ; x_i += attn
  MOVI r10,0
  ST r10,r0,@hw6_d
hw6_res1:
  LD r10,r0,@hw6_d
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hw6_res1_done
  MOVI r12,128
  LD r13,r0,@hw6_i
  MUL r13,r13,r12
  MOVI r11,0x0000
  MOVHI r11,0x00D0
  ADD r11,r11,r13
  ADD r11,r11,r10
  LD r14,r11,0
  MOVI r12,0x1200
  MOVHI r12,0x00D0
  ADD r12,r12,r13
  ADD r12,r12,r10
  LD r15,r12,0
  FADD r14,r14,r15
  ST r14,r11,0
  ADDI r10,r10,1
  ST r10,r0,@hw6_d
  JMP @hw6_res1
hw6_res1_done:
  LD r10,r0,@hw6_i
  ADDI r10,r10,1
  ST r10,r0,@hw6_i
  JMP @hw6_query_loop
hw6_attention_done:

  ; Second LayerNorm and MLP for every token.
  MOVI r10,0
  ST r10,r0,@hw6_i
hw6_mlp_tokens:
  LD r10,r0,@hw6_i
  LD r11,r0,@hw6_t
  CMP r10,r11
  JMP[GE] @hw6_layer_done
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r1,0x0000
  MOVHI r1,0x00D0
  ADD r1,r1,r12
  MOVI r2,0x0300
  MOVHI r2,0x00D0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hw6_ln
  LD r10,r0,@hw6_layer_page
  MOVI r12,0x8000
  ADD r1,r10,r12
  MOVI r2,0x0300
  MOVHI r2,0x00D0
  LD r13,r0,@hw6_i
  MOVI r12,128
  MUL r13,r13,r12
  ADD r2,r2,r13
  MOVI r3,0x1500
  MOVHI r3,0x00D0
  MOVI r4,384
  MOVI r5,128
  CALL @hw6_mv
  ; tanh hidden
  MOVI r10,0
hw6_tanh:
  MOVI r11,384
  CMP r10,r11
  JMP[GE] @hw6_tanh_done
  MOVI r12,0x1500
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r12,0
  FTANH r13,r13
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hw6_tanh
hw6_tanh_done:
  LD r10,r0,@hw6_layer_page
  MOVI r12,0xE000
  ADD r1,r10,r12
  MOVI r2,0x1500
  MOVHI r2,0x00D0
  MOVI r3,0x1700
  MOVHI r3,0x00D0
  MOVI r4,128
  MOVI r5,384
  CALL @hw6_mv
  ; x_i += mlp
  MOVI r10,0
hw6_res2:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hw6_res2_done
  MOVI r12,128
  LD r13,r0,@hw6_i
  MUL r13,r13,r12
  MOVI r11,0x0000
  MOVHI r11,0x00D0
  ADD r11,r11,r13
  ADD r11,r11,r10
  LD r14,r11,0
  MOVI r12,0x1700
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r15,r12,0
  FADD r14,r14,r15
  ST r14,r11,0
  ADDI r10,r10,1
  JMP @hw6_res2
hw6_res2_done:
  LD r10,r0,@hw6_i
  ADDI r10,r10,1
  ST r10,r0,@hw6_i
  JMP @hw6_mlp_tokens
hw6_layer_done:
  LD r10,r0,@hw6_layer
  ADDI r10,r10,1
  ST r10,r0,@hw6_layer
  JMP @hw6_layer_loop

hw6_finish:
  MOVI r10,0
  LD r11,r0,@hw6_n
hw6_copy_out:
  CMP r10,r11
  JMP[GE] @hw6_ok
  MOVI r12,0x0000
  MOVHI r12,0x00D0
  ADD r12,r12,r10
  LD r13,r12,0
  LD r14,r0,@hw6_out
  ADD r14,r14,r10
  ST r13,r14,0
  ADDI r10,r10,1
  JMP @hw6_copy_out
hw6_ok:
  MOVI r1,1
  LD r2,r0,@hw6_n
  LD r3,r0,@hw6_slot
  MOVI r4,0
  LD r10,r0,@hw6_link
  ADD r15,r10,r0
  RET
hw6_bad_slot:
  MOVI r4,1
  JMP @hw6_reject
hw6_bad_header:
  MOVI r4,2
  JMP @hw6_reject
hw6_bad:
  MOVI r4,3
hw6_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r10,r0,@hw6_link
  ADD r15,r10,r0
  RET

; dot product of two f32[D] vectors. r1=a, r2=b, r3=D -> dot_value cell.
hw6_dot:
  MOVI r0,0
  ST r15,r0,@hw6_dot_link
  MOVI r10,0
  MOVI r14,0
hw6_dot_loop:
  CMP r10,r3
  JMP[GE] @hw6_dot_done
  ADD r11,r1,r10
  LD r11,r11,0
  ADD r12,r2,r10
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r10,r10,1
  JMP @hw6_dot_loop
hw6_dot_done:
  ST r14,r0,@hw6_dot_value
  LD r15,r0,@hw6_dot_link
  RET

; bf16 matrix-vector. r1=matrix words, r2=f32 vector, r3=output,
; r4=rows, r5=cols (even).
hw6_mv:
  MOVI r0,0
  ST r15,r0,@hw6_mv_link
  MOVI r11,0
hw6_mv_row:
  CMP r11,r4
  JMP[GE] @hw6_mv_done
  MOVI r14,0
  MOVI r10,0
hw6_mv_col:
  CMP r10,r5
  JMP[GE] @hw6_mv_row_done
  SHR r6,r5,1
  MUL r6,r11,r6
  SHR r7,r10,1
  ADD r6,r6,r7
  ADD r6,r6,r1
  LD r7,r6,0
  SHL r8,r10,31
  SHR r8,r8,31
  CMP r8,r0
  JMP[EQ] @hw6_mv_low
  SHR r7,r7,16
hw6_mv_low:
  SHL r7,r7,16
  ADD r8,r2,r10
  LD r8,r8,0
  FMUL r7,r7,r8
  FADD r14,r14,r7
  ADDI r10,r10,1
  JMP @hw6_mv_col
hw6_mv_row_done:
  ADD r6,r3,r11
  ST r14,r6,0
  ADDI r11,r11,1
  JMP @hw6_mv_row
hw6_mv_done:
  LD r15,r0,@hw6_mv_link
  RET

; LayerNorm. r1=input, r2=output, r3=D.
hw6_ln:
  MOVI r0,0
  ST r15,r0,@hw6_ln_link
  ST r1,r0,@hw6_ln_in
  ST r2,r0,@hw6_ln_dst
  ST r3,r0,@hw6_ln_d
  MOVI r10,0
  MOVI r11,0
hw6_ln_sum:
  LD r12,r0,@hw6_ln_d
  CMP r10,r12
  JMP[GE] @hw6_ln_sum_done
  LD r12,r0,@hw6_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @hw6_ln_sum
hw6_ln_sum_done:
  LD r12,r0,@hw6_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  ST r11,r0,@hw6_mean
  MOVI r10,0
  MOVI r11,0
hw6_ln_var:
  LD r12,r0,@hw6_ln_d
  CMP r10,r12
  JMP[GE] @hw6_ln_var_done
  LD r12,r0,@hw6_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hw6_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  FMUL r13,r13,r13
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @hw6_ln_var
hw6_ln_var_done:
  LD r12,r0,@hw6_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  MOVI r12,@hw6_eps
  LD r12,r12,0
  FADD r11,r11,r12
  FSQRT r11,r11
  MOVI r12,@hw6_one
  LD r12,r12,0
  FDIV r11,r12,r11
  ST r11,r0,@hw6_inv
  MOVI r10,0
hw6_ln_out:
  LD r12,r0,@hw6_ln_d
  CMP r10,r12
  JMP[GE] @hw6_ln_done
  LD r12,r0,@hw6_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hw6_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  MOVI r14,@hw6_inv
  LD r14,r14,0
  FMUL r13,r13,r14
  LD r12,r0,@hw6_ln_dst
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hw6_ln_out
hw6_ln_done:
  LD r15,r0,@hw6_ln_link
  RET

hw6_link:
  .word 0
hw6_in:
  .word 0
hw6_out:
  .word 0
hw6_slot:
  .word 0
hw6_t:
  .word 0
hw6_n:
  .word 0
hw6_page:
  .word 0
hw6_layer_page:
  .word 0
hw6_layer:
  .word 0
hw6_i:
  .word 0
hw6_j:
  .word 0
hw6_d:
  .word 0
hw6_sum:
  .word 0
hw6_max:
  .word 0
hw6_mean:
  .word 0
hw6_inv:
  .word 0
hw6_dot_link:
  .word 0
hw6_dot_value:
  .word 0
hw6_mv_link:
  .word 0
hw6_ln_link:
  .word 0
hw6_ln_in:
  .word 0
hw6_ln_dst:
  .word 0
hw6_ln_d:
  .word 0
hw6_scale:
  .word 0x413504F3
hw6_one:
  .word 0x3F800000
hw6_eps:
  .word 0x3727C5AC
