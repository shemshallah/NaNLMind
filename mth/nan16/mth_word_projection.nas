; Raw NaN16 full-vocabulary word projection.
;
; One sparse count matrix over word IDs:
;   0x00700000  unigram counts, V words
;   0x00800000  bigram counts, V*V words (row = previous word ID)
;   0x00060000  host-supplied training token IDs (N words)
;   0x00701000  top-5 scratch
;
; Evaluation is the same interpolated add-alpha model used by the reference
; word baseline:
;   pu(w) = (unigram[w]+alpha)/(N+alpha*V)
;   pb(w) = (bigram[ctx,w]+alpha)/(row_total+alpha*V)
;   p(w)  = lambda*pb + (1-lambda)*pu, lambda=0.7, alpha=0.01
;
; ABI:
;   build: r1=N, r2=V, r3=token base. Returns r1=N.
;   top5:  r1=target, r2=context word ID, r3=V, r4=N.
;          Returns r1..r5 word IDs and r6=natural-log target loss.

; Build unigram and bigram counts from N token IDs.
mth_word_build:
  MOVI r12,@mwd_build_link
  ST r15,r12,0
  MOVI r12,@mwd_build_n
  ST r1,r12,0
  MOVI r12,@mwd_build_v
  ST r2,r12,0
  MOVI r12,@mwd_build_base
  ST r3,r12,0

  ; unigram pass
  MOVI r10,0
mwd_uni_loop:
  MOVI r12,@mwd_build_n
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mwd_uni_done
  MOVI r12,@mwd_build_base
  LD r13,r12,0
  ADD r13,r13,r10
  LD r14,r13,0
  MOVI r12,0x0000
  MOVHI r12,0x0070
  ADD r12,r12,r14
  LD r13,r12,0
  ADDI r13,r13,1
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @mwd_uni_loop
mwd_uni_done:

  ; bigram pass
  MOVI r10,1
mwd_bi_loop:
  MOVI r12,@mwd_build_n
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mwd_bi_done
  MOVI r12,@mwd_build_base
  LD r13,r12,0
  ADDI r14,r10,-1
  ADD r13,r13,r14
  LD r14,r13,0
  MOVI r12,@mwd_build_v
  LD r13,r12,0
  MUL r14,r14,r13
  MOVI r12,@mwd_build_base
  LD r13,r12,0
  ADD r13,r13,r10
  LD r13,r13,0
  ADD r14,r14,r13
  MOVI r12,0x0000
  MOVHI r12,0x0080
  ADD r12,r12,r14
  LD r13,r12,0
  ADDI r13,r13,1
  ST r13,r12,0
  ADDI r10,r10,1
  JMP @mwd_bi_loop
mwd_bi_done:
  MOVI r12,@mwd_build_n
  LD r1,r12,0
  MOVI r12,@mwd_build_link
  LD r15,r12,0
  RET

; Full-vocabulary interpolated top-5.
mth_word_top5:
  MOVI r12,@mwd_top_link
  ST r15,r12,0
  MOVI r12,@mwd_target
  ST r1,r12,0
  MOVI r12,@mwd_ctx
  ST r2,r12,0
  MOVI r12,@mwd_v
  ST r3,r12,0
  MOVI r12,@mwd_n
  ST r4,r12,0

  ; row_total = sum bigram[ctx,w]
  MOVI r12,@mwd_ctx
  LD r6,r12,0
  MOVI r12,@mwd_v
  LD r7,r12,0
  MUL r6,r6,r7
  MOVI r7,0x0000
  MOVHI r7,0x0080
  ADD r6,r6,r7
  MOVI r12,@mwd_row
  ST r6,r12,0
  MOVI r10,0
  MOVI r9,0
mwd_row_sum:
  MOVI r12,@mwd_v
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mwd_row_sum_done
  MOVI r12,@mwd_row
  LD r13,r12,0
  ADD r13,r13,r10
  LD r14,r13,0
  ADD r9,r9,r14
  ADDI r10,r10,1
  JMP @mwd_row_sum
mwd_row_sum_done:
  MOVI r12,@mwd_row_total
  ST r9,r12,0

  ; alphaV = alpha*V
  MOVI r12,@mwd_v
  LD r6,r12,0
  CVTIF r6,r6
  MOVI r12,@mwd_alpha
  LD r7,r12,0
  FMUL r6,r6,r7
  MOVI r12,@mwd_alphav
  ST r6,r12,0

  ; unigram denominator = N + alphaV
  MOVI r12,@mwd_n
  LD r6,r12,0
  CVTIF r6,r6
  MOVI r12,@mwd_alphav
  LD r7,r12,0
  FADD r6,r6,r7
  MOVI r12,@mwd_uden
  ST r6,r12,0

  ; bigram denominator = row_total + alphaV
  MOVI r12,@mwd_row_total
  LD r6,r12,0
  CVTIF r6,r6
  MOVI r12,@mwd_alphav
  LD r7,r12,0
  FADD r6,r6,r7
  MOVI r12,@mwd_bden
  ST r6,r12,0

  ; clear top-5
  MOVI r10,0
mwd_clear:
  MOVI r12,5
  CMP r10,r12
  JMP[GE] @mwd_clear_done
  MOVI r12,0x1000
  MOVHI r12,0x0070
  ADD r12,r12,r10
  MOVI r13,0
  MOVHI r13,0xBF80
  ST r13,r12,0
  MOVI r12,0x1100
  MOVHI r12,0x0070
  ADD r12,r12,r10
  ST r0,r12,0
  ADDI r10,r10,1
  JMP @mwd_clear
mwd_clear_done:
  MOVI r12,@mwd_targp
  ST r0,r12,0

  ; scan all V words
  MOVI r10,0
mwd_scan:
  MOVI r12,@mwd_v
  LD r11,r12,0
  CMP r10,r11
  JMP[GE] @mwd_scan_done

  ; unigram probability
  MOVI r12,0x0000
  MOVHI r12,0x0070
  ADD r12,r12,r10
  LD r14,r12,0
  CVTIF r14,r14
  MOVI r12,@mwd_alpha
  LD r13,r12,0
  FADD r14,r14,r13
  MOVI r12,@mwd_uden
  LD r13,r12,0
  FDIV r14,r14,r13

  ; bigram probability
  MOVI r12,@mwd_row
  LD r13,r12,0
  ADD r13,r13,r10
  LD r15,r13,0
  CVTIF r15,r15
  MOVI r12,@mwd_alpha
  LD r13,r12,0
  FADD r15,r15,r13
  MOVI r12,@mwd_bden
  LD r13,r12,0
  FDIV r15,r15,r13

  ; p = lambda*pb + (1-lambda)*pu
  MOVI r12,@mwd_lambda
  LD r13,r12,0
  FMUL r15,r15,r13
  MOVI r12,@mwd_one_minus
  LD r13,r12,0
  FMUL r14,r14,r13
  FADD r15,r15,r14

  ; target probability
  MOVI r12,@mwd_target
  LD r13,r12,0
  CMP r13,r10
  JMP[NE] @mwd_not_target
  MOVI r12,@mwd_targp
  ST r15,r12,0
mwd_not_target:
  ; insert by probability, ties lower ID
  MOVI r11,4
mwd_find:
  CMPS r11,r0
  JMP[LT] @mwd_insert
  MOVI r12,0x1000
  MOVHI r12,0x0070
  ADD r12,r12,r11
  LD r9,r12,0
  FCMP r15,r9
  JMP[GT] @mwd_find_prev
  JMP @mwd_insert
mwd_find_prev:
  ADDI r11,r11,-1
  JMP @mwd_find
mwd_insert:
  ADDI r11,r11,1
  MOVI r12,4
  CMP r11,r12
  JMP[GT] @mwd_next
  MOVI r9,4
mwd_shift:
  CMP r9,r11
  JMP[LE] @mwd_shift_done
  MOVI r12,0x1000
  MOVHI r12,0x0070
  ADD r12,r12,r9
  MOVI r13,0x1000
  MOVHI r13,0x0070
  ADDI r14,r9,-1
  ADD r13,r13,r14
  LD r8,r13,0
  ST r8,r12,0
  MOVI r12,0x1100
  MOVHI r12,0x0070
  ADD r12,r12,r9
  MOVI r13,0x1100
  MOVHI r13,0x0070
  ADD r13,r13,r14
  LD r8,r13,0
  ST r8,r12,0
  ADDI r9,r9,-1
  JMP @mwd_shift
mwd_shift_done:
  MOVI r12,0x1000
  MOVHI r12,0x0070
  ADD r12,r12,r11
  ST r15,r12,0
  MOVI r12,0x1100
  MOVHI r12,0x0070
  ADD r12,r12,r11
  ST r10,r12,0
mwd_next:
  ADDI r10,r10,1
  JMP @mwd_scan
mwd_scan_done:
  ; loss = -ln(target probability)
  MOVI r12,@mwd_targp
  LD r7,r12,0
  FLOG r7,r7
  FSUB r7,r0,r7
  MOVI r12,@mwd_loss
  ST r7,r12,0
  MOVI r12,0x1100
  MOVHI r12,0x0070
  LD r1,r12,0
  LD r2,r12,1
  LD r3,r12,2
  LD r4,r12,3
  LD r5,r12,4
  MOVI r12,@mwd_loss
  LD r6,r12,0
  MOVI r12,@mwd_top_link
  LD r15,r12,0
  RET

mwd_alpha:
  .word 0x3C23D70A
mwd_lambda:
  .word 0x3F333333
mwd_one_minus:
  .word 0x3E99999A
mwd_build_link:
  .word 0
mwd_build_n:
  .word 0
mwd_build_v:
  .word 0
mwd_build_base:
  .word 0
mwd_top_link:
  .word 0
mwd_target:
  .word 0
mwd_ctx:
  .word 0
mwd_v:
  .word 0
mwd_n:
  .word 0
mwd_row:
  .word 0
mwd_row_total:
  .word 0
mwd_alphav:
  .word 0
mwd_uden:
  .word 0
mwd_bden:
  .word 0
mwd_targp:
  .word 0
mwd_loss:
  .word 0
