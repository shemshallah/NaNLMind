; Raw NaN16 full-GPT2-vocabulary token projection.
;
; Context rows: 256 most frequent previous-token IDs plus one fallback row.
; Targets: full V=50,257 GPT-2 token vocabulary. No <unk> target is used.
;
; Layout:
;   0x00100000  bigram counts, rows*V words
;   0x00E00000  unigram counts, V words
;   0x000C0000  row map, 65,536 words: previous token ID -> 0..256
;   0x00060000  host-supplied token IDs (N words)
;   0x00E10000  top-5 scratch
;
; ABI:
;   build: r1=N, r2=V, r3=rows, r4=token base, r5=rowmap base,
;          r6=previous token or 0xFFFFFFFF
;   top5:  r1=target, r2=row, r3=V, r4=N
;          returns r1..r5 token IDs, r6=natural-log target loss.

mth_token_build:
  MOVI r12,@mtp_build_link
  ST r15,r12,0
  MOVI r12,@mtp_n
  ST r1,r12,0
  MOVI r12,@mtp_v
  ST r2,r12,0
  MOVI r12,@mtp_rows
  ST r3,r12,0
  MOVI r12,@mtp_token_base
  ST r4,r12,0
  MOVI r12,@mtp_rowmap_base
  ST r5,r12,0
  MOVI r12,@mtp_prev
  ST r6,r12,0

  ; unigrams
  MOVI r10,0
mtp_uni:
  MOVI r12,@mtp_n
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mtp_uni_done
  MOVI r12,@mtp_token_base
  LD r13,r12,0
  ADD r13,r13,r10
  LD r14,r13,0
  MOVI r12,0x0000
  MOVHI r12,0x00E0
  ADD r12,r12,r14
  LD r13,r12,0
  ADDI r13,r13,1
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @mtp_uni
mtp_uni_done:

  ; boundary from previous chunk
  MOVI r12,@mtp_prev
  LD r10,r12,0
  MOVI r12,0xFFFF
  MOVHI r12,0xFFFF
  CMP r10,r12
  JMP[EQ] @mtp_internal
  MOVI r12,@mtp_token_base
  LD r13,r12,0
  LD r14,r13,0          ; first target
  MOVI r12,@mtp_rowmap_base
  LD r13,r12,0
  ADD r13,r13,r10
  LD r10,r13,0          ; row
  MOVI r12,@mtp_v
  LD r13,r12,0
  MUL r10,r10,r13
  ADD r10,r10,r14
  MOVI r12,0x0000
  MOVHI r12,0x0010
  ADD r12,r12,r10
  LD r13,r12,0
  ADDI r13,r13,1
  ST r13,r12,0

mtp_internal:
  MOVI r10,1
mtp_bi:
  MOVI r12,@mtp_n
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mtp_done
  ; prev target id
  MOVI r12,@mtp_token_base
  LD r13,r12,0
  ADDI r14,r10,-1
  ADD r13,r13,r14
  LD r14,r13,0
  ; row = rowmap[prev]
  MOVI r12,@mtp_rowmap_base
  LD r13,r12,0
  ADD r13,r13,r14
  LD r14,r13,0
  ; address = bi_base + row*V + current
  MOVI r12,@mtp_v
  LD r13,r12,0
  MUL r14,r14,r13
  MOVI r12,@mtp_token_base
  LD r13,r12,0
  ADD r13,r13,r10
  LD r13,r13,0
  ADD r14,r14,r13
  MOVI r12,0x0000
  MOVHI r12,0x0010
  ADD r12,r12,r14
  LD r13,r12,0
  ADDI r13,r13,1
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @mtp_bi
mtp_done:
  MOVI r12,@mtp_n
  LD r1,r12,0
  MOVI r12,@mtp_build_link
  LD r15,r12,0
  RET

mth_token_top5:
  MOVI r12,@mtp_top_link
  ST r15,r12,0
  MOVI r12,@mtp_target
  ST r1,r12,0
  MOVI r12,@mtp_row
  ST r2,r12,0
  MOVI r12,@mtp_v
  ST r3,r12,0
  MOVI r12,@mtp_n
  ST r4,r12,0

  ; row_total
  MOVI r12,@mtp_row
  LD r6,r12,0
  MOVI r12,@mtp_v
  LD r7,r12,0
  MUL r6,r6,r7
  MOVI r7,0x0000
  MOVHI r7,0x0010
  ADD r6,r6,r7
  MOVI r12,@mtp_rowp
  ST r6,r12,0
  MOVI r10,0
  MOVI r9,0
mtp_sum:
  MOVI r12,@mtp_v
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mtp_sum_done
  MOVI r12,@mtp_rowp
  LD r13,r12,0
  ADD r13,r13,r10
  LD r14,r13,0
  ADD r9,r9,r14
  ADDI r10,r10,1
  JMP @mtp_sum
mtp_sum_done:
  MOVI r12,@mtp_rowtot
  ST r9,r12,0

  ; alphaV
  MOVI r12,@mtp_v
  LD r6,r12,0
  CVTIF r6,r6
  MOVI r12,@mtp_alpha
  LD r7,r12,0
  FMUL r6,r6,r7
  MOVI r12,@mtp_alphav
  ST r6,r12,0
  ; unigram denom
  MOVI r12,@mtp_n
  LD r6,r12,0
  CVTIF r6,r6
  MOVI r12,@mtp_alphav
  LD r7,r12,0
  FADD r6,r6,r7
  MOVI r12,@mtp_uden
  ST r6,r12,0
  ; row denom
  MOVI r12,@mtp_rowtot
  LD r6,r12,0
  CVTIF r6,r6
  MOVI r12,@mtp_alphav
  LD r7,r12,0
  FADD r6,r6,r7
  MOVI r12,@mtp_rden
  ST r6,r12,0

  ; clear top-5
  MOVI r10,0
mtp_clear:
  MOVI r12,5
  CMP r10,r12
  JMP[GE] @mtp_clear_done
  MOVI r12,0x0000
  MOVHI r12,0x00E1
  ADD r12,r12,r10
  MOVI r13,0
  MOVHI r13,0xBF80
  ST r13,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x00E1
  ADD r12,r12,r10
  ST r0,r12,0
  ADDI r10,r10,1
  JMP @mtp_clear
mtp_clear_done:
  MOVI r12,@mtp_targp
  ST r0,r12,0

  MOVI r10,0
mtp_scan:
  MOVI r12,@mtp_v
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mtp_scan_done
  ; unigram probability
  MOVI r12,0x0000
  MOVHI r12,0x00E0
  ADD r12,r12,r10
  LD r14,r12,0
  CVTIF r14,r14
  MOVI r12,@mtp_alpha
  LD r13,r12,0
  FADD r14,r14,r13
  MOVI r12,@mtp_uden
  LD r13,r12,0
  FDIV r14,r14,r13
  ; bigram probability
  MOVI r12,@mtp_rowp
  LD r13,r12,0
  ADD r13,r13,r10
  LD r15,r13,0
  CVTIF r15,r15
  MOVI r12,@mtp_alpha
  LD r13,r12,0
  FADD r15,r15,r13
  MOVI r12,@mtp_rden
  LD r13,r12,0
  FDIV r15,r15,r13
  ; p = .7*b + .3*u
  MOVI r12,@mtp_lambda
  LD r13,r12,0
  FMUL r15,r15,r13
  MOVI r12,@mtp_one_minus
  LD r13,r12,0
  FMUL r14,r14,r13
  FADD r15,r15,r14
  ; target
  MOVI r12,@mtp_target
  LD r13,r12,0
  CMP r13,r10
  JMP[NE] @mtp_not_target
  MOVI r12,@mtp_targp
  ST r15,r12,0
mtp_not_target:
  MOVI r11,4
mtp_find:
  CMPS r11,r0
  JMP[LT] @mtp_insert
  MOVI r12,0x0000
  MOVHI r12,0x00E1
  ADD r12,r12,r11
  LD r9,r12,0
  FCMP r15,r9
  JMP[GT] @mtp_find_prev
  JMP @mtp_insert
mtp_find_prev:
  ADDI r11,r11,-1
  JMP @mtp_find
mtp_insert:
  ADDI r11,r11,1
  MOVI r12,4
  CMP r11,r12
  JMP[GT] @mtp_next
  MOVI r9,4
mtp_shift:
  CMP r9,r11
  JMP[LE] @mtp_shift_done
  MOVI r12,0x0000
  MOVHI r12,0x00E1
  ADD r12,r12,r9
  MOVI r13,0x0000
  MOVHI r13,0x00E1
  ADDI r14,r9,-1
  ADD r13,r13,r14
  LD r8,r13,0
  ST r8,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x00E1
  ADD r12,r12,r9
  MOVI r13,0x0100
  MOVHI r13,0x00E1
  ADD r13,r13,r14
  LD r8,r13,0
  ST r8,r12,0
  ADDI r9,r9,-1
  JMP @mtp_shift
mtp_shift_done:
  MOVI r12,0x0000
  MOVHI r12,0x00E1
  ADD r12,r12,r11
  ST r15,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x00E1
  ADD r12,r12,r11
  ST r10,r12,0
mtp_next:
  ADDI r10,r10,1
  JMP @mtp_scan
mtp_scan_done:
  MOVI r12,@mtp_targp
  LD r7,r12,0
  FLOG r7,r7
  FSUB r7,r0,r7
  MOVI r12,@mtp_loss
  ST r7,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x00E1
  LD r1,r12,0
  LD r2,r12,1
  LD r3,r12,2
  LD r4,r12,3
  LD r5,r12,4
  MOVI r12,@mtp_loss
  LD r6,r12,0
  MOVI r12,@mtp_top_link
  LD r15,r12,0
  RET

mtp_alpha:
  .word 0x3C23D70A
mtp_lambda:
  .word 0x3F333333
mtp_one_minus:
  .word 0x3E99999A
mtp_build_link:
  .word 0
mtp_n:
  .word 0
mtp_v:
  .word 0
mtp_rows:
  .word 0
mtp_token_base:
  .word 0
mtp_rowmap_base:
  .word 0
mtp_prev:
  .word 0
mtp_top_link:
  .word 0
mtp_target:
  .word 0
mtp_row:
  .word 0
mtp_rowp:
  .word 0
mtp_rowtot:
  .word 0
mtp_alphav:
  .word 0
mtp_uden:
  .word 0
mtp_rden:
  .word 0
mtp_targp:
  .word 0
mtp_loss:
  .word 0
