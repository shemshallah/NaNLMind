; Raw NaN16 64-token 128D three-layer bf16 local head block.
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

mth_head_block64:
  MOVI r0,0
  ST r15,r0,@hb64_link
  ST r1,r0,@hb64_in
  ST r2,r0,@hb64_out
  ST r3,r0,@hb64_slot
  ST r4,r0,@hb64_t
  CMP r1,r0
  JMP[EQ] @hb64_bad
  CMP r2,r0
  JMP[EQ] @hb64_bad
  CMP r4,r0
  JMP[EQ] @hb64_bad
  MOVI r5,64
  CMP r4,r5
  JMP[GT] @hb64_bad
  MOVI r5,20
  CMP r3,r5
  JMP[GE] @hb64_bad_slot
  SHL r5,r3,18
  MOVI r6,0x0000
  MOVHI r6,0x0080
  ADD r6,r6,r5
  ST r6,r0,@hb64_page
  MOVI r7,0xF300
  MOVHI r7,0x0003
  ADD r7,r6,r7
  LD r8,r7,0
  MOVI r9,0x5233
  MOVHI r9,0x4831
  CMP r8,r9
  JMP[NE] @hb64_bad_header

  ; Copy T*128 input floats to the working bank.
  MOVI r10,0
  MOVI r5,128
  LD r11,r0,@hb64_t
  MUL r11,r11,r5
  ST r11,r0,@hb64_n
hb64_copy_in:
  LD r11,r0,@hb64_n
  CMP r10,r11
  JMP[GE] @hb64_copy_in_done
  LD r12,r0,@hb64_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r12,0x0000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hb64_copy_in
hb64_copy_in_done:
  MOVI r10,0
  ST r10,r0,@hb64_layer

hb64_layer_loop:
  LD r10,r0,@hb64_layer
  MOVI r11,3
  CMP r10,r11
  JMP[GE] @hb64_finish

  ; LayerNorm all tokens.
  MOVI r10,0
  ST r10,r0,@hb64_i
hb64_ln_tokens:
  LD r10,r0,@hb64_i
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_ln_tokens_done
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r1,0x0000
  MOVHI r1,0x00E0
  ADD r1,r1,r12
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hb64_ln
  LD r10,r0,@hb64_i
  ADDI r10,r10,1
  ST r10,r0,@hb64_i
  JMP @hb64_ln_tokens
hb64_ln_tokens_done:

  ; Layer page = page + layer*0x14000 words.
  LD r10,r0,@hb64_page
  LD r11,r0,@hb64_layer
  MOVI r12,0x4000
  MOVHI r12,0x0001
  MUL r12,r11,r12
  ADD r10,r10,r12
  ST r10,r0,@hb64_layer_page

  ; Q, K, V for every token.
  MOVI r10,0
  ST r10,r0,@hb64_i
hb64_qkv_tokens:
  LD r10,r0,@hb64_i
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_qkv_done
  MOVI r12,128
  MUL r12,r10,r12
  ; q
  LD r1,r0,@hb64_layer_page
  ADD r1,r1,r0
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,0x4000
  MOVHI r3,0x00E0
  ADD r3,r3,r12
  MOVI r4,128
  MOVI r5,128
  CALL @hb64_mv
  ; k
  LD r1,r0,@hb64_layer_page
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
  CALL @hb64_mv
  ; v
  LD r1,r0,@hb64_layer_page
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
  CALL @hb64_mv
  LD r10,r0,@hb64_i
  ADDI r10,r10,1
  ST r10,r0,@hb64_i
  JMP @hb64_qkv_tokens
hb64_qkv_done:

  ; For each query token, score against all keys and mix values.
  MOVI r10,0
  ST r10,r0,@hb64_i
hb64_query_loop:
  LD r10,r0,@hb64_i
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_attention_done
  ; scores[j] = dot(q_i,k_j)/sqrt(128), max tracked
  MOVI r10,0
  ST r10,r0,@hb64_j
  MOVI r10,0
  MOVHI r10,0xFF80
  ST r10,r0,@hb64_max
hb64_score_loop:
  LD r10,r0,@hb64_j
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_score_done
  ; Causal local attention: query i cannot read key j > i.
  LD r12,r0,@hb64_i
  CMP r10,r12
  JMP[LE] @hb64_score_compute
  MOVI r13,0
  MOVHI r13,0xFF80
  MOVI r12,0xF000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  ST r13,r12,0
  JMP @hb64_score_next
hb64_score_compute:
  MOVI r12,128
  LD r13,r0,@hb64_i
  MUL r13,r13,r12
  MOVI r1,0x4000
  MOVHI r1,0x00E0
  ADD r1,r1,r13
  MUL r12,r10,r12
  MOVI r2,0x6000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hb64_dot
  LD r10,r0,@hb64_dot_value
  MOVI r12,@hb64_scale
  LD r12,r12,0
  FDIV r10,r10,r12
  LD r11,r0,@hb64_j
  MOVI r12,0xF000
  MOVHI r12,0x00E0
  ADD r12,r12,r11
  ST r10,r12,0
  ; compare against max cell
  MOVI r12,@hb64_max
  LD r13,r12,0
  FCMP r10,r13
  JMP[LE] @hb64_score_next
  ST r10,r12,0
hb64_score_next:
  LD r10,r0,@hb64_j
  ADDI r10,r10,1
  ST r10,r0,@hb64_j
  JMP @hb64_score_loop
hb64_score_done:

  ; probs[j] = exp(score-max), sum
  MOVI r10,0
  ST r10,r0,@hb64_j
  MOVI r10,0
  ST r10,r0,@hb64_sum
hb64_prob_loop:
  LD r10,r0,@hb64_j
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_prob_done
  MOVI r12,0xF000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hb64_max
  LD r14,r14,0
  FSUB r13,r13,r14
  FEXP r13,r13
  MOVI r14,0xF800
  MOVHI r14,0x00E0
  ADD r14,r14,r10
  ST r13,r14,0
  MOVI r14,@hb64_sum
  LD r15,r14,0
  FADD r15,r15,r13
  ST r15,r14,0
  ADDI r10,r10,1
  ST r10,r0,@hb64_j
  JMP @hb64_prob_loop
hb64_prob_done:
  ; normalize probs and clear context
  MOVI r10,0
  ST r10,r0,@hb64_j
hb64_norm_loop:
  LD r10,r0,@hb64_j
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_ctx_begin
  MOVI r12,0xF800
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hb64_sum
  LD r14,r14,0
  FDIV r13,r13,r14
  ST r13,r12,0
  ADDI r10,r10,1
  ST r10,r0,@hb64_j
  JMP @hb64_norm_loop
hb64_ctx_begin:
  ; Context row pointer for this query.
  MOVI r12,0xA000
  MOVHI r12,0x00E0
  LD r13,r0,@hb64_i
  MOVI r14,128
  MUL r13,r13,r14
  ADD r12,r12,r13
  ST r12,r0,@hb64_ctx_row
  MOVI r10,0
  MOVI r11,128
hb64_ctx_clear:
  CMP r10,r11
  JMP[GE] @hb64_ctx_clear_done
  ST r0,r12,0
  ADDI r12,r12,1
  ADDI r10,r10,1
  JMP @hb64_ctx_clear
hb64_ctx_clear_done:
  MOVI r10,0
  ST r10,r0,@hb64_j
hb64_ctx_j:
  LD r10,r0,@hb64_j
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_ctx_done
  MOVI r12,0xF800
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r15,r12,0
  ; Value-row and context-row cursors, advanced once per dimension.
  MOVI r11,128
  MUL r11,r10,r11
  MOVI r13,0x8000
  MOVHI r13,0x00E0
  ADD r13,r13,r11
  MOVI r14,128
  ADD r10,r13,r14
  MOVI r9,4
  SUB r9,r10,r9
  LD r12,r0,@hb64_ctx_row
hb64_ctx_d:
  CMP r13,r9
  JMP[GT] @hb64_ctx_tail
  LD r11,r13,0
  FMUL r11,r11,r15
  LD r14,r12,0
  FADD r14,r14,r11
  ST r14,r12,0
  LD r11,r13,1
  FMUL r11,r11,r15
  LD r14,r12,1
  FADD r14,r14,r11
  ST r14,r12,1
  LD r11,r13,2
  FMUL r11,r11,r15
  LD r14,r12,2
  FADD r14,r14,r11
  ST r14,r12,2
  LD r11,r13,3
  FMUL r11,r11,r15
  LD r14,r12,3
  FADD r14,r14,r11
  ST r14,r12,3
  ADDI r13,r13,4
  ADDI r12,r12,4
  JMP @hb64_ctx_d
hb64_ctx_tail:
  CMP r13,r10
  JMP[GE] @hb64_ctx_next_j
  LD r11,r13,0
  FMUL r11,r11,r15
  LD r14,r12,0
  FADD r14,r14,r11
  ST r14,r12,0
  ADDI r13,r13,1
  ADDI r12,r12,1
  JMP @hb64_ctx_tail
hb64_ctx_next_j:
  LD r10,r0,@hb64_j
  ADDI r10,r10,1
  ST r10,r0,@hb64_j
  JMP @hb64_ctx_j
hb64_ctx_done:

  ; attn = Wo * ctx
  LD r10,r0,@hb64_layer_page
  MOVI r12,0x6000
  ADD r1,r10,r12
  MOVI r2,0xA000
  MOVHI r2,0x00E0
  LD r13,r0,@hb64_i
  MOVI r12,128
  MUL r13,r13,r12
  ADD r2,r2,r13
  MOVI r3,0xC000
  MOVHI r3,0x00E0
  ADD r3,r3,r13
  MOVI r4,128
  MOVI r5,128
  CALL @hb64_mv
  ; x_i += attn
  MOVI r10,0
  ST r10,r0,@hb64_d
hb64_res1:
  LD r10,r0,@hb64_d
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hb64_res1_done
  MOVI r12,128
  LD r13,r0,@hb64_i
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
  ST r10,r0,@hb64_d
  JMP @hb64_res1
hb64_res1_done:
  LD r10,r0,@hb64_i
  ADDI r10,r10,1
  ST r10,r0,@hb64_i
  JMP @hb64_query_loop
hb64_attention_done:

  ; Second LayerNorm and MLP for every token.
  MOVI r10,0
  ST r10,r0,@hb64_i
hb64_mlp_tokens:
  LD r10,r0,@hb64_i
  LD r11,r0,@hb64_t
  CMP r10,r11
  JMP[GE] @hb64_layer_done
  MOVI r12,128
  MUL r12,r10,r12
  MOVI r1,0x0000
  MOVHI r1,0x00E0
  ADD r1,r1,r12
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  ADD r2,r2,r12
  MOVI r3,128
  CALL @hb64_ln
  LD r10,r0,@hb64_layer_page
  MOVI r12,0x8000
  ADD r1,r10,r12
  MOVI r2,0x2000
  MOVHI r2,0x00E0
  LD r13,r0,@hb64_i
  MOVI r12,128
  MUL r13,r13,r12
  ADD r2,r2,r13
  MOVI r3,0xE000
  MOVHI r3,0x00E0
  MOVI r4,384
  MOVI r5,128
  CALL @hb64_mv
  ; tanh hidden
  MOVI r10,0
hb64_tanh:
  MOVI r11,384
  CMP r10,r11
  JMP[GE] @hb64_tanh_done
  MOVI r12,0xE000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  FTANH r13,r13
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hb64_tanh
hb64_tanh_done:
  LD r10,r0,@hb64_layer_page
  MOVI r12,0xE000
  ADD r1,r10,r12
  MOVI r2,0xE000
  MOVHI r2,0x00E0
  MOVI r3,0xE800
  MOVHI r3,0x00E0
  MOVI r4,128
  MOVI r5,384
  CALL @hb64_mv
  ; x_i += mlp
  MOVI r10,0
hb64_res2:
  MOVI r11,128
  CMP r10,r11
  JMP[GE] @hb64_res2_done
  MOVI r12,128
  LD r13,r0,@hb64_i
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
  JMP @hb64_res2
hb64_res2_done:
  LD r10,r0,@hb64_i
  ADDI r10,r10,1
  ST r10,r0,@hb64_i
  JMP @hb64_mlp_tokens
hb64_layer_done:
  LD r10,r0,@hb64_layer
  ADDI r10,r10,1
  ST r10,r0,@hb64_layer
  JMP @hb64_layer_loop

hb64_finish:
  MOVI r10,0
  LD r11,r0,@hb64_n
hb64_copy_out:
  CMP r10,r11
  JMP[GE] @hb64_ok
  MOVI r12,0x0000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r13,r12,0
  LD r14,r0,@hb64_out
  ADD r14,r14,r10
  ST r13,r14,0
  ADDI r10,r10,1
  JMP @hb64_copy_out
hb64_ok:
  MOVI r1,1
  LD r2,r0,@hb64_n
  LD r3,r0,@hb64_slot
  MOVI r4,0
  LD r10,r0,@hb64_link
  ADD r15,r10,r0
  RET
hb64_bad_slot:
  MOVI r4,1
  JMP @hb64_reject
hb64_bad_header:
  MOVI r4,2
  JMP @hb64_reject
hb64_bad:
  MOVI r4,3
hb64_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  LD r10,r0,@hb64_link
  ADD r15,r10,r0
  RET

; dot product of two f32[D] vectors. r1=a, r2=b, r3=D -> dot_value cell.
hb64_dot:
  MOVI r0,0
  ST r15,r0,@hb64_dot_link
  ADD r3,r1,r3
  MOVI r14,0
hb64_dot_loop:
  CMP r1,r3
  JMP[GE] @hb64_dot_done
  LD r11,r1,0
  LD r12,r2,0
  FMUL r11,r11,r12
  FADD r14,r14,r11
  ADDI r1,r1,1
  ADDI r2,r2,1
  JMP @hb64_dot_loop
hb64_dot_done:
  ST r14,r0,@hb64_dot_value
  LD r15,r0,@hb64_dot_link
  RET

; bf16 matrix-vector. r1=matrix words, r2=f32 vector, r3=output,
; r4=rows (even), r5=cols (even).
hb64_mv:
  MOVI r0,0
  ST r15,r0,@hb64_mv_link
  ; Two matrix rows share each vector load. All callers pass even row
  ; counts, so rows advance together and the vector pair is loaded once.
  ADD r13,r2,r5
  MOVI r6,0
  ADD r6,r1,r6
  ADD r4,r3,r4
  ST r4,r0,@hb64_mv_out_end
  SHR r4,r5,1
  ST r4,r0,@hb64_mv_pairs
  ADD r6,r6,r4
  MOVI r9,16
  SUB r5,r13,r9
hb64_mv_row:
  LD r4,r0,@hb64_mv_out_end
  CMP r3,r4
  JMP[GE] @hb64_mv_done
  MOVI r14,0
  MOVI r12,0
  ADD r7,r2,r0
hb64_mv_col:
  CMP r7,r5
  JMP[GT] @hb64_mv_tail
  LD r8,r1,0
  LD r11,r6,0
  LD r4,r7,0
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,1
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  LD r8,r1,1
  LD r11,r6,1
  LD r4,r7,2
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,3
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  LD r8,r1,2
  LD r11,r6,2
  LD r4,r7,4
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,5
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  LD r8,r1,3
  LD r11,r6,3
  LD r4,r7,6
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,7
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  LD r8,r1,4
  LD r11,r6,4
  LD r4,r7,8
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,9
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  LD r8,r1,5
  LD r11,r6,5
  LD r4,r7,10
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,11
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  LD r8,r1,6
  LD r11,r6,6
  LD r4,r7,12
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,13
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  LD r8,r1,7
  LD r11,r6,7
  LD r4,r7,14
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,15
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  ADDI r1,r1,8
  ADDI r6,r6,8
  ADDI r7,r7,16
  JMP @hb64_mv_col
hb64_mv_tail:
  CMP r7,r13
  JMP[GE] @hb64_mv_row_done
  LD r8,r1,0
  LD r11,r6,0
  LD r4,r7,0
  SHL r9,r8,16
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHL r9,r11,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  SHR r9,r8,16
  SHL r9,r9,16
  LD r4,r7,1
  FMUL r9,r9,r4
  FADD r14,r14,r9
  SHR r9,r11,16
  SHL r9,r9,16
  FMUL r9,r9,r4
  FADD r12,r12,r9
  ADDI r1,r1,1
  ADDI r6,r6,1
  ADDI r7,r7,2
  JMP @hb64_mv_tail
hb64_mv_row_done:
  ST r14,r3,0
  ST r12,r3,1
  ADDI r3,r3,2
  LD r4,r0,@hb64_mv_pairs
  ADD r1,r1,r4
  ADD r6,r6,r4
  JMP @hb64_mv_row
hb64_mv_done:
  ; The 64-token QKV loop reads r12 after a matvec; retain its old
  ; post-call value (last matrix word) so results stay bit-identical.
  ADDI r12,r1,-1
  LD r15,r0,@hb64_mv_link
  RET

; LayerNorm. r1=input, r2=output, r3=D.
hb64_ln:
  MOVI r0,0
  ST r15,r0,@hb64_ln_link
  ST r1,r0,@hb64_ln_in
  ST r2,r0,@hb64_ln_dst
  ST r3,r0,@hb64_ln_d
  MOVI r10,0
  MOVI r11,0
hb64_ln_sum:
  LD r12,r0,@hb64_ln_d
  CMP r10,r12
  JMP[GE] @hb64_ln_sum_done
  LD r12,r0,@hb64_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @hb64_ln_sum
hb64_ln_sum_done:
  LD r12,r0,@hb64_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  ST r11,r0,@hb64_mean
  MOVI r10,0
  MOVI r11,0
hb64_ln_var:
  LD r12,r0,@hb64_ln_d
  CMP r10,r12
  JMP[GE] @hb64_ln_var_done
  LD r12,r0,@hb64_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hb64_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  FMUL r13,r13,r13
  FADD r11,r11,r13
  ADDI r10,r10,1
  JMP @hb64_ln_var
hb64_ln_var_done:
  LD r12,r0,@hb64_ln_d
  CVTIF r12,r12
  FDIV r11,r11,r12
  MOVI r12,@hb64_eps
  LD r12,r12,0
  FADD r11,r11,r12
  FSQRT r11,r11
  MOVI r12,@hb64_one
  LD r12,r12,0
  FDIV r11,r12,r11
  ST r11,r0,@hb64_inv
  MOVI r10,0
hb64_ln_out:
  LD r12,r0,@hb64_ln_d
  CMP r10,r12
  JMP[GE] @hb64_ln_done
  LD r12,r0,@hb64_ln_in
  ADD r12,r12,r10
  LD r13,r12,0
  MOVI r14,@hb64_mean
  LD r14,r14,0
  FSUB r13,r13,r14
  MOVI r14,@hb64_inv
  LD r14,r14,0
  FMUL r13,r13,r14
  LD r12,r0,@hb64_ln_dst
  ADD r12,r12,r10
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @hb64_ln_out
hb64_ln_done:
  LD r15,r0,@hb64_ln_link
  RET

hb64_link:
  .word 0
hb64_in:
  .word 0
hb64_out:
  .word 0
hb64_slot:
  .word 0
hb64_t:
  .word 0
hb64_n:
  .word 0
hb64_page:
  .word 0
hb64_layer_page:
  .word 0
hb64_layer:
  .word 0
hb64_i:
  .word 0
hb64_j:
  .word 0
hb64_d:
  .word 0
hb64_sum:
  .word 0
hb64_max:
  .word 0
hb64_mean:
  .word 0
hb64_inv:
  .word 0
hb64_dot_link:
  .word 0
hb64_dot_value:
  .word 0
hb64_mv_link:
  .word 0
hb64_ln_link:
  .word 0
hb64_ln_in:
  .word 0
hb64_ln_dst:
  .word 0
hb64_ln_d:
  .word 0
hb64_scale:
  .word 0x413504F3
hb64_one:
  .word 0x3F800000
hb64_eps:
  .word 0x3727C5AC

hb64_cap_hidden:
  .word 0
hb64_cap_xn:
  .word 0
hb64_cap_ctx:
  .word 0
hb64_cap_src:
  .word 0
hb64_cap_i:
  .word 0

hb64_cap_off:
  .word 0
hb64_cap_n:
  .word 0
hb64_copy_link:
  .word 0

hb64_mv_pairs:
  .word 0

hb64_mv_out_end:
  .word 0

hb64_ctx_row:
  .word 0
