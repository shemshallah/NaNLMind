; Raw NaN16 real head0/1/2 -> native trihead0 -> 85-vote
; global/meta -> five typed candidate tensor/leaf descriptors.
; Quorum masks for other 84 triheads are FIXTURE CONTROL INPUT, not
; proof those other triheads have been sourced from real observations.
.org 0
JMP @slft_main
.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_hyperedge_poincare128_curl.nas"
.include "../nan16/mth_head16_poincare_vector.nas"
.include "../nan16/mth_triad_hotcold_poincare128.nas"
.include "../nan16/mth_hypertensor256_mirror_arena_map.nas"
.include "../nan16/mth_hypertensor256_mirror_dual_map.nas"
.include "../nan16/mth_native_symbiotic_leaf_feedback.nas"

slft_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r9,0
  ST r9,r0,@slft_h
  MOVI r9,1
  ST r9,r0,@slft_stage
slft_head_loop:
  LD r9,r0,@slft_h
  MOVI r10,0
  MOVHI r10,0x003B
  SHL r11,r9,8
  ADD r10,r10,r11
  MOVI r11,0
  MOVHI r11,0x3F80
  ST r11,r10,0
  MOVI r11,64           ; XOR function, hot 1 xor 0 = 1
  MOVI r12,2
  CMP r9,r12
  JMP[LT] @slft_rule_set
  MOVI r11,256          ; AND function, cold 1 and 0 = 0
slft_rule_set:
  ST r11,r10,128
  ST r0,r10,129
  MOVI r11,1
  ST r11,r10,130
  ST r0,r10,131
  ST r11,r10,132
  MOVI r11,7
  ST r11,r10,133
  ST r11,r10,134
  ST r0,r10,135
  MOVI r11,1
  ST r11,r10,136
  MOVI r11,2
  ST r11,r10,137
  MOVI r11,0
  MOVHI r11,0x3F00
  ST r11,r10,138
  MOVI r11,2048
  ST r11,r10,139
  ADD r1,r9,r0
  CALL @mth_head16_poincare_measure
  CMP r1,r13
  JMP[NE] @slft_fail
  LD r9,r0,@slft_h
  ADDI r9,r9,1
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @slft_trihead
  ST r9,r0,@slft_h
  JMP @slft_head_loop

slft_trihead:
  MOVI r14,2
  ST r14,r0,@slft_stage
  ; Initialize the same unique 255-member map BEFORE native trihead
  ; preflight; zero-filled mapping would repeat head 0 three times.
  MOVI r9,0
slft_map_loop:
  MOVI r10,255
  CMP r9,r10
  JMP[GE] @slft_native_trihead
  MOVI r10,@slft_mapping
  ADD r10,r10,r9
  ST r9,r10,0
  ADDI r9,r9,1
  JMP @slft_map_loop
slft_native_trihead:
  MOVI r14,3
  ST r14,r0,@slft_stage
  ; Native measured trihead0 (2 hot 1 cold), same source + generation.
  MOVI r1,0
  MOVI r2,@slft_mapping
  MOVI r3,0
  MOVHI r3,0x3F00
  MOVI r4,7
  MOVI r5,7
  MOVI r6,0
  MOVHI r6,1
  CALL @mth_triad_hotcold_poincare128
  CMP r1,r13
  JMP[NE] @slft_fail
  MOVI r10,2
  CMP r2,r10
  JMP[NE] @slft_fail
  CMP r3,r13
  JMP[NE] @slft_fail

  ; The same native head permutation was initialized before trihead use.
slft_votes:
  MOVI r14,4
  ST r14,r0,@slft_stage
  MOVI r9,0
slft_vote_loop:
  MOVI r10,85
  CMP r9,r10
  JMP[GE] @slft_permissions
  MOVI r10,@slft_votes
  ADD r10,r10,r9
  MOVI r11,3
  ST r11,r10,0          ; 2-of-3 mocked quorum for OTHER 84 triheads
  ADDI r9,r9,1
  JMP @slft_vote_loop
slft_permissions:
  MOVI r9,0
slft_permissions_loop:
  MOVI r10,255
  CMP r9,r10
  JMP[GE] @slft_request
  MOVI r10,@slft_writers
  ADD r10,r10,r9
  MOVI r11,0
  MOVI r12,3
  CMP r9,r12
  JMP[GE] @slft_writer_set
  MOVI r11,1
slft_writer_set:
  ST r11,r10,0
  ADDI r9,r9,1
  JMP @slft_permissions_loop
slft_request:
  MOVI r14,5
  ST r14,r0,@slft_stage
  MOVI r10,@slft_req
  ST r0,r10,0
  MOVI r11,7
  ST r11,r10,1
  ST r11,r10,2
  ST r13,r10,3
  ST r13,r10,4
  MOVI r11,@slft_votes
  ST r11,r10,5
  MOVI r11,@slft_mapping
  ST r11,r10,6
  MOVI r11,@slft_writers
  ST r11,r10,7
  MOVI r11,@slft_scratch
  ST r11,r10,8
  MOVI r11,@slft_output
  ST r11,r10,9
  MOVI r11,@slft_sha
  ST r11,r10,10
  MOVI r11,1000
  ST r11,r10,11
  MOVI r11,54321
  ST r11,r0,@slft_output
  MOVI r1,@slft_req
  CALL @mth_native_symbiotic_leaf_feedback
  CMP r1,r13
  JMP[NE] @slft_fail
  MOVI r11,85
  CMP r2,r11
  JMP[NE] @slft_fail
  MOVI r11,5
  CMP r3,r11
  JMP[NE] @slft_fail
  CMP r4,r0
  JMP[NE] @slft_fail

  ; Three independent head diagonal leaf descriptors.
  MOVI r9,0
slft_test_head_records:
  MOVI r14,6
  ST r14,r0,@slft_stage
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @slft_test_triad_records
  MOVI r10,12
  MUL r10,r9,r10
  MOVI r11,@slft_output
  ADD r10,r10,r11
  LD r11,r10,0
  CMP r11,r9
  JMP[NE] @slft_fail
  LD r11,r10,1
  CMP r11,r9
  JMP[NE] @slft_fail
  LD r11,r10,2
  CMP r11,r9
  JMP[NE] @slft_fail
  LD r11,r10,3
  CMP r11,r9
  JMP[NE] @slft_fail
  LD r11,r10,4
  MOVI r12,0
  MOVHI r12,0x0400      ; candidate bank begins 64MiB
  CMP r11,r12
  JMP[LT] @slft_fail
  LD r11,r10,6
  CMP r11,r13
  JMP[NE] @slft_fail
  LD r11,r10,8
  MOVI r12,128
  CMP r11,r12
  JMP[NE] @slft_fail
  LD r11,r10,9
  MOVI r12,7
  CMP r11,r12
  JMP[NE] @slft_fail
  ADDI r9,r9,1
  JMP @slft_test_head_records
slft_test_triad_records:
  MOVI r14,7
  ST r14,r0,@slft_stage
  MOVI r10,@slft_output
  MOVI r11,36
  ADD r10,r10,r11
  LD r11,r10,0
  CMP r11,r0
  JMP[NE] @slft_fail
  LD r11,r10,1
  CMP r11,r0
  JMP[NE] @slft_fail
  LD r11,r10,2
  CMP r11,r13
  JMP[NE] @slft_fail
  LD r11,r10,3
  CMP r11,r13
  JMP[NE] @slft_fail
  LD r11,r10,6
  MOVI r12,2
  CMP r11,r12
  JMP[NE] @slft_fail
  LD r11,r10,8
  MOVI r12,128
  CMP r11,r12
  JMP[NE] @slft_fail
  MOVI r10,@slft_output
  MOVI r11,48
  ADD r10,r10,r11
  LD r11,r10,2
  MOVI r12,2
  CMP r11,r12
  JMP[NE] @slft_fail
  LD r11,r10,3
  CMP r11,r12
  JMP[NE] @slft_fail
  LD r11,r10,6
  MOVI r12,3
  CMP r11,r12
  JMP[NE] @slft_fail
  LD r11,r10,8
  MOVI r12,8
  CMP r11,r12
  JMP[NE] @slft_fail

  MOVI r14,8
  ST r14,r0,@slft_stage
  ; Stale native generation MUST leave output record intact.
  MOVI r10,@slft_req
  MOVI r11,8
  ST r11,r10,2
  MOVI r11,777
  ST r11,r0,@slft_output
  MOVI r1,@slft_req
  CALL @mth_native_symbiotic_leaf_feedback
  CMP r1,r0
  JMP[NE] @slft_fail
  MOVI r11,1
  CMP r4,r11
  JMP[NE] @slft_fail
  MOVI r11,777
  LD r10,r0,@slft_output
  CMP r10,r11
  JMP[NE] @slft_fail
  MOVI r14,9
  ST r14,r0,@slft_stage
  ; Restore generation and deny meta: output also remains unchanged.
  MOVI r10,@slft_req
  MOVI r11,7
  ST r11,r10,2
  ST r0,r10,4
  MOVI r1,@slft_req
  CALL @mth_native_symbiotic_leaf_feedback
  CMP r1,r0
  JMP[NE] @slft_fail
  MOVI r11,777
  LD r10,r0,@slft_output
  CMP r10,r11
  JMP[NE] @slft_fail

  MOVI r1,@slft_pass
  CALL @slft_puts
  HALT
slft_fail:
  ; Print native stage (1..9) and last guest result r4 before FAIL.
  LD r5,r0,@slft_stage
  ADDI r5,r5,48
  PUTC r5
  ADDI r5,r4,48
  PUTC r5
  MOVI r1,@slft_bad
  CALL @slft_puts
  HALT
slft_puts:
  MOVI r13,1
  MOVI r4,255
slft_puts_word:
  LD r2,r1,0
  MOVI r3,4
slft_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @slft_puts_byte
  ADD r1,r1,r13
  JMP @slft_puts_word
slft_h:
  .word 0
slft_stage:
  .word 0
slft_pass:
.str "MTH NATIVE SYMBIOTIC LEAF FEEDBACK PASS\n"
slft_bad:
.str "MTH NATIVE SYMBIOTIC LEAF FEEDBACK FAIL\n"

.org 30000
slft_mapping:
  .word 0
.org 30300
slft_votes:
  .word 0
.org 30400
slft_writers:
  .word 0
.org 30700
slft_req:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
slft_sha:
  .word 0x11223344
.org 30900
slft_scratch:
  .word 0
.org 31100
slft_output:
  .word 0
