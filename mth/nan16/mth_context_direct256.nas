; Raw NaN16 direct 256-class context counts.
;
; This is a sparse context-indexed histogram readout, not a second language
; model.  It keeps one 256-bin count row per exact 4-byte context and one row
; per hashed 2-byte fallback bucket:
;
;   0x100000  exact rows, 8000 max * 256 float counts
;   0x300000  fallback rows, 16384 max * 256 float counts
;   0x700000  top-5 scratch
;
; The exact table is selected by mth_ctxb_build/select from observed contexts;
; exact keys use their compact slot.  Every other key uses
; (last_two_bytes mod fallback_count) in the fallback table.
;
; ABI:
;   step:  r1=target 0..254, r2=packed k=4 key, r3=exact_count,
;          r4=fallback_count. Returns r1=1, r2=bucket, r3=exact flag.
;   top5:  r1=target 0..254, r2=packed k=4 key, r3=exact_count,
;          r4=fallback_count. Returns r1..r5 classes, r6=natural-log loss.
;
; The smoothing constant is alpha=0.01:
;   P(c|row) = (count[c]+alpha) / (sum_count + alpha*256)
; Ranking is by raw count (alpha is constant), ties by lower class.

.org 0x5000
mth_context_direct_step:
  JMP @mth_ctxd_step_body

.org 0x5200
mth_context_direct_top5:
  JMP @mth_ctxd_top5_body

; r1=key, r2=exact_count, r3=fallback_count
; returns r1=bucket, r2=exact flag.
mth_ctxd_route:
  MOVI r12,@mth_ctxd_link
  ST r15,r12,0
  MOVI r12,@mth_ctxd_key
  ST r1,r12,0
  MOVI r12,@mth_ctxd_exactn
  ST r2,r12,0
  MOVI r12,@mth_ctxd_fallbackn
  ST r3,r12,0
  MOVI r12,@mth_ctxd_key
  LD r1,r12,0
  CALL @mth_ctxb_route
  MOVI r12,@mth_ctxd_exactflag
  ST r2,r12,0
  MOVI r12,@mth_ctxd_bucket
  ST r1,r12,0
  CMP r2,r0
  JMP[NE] @mth_ctxd_route_done
  ; fallback = low16(key) mod fallback_count, offset by exact_count.
  MOVI r12,@mth_ctxd_key
  LD r6,r12,0
  SHL r6,r6,16
  SHR r6,r6,16
  MOVI r12,@mth_ctxd_fallbackn
  LD r7,r12,0
  MODU r6,r6,r7
  MOVI r12,@mth_ctxd_exactn
  LD r7,r12,0
  ADD r6,r6,r7
  MOVI r12,@mth_ctxd_bucket
  ST r6,r12,0
mth_ctxd_route_done:
  MOVI r12,@mth_ctxd_bucket
  LD r1,r12,0
  MOVI r12,@mth_ctxd_exactflag
  LD r2,r12,0
  MOVI r12,@mth_ctxd_link
  LD r15,r12,0
  RET

; r1=target, r2=key, r3=exact_count, r4=fallback_count
mth_ctxd_step_body:
  MOVI r12,@mth_ctxd_step_link
  ST r15,r12,0
  MOVI r12,@mth_ctxd_target
  ST r1,r12,0
  MOVI r12,@mth_ctxd_exactn
  ST r3,r12,0
  MOVI r12,@mth_ctxd_fallbackn
  ST r4,r12,0
  MOVI r12,@mth_ctxd_target
  LD r1,r12,0
  MOVI r12,@mth_ctxd_step_key
  ST r2,r12,0
  MOVI r12,@mth_ctxd_exactn
  LD r2,r12,0
  MOVI r12,@mth_ctxd_fallbackn
  LD r3,r12,0
  MOVI r12,@mth_ctxd_step_key
  LD r1,r12,0
  CALL @mth_ctxd_route
  MOVI r12,@mth_ctxd_step_bucket
  ST r1,r12,0
  MOVI r12,@mth_ctxd_step_exact
  ST r2,r12,0
  ; row base
  CMP r2,r0
  JMP[EQ] @mth_ctxd_step_fallback
  MOVI r12,@mth_ctxd_exactn
  LD r6,r12,0
  ; bucket is already exact slot
  MOVI r7,256
  MUL r6,r1,r7
  MOVI r7,0x0000
  MOVHI r7,0x0010
  ADD r6,r6,r7
  JMP @mth_ctxd_step_row
mth_ctxd_step_fallback:
  MOVI r12,@mth_ctxd_exactn
  LD r7,r12,0
  SUB r6,r1,r7
  MOVI r7,256
  MUL r6,r6,r7
  MOVI r7,0x0000
  MOVHI r7,0x0030
  ADD r6,r6,r7
mth_ctxd_step_row:
  MOVI r12,@mth_ctxd_target
  LD r7,r12,0
  ADD r6,r6,r7
  ; the count is int-valued but stored as float
  MOVI r12,@mth_ctxd_one
  LD r8,r12,0
  LD r9,r6,0
  FADD r9,r9,r8
  ST r9,r6,0
  MOVI r1,1
  MOVI r12,@mth_ctxd_step_bucket
  LD r2,r12,0
  MOVI r12,@mth_ctxd_step_exact
  LD r3,r12,0
  MOVI r12,@mth_ctxd_step_link
  LD r15,r12,0
  RET

; r1=target, r2=key, r3=exact_count, r4=fallback_count
mth_ctxd_top5_body:
  MOVI r12,@mth_ctxd_top_link
  ST r15,r12,0
  MOVI r12,@mth_ctxd_target
  ST r1,r12,0
  MOVI r12,@mth_ctxd_exactn
  ST r3,r12,0
  MOVI r12,@mth_ctxd_fallbackn
  ST r4,r12,0
  MOVI r12,@mth_ctxd_top_key
  ST r2,r12,0
  MOVI r12,@mth_ctxd_target
  LD r1,r12,0
  MOVI r12,@mth_ctxd_top_key
  LD r1,r12,0
  MOVI r12,@mth_ctxd_exactn
  LD r2,r12,0
  MOVI r12,@mth_ctxd_fallbackn
  LD r3,r12,0
  CALL @mth_ctxd_route
  MOVI r12,@mth_ctxd_top_bucket
  ST r1,r12,0
  MOVI r12,@mth_ctxd_top_exact
  ST r2,r12,0
  ; row base
  CMP r2,r0
  JMP[EQ] @mth_ctxd_top_fallback
  MOVI r7,256
  MUL r6,r1,r7
  MOVI r7,0x0000
  MOVHI r7,0x0010
  ADD r6,r6,r7
  JMP @mth_ctxd_top_row
mth_ctxd_top_fallback:
  MOVI r12,@mth_ctxd_exactn
  LD r7,r12,0
  SUB r6,r1,r7
  MOVI r7,256
  MUL r6,r6,r7
  MOVI r7,0x0000
  MOVHI r7,0x0030
  ADD r6,r6,r7
mth_ctxd_top_row:
  MOVI r12,@mth_ctxd_row
  ST r6,r12,0
  ; clear top scores to -1 and classes to 0
  MOVI r10,0
mth_ctxd_top_clear:
  MOVI r12,5
  CMP r10,r12
  JMP[GE] @mth_ctxd_top_clear_done
  MOVI r12,0x0000
  MOVHI r12,0x0070
  ADD r12,r12,r10
  MOVI r13,0
  MOVHI r13,0xBF80
  ST r13,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x0070
  ADD r12,r12,r10
  ST r0,r12,0
  ADDI r10,r10,1
  JMP @mth_ctxd_top_clear
mth_ctxd_top_clear_done:
  ; total=0, scan 256 counts
  MOVI r12,@mth_ctxd_total
  ST r0,r12,0
  MOVI r10,0
mth_ctxd_top_scan:
  MOVI r12,256
  CMP r10,r12
  JMP[GE] @mth_ctxd_top_scan_done
  MOVI r12,@mth_ctxd_row
  LD r13,r12,0
  ADD r13,r13,r10
  LD r7,r13,0
  MOVI r12,@mth_ctxd_total
  LD r8,r12,0
  FADD r8,r8,r7
  ST r8,r12,0
  ; insertion into descending top5, ties lower class first
  MOVI r11,4
mth_ctxd_find:
  CMPS r11,r0
  JMP[LT] @mth_ctxd_insert
  MOVI r12,0x0000
  MOVHI r12,0x0070
  ADD r12,r12,r11
  LD r9,r12,0
  FCMP r7,r9
  JMP[GT] @mth_ctxd_find_prev
  JMP @mth_ctxd_insert
mth_ctxd_find_prev:
  ADDI r11,r11,-1
  JMP @mth_ctxd_find
mth_ctxd_insert:
  ADDI r11,r11,1
  MOVI r12,4
  CMP r11,r12
  JMP[GT] @mth_ctxd_top_next
  MOVI r9,4
mth_ctxd_shift:
  CMP r9,r11
  JMP[LE] @mth_ctxd_shift_done
  MOVI r12,0x0000
  MOVHI r12,0x0070
  ADD r12,r12,r9
  MOVI r13,0x0000
  MOVHI r13,0x0070
  ADDI r14,r9,-1
  ADD r13,r13,r14
  LD r8,r13,0
  ST r8,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x0070
  ADD r12,r12,r9
  MOVI r13,0x0100
  MOVHI r13,0x0070
  ADD r13,r13,r14
  LD r8,r13,0
  ST r8,r12,0
  ADDI r9,r9,-1
  JMP @mth_ctxd_shift
mth_ctxd_shift_done:
  MOVI r12,0x0000
  MOVHI r12,0x0070
  ADD r12,r12,r11
  MOVI r13,@mth_ctxd_cur
  ST r7,r13,0
  ST r7,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x0070
  ADD r12,r12,r11
  ST r10,r12,0
mth_ctxd_top_next:
  ADDI r10,r10,1
  JMP @mth_ctxd_top_scan
mth_ctxd_top_scan_done:
  ; target loss: (count+0.01)/(total+2.56)
  MOVI r12,@mth_ctxd_row
  LD r13,r12,0
  MOVI r12,@mth_ctxd_target
  LD r14,r12,0
  ADD r13,r13,r14
  LD r7,r13,0
  MOVI r12,@mth_ctxd_alpha
  LD r8,r12,0
  FADD r7,r7,r8
  MOVI r12,@mth_ctxd_total
  LD r8,r12,0
  MOVI r12,@mth_ctxd_denom
  LD r9,r12,0
  FADD r8,r8,r9
  FDIV r7,r7,r8
  FLOG r7,r7
  FSUB r7,r0,r7
  MOVI r12,@mth_ctxd_loss
  ST r7,r12,0
  MOVI r12,0x0100
  MOVHI r12,0x0070
  LD r1,r12,0
  LD r2,r12,1
  LD r3,r12,2
  LD r4,r12,3
  LD r5,r12,4
  MOVI r12,@mth_ctxd_loss
  LD r6,r12,0
  MOVI r12,@mth_ctxd_top_link
  LD r15,r12,0
  RET

mth_ctxd_one:
  .word 0x3F800000
mth_ctxd_alpha:
  .word 0x3C23D70A
mth_ctxd_denom:
  .word 0x4023D70A
mth_ctxd_link:
  .word 0
mth_ctxd_key:
  .word 0
mth_ctxd_exactn:
  .word 0
mth_ctxd_fallbackn:
  .word 0
mth_ctxd_exactflag:
  .word 0
mth_ctxd_bucket:
  .word 0
mth_ctxd_step_link:
  .word 0
mth_ctxd_step_key:
  .word 0
mth_ctxd_step_bucket:
  .word 0
mth_ctxd_step_exact:
  .word 0
mth_ctxd_target:
  .word 0
mth_ctxd_row:
  .word 0
mth_ctxd_total:
  .word 0
mth_ctxd_cur:
  .word 0
mth_ctxd_top_link:
  .word 0
mth_ctxd_top_key:
  .word 0
mth_ctxd_top_bucket:
  .word 0
mth_ctxd_top_exact:
  .word 0
mth_ctxd_loss:
  .word 0
