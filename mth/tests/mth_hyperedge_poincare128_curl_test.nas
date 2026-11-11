; Native 128D Poincare depth + signed orientation of TRUE Hodge curl.
.org 0
JMP @hp128_test_main
.include "../nan16/mth_hyperedge_poincare128_curl.nas"

hp128_test_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r10,@hp128_test_src
  MOVI r11,0
  MOVHI r11,0x3F80  ; x=+1 float
  ST r11,r10,0
  MOVI r10,@hp128_test_record
  ST r13,r10,0       ; a=1
  MOVI r11,2
  ST r11,r10,1       ; b=2
  MOVI r11,3
  ST r11,r10,2       ; c=3
  MOVI r11,0
  MOVHI r11,0x3F00
  ST r11,r10,3       ; curl=+1/2
  MOVI r11,11
  ST r11,r10,4
  ST r11,r10,5
  MOVI r11,255
  ST r11,r10,6
  ST r13,r10,7
  MOVI r11,777
  ST r11,r0,@hp128_test_dst
  ST r11,r0,@hp128_test_meta
  MOVI r1,@hp128_test_src
  MOVI r2,@hp128_test_dst
  MOVI r3,@hp128_test_record
  MOVI r4,@hp128_test_meta
  CALL @mth_hyperedge_poincare128_curl
  CMP r1,r13
  JMP[NE] @hp128_test_fail
  MOVI r10,128
  CMP r2,r10
  JMP[NE] @hp128_test_fail
  CMP r3,r13
  JMP[NE] @hp128_test_fail
  CMP r4,r0
  JMP[NE] @hp128_test_fail
  MOVI r10,0
  MOVHI r10,0x3F00     ; exactly 0.5
  LD r11,r0,@hp128_test_dst
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_meta
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  MOVI r10,0
  MOVHI r10,0x3E80     ; exactly 0.25 curl*radius
  LD r11,r0,@hp128_test_meta+2
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_meta+3
  CMP r11,r13
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_meta+4
  MOVI r10,255
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_meta+1
  ST r11,r0,@hp128_test_depth_reference
  MOVI r10,0
  MOVHI r10,0x3F80
  FCMP r11,r10
  JMP[LE] @hp128_test_fail ; log(3)>1

  ; Same geometry, inverted oriented curl: sign and feedback reverse,
  ; radial depth remains identical (mirror directions must not collapse).
  MOVI r10,0
  MOVHI r10,0xBF00
  ST r10,r0,@hp128_test_record+3
  MOVI r1,@hp128_test_src
  MOVI r2,@hp128_test_dst
  MOVI r3,@hp128_test_record
  MOVI r4,@hp128_test_meta
  CALL @mth_hyperedge_poincare128_curl
  CMP r1,r13
  JMP[NE] @hp128_test_fail
  MOVI r10,0
  MOVHI r10,0xBE80    ; -0.25
  LD r11,r0,@hp128_test_meta+2
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  MOVI r10,0xFFFF
  MOVHI r10,0xFFFF
  LD r11,r0,@hp128_test_meta+3
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_meta+1
  LD r10,r0,@hp128_test_depth_reference
  CMP r11,r10
  JMP[NE] @hp128_test_fail

  ; Rotate vector by quarter turn (x=0,y=1); depth is invariant.
  ST r0,r0,@hp128_test_src
  MOVI r10,0
  MOVHI r10,0x3F80
  ST r10,r0,@hp128_test_src+1
  MOVI r1,@hp128_test_src
  MOVI r2,@hp128_test_dst
  MOVI r3,@hp128_test_record
  MOVI r4,@hp128_test_meta
  CALL @mth_hyperedge_poincare128_curl
  CMP r1,r13
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_depth_reference
  LD r10,r0,@hp128_test_meta+1
  CMP r10,r11
  JMP[NE] @hp128_test_fail
  LD r10,r0,@hp128_test_dst
  CMP r10,r0
  JMP[NE] @hp128_test_fail
  MOVI r11,0
  MOVHI r11,0x3F00
  LD r10,r0,@hp128_test_dst+1
  CMP r10,r11
  JMP[NE] @hp128_test_fail

  ; Higher norm -> deeper Poincare radius/distance (not learned semantics).
  MOVI r11,0
  MOVHI r11,0x4000
  ST r11,r0,@hp128_test_src+1  ; +2
  MOVI r1,@hp128_test_src
  MOVI r2,@hp128_test_dst
  MOVI r3,@hp128_test_record
  MOVI r4,@hp128_test_meta
  CALL @mth_hyperedge_poincare128_curl
  CMP r1,r13
  JMP[NE] @hp128_test_fail
  LD r10,r0,@hp128_test_meta+1
  LD r11,r0,@hp128_test_depth_reference
  FCMP r10,r11
  JMP[LE] @hp128_test_fail

  ; Rejected bad-vector input leaves ALL output buffers unchanged.
  MOVI r10,777
  ST r10,r0,@hp128_test_dst
  ST r10,r0,@hp128_test_meta
  MOVI r11,0
  MOVHI r11,0x7FC0  ; qNaN
  ST r11,r0,@hp128_test_src+2
  MOVI r1,@hp128_test_src
  MOVI r2,@hp128_test_dst
  MOVI r3,@hp128_test_record
  MOVI r4,@hp128_test_meta
  CALL @mth_hyperedge_poincare128_curl
  CMP r1,r0
  JMP[NE] @hp128_test_fail
  MOVI r10,3
  CMP r4,r10
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_dst
  MOVI r10,777
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_meta
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  ST r0,r0,@hp128_test_src+2

  ; Stale generation also leaves outputs unchanged.
  MOVI r10,12
  ST r10,r0,@hp128_test_record+5
  MOVI r1,@hp128_test_src
  MOVI r2,@hp128_test_dst
  MOVI r3,@hp128_test_record
  MOVI r4,@hp128_test_meta
  CALL @mth_hyperedge_poincare128_curl
  CMP r1,r0
  JMP[NE] @hp128_test_fail
  MOVI r10,2
  CMP r4,r10
  JMP[NE] @hp128_test_fail
  LD r11,r0,@hp128_test_dst
  MOVI r10,777
  CMP r11,r10
  JMP[NE] @hp128_test_fail
  MOVI r1,@hp128_test_pass
  CALL @hp128_test_puts
  HALT

hp128_test_fail:
  MOVI r1,@hp128_test_bad
  CALL @hp128_test_puts
  HALT
hp128_test_puts:
  MOVI r13,1
  MOVI r4,255
hp128_test_puts_word:
  LD r2,r1,0
  MOVI r3,4
hp128_test_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @hp128_test_puts_byte
  ADD r1,r1,r13
  JMP @hp128_test_puts_word
hp128_test_pass:
.str "MTH POINCARE128 HODGE CURL HYPEREDGE PASS\n"
hp128_test_bad:
.str "MTH POINCARE128 HODGE CURL HYPEREDGE FAIL\n"

.org 30000
hp128_test_src:
  .word 0
.org 30200
hp128_test_dst:
  .word 0
.org 30400
hp128_test_record:
  .word 0,0,0,0,0,0,0,0
.org 30500
hp128_test_meta:
  .word 0,0,0,0,0
hp128_test_depth_reference:
  .word 0
