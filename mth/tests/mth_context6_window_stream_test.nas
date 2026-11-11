; Native corpus words -> masked six-slot query with provable target isolation.
.org 0
JMP @win6_test_main
.include "../nan16/mth_context6_window_stream.nas"

win6_test_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r10,@win6_words
  MOVI r11,10
  ST r11,r10,0
  MOVI r11,20
  ST r11,r10,1
  MOVI r11,30
  ST r11,r10,2
  MOVI r11,40
  ST r11,r10,3
  MOVI r11,50
  ST r11,r10,4
  MOVI r11,60
  ST r11,r10,5
  MOVI r11,70
  ST r11,r10,6
  ; Predict NEXT after seven observed words. No target token exists.
  MOVI r1,@win6_words
  MOVI r2,7
  MOVI r3,7
  MOVI r4,0
  MOVI r5,0
  MOVI r6,42
  MOVI r7,42
  MOVI r8,@win6_request
  CALL @mth_context6_window_stream
  CMP r1,r13
  JMP[NE] @win6_test_fail
  MOVI r9,7
  CMP r2,r9
  JMP[NE] @win6_test_fail
  MOVI r9,3
  CMP r3,r9
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request
  MOVI r11,70
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+1
  MOVI r11,50
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+2
  MOVI r11,60
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+3
  MOVI r11,70
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+4
  CMP r10,r0
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+7
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @win6_test_fail

  ; Offline infilling: center3 has target w[3], must NEVER be loaded.
  MOVI r1,@win6_words
  MOVI r2,7
  MOVI r3,3
  MOVI r4,1
  MOVI r5,8192
  MOVI r6,42
  MOVI r7,42
  MOVI r8,@win6_request
  CALL @mth_context6_window_stream
  CMP r1,r13
  JMP[NE] @win6_test_fail
  MOVI r11,63
  CMP r2,r11
  JMP[NE] @win6_test_fail
  MOVI r11,6
  CMP r3,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request
  MOVI r11,8192
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+1
  MOVI r11,10
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+2
  MOVI r11,20
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+3
  MOVI r11,30
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+4
  MOVI r11,50
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+5
  MOVI r11,60
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+6
  MOVI r11,70
  CMP r10,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_request+11
  MOVI r11,255
  CMP r10,r11
  JMP[NE] @win6_test_fail

  ; Change the actual target word in the *source*; selected context MUST
  ; remain exactly bit-identical for masked infill at this position.
  MOVI r11,12345
  ST r11,r0,@win6_words+3
  MOVI r1,@win6_words
  MOVI r2,7
  MOVI r3,3
  MOVI r4,1
  MOVI r5,8192
  MOVI r6,42
  MOVI r7,42
  MOVI r8,@win6_second
  CALL @mth_context6_window_stream
  CMP r1,r13
  JMP[NE] @win6_test_fail
  MOVI r9,0
win6_compare_all:
  MOVI r10,12
  CMP r9,r10
  JMP[GE] @win6_test_stale
  MOVI r10,@win6_request
  ADD r10,r10,r9
  LD r11,r10,0
  MOVI r10,@win6_second
  ADD r10,r10,r9
  LD r12,r10,0
  CMP r11,r12
  JMP[NE] @win6_test_fail
  ADDI r9,r9,1
  JMP @win6_compare_all

win6_test_stale:
  MOVI r11,1111
  ST r11,r0,@win6_second
  MOVI r1,@win6_words
  MOVI r2,7
  MOVI r3,3
  MOVI r4,1
  MOVI r5,8192
  MOVI r6,42
  MOVI r7,41
  MOVI r8,@win6_second
  CALL @mth_context6_window_stream
  CMP r1,r0
  JMP[NE] @win6_test_fail
  MOVI r11,2
  CMP r4,r11
  JMP[NE] @win6_test_fail
  MOVI r11,1111
  LD r10,r0,@win6_second
  CMP r11,r10
  JMP[NE] @win6_test_fail
  ; Causal builder rejects any attempt to predict an observed center.
  MOVI r1,@win6_words
  MOVI r2,7
  MOVI r3,6
  MOVI r4,0
  MOVI r5,0
  MOVI r6,42
  MOVI r7,42
  MOVI r8,@win6_second
  CALL @mth_context6_window_stream
  CMP r1,r0
  JMP[NE] @win6_test_fail
  MOVI r11,1
  CMP r4,r11
  JMP[NE] @win6_test_fail
  LD r10,r0,@win6_second
  MOVI r11,1111
  CMP r10,r11
  JMP[NE] @win6_test_fail

  MOVI r1,@win6_test_pass
  CALL @win6_test_puts
  HALT
win6_test_fail:
  MOVI r1,@win6_test_bad
  CALL @win6_test_puts
  HALT
win6_test_puts:
  MOVI r13,1
  MOVI r4,255
win6_test_puts_word:
  LD r2,r1,0
  MOVI r3,4
win6_test_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @win6_test_puts_byte
  ADD r1,r1,r13
  JMP @win6_test_puts_word
win6_test_pass:
.str "MTH CONTEXT6 STREAM TARGET ISOLATION PASS\n"
win6_test_bad:
.str "MTH CONTEXT6 STREAM TARGET ISOLATION FAIL\n"

.org 30000
win6_words:
  .word 0,0,0,0,0,0,0
win6_request:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
win6_second:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
