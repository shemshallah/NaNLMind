; Full-field 255 independent Boolean16 Poincare heads, 85 independent
; 128D Poincare triheads and 43/85 native quorum. The source vectors,
; Hodge curl and seven-credit are FIXTURE INPUTS, not claims about corpus.
; Unlike the old three-head fixture, all 85 trihead masks below are
; actually computed from the 255 individually executed NaN16 head kernels.
.org 0
JMP @fft_main
.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_hyperedge_poincare128_curl.nas"
.include "../nan16/mth_head16_poincare_vector.nas"
.include "../nan16/mth_triad_hotcold_poincare128.nas"
.include "../nan16/mth_full_field_head_triad_measure.nas"

fft_main:
  MOVI r0,0
  MOVI r13,1
  ST r0,r0,@fft_i
fft_seed:
  LD r9,r0,@fft_i
  MOVI r10,255
  CMP r9,r10
  JMP[GE] @fft_seed_triads
  ; All 255 mapping entries are independent head points 0..254.
  MOVI r10,@fft_map
  ADD r10,r10,r9
  ST r9,r10,0
  ; Each head source vector and model parameters live in its own 256-word
  ; slab. The native kernel performs each independent trig/128D projection.
  MOVI r8,0
  MOVHI r8,0x003B
  SHL r11,r9,8
  ADD r8,r8,r11
  MOVI r10,0
  MOVHI r10,0x3F80
  ST r10,r8,0           ; sourced vector x[0]=1.0 in this FIXTURE
  MOVI r10,0
  MOVHI r10,0x3F00
  ST r10,r8,127         ; sourced vector x[127]=0.5 (128D)
  MOVI r10,64          ; truth rule6 XOR(a=1,b=0) => HOT
  MOVI r11,129
  CMP r9,r11
  JMP[LT] @fft_mask_ready
  MOVI r10,256         ; truth rule8 AND => COLD
fft_mask_ready:
  ST r10,r8,128
  ST r0,r8,129         ; self-mod candidate patch=0
  MOVI r10,1
  ST r10,r8,130
  ST r0,r8,131
  ST r10,r8,132        ; explicit per-head candidate lease
  MOVI r11,7
  ST r11,r8,133
  ST r11,r8,134
  ST r0,r8,135         ; oriented (0,1,2), distinct from VOID255
  MOVI r10,1
  ST r10,r8,136
  MOVI r10,2
  ST r10,r8,137
  MOVI r10,0
  MOVHI r10,0x3F00
  ST r10,r8,138        ; test source curl +0.5
  LD r10,r0,@fft_i
  MOVI r11,257
  MUL r10,r10,r11
  ST r10,r8,139        ; each head has distinct native phase
  LD r9,r0,@fft_i
  ADDI r9,r9,1
  ST r9,r0,@fft_i
  JMP @fft_seed

fft_seed_triads:
  ST r0,r0,@fft_i
fft_triad_seed_loop:
  LD r9,r0,@fft_i
  MOVI r10,85
  CMP r9,r10
  JMP[GE] @fft_run
  MOVI r10,@fft_curls
  ADD r10,r10,r9
  MOVI r11,0
  MOVHI r11,0x3F00
  ST r11,r10,0         ; test Hodge curl +0.5 float
  MOVI r10,@fft_credits
  ADD r10,r10,r9
  MOVI r11,0
  MOVHI r11,1
  ST r11,r10,0         ; test sourced seven-credit +1 Q16
  ADDI r9,r9,1
  ST r9,r0,@fft_i
  JMP @fft_triad_seed_loop

fft_run:
  MOVI r1,@fft_map
  MOVI r2,@fft_curls
  MOVI r3,@fft_credits
  MOVI r4,7
  MOVI r5,7
  MOVI r6,@fft_votes
  MOVI r7,@fft_report
  CALL @mth_full_field_head_triad_measure
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @fft_fail
  MOVI r10,43
  CMP r2,r10
  JMP[NE] @fft_fail
  MOVI r10,255
  CMP r3,r10
  JMP[NE] @fft_fail
  CMP r4,r0
  JMP[NE] @fft_fail

  ; Complete report: 255 actual head measurements and 85 native triheads,
  ; 129 HOT heads (43 unanimous HOT triangles), 126 COLD (42 unanimous).
  LD r10,r0,@fft_report
  MOVI r11,255
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+1
  MOVI r11,85
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+2
  MOVI r11,129
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+3
  MOVI r11,43
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+4
  MOVI r11,42
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+5
  MOVI r11,43
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+6
  MOVI r11,42
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+7
  CMP r10,r13
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+8
  MOVI r11,255
  CMP r10,r11
  JMP[NE] @fft_fail

  ; Every one of 85 masks from its real three Boolean head outputs.
  ST r0,r0,@fft_i
fft_check_votes:
  LD r9,r0,@fft_i
  MOVI r10,85
  CMP r9,r10
  JMP[GE] @fft_check_geometry
  MOVI r10,@fft_votes
  ADD r10,r10,r9
  LD r11,r10,0
  MOVI r10,43
  CMP r9,r10
  JMP[LT] @fft_vote_hot
  CMP r11,r0
  JMP[NE] @fft_fail
  JMP @fft_next_vote
fft_vote_hot:
  MOVI r10,7
  CMP r11,r10
  JMP[NE] @fft_fail
fft_next_vote:
  ADDI r9,r9,1
  ST r9,r0,@fft_i
  JMP @fft_check_votes

fft_check_geometry:
  ; All 255 head scratch acceptance stamps exist; NOW255 has none.
  ST r0,r0,@fft_i
fft_stamp_loop:
  LD r9,r0,@fft_i
  MOVI r10,255
  CMP r9,r10
  JMP[GE] @fft_trihead_geometry
  MOVI r8,0
  MOVHI r8,0x003B
  SHL r11,r9,8
  ADD r8,r8,r11
  LD r10,r8,147
  CMP r10,r13
  JMP[NE] @fft_fail
  LD r10,r8,142
  FCMP r10,r0
  JMP[LE] @fft_fail ; radial depth positive at every head
  ADDI r9,r9,1
  ST r9,r0,@fft_i
  JMP @fft_stamp_loop

fft_trihead_geometry:
  ; Two different triad vector scratch banks and their actual HOT/COLD
  ; eligibility sign. These are genuinely measured by NaN16.
  MOVI r8,0xE000
  MOVHI r8,0x003E
  LD r10,r8,8
  CMP r10,r13
  JMP[NE] @fft_fail
  LD r10,r8,9
  CMP r10,r0
  JMP[NE] @fft_fail
  LD r10,r8,10
  FCMP r10,r0
  JMP[LE] @fft_fail
  MOVI r8,0xE540
  MOVHI r8,0x003E    ; triad84 meta = 0x3EE000 + 84*16
  LD r10,r8,8
  CMP r10,r0
  JMP[NE] @fft_fail
  LD r10,r8,9
  CMP r10,r13
  JMP[NE] @fft_fail
  LD r10,r8,10
  FCMP r10,r0
  JMP[GE] @fft_fail
  LD r10,r8,1
  FCMP r10,r0
  JMP[LE] @fft_fail

  ; Fail-closed before publication: stale epoch keeps output intact.
  MOVI r11,9999
  ST r11,r0,@fft_votes
  ST r11,r0,@fft_report
  MOVI r1,@fft_map
  MOVI r2,@fft_curls
  MOVI r3,@fft_credits
  MOVI r4,7
  MOVI r5,8
  MOVI r6,@fft_votes
  MOVI r7,@fft_report
  CALL @mth_full_field_head_triad_measure
  CMP r1,r0
  JMP[NE] @fft_fail
  MOVI r11,2
  CMP r4,r11
  JMP[NE] @fft_fail
  MOVI r11,9999
  LD r10,r0,@fft_votes
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report
  CMP r10,r11
  JMP[NE] @fft_fail

  ; Break the last member of all-hot triad 42: 2 cold +1 hot =>
  ; only 42/85 HOT triheads. All 85 still measured but field DENIES.
  MOVI r8,0
  MOVHI r8,0x003B
  MOVI r10,126
  SHL r11,r10,8
  ADD r8,r8,r11
  MOVI r10,256
  ST r10,r8,128
  MOVI r8,0
  MOVHI r8,0x003B
  MOVI r10,127
  SHL r11,r10,8
  ADD r8,r8,r11
  MOVI r10,256
  ST r10,r8,128
  MOVI r1,@fft_map
  MOVI r2,@fft_curls
  MOVI r3,@fft_credits
  MOVI r4,7
  MOVI r5,7
  MOVI r6,@fft_votes
  MOVI r7,@fft_report
  CALL @mth_full_field_head_triad_measure
  CMP r1,r13
  JMP[NE] @fft_fail
  MOVI r10,42
  CMP r2,r10
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+7
  CMP r10,r0
  JMP[NE] @fft_fail
  LD r10,r0,@fft_votes+42
  MOVI r11,4         ; head126 cold,127 cold,128 hot -> mask 0b100
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+5
  MOVI r11,42
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report+6
  MOVI r11,42
  CMP r10,r11
  JMP[NE] @fft_fail

  ; Duplicate identity / absent 254 rejects before writing any report.
  MOVI r10,@fft_map
  MOVI r11,0
  ST r11,r10,254
  MOVI r11,9999
  ST r11,r0,@fft_votes
  ST r11,r0,@fft_report
  MOVI r1,@fft_map
  MOVI r2,@fft_curls
  MOVI r3,@fft_credits
  MOVI r4,7
  MOVI r5,7
  MOVI r6,@fft_votes
  MOVI r7,@fft_report
  CALL @mth_full_field_head_triad_measure
  CMP r1,r0
  JMP[NE] @fft_fail
  MOVI r11,3
  CMP r4,r11
  JMP[NE] @fft_fail
  MOVI r11,9999
  LD r10,r0,@fft_votes
  CMP r10,r11
  JMP[NE] @fft_fail
  LD r10,r0,@fft_report
  CMP r10,r11
  JMP[NE] @fft_fail
  MOVI r1,@fft_pass
  CALL @fft_puts
  HALT

fft_fail:
  MOVI r1,@fft_bad
  CALL @fft_puts
  HALT
fft_puts:
  MOVI r13,1
  MOVI r4,255
fft_puts_word:
  LD r2,r1,0
  MOVI r3,4
fft_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @fft_puts_byte
  ADD r1,r1,r13
  JMP @fft_puts_word
fft_pass:
.str "MTH FULL FIELD 255 HEAD 85 TRIHEAD REAL VOTES PASS\n"
fft_bad:
.str "MTH FULL FIELD 255 HEAD 85 TRIHEAD REAL VOTES FAIL\n"
fft_i:
  .word 0

.org 30000
fft_map:
  .word 0
.org 30280
fft_curls:
  .word 0
.org 30380
fft_credits:
  .word 0
.org 30480
fft_votes:
  .word 0
.org 30580
fft_report:
  .word 0
