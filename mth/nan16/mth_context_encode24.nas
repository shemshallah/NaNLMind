; Raw NaN16 contextual encoder shared by role and sense learners.
;
; Fixed memory:
;   0x7000 tokens[T] word ids 0..63
;   0x8000 word embeddings 64 x 24 float32
;   0x8600 position gates 4 x 24 float32
;   0x8700 bias[24], 0x8720 order[24], 0x8740 output[24]
;   0x7400 positions[T] in 0..3
;   0x4001 T, 0x4002 orientation float32 bits
; Returns r1=8.
;
; h[d] = tanh(bias[d] + order[d]*orientation
;             + (1/sqrt(T)) * sum_i gate[pos_i][d] * embed[token_i][d])
mth_context_encode24:
  MOVI r12,@mth_ce24_link
  ST r15,r12,0
  MOVI r10,0x4001
  LD r1,r10,0
  MOVI r12,@mth_ce24_T
  ST r1,r12,0
  MOVI r10,0x4002
  LD r2,r10,0
  MOVI r12,@mth_ce24_orient
  ST r2,r12,0

  ; h = bias + order*orientation
  MOVI r6,0
mth_ce24_init:
  MOVI r7,24
  CMP r6,r7
  JMP[GE] @mth_ce24_sum
  MOVI r10,0x8700
  ADD r10,r10,r6
  LD r8,r10,0
  MOVI r10,0x8720
  ADD r10,r10,r6
  LD r9,r10,0
  MOVI r12,@mth_ce24_orient
  LD r12,r12,0
  FMUL r9,r9,r12
  FADD r8,r8,r9
  MOVI r10,0x8740
  ADD r10,r10,r6
  ST r8,r10,0
  ADDI r6,r6,1
  JMP @mth_ce24_init

  ; norm = 1/sqrt(T)
mth_ce24_sum:
  MOVI r10,@mth_ce24_T
  LD r1,r10,0
  CVTIF r1,r1
  FSQRT r1,r1
  MOVI r2,0
  MOVHI r2,0x3F80
  FDIV r2,r2,r1
  MOVI r12,@mth_ce24_norm
  ST r2,r12,0

  MOVI r10,@mth_ce24_i
  ST r0,r10,0
mth_ce24_token:
  MOVI r10,@mth_ce24_T
  LD r3,r10,0
  MOVI r10,@mth_ce24_i
  LD r4,r10,0
  CMP r4,r3
  JMP[GE] @mth_ce24_done
  MOVI r10,0x7000
  ADD r10,r10,r4
  LD r5,r10,0          ; token id
  MOVI r10,0x7400
  ADD r10,r10,r4
  LD r6,r10,0          ; position slot
  MOVI r7,0
mth_ce24_d:
  MOVI r8,24
  CMP r7,r8
  JMP[GE] @mth_ce24_next
  MOVI r9,24
  MUL r9,r5,r9
  ADD r9,r9,r7
  MOVI r10,0x8000
  ADD r10,r10,r9
  LD r9,r10,0          ; embedding
  MOVI r10,24
  MUL r10,r6,r10
  ADD r10,r10,r7
  MOVI r11,0x8600
  ADD r11,r11,r10
  LD r11,r11,0         ; gate
  FMUL r9,r9,r11
  MOVI r12,@mth_ce24_norm
  LD r12,r12,0
  FMUL r9,r9,r12
  MOVI r10,0x8740
  ADD r10,r10,r7
  LD r11,r10,0
  FADD r11,r11,r9
  ST r11,r10,0
  ADDI r7,r7,1
  JMP @mth_ce24_d
mth_ce24_next:
  MOVI r10,@mth_ce24_i
  LD r4,r10,0
  ADDI r4,r4,1
  ST r4,r10,0
  JMP @mth_ce24_token

mth_ce24_done:
  MOVI r6,0
mth_ce24_tanh:
  MOVI r7,24
  CMP r6,r7
  JMP[GE] @mth_ce24_out
  MOVI r10,0x8740
  ADD r10,r10,r6
  LD r8,r10,0
  FTANH r8,r8
  ST r8,r10,0
  ADDI r6,r6,1
  JMP @mth_ce24_tanh
mth_ce24_out:
  MOVI r1,24
  MOVI r13,1
  MOVI r12,@mth_ce24_link
  LD r15,r12,0
  RET
mth_ce24_link:
  .word 0
mth_ce24_T:
  .word 0
mth_ce24_orient:
  .word 0
mth_ce24_i:
  .word 0
mth_ce24_norm:
  .word 0
