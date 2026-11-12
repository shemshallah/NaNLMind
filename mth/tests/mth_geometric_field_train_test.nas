; End-to-end raw NaN16 TRAIL -> triad 2/3 -> field 43/85
; -> transactional coefficient/eligibility update.
; All Q16.16 arithmetic executes inside the canonical guest.
.org 0
JMP @mth_gcf_test_main
.include "../drivers/field_driver_base.nas"

mth_gcf_test_main:
  MOVI r13,1
  MOVI r12,@mth_gcf_index
  ST r0,r12,0
mth_gcf_seed:
  MOVI r12,@mth_gcf_index
  LD r8,r12,0
  MOVI r9,255
  CMP r8,r9
  JMP[GE] @mth_gcf_stale
  MOVI r9,9
  MUL r10,r8,r9
  MOVI r9,0xD000
  ADD r10,r10,r9

  MOVI r11,0
  MOVI r9,129
  CMP r8,r9
  JMP[GE] @mth_gcf_seed_reward
  MOVI r11,0x8000       ; +0.5
mth_gcf_seed_reward:
  MOVI r9,2
  CMP r8,r9
  JMP[NE] @mth_gcf_seed_store
  MOVI r11,0x8000
  MOVHI r11,0xFFFF      ; -0.5, minority of triad zero
mth_gcf_seed_store:
  ST r11,r10,0
  ST r0,r10,1
  ST r0,r10,2
  ST r0,r10,3
  ST r0,r10,4
  MOVI r11,0
  MOVHI r11,1          ; g+ = +1.0
  ST r11,r10,5
  ST r0,r10,6         ; g- = zero
  MOVI r11,0xE666    ; gamma ~= 0.9
  ST r11,r10,7
  MOVI r11,0xCCCC    ; lambda ~= 0.8
  ST r11,r10,8

  MOVI r9,0xE600
  ADD r9,r9,r8
  ST r0,r9,0
  MOVI r9,0xE700
  ADD r9,r9,r8
  ST r0,r9,0
  MOVI r9,0xE800
  ADD r9,r9,r8
  ST r0,r9,0
  ADDI r8,r8,1
  ST r8,r12,0
  JMP @mth_gcf_seed

mth_gcf_stale:
  MOVI r10,0x4000
  MOVI r11,41
  ST r11,r10,0
  MOVI r11,0x1000      ; |credit| > 0.0625
  ST r11,r10,1
  MOVI r11,0x4000      ; rate = 0.25
  ST r11,r10,2
  MOVI r11,1           ; expected generation=1, actual=0
  ST r11,r10,3
  ST r0,r10,4
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  MOVI r12,43
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,1
  CMP r11,r0
  JMP[NE] @mth_gcf_fail
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_gcf_fail
  MOVI r10,0xE800
  LD r11,r10,0
  CMP r11,r0
  JMP[NE] @mth_gcf_fail
  MOVI r10,0xE600
  LD r11,r10,0
  CMP r11,r0
  JMP[NE] @mth_gcf_fail

mth_gcf_commit:
  MOVI r10,0x4003
  ST r0,r10,0         ; generation fresh
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  MOVI r12,43
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,1
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,2
  MOVI r12,128       ; group0: only two + sign voters
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,3
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  MOVI r10,0xE800
  LD r11,r10,0
  MOVI r12,0x2000
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,1
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_gcf_fail
  MOVI r10,0xE600
  LD r11,r10,0
  MOVI r12,0
  MOVHI r12,1
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_gcf_fail

mth_gcf_below_field:
  ; Remove three votes from group42 => only 42 approving triads.
  MOVI r10,126
mth_gcf_clear_last:
  MOVI r11,129
  CMP r10,r11
  JMP[GE] @mth_gcf_run_rejected
  MOVI r11,9
  MUL r12,r10,r11
  MOVI r11,0xD000
  ADD r12,r12,r11
  ST r0,r12,0
  ADDI r10,r10,1
  JMP @mth_gcf_clear_last
mth_gcf_run_rejected:
  CALL @field_driver_main
  MOVI r10,0x4010
  LD r11,r10,0
  MOVI r12,42
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  LD r11,r10,1
  CMP r11,r0
  JMP[NE] @mth_gcf_fail
  LD r11,r10,2
  CMP r11,r0
  JMP[NE] @mth_gcf_fail
  LD r11,r10,3
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  MOVI r10,0xE800
  LD r11,r10,0
  MOVI r12,0x2000
  CMP r11,r12
  JMP[NE] @mth_gcf_fail
  MOVI r10,0xE600
  LD r11,r10,0
  MOVI r12,0
  MOVHI r12,1
  CMP r11,r12
  JMP[NE] @mth_gcf_fail

  MOVI r1,@mth_gcf_pass
  CALL @mth_gcf_puts
  HALT
mth_gcf_fail:
  MOVI r1,@mth_gcf_bad
  CALL @mth_gcf_puts
  HALT

mth_gcf_puts:
  MOVI r4,255
mth_gcf_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_gcf_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_gcf_puts_byte
  ADD r1,r1,r13
  JMP @mth_gcf_puts_word

mth_gcf_index:
  .word 0
mth_gcf_pass:
  .str "MTH GEOMETRIC FIELD TRAIN PASS\n"
mth_gcf_bad:
  .str "MTH GEOMETRIC FIELD TRAIN FAIL\n"
