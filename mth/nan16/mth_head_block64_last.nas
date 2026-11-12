; Raw NaN16 64-token causal last-token head block.
; Layers 0 and 1 run fully; layer 2 computes only the last query/MLP.
; Higher-memory local-attention variant of the six-token worker.
;
; This block is assembled into mth/drivers/head_worker.nas in the worker's
; low code window, so every JMP/CALL is a normal 16-bit guest transfer and the
; 0x4000 command block remains untouched.
;
; ABI (worker dispatcher writes args at 0x4001..0x4004):
;   r1 = input f32[T][128]
;   r2 = output f32[T][128]
;   r3 = slot 0..15
;   r4 = T 1..64
; Returns r1=1, r2=T*128, r3=slot, r4=0 on success.
; Attention is causal: query i reads keys j <= i.
;
; Page layout is the same frozen 1 MiB layout as the single-token block:
;   +0x00000 Wq, +0x02000 Wk, +0x04000 Wv, +0x06000 Wo,
;   +0x08000 W1 (384x128), +0x0E000 W2 (128x384),
;   layer stride 0x14000 (guest words), header at +0x3F300.
; All page reads are bf16 pairs; all arithmetic is guest-side.

mth_head_block64_last:
  MOVI r0,0
  ST r15,r0,@hbl64_link
  ST r1,r0,@hbl64_in
  ST r2,r0,@hbl64_out
  ST r3,r0,@hbl64_slot
  ST r4,r0,@hbl64_t
  CMP r1,r0
  JMP[EQ] @hbl64_bad
  CMP r2,r0
  JMP[EQ] @hbl64_bad
  CMP r4,r0
  JMP[EQ] @hbl64_bad
  MOVI r5,64
  CMP r4,r5
  JMP[GT] @hbl64_bad
  MOVI r5,16
  CMP r3,r5
  JMP[GE] @hbl64_bad_slot
  SHL r5,r3,18
  MOVI r6,0x0000
  MOVHI r6,0x0080
  ADD r6,r6,r5
  ST r6,r0,@hbl64_page
  MOVI r7,0xF300
  MOVHI r7,0x0003
  ADD r7,r6,r7
  LD r8,r7,0
  MOVI r9,0x5233
  MOVHI r9,0x4831
  CMP r8,r9
  JMP[NE] @hbl64_bad_header

  ; Copy T*128 input floats to the working bank.
  MOVI r10,0
  MOVI r5,128
  LD r11,r0,@hbl64_t
  MUL r11,r11,r5
  ST r11,r0,@hbl64_n
hbl64_copy_in:
  LD r11,r0,@hbl64_n
  CMP r10,r11
  JMP[GE] @hbl64_copy_in_done
  LD r12,r0,@hbl64_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r12,0x0000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hbl64_copy_in
hbl64_copy_in_done:
  MOVI r10,0
  ST r10,r0,@hbl64_layer

hbl64_layer_loop:
  LD r10,r0,@hbl64_layer
  MOVI r11,3
  CMP r10,r11
  JMP[GE] @hbl64_finish

  ; LayerNorm all tokens.
  MOVI r10,0
  ST r10,r0,@hbl64_i
hbl64_ln_tokens:
  LD r10,r0,@hbl64_i
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_ln_tokens_done
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r1,0x0000
  MOVHI r1,0x00E0
  ADD r1,r1,r12
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hbl64_ln
  LD r10,r0,@hbl64_i
  ADDI r10,r10,1
  ST r10,r0,@hbl64_i
  JMP @hbl64_ln_tokens
hbl64_ln_tokens_done:

  ; Layer page = page + layer*0x14000 words.
  LD r10,r0,@hbl64_page
  LD r11,r0,@hbl64_layer
  MOVI r12,0x4000
  MOVHI r12,0x0001
  MUL r12,r11,r12
  ADD r10,r10,r12
  ST r10,r0,@hbl64_layer_page

  ; Q, K, V for every token.
  MOVI r10,0
  ST r10,r0,@hbl64_i
hbl64_qkv_tokens:
  LD r10,r0,@hbl64_i
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_qkv_done
  MOVI r12,128
  MUL r12,r10,r12
  ; q
  LD r1,r0,@hbl64_layer_page
  ADD r1,r1,r0
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,0x4000
  MOVHI r3,0x00E0
  ADD r3,r3,r12
  MOVI r4,128
  MOVI r5,128
  CALL @hbl64_mv
  ; k
  LD r1,r0,@hbl64_layer_page
  MOVI r13,0x2000
  ADD r1,r1,r13
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,0x6000
  MOVHI r3,0x00E0
  ADD r3,r3,r12
  MOVI r4,128
  MOVI r5,128
  CALL @hbl64_mv
  ; v
  LD r1,r0,@hbl64_layer_page
  MOVI r13,0x4000
  ADD r1,r1,r13
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,0x8000
  MOVHI r3,0x00E0
  ADD r3,r3,r12
  MOVI r4,128
  MOVI r5,128
  CALL @hbl64_mv
  LD r10,r0,@hbl64_i
  ADDI r10,r10,1
  ST r10,r0,@hbl64_i
  JMP @hbl64_qkv_tokens
hbl64_qkv_done:

  ; For each query token, score against all keys and mix values.
  MOVI r10,0
  ST r10,r0,@hbl64_i
hbl64_query_loop:
  LD r10,r0,@hbl64_i
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_attention_done
  ; In the final layer only the last query is consumed.
  LD r12,r0,@hbl64_layer
  MOVI r13,2
  CMP r12,r13
  JMP[NE] @hbl64_query_normal
  LD r12,r0,@hbl64_t
  MOVI r13,1
  SUB r12,r12,r13
  CMP r10,r12
  JMP[EQ] @hbl64_query_normal
  JMP @hbl64_query_next
hbl64_query_normal:
  ; scores[j] = dot(q_i,k_j)/sqrt(128), max tracked
  MOVI r10,0
  ST r10,r0,@hbl64_j
  MOVI r10,0
  MOVHI r10,0xFF80
  ST r10,r0,@hbl64_max
hbl64_score_loop:
  LD r10,r0,@hbl64_j
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_score_done
  ; Causal local attention: query i cannot read key j > i.
  LD r12,r0,@hbl64_i
  CMP r10,r12
  JMP[LE] @hbl64_score_compute
  MOVI r13,0
  MOVHI r13,0xFF80
  MOVI r12,0xF000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  ST r13,r12,0
  JMP @hbl64_score_next
hbl64_score_compute:
  MOVI r12,128
  LD r13,r0,@hbl64_i
  MUL r13,r13,r12
  MOVI r1,0x4000
  MOVHI r1,0x00E0
  ADD r1,r1,r13
  MUL r12,r10,r12
  MOVI r2,0x6000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hbl64_dot
  LD r10,r0,@hbl64_dot_value
  MOVI r12,@hbl64_scale
  LD r12,r12,0
  FDIV r10,r10,r12
  LD r11,r0,@hbl64_j
  MOVI r12,0xF000
  MOVHI r12,0x00E0
  ADD r12,r12,r11
  ST r10,r12,0
  ; compare against max cell
  MOVI r12,@hbl64_max
  LD r13,r12,0
  FCMP r10,r13
  JMP[LE] @hbl64_score_next
  ST r10,r12,0
hbl64_score_next:
  LD r10,r0,@hbl64_j
  ADDI r10,r10,1
  ST r10,r0,@hbl64_j
  JMP @hbl64_score_loop
hbl64_score_done:

  ; probs[j] = exp(score-max), sum
  MOVI r10,0
  ST r10,r0,@hbl64_j
  MOVI r10,0
  ST r10,r0,@hbl64_sum
hbl64_prob_loop:
  LD r10,r0,@hbl64_j
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_prob_done
  MOVI r12,0xF000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hbl64_max
  LD r14,r14,0
  FSUB r13,r13,r14
  FEXP r13,r13
  MOVI r14,0xF800
  MOVHI r14,0x00E0
  ADD r14,r14,r10
  ST r13,r14,0
  MOVI r14,@hbl64_sum
  LD r15,r14,0
  FADD r15,r15,r13
  ST r15,r14,0
  ADDI r10,r10,1
  ST r10,r0,@hbl64_j
  JMP @hbl64_prob_loop
hbl64_prob_done:
  ; normalize probs and clear context
  MOVI r10,0
  ST r10,r0,@hbl64_j
hbl64_norm_loop:
  LD r10,r0,@hbl64_j
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_ctx_begin
  MOVI r12,0xF800
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hbl64_sum
  LD r14,r14,0
  FDIV r13,r13,r14
  ST r13,r12,0
  ADDI r10,r10,1
  ST r10,r0,@hbl64_j
  JMP @hbl64_norm_loop
hbl64_ctx_begin:
  MOVI r10,0
  ST r10,r0,@hbl64_d
hbl64_ctx_clear:
  LD r10,r0,@hbl64_d
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hbl64_ctx_clear_done
  MOVI r12,0xA000
  MOVHI r12,0x00E0
  LD r13,r0,@hbl64_i
  MOVI r14,128
  MUL r13,r13,r14
  ADD r12,r12,r13
  ADD r12,r12,r10
  ST r0,r12,0
  ADDI r10,r10,1
  ST r10,r0,@hbl64_d
  JMP @hbl64_ctx_clear
hbl64_ctx_clear_done:
  MOVI r10,0
  ST r10,r0,@hbl64_j
hbl64_ctx_j:
  LD r10,r0,@hbl64_j
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_ctx_done
  MOVI r12,0xF800
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r15,r12,0
  MOVI r13,0
  ST r13,r0,@hbl64_d
hbl64_ctx_d:
  LD r13,r0,@hbl64_d
  MOVI r14,128
  CMP r13,r14
  JMP[GE] @hbl64_ctx_next_j
  MOVI r12,128
  LD r14,r0,@hbl64_j
  MUL r14,r14,r12
  MOVI r11,0x8000
  MOVHI r11,0x00E0
  ADD r11,r11,r14
  ADD r11,r11,r13
  LD r11,r11,0
  FMUL r11,r11,r15
  MOVI r12,128
  LD r14,r0,@hbl64_i
  MUL r14,r14,r12
  MOVI r12,0xA000
  MOVHI r12,0x00E0
  ADD r12,r12,r14
  ADD r12,r12,r13
  LD r14,r12,0
  FADD r14,r14,r11
  ST r14,r12,0
  ADDI r13,r13,1
  ST r13,r0,@hbl64_d
  JMP @hbl64_ctx_d
hbl64_ctx_next_j:
  LD r10,r0,@hbl64_j
  ADDI r10,r10,1
  ST r10,r0,@hbl64_j
  JMP @hbl64_ctx_j
hbl64_ctx_done:

  ; attn = Wo * ctx
  LD r10,r0,@hbl64_layer_page
  MOVI r12,0x6000
  ADD r1,r10,r12
  MOVI r2,0xA000
  MOVHI r2,0x00E0
  LD r13,r0,@hbl64_i
  MOVI r12,128
  MUL r13,r13,r12
  ADD r2,r2,r13
  MOVI r3,0xC000
  MOVHI r3,0x00E0
  ADD r3,r3,r13
  MOVI r4,128
  MOVI r5,128
  CALL @hbl64_mv
  ; x_i += attn
  MOVI r10,0
  ST r10,r0,@hbl64_d
hbl64_res1:
  LD r10,r0,@hbl64_d
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hbl64_res1_done
  MOVI r12,128
  LD r13,r0,@hbl64_i
  MUL r13,r13,r12
  MOVI r11,0x0000
  MOVHI r11,0x00E0
  ADD r11,r11,r13
  ADD r11,r11,r10
  LD r14,r11,0
  MOVI r12,0xC000
  MOVHI r12,0x00E0
  ADD r12,r12,r13
  ADD r12,r12,r10
  LD r15,r12,0
  FADD r14,r14,r15
  ST r14,r11,0
  ADDI r10,r10,1
  ST r10,r0,@hbl64_d
  JMP @hbl64_res1
hbl64_res1_done:
hbl64_query_next:
  LD r10,r0,@hbl64_i
  ADDI r10,r10,1
  ST r10,r0,@hbl64_i
  JMP @hbl64_query_loop
hbl64_attention_done:

  ; Second LayerNorm and MLP for every token.
  MOVI r10,0
  ST r10,r0,@hbl64_i
hbl64_mlp_tokens:
  LD r10,r0,@hbl64_i
  LD r11,r0,@hbl64_t
  CMP r10,r11
  JMP[GE] @hbl64_layer_done
  ; Final layer MLP only matters for the last token.
  LD r12,r0,@hbl64_layer
  MOVI r13,2
  CMP r12,r13
  JMP[NE] @hbl64_mlp_normal
  LD r12,r0,@hbl64_t
  MOVI r13,1
  SUB r12,r12,r13
  CMP r10,r12
  JMP[EQ] @hbl64_mlp_normal
  JMP @hbl64_mlp_next
hbl64_mlp_normal:
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r1,0x0000
  MOVHI r1,0x00E0
  ADD r1,r1,r12
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hbl64_ln
  LD r10,r0,@hbl64_layer_page
  MOVI r12,0x8000
  ADD r1,r10,r12
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  LD r13,r0,@hbl64_i
  MOVI r12,128
  MUL r13,r13,r12
  ADD r2,r2,r13
  MOVI r3,0xE000
  MOVHI r3,0x00E0
  MOVI r4,384
  MOVI r5,128
  CALL @hbl64_mv
  ; tanh hidden
  MOVI r10,0
hbl64_tanh:
  MOVI r11,384
  CMP r10,r11
  JMP[GE] @hbl64_tanh_done
  MOVI r12,0xE000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  FTANH r13,r13
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hbl64_tanh
hbl64_tanh_done:
  LD r10,r0,@hbl64_layer_page
  MOVI r12,0xE000
  ADD r1,r10,r12
  MOVI r2,0xE000
  MOVHI r2,0x00E0
  MOVI r3,0xE800
  MOVHI r3,0x00E0
  MOVI r4,128
  MOVI r5,384
  CALL @hbl64_mv
  ; x_i += mlp
  MOVI r10,0
hbl64_res2:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hbl64_res2_done
  MOVI r12,128
  LD r13,r0,@hbl64_i
  MUL r13,r13,r12
  MOVI r11,0x0000
  MOVHI r11,0x00E0
  ADD r11,r11,r13
  ADD r11,r11,r10
  LD r14,r11,0
  MOVI r12,0xE800
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r15,r12,0
  FADD r14,r14,r15
  ST r14,r11,0
  ADDI r10,r10,1
  JMP @hbl64_res2
hbl64_res2_done:
hbl64_mlp_next:
  LD r10,r0,@hbl64_i
  ADDI r10,r10,1
  ST r10,r0,@hbl64_i
  JMP @hbl64_mlp_tokens
hbl64_layer_done:
  LD r10,r0,@hbl64_layer
  ADDI r10,r10,1
  ST r10,r0,@hbl64_layer
  JMP @hbl64_layer_loop

hbl64_finish:
  MOVI r10,0
  LD r11,r0,@hbl64_n
hbl64_copy_out:
  CMP r10,r11
  JMP[GE] @hbl64_ok
  MOVI r12,0x0000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  LD r14,r0,@hbl64_out
  ADD r14,r14,r10
  ST r13,r14,0
  ADDI r10,r10,1
  JMP @hbl64_copy_out
hbl64_ok:
  MOVI r1,1
  LD r2,r0,@hbl64_n
  LD r3,r0,@hbl64_slot
  MOVI r4,0
  LD r10,r0,@hbl64_link
  ADD r15,r10,r0
  RET
hbl64_bad_slot:
  MOVI r4,1
  JMP @hbl64_reject
hbl64_bad_header:
  MOVI r4,2
  JMP @hbl64_reject
hbl64_bad:
  MOVI r4,3
hbl64_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r10,r0,@hbl64_link
  ADD r15,r10,r0
  RET

; dot product of two f32[D] vectors. r1=a, r2=b, r3=D -> dot_value cell.
hbl64_dot:
  MOVI r0,0
  ST r15,r0,@hbl64_dot_link
  MOVI r10,0
  MOVI r14,0
hbl64_dot_loop:
  CMP r10,r3
  JMP[GE] @hbl64_dot_done
  ADD r11,r1,r10
  LD r11,r11,0
  ADD r12,r2,r10
  LD r12,r12,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r10,r10,1
  JMP @hbl64_dot_loop
hbl64_dot_done:
  ST r14,r0,@hbl64_dot_value
  LD r15,r0,@hbl64_dot_link
  RET

; bf16 matrix-vector. r1=matrix words, r2=f32 vector, r3=output,
; r4=rows, r5=cols (even).
hbl64_mv:
  MOVI r0,0
  ST r15,r0,@hbl64_mv_link
  ST r1,r0,@hbl64_mv_mat
  ST r2,r0,@hbl64_mv_vec
  ST r3,r0,@hbl64_mv_out
  ST r4,r0,@hbl64_mv_rows
  SHR r5,r5,1
  ST r5,r0,@hbl64_mv_pairs
  MOVI r10,0
hbl64_mv_row:
  LD r9,r0,@hbl64_mv_rows
  CMP r10,r9
  JMP[GE] @hbl64_mv_done
  LD r5,r0,@hbl64_mv_pairs
  MUL r12,r10,r5
  LD r1,r0,@hbl64_mv_mat
  ADD r12,r12,r1
  ST r12,r0,@hbl64_mv_rowptr
  MOVI r14,0
  MOVI r11,0
hbl64_mv_col:
  LD r5,r0,@hbl64_mv_pairs
  CMP r11,r5
  JMP[GE] @hbl64_mv_row_done
  LD r12,r0,@hbl64_mv_rowptr
  ADD r12,r12,r11
  LD r13,r12,0
  SHL r6,r13,16
  SHL r7,r11,1
  LD r8,r0,@hbl64_mv_vec
  ADD r8,r8,r7
  LD r8,r8,0
  FMUL r6,r6,r8
  FADD r14,r14,r6
  SHR r7,r13,16
  SHL r7,r7,16
  SHL r8,r11,1
  ADDI r8,r8,1
  LD r9,r0,@hbl64_mv_vec
  ADD r9,r9,r8
  LD r9,r9,0
  FMUL r7,r7,r9
  FADD r14,r14,r7
  ADDI r11,r11,1
  JMP @hbl64_mv_col
hbl64_mv_row_done:
  LD r1,r0,@hbl64_mv_out
  ADD r1,r1,r10
  ST r14,r1,0
  ADDI r10,r10,1
  JMP @hbl64_mv_row
hbl64_mv_done:
  LD r15,r0,@hbl64_mv_link
  RET

; LayerNorm. r1=input, r2=output, r3=D.
hbl64_ln:
  MOVI r0,0
  ST r15,r0,@hbl64_ln_link
  ST r1,r0,@hbl64_ln_in
  ST r2,r0,@hbl64_ln_dst
  ST r3,r0,@hbl64_ln_d
  MOVI r10,0
  MOVI r11,0
hbl64_ln_sum:
  LD r12,r0,@hbl64_ln_d
  CMP r10,r12
  JMP[GE] @hbl64_ln_sum_done
  LD r12,r0,@hbl64_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @hbl64_ln_sum
hbl64_ln_sum_done:
  LD r12,r0,@hbl64_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  ST r11,r0,@hbl64_mean
  MOVI r10,0
  MOVI r11,0
hbl64_ln_var:
  LD r12,r0,@hbl64_ln_d
  CMP r10,r12
  JMP[GE] @hbl64_ln_var_done
  LD r12,r0,@hbl64_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hbl64_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  FMUL r13,r13,r13
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @hbl64_ln_var
hbl64_ln_var_done:
  LD r12,r0,@hbl64_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  MOVI r12,@hbl64_eps
  LD r12,r12,0
  FADD r11,r11,r12
  FSQRT r11,r11
  MOVI r12,@hbl64_one
  LD r12,r12,0
  FDIV r11,r12,r11
  ST r11,r0,@hbl64_inv
  MOVI r10,0
hbl64_ln_out:
  LD r12,r0,@hbl64_ln_d
  CMP r10,r12
  JMP[GE] @hbl64_ln_done
  LD r12,r0,@hbl64_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hbl64_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  MOVI r14,@hbl64_inv
  LD r14,r14,0
  FMUL r13,r13,r14
  LD r12,r0,@hbl64_ln_dst
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hbl64_ln_out
hbl64_ln_done:
  LD r15,r0,@hbl64_ln_link
  RET

hbl64_link:
  .word 0
hbl64_in:
  .word 0
hbl64_out:
  .word 0
hbl64_slot:
  .word 0
hbl64_t:
  .word 0
hbl64_n:
  .word 0
hbl64_page:
  .word 0
hbl64_layer_page:
  .word 0
hbl64_layer:
  .word 0
hbl64_i:
  .word 0
hbl64_j:
  .word 0
hbl64_d:
  .word 0
hbl64_sum:
  .word 0
hbl64_max:
  .word 0
hbl64_mean:
  .word 0
hbl64_inv:
  .word 0
hbl64_dot_link:
  .word 0
hbl64_dot_value:
  .word 0
hbl64_mv_link:
  .word 0
hbl64_ln_link:
  .word 0
hbl64_ln_in:
  .word 0
hbl64_ln_dst:
  .word 0
hbl64_ln_d:
  .word 0
hbl64_scale:
  .word 0x413504F3
hbl64_one:
  .word 0x3F800000
hbl64_eps:
  .word 0x3727C5AC

hbl64_cap_hidden:
  .word 0
hbl64_cap_xn:
  .word 0
hbl64_cap_ctx:
  .word 0
hbl64_cap_src:
  .word 0
hbl64_cap_i:
  .word 0

hbl64_cap_off:
  .word 0
hbl64_cap_n:
  .word 0
hbl64_copy_link:
  .word 0

hbl64_mv_mat:
  .word 0

hbl64_mv_vec:
  .word 0

hbl64_mv_out:
  .word 0

hbl64_mv_rows:
  .word 0

hbl64_mv_pairs:
  .word 0

hbl64_mv_rowptr:
  .word 0
