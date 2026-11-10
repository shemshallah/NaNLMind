; Raw NaN16 contextual encoder shared by role and sense learners.
;
; Fixed memory:
;   0x7000 tokens[T] word ids 0..63
;   0x7100 word embeddings 64 x 8 float32
;   0x7300 position gates 4 x 8 float32
;   0x7380 bias[8], 0x7390 order[8], 0x73A0 output[8]
;   0x7400 positions[T] in 0..3
;   0x4001 T, 0x4002 orientation float32 bits
; Returns r1=8.
;
; h[d] = tanh(bias[d] + order[d]*orientation
;             + (1/sqrt(T)) * sum_i gate[pos_i][d] * embed[token_i][d])
mth_context_encode:
  MOVI r12,@mth_ce_link
  ST r15,r12,0
  MOVI r10,0x4001
  LD r1,r10,0
  MOVI r12,@mth_ce_T
  ST r1,r12,0
  MOVI r10,0x4002
  LD r2,r10,0
  MOVI r12,@mth_ce_orient
  ST r2,r12,0

  ; h = bias + order*orientation
  MOVI r6,0
mth_ce_init:
  MOVI r7,8
  CMP r6,r7
  JMP[GE] @mth_ce_sum
  MOVI r10,0x7380
  ADD r10,r10,r6
  LD r8,r10,0
  MOVI r10,0x7390
  ADD r10,r10,r6
  LD r9,r10,0
  MOVI r12,@mth_ce_orient
  LD r12,r12,0
  FMUL r9,r9,r12
  FADD r8,r8,r9
  MOVI r10,0x73A0
  ADD r10,r10,r6
  ST r8,r10,0
  ADDI r6,r6,1
  JMP @mth_ce_init

  ; norm = 1/sqrt(T)
mth_ce_sum:
  MOVI r10,@mth_ce_T
  LD r1,r10,0
  CVTFI r1,r1
  FSQRT r1,r1
  MOVI r2,0
  MOVHI r2,0x3F80
  FDIV r2,r2,r1
  MOVI r12,@mth_ce_norm
  ST r2,r12,0

  MOVI r10,@mth_ce_i
  ST r0,r10,0
mth_ce_token:
  MOVI r10,@mth_ce_T
  LD r3,r10,0
  MOVI r10,@mth_ce_i
  LD r4,r10,0
  CMP r4,r3
  JMP[GE] @mth_ce_done
  MOVI r10,0x7000
  ADD r10,r10,r4
  LD r5,r10,0          ; token id
  MOVI r10,0x7400
  ADD r10,r10,r4
  LD r6,r10,0          ; position slot
  MOVI r7,0
mth_ce_d:
  MOVI r8,8
  CMP r7,r8
  JMP[GE] @mth_ce_next
  MOVI r9,8
  MUL r9,r5,r9
  ADD r9,r9,r7
  MOVI r10,0x7100
  ADD r10,r10,r9
  LD r9,r10,0          ; embedding
  MOVI r10,8
  MUL r10,r6,r10
  ADD r10,r10,r7
  MOVI r11,0x7300
  ADD r11,r11,r10
  LD r11,r11,0         ; gate
  FMUL r9,r9,r11
  MOVI r12,@mth_ce_norm
  LD r12,r12,0
  FMUL r9,r9,r12
  MOVI r10,0x73A0
  ADD r10,r10,r7
  LD r11,r10,0
  FADD r11,r11,r9
  ST r11,r10,0
  ADDI r7,r7,1
  JMP @mth_ce_d
mth_ce_next:
  MOVI r10,@mth_ce_i
  LD r4,r10,0
  ADDI r4,r4,1
  ST r4,r10,0
  JMP @mth_ce_token

mth_ce_done:
  MOVI r6,0
mth_ce_tanh:
  MOVI r7,8
  CMP r6,r7
  JMP[GE] @mth_ce_out
  MOVI r10,0x73A0
  ADD r10,r10,r6
  LD r8,r10,0
  FTANH r8,r8
  ST r8,r10,0
  ADDI r6,r6,1
  JMP @mth_ce_tanh
mth_ce_out:
  MOVI r1,8
  MOVI r13,1
  MOVI r12,@mth_ce_link
  LD r15,r12,0
  RET
mth_ce_link:
  .word 0
mth_ce_T:
  .word 0
mth_ce_orient:
  .word 0
mth_ce_i:
  .word 0
mth_ce_norm:
  .word 0
