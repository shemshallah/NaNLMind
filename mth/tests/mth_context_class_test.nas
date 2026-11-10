.org 0
JMP @mth_cc_test_main
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_cft_credit.nas"
.include "../nan16/mth_context_class.nas"

; Deterministic fixture for the context 16x16 -> canonical 255-head link.
;
; Table layout: 4 buckets. High class 8 (score 1.0) and low class 5
; (score 1.0 under high group 8) must map to class head 133, triad 44,
; member 1. The field has 42 accepted triads before the native CFT credit,
; and the selected head 133 receives +0x2000 which makes triad 44 the
; 43rd accepted triad.
mth_cc_test_main:
  MOVI r13,1

  ; high[8] at 0x100000 + 8*4 + bucket 1 = 0x100021.
  MOVI r10,0
  MOVHI r10,0x0010
  ADDI r10,r10,33
  MOVI r11,0
  MOVHI r11,0x3F80          ; float 1.0
  ST r11,r10,0

  ; low table starts at 0x100000 + 16*4; group 8 offset 8*16*4, row 5*4,
  ; bucket 1 -> 0x100000 + 64 + 512 + 21 = 0x100255.
  MOVI r10,0
  MOVHI r10,0x0010
  ADDI r10,r10,0x255
  ST r11,r10,0

  ; Table mode: high=8, low=5, head=133, triad=44, member=1.
  MOVI r1,0
  MOVHI r1,0x0010
  MOVI r2,4
  MOVI r3,1
  MOVI r4,0                 ; derive low base from high base + 16*B
  MOVI r5,0
  MOVI r6,0
  MOVI r7,0
  CALL @mth_context_pick
  MOVI r10,8
  CMP r5,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,5
  CMP r6,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,133
  CMP r1,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,44
  CMP r2,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,1
  CMP r3,r10
  JMP[NE] @mth_cc_fail
  CMP r4,r0
  JMP[NE] @mth_cc_fail

  ; Clear 255 head credits, then support triads 0..41 (heads 0..125)
  ; and head 132 (triad 44 has one supporting member).
  MOVI r10,0x7000
  MOVI r11,0
  MOVI r12,255
mth_cc_clear:
  ST r0,r10,0
  ADDI r10,r10,1
  ADDI r11,r11,1
  CMP r11,r12
  JMP[LT] @mth_cc_clear

  MOVI r10,0x7000
  MOVI r11,0x2000
  MOVI r12,0
  MOVI r9,126
mth_cc_seed:
  ST r11,r10,0
  ADDI r10,r10,1
  ADDI r12,r12,1
  CMP r12,r9
  JMP[LT] @mth_cc_seed
  MOVI r10,0x7000
  ADDI r10,r10,132
  ST r11,r10,0

  ; Before credit: 42 accepted triads, field rejected, selected triad
  ; (44) has only one supporting member.
  MOVI r1,0x7000
  MOVI r2,0x1000
  MOVI r3,0x7100
  MOVI r4,133
  MOVI r5,0
  CALL @mth_context_field
  MOVI r10,42
  CMP r1,r10
  JMP[NE] @mth_cc_fail
  CMP r2,r0
  JMP[NE] @mth_cc_fail
  CMP r3,r0
  JMP[NE] @mth_cc_fail
  CMP r4,r0
  JMP[NE] @mth_cc_fail
  CMP r5,r0
  JMP[NE] @mth_cc_fail
  MOVI r10,0x7100
  ADDI r10,r10,44
  LD r11,r10,0
  CMP r11,r0
  JMP[NE] @mth_cc_fail

  ; Native CFT credit: error 1.0, rate 0.375 -> +0x2000 to head 133.
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r4,0
  MOVHI r4,1
  MOVI r5,0x6000
  CALL @mth_cft_credit
  MOVI r10,0x2000
  CMP r4,r10
  JMP[NE] @mth_cc_fail
  ADD r11,r4,r0

  ; After credit: triad 44 flips 1/3 -> 2/3, so 43/85 accepts the field.
  MOVI r1,0x7000
  MOVI r2,0x1000
  MOVI r3,0x7100
  MOVI r4,133
  ADD r5,r11,r0
  CALL @mth_context_field
  MOVI r10,43
  CMP r1,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,1
  CMP r2,r10
  JMP[NE] @mth_cc_fail
  CMP r3,r10
  JMP[NE] @mth_cc_fail
  CMP r4,r0
  JMP[NE] @mth_cc_fail
  MOVI r10,0x2000
  CMP r5,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,0x7000
  ADDI r10,r10,133
  LD r11,r10,0
  MOVI r12,0x2000
  CMP r11,r12
  JMP[NE] @mth_cc_fail
  MOVI r10,0x7100
  ADDI r10,r10,44
  LD r11,r10,0
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_cc_fail

  ; Direct-prediction mode still uses the same guest mapping law.
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  MOVI r4,0
  MOVI r5,1
  MOVI r6,15
  MOVI r7,14
  CALL @mth_context_pick
  MOVI r10,254
  CMP r1,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,84
  CMP r2,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,2
  CMP r3,r10
  JMP[NE] @mth_cc_fail
  CMP r4,r0
  JMP[NE] @mth_cc_fail

  ; 15/15 is field head 255, not triad 85.
  MOVI r5,1
  MOVI r6,15
  MOVI r7,15
  CALL @mth_context_pick
  MOVI r10,255
  CMP r1,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,0xFFFF
  CMP r2,r10
  JMP[NE] @mth_cc_fail
  CMP r3,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,1
  CMP r4,r10
  JMP[NE] @mth_cc_fail

  ; The field head 255 is never inserted into a triad or credited.
  MOVI r1,0x7000
  MOVI r2,0x1000
  MOVI r3,0x7100
  MOVI r4,255
  MOVI r5,0
  CALL @mth_context_field
  MOVI r10,43
  CMP r1,r10
  JMP[NE] @mth_cc_fail
  MOVI r10,1
  CMP r2,r10
  JMP[NE] @mth_cc_fail
  CMP r3,r0
  JMP[NE] @mth_cc_fail
  CMP r4,r0
  JMP[NE] @mth_cc_fail
  CMP r5,r0
  JMP[NE] @mth_cc_fail

  MOVI r1,@mth_cc_pass
  CALL @mth_puts
  HALT

mth_cc_fail:
  MOVI r1,@mth_cc_bad
  CALL @mth_puts
  HALT

mth_puts:
  MOVI r4,255
mth_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_puts_byte
  ADD r1,r1,r13
  JMP @mth_puts_word

mth_cc_pass:
.str "MTH CONTEXT CLASS PASS\n"
mth_cc_bad:
.str "MTH CONTEXT CLASS FAIL\n"
