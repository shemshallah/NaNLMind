; Native private-scratch Boolean16 -> CORDIC -> vector -> Poincare
; for multiple heads in same single canonical universe; VOID fails closed.
.org 0
JMP @hphead_test_main
.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_hyperedge_poincare128_curl.nas"
.include "../nan16/mth_head16_poincare_vector.nas"

hphead_test_main:
  MOVI r0,0
  MOVI r13,1
  ; Head1 candidate changes AND (rule8) to XOR (rule6) via XOR patch,
  ; leaving original committed truth mask unchanged.
  MOVI r8,0x0100
  MOVHI r8,0x003B
  MOVI r10,0
  MOVHI r10,0x3F80
  ST r10,r8,0                 ; sourced vector first coordinate 1.0f
  MOVI r10,256
  ST r10,r8,128               ; committed mask 1<<8 = AND
  MOVI r10,320
  ST r10,r8,129               ; 1<<8 xor 1<<6
  MOVI r10,1
  ST r10,r8,130               ; A=1
  ST r0,r8,131                ; B=0
  ST r10,r8,132               ; capability
  MOVI r10,7
  ST r10,r8,133
  ST r10,r8,134
  MOVI r10,1
  ST r10,r8,135
  MOVI r10,2
  ST r10,r8,136
  MOVI r10,3
  ST r10,r8,137
  MOVI r10,0
  MOVHI r10,0x3F00
  ST r10,r8,138               ; signed Hodge face curl +0.5f
  MOVI r10,1024
  ST r10,r8,139
  MOVI r1,1
  CALL @mth_head16_poincare_measure
  CMP r1,r13
  JMP[NE] @hphead_fail
  CMP r2,r13
  JMP[NE] @hphead_fail
  CMP r3,r13
  JMP[NE] @hphead_fail
  MOVI r8,0x0100
  MOVHI r8,0x003B
  LD r10,r8,128
  MOVI r11,256
  CMP r10,r11
  JMP[NE] @hphead_fail
  LD r10,r8,146
  MOVI r11,64
  CMP r10,r11
  JMP[NE] @hphead_fail
  LD r10,r8,141
  MOVI r11,6
  CMP r10,r11
  JMP[NE] @hphead_fail
  LD r10,r8,143
  MOVI r11,0
  MOVHI r11,0x3E80
  CMP r10,r11
  JMP[NE] @hphead_fail     ; +0.25f exact feedback
  LD r10,r8,142
  ST r10,r0,@hphead_saved_depth
  MOVI r11,0
  MOVHI r11,0x3F80
  FCMP r10,r11
  JMP[LE] @hphead_fail
  MOVI r9,0x0100
  MOVHI r9,0x003F
  LD r10,r9,0
  ST r10,r0,@hphead_saved_x
  LD r10,r9,1
  ST r10,r0,@hphead_saved_y
  ; Head2 is a different independent scratch and directed geometry.
  MOVI r8,0x0200
  MOVHI r8,0x003B
  MOVI r10,0
  MOVHI r10,0x4000
  ST r10,r8,0                  ; vector radius derived from 2, not 1
  MOVI r10,256
  ST r10,r8,128                ; AND stays AND
  ST r0,r8,129
  MOVI r10,1
  ST r10,r8,130
  ST r0,r8,131
  ST r10,r8,132
  MOVI r10,7
  ST r10,r8,133
  ST r10,r8,134
  MOVI r10,2
  ST r10,r8,135
  MOVI r10,3
  ST r10,r8,136
  MOVI r10,4
  ST r10,r8,137
  MOVI r10,0
  MOVHI r10,0xBF00
  ST r10,r8,138                  ; opposite Hodge curl
  MOVI r10,4096
  ST r10,r8,139
  MOVI r1,2
  CALL @mth_head16_poincare_measure
  CMP r1,r13
  JMP[NE] @hphead_fail
  CMP r3,r0
  JMP[NE] @hphead_fail           ; AND(1,0)=0 cold
  MOVI r8,0x0200
  MOVHI r8,0x003B
  LD r10,r8,146
  MOVI r11,256
  CMP r10,r11
  JMP[NE] @hphead_fail
  LD r10,r8,142
  LD r11,r0,@hphead_saved_depth
  FCMP r10,r11
  JMP[LE] @hphead_fail
  ; Head1 private scratch and output are not overwritten by head2.
  MOVI r8,0x0100
  MOVHI r8,0x003B
  LD r10,r8,140
  CMP r10,r13
  JMP[NE] @hphead_fail
  LD r10,r8,146
  MOVI r11,64
  CMP r10,r11
  JMP[NE] @hphead_fail
  MOVI r9,0x0100
  MOVHI r9,0x003F
  LD r10,r9,0
  LD r11,r0,@hphead_saved_x
  CMP r10,r11
  JMP[NE] @hphead_fail
  LD r10,r9,1
  LD r11,r0,@hphead_saved_y
  CMP r10,r11
  JMP[NE] @hphead_fail
  ; Physical head255 is NOW/VOID, cannot have any private writer scratch.
  MOVI r1,255
  CALL @mth_head16_poincare_measure
  CMP r1,r0
  JMP[NE] @hphead_fail
  MOVI r10,1
  CMP r4,r10
  JMP[NE] @hphead_fail
  ; Stale version: old candidate leaves vector and candidate mask intact.
  MOVI r8,0x0100
  MOVHI r8,0x003B
  MOVI r10,8
  ST r10,r8,134
  MOVI r1,1
  CALL @mth_head16_poincare_measure
  CMP r1,r0
  JMP[NE] @hphead_fail
  MOVI r10,3
  CMP r4,r10
  JMP[NE] @hphead_fail
  MOVI r8,0x0100
  MOVHI r8,0x003B
  LD r10,r8,146
  MOVI r11,64
  CMP r10,r11
  JMP[NE] @hphead_fail
  MOVI r9,0x0100
  MOVHI r9,0x003F
  LD r10,r9,0
  LD r11,r0,@hphead_saved_x
  CMP r10,r11
  JMP[NE] @hphead_fail
  MOVI r1,@hphead_pass
  CALL @hphead_puts
  HALT
hphead_fail:
  MOVI r1,@hphead_bad
  CALL @hphead_puts
  HALT
hphead_puts:
  MOVI r13,1
  MOVI r4,255
hphead_puts_word:
  LD r2,r1,0
  MOVI r3,4
hphead_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @hphead_puts_byte
  ADD r1,r1,r13
  JMP @hphead_puts_word
hphead_pass:
.str "MTH HEAD16 PRIVATE POINCARE VECTOR PASS\n"
hphead_bad:
.str "MTH HEAD16 PRIVATE POINCARE VECTOR FAIL\n"
hphead_saved_x:
  .word 0
hphead_saved_y:
  .word 0
hphead_saved_depth:
  .word 0
