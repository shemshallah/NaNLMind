; Real native 6 private heads => 4 trihead vector/vote/curl cases.
; 3 HOT / 3 COLD / 2 HOT+1 COLD / 1 HOT+2 COLD.
.org 0
JMP @tv_main
.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_hyperedge_poincare128_curl.nas"
.include "../nan16/mth_head16_poincare_vector.nas"
.include "../nan16/mth_triad_hotcold_poincare128.nas"
tv_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r9,1
  ST r9,r0,@tv_head
tv_seed_head:
  LD r9,r0,@tv_head
  MOVI r8,0
  MOVHI r8,0x003B
  SHL r10,r9,8
  ADD r8,r8,r10
  MOVI r10,0
  MOVHI r10,0x3F80
  ST r10,r8,0
  MOVI r10,256              ; rule8 AND=0 when a=1,b=0
  MOVI r11,4
  CMP r9,r11
  JMP[GE] @tv_ish_cold
  MOVI r10,64               ; rule6 XOR=1 when a=1,b=0
tv_ish_cold:
  ST r10,r8,128
  ST r0,r8,129
  MOVI r10,1
  ST r10,r8,130
  ST r0,r8,131
  ST r10,r8,132
  MOVI r10,7
  ST r10,r8,133
  ST r10,r8,134
  ST r9,r8,135
  ADDI r10,r9,1
  ST r10,r8,136
  ADDI r10,r9,2
  ST r10,r8,137
  MOVI r10,0
  MOVHI r10,0x3F00
  ST r10,r8,138
  MOVI r10,1024
  ST r10,r8,139
  ADD r1,r9,r0
  CALL @mth_head16_poincare_measure
  CMP r1,r13
  JMP[NE] @tv_fail
  LD r9,r0,@tv_head
  MOVI r10,4
  CMP r9,r10
  JMP[GE] @tv_expect_cold
  CMP r3,r13
  JMP[NE] @tv_fail
  JMP @tv_next_seed
tv_expect_cold:
  CMP r3,r0
  JMP[NE] @tv_fail
tv_next_seed:
  ADDI r9,r9,1
  MOVI r10,7
  CMP r9,r10
  JMP[GE] @tv_triads
  ST r9,r0,@tv_head
  JMP @tv_seed_head

tv_triads:
  MOVI r9,0
  ST r9,r0,@tv_triad
tv_triad_loop:
  LD r9,r0,@tv_triad
  ADD r1,r9,r0
  MOVI r2,@tv_mapping
  MOVI r3,0
  MOVHI r3,0x3F00       ; real sourced triangle curl +0.5f
  MOVI r4,7
  MOVI r5,7
  MOVI r6,0
  MOVHI r6,1            ; native seven credit +1 Q16
  CALL @mth_triad_hotcold_poincare128
  CMP r1,r13
  JMP[NE] @tv_fail
  MOVI r10,3
  ADD r11,r2,r3
  CMP r11,r10
  JMP[NE] @tv_fail
  LD r9,r0,@tv_triad
  MOVI r10,0xE000
  MOVHI r10,0x003E
  SHL r11,r9,4
  ADD r10,r10,r11
  LD r11,r10,12
  CMP r11,r13
  JMP[NE] @tv_fail
  LD r11,r10,4
  MOVI r12,255
  CMP r11,r12
  JMP[NE] @tv_fail
  LD r11,r10,0
  MOVI r12,0
  FCMP r11,r12
  JMP[LE] @tv_fail
  MOVI r12,0
  MOVHI r12,0x3F80
  FCMP r11,r12
  JMP[GE] @tv_fail
  LD r11,r10,1
  MOVI r12,0
  FCMP r11,r12
  JMP[LE] @tv_fail
  LD r11,r10,10
  MOVI r12,0
  MOVI r9,0
  LD r9,r0,@tv_triad
  MOVI r8,1
  CMP r9,r8
  JMP[EQ] @tv_negative
  MOVI r8,3
  CMP r9,r8
  JMP[EQ] @tv_negative
  FCMP r11,r12
  JMP[LE] @tv_fail
  JMP @tv_sign_done
tv_negative:
  FCMP r11,r12
  JMP[GE] @tv_fail
tv_sign_done:
  MOVI r8,0
  CMP r9,r8
  JMP[NE] @tv_not_allhot
  LD r11,r10,8
  CMP r11,r13
  JMP[NE] @tv_fail
  LD r11,r10,9
  CMP r11,r0
  JMP[NE] @tv_fail
  LD r11,r10,10
  ST r11,r0,@tv_first_gradient
  JMP @tv_next_triad
tv_not_allhot:
  MOVI r8,1
  CMP r9,r8
  JMP[NE] @tv_mixed
  LD r11,r10,8
  CMP r11,r0
  JMP[NE] @tv_fail
  LD r11,r10,9
  CMP r11,r13
  JMP[NE] @tv_fail
  JMP @tv_next_triad
tv_mixed:
  LD r11,r10,8
  CMP r11,r0
  JMP[NE] @tv_fail
  LD r11,r10,9
  CMP r11,r0
  JMP[NE] @tv_fail
tv_next_triad:
  LD r9,r0,@tv_triad
  ADDI r9,r9,1
  MOVI r8,4
  CMP r9,r8
  JMP[GE] @tv_stale
  ST r9,r0,@tv_triad
  JMP @tv_triad_loop

tv_stale:
  ; Reject stale generation without changing existing hot3 gradient.
  MOVI r1,0
  MOVI r2,@tv_mapping
  MOVI r3,0
  MOVHI r3,0x3F00
  MOVI r4,7
  MOVI r5,8
  MOVI r6,0
  MOVHI r6,1
  CALL @mth_triad_hotcold_poincare128
  CMP r1,r0
  JMP[NE] @tv_fail
  MOVI r10,2
  CMP r4,r10
  JMP[NE] @tv_fail
  MOVI r10,0xE00A
  MOVHI r10,0x003E
  LD r11,r10,0            ; trihead0 meta gradient at +10
  LD r10,r0,@tv_first_gradient
  CMP r11,r10
  JMP[NE] @tv_fail
  MOVI r1,@tv_pass
  CALL @tv_puts
  HALT
tv_fail:
  MOVI r1,@tv_bad
  CALL @tv_puts
  HALT
tv_puts:
  MOVI r13,1
  MOVI r4,255
tv_puts_word:
  LD r2,r1,0
  MOVI r3,4
tv_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @tv_puts_byte
  ADD r1,r1,r13
  JMP @tv_puts_word
tv_mapping:
  .word 1,2,3,4,5,6,1,2,4,1,4,5
tv_head:
  .word 0
tv_triad:
  .word 0
tv_first_gradient:
  .word 0
tv_pass:
.str "MTH TRIAD HOTCOLD POINCARE128 PASS\n"
tv_bad:
.str "MTH TRIAD HOTCOLD POINCARE128 FAIL\n"
