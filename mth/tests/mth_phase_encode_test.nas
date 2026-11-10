.org 0
JMP @mth_phase_test_main
.include "../nan16/mth_phase_encode.nas"
.include "../nan16/mth_q16_sin_cos.nas"

mth_phase_test_main:
  MOVI r13,1
  ; input bytes 0,1,2 at 0x7000
  MOVI r1,0x7000
  ST r0,r1,0
  MOVI r2,1
  ST r2,r1,1
  MOVI r2,2
  ST r2,r1,2

  MOVI r1,0x7000
  MOVI r2,3
  MOVI r3,0x5000
  CALL @mth_phase_encode

  ; lane 0 is phase 0: cos ~ 65536, sin ~ 0
  MOVI r10,0x5000
  LD r11,r10,0
  MOVI r12,65000
  CMP r11,r12
  JMP[LT] @mth_phase_fail_cos
  LD r11,r10,1
  MOVI r12,64
  CMPS r11,r12
  JMP[GT] @mth_phase_fail_sin1
  MOVI r12,64
  SUB r12,r0,r12
  CMPS r11,r12
  JMP[LT] @mth_phase_fail_sin2

  ; nonzero complex energy in lane 1
  LD r11,r10,4
  LD r12,r10,5
  ADD r11,r11,r12
  CMP r11,r0
  JMP[EQ] @mth_phase_fail_lane
  ; shard must be 0..15
  MOVI r12,15
  CMP r1,r12
  JMP[GT] @mth_phase_fail_shard
  MOVI r1,@mth_phase_pass
  CALL @mth_phase_puts
  HALT
mth_phase_fail_cos:
  MOVI r1,@mth_phase_bad_cos
  CALL @mth_phase_puts
  HALT
mth_phase_fail_sin1:
  MOVI r1,@mth_phase_bad_sin1
  CALL @mth_phase_puts
  HALT
mth_phase_fail_sin2:
  MOVI r1,@mth_phase_bad_sin2
  CALL @mth_phase_puts
  HALT
mth_phase_fail_lane:
  MOVI r1,@mth_phase_bad_lane
  CALL @mth_phase_puts
  HALT
mth_phase_fail_shard:
  MOVI r1,@mth_phase_bad_shard
  CALL @mth_phase_puts
  HALT

mth_phase_puts:
  MOVI r4,255
mth_phase_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_phase_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_phase_puts_byte
  ADD r1,r1,r13
  JMP @mth_phase_puts_word

mth_phase_pass:
.str "MTH PHASE ENCODE PASS\n"
mth_phase_bad_cos:
.str "MTH PHASE ENCODE FAIL COS\n"
mth_phase_bad_sin1:
.str "MTH PHASE ENCODE FAIL SIN1\n"
mth_phase_bad_sin2:
.str "MTH PHASE ENCODE FAIL SIN2\n"
mth_phase_bad_lane:
.str "MTH PHASE ENCODE FAIL LANE\n"
mth_phase_bad_shard:
.str "MTH PHASE ENCODE FAIL SHARD\n"
