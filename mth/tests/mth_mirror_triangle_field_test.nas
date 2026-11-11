; Full raw NaN16 palindrome/mirror HOT/COLD triangle curvature, boot
; sampling, discrete curl, candidate repair, and 128D Poincare coupling.
.org 0
JMP @mpt_main
.include "../nan16/mth_bool_dynamic.nas"
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_hyperedge_poincare128_curl.nas"
.include "../nan16/mth_head16_poincare_vector.nas"
.include "../nan16/mth_mirror_triangle_boot.nas"
.include "../nan16/mth_mirror_rail_gradient.nas"
.include "../nan16/mth_mirror_triangle_field.nas"
.include "../nan16/mth_mirror_triangle_recover.nas"
.include "../nan16/mth_mirror_triangle_poincare128.nas"
mpt_main:
  MOVI r0,0
  MOVI r13,1
  ; Seed once: 255 ring triangles and 255 reproducible long-range samples.
  MOVI r1,0xD00D
  MOVI r2,7
  MOVI r3,0
  MOVHI r3,0x0039 ; table 0x390000[1530]
  MOVI r4,0x4000
  MOVHI r4,0x0039 ; boot flag 0x394000[3]
  CALL @mth_mirror_triangle_boot
  CMP r1,r13
  JMP[NE] @mpt_fail
  MOVI r10,510
  CMP r2,r10
  JMP[NE] @mpt_fail
  MOVI r8,0x0000
  MOVHI r8,0x0039
  LD r10,r8,0
  CMP r10,r0
  JMP[NE] @mpt_fail
  LD r10,r8,1
  CMP r10,r13
  JMP[NE] @mpt_fail
  MOVI r11,2
  LD r10,r8,2
  CMP r10,r11
  JMP[NE] @mpt_fail
  ; Last local ring wraps 254 -> 0 -> 1, not VOID255.
  MOVI r8,762
  MOVI r10,0
  MOVHI r10,0x0039
  ADD r8,r8,r10
  LD r10,r8,0
  MOVI r11,254
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,1
  CMP r10,r0
  JMP[NE] @mpt_fail
  LD r10,r8,2
  CMP r10,r13
  JMP[NE] @mpt_fail
  ; First fixed random long triangle anchored on 0, spans [32..95] and
  ; [128..191] relative to anchor, never any VOID255.
  MOVI r8,765
  MOVI r10,0
  MOVHI r10,0x0039
  ADD r8,r8,r10
  LD r10,r8,0
  CMP r10,r0
  JMP[NE] @mpt_fail
  LD r10,r8,1
  MOVI r11,32
  CMP r10,r11
  JMP[LT] @mpt_fail
  MOVI r11,95
  CMP r10,r11
  JMP[GT] @mpt_fail
  LD r10,r8,2
  MOVI r11,128
  CMP r10,r11
  JMP[LT] @mpt_fail
  MOVI r11,191
  CMP r10,r11
  JMP[GT] @mpt_fail
  ST r10,r0,@mpt_random_c
  ; Second boot invocation cannot regenerate or damage frozen selection.
  MOVI r1,123
  MOVI r2,7
  MOVI r3,0
  MOVHI r3,0x0039
  MOVI r4,0x4000
  MOVHI r4,0x0039
  CALL @mth_mirror_triangle_boot
  CMP r1,r0
  JMP[NE] @mpt_fail
  MOVI r10,2
  CMP r3,r10
  JMP[NE] @mpt_fail
  MOVI r8,767
  MOVI r10,0
  MOVHI r10,0x0039
  ADD r8,r8,r10
  LD r10,r8,0
  LD r11,r0,@mpt_random_c
  CMP r10,r11
  JMP[NE] @mpt_fail

  MOVI r10,1
  ST r10,r0,@mpt_stage
  ; Authenticated-source fixture S+/S- mirror rails are two INDEPENDENT
  ; directed stored float32 values per canonical C(256,2) cell.
  ; The guest, NOT the test harness, constructs anti-symmetric g=S+-S-.
  MOVI r8,0
  MOVHI r8,0x0034  ; physical per-pair [S+,S-] source snapshot
  MOVI r10,0
  MOVHI r10,0x3F80  ; +1
  ST r10,r8,0        ; pair0 (0,1): +1 - 0 = +1
  MOVI r10,0
  MOVHI r10,0x4040  ; +3
  ST r10,r8,3        ; pair1 (0,2): 0 - 3 = -3
  MOVI r10,0
  MOVHI r10,0x4000  ; +2
  ST r10,r8,510      ; pair255 (1,2): +2
  ST r10,r8,512      ; pair256 (1,3): +2
  ST r10,r8,5012     ; pair2506 (10,12): +2
  MOVI r10,0
  MOVHI r10,0x3F80  ; +1 reverse directed weights
  ST r10,r8,1019     ; pair509 (2,3): -1
  ST r10,r8,5011     ; pair2505 (10,11): -1
  ST r10,r8,5501     ; pair2750 (11,12): -1

  MOVI r1,0
  MOVHI r1,0x0034    ; raw mirrored S+/S- rail pairs
  MOVI r2,0
  MOVHI r2,0x0035    ; scratch signed edge gradients
  MOVI r3,0
  MOVHI r3,0x003A    ; published 32640 native gradient 1-form
  MOVI r4,7
  MOVI r5,7
  MOVI r6,0x8000
  MOVHI r6,0x0035    ; sample report
  CALL @mth_mirror_rail_gradient
  CMP r1,r13
  JMP[NE] @mpt_fail
  MOVI r10,32640
  CMP r2,r10
  JMP[NE] @mpt_fail
  CMP r3,r0
  JMP[LE] @mpt_fail
  MOVI r8,0
  MOVHI r8,0x003A
  LD r10,r8,0
  MOVI r11,0
  MOVHI r11,0x3F80
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,1
  MOVI r11,0
  MOVHI r11,0xC040
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,255
  MOVI r11,0
  MOVHI r11,0x4000
  CMP r10,r11
  JMP[NE] @mpt_fail
  MOVI r10,2
  ST r10,r0,@mpt_stage
  ; Invalid nonzero VOID255 mirror rail rejected before publishing.
  MOVI r8,0
  MOVHI r8,0x0034
  MOVI r10,0
  MOVHI r10,0x3F80
  ST r10,r8,508      ; pair(0,255) forward rail must be zero
  MOVI r1,0
  MOVHI r1,0x0034
  MOVI r2,0
  MOVHI r2,0x0035
  MOVI r3,0
  MOVHI r3,0x003A
  MOVI r4,7
  MOVI r5,7
  MOVI r6,0x8000
  MOVHI r6,0x0035
  CALL @mth_mirror_rail_gradient
  CMP r1,r0
  JMP[NE] @mpt_fail
  MOVI r10,3
  CMP r4,r10
  JMP[NE] @mpt_fail
  MOVI r8,0
  MOVHI r8,0x0034
  MOVI r10,3
  ST r10,r0,@mpt_stage
  ST r0,r8,508       ; restore valid physical snapshot
  MOVI r8,0
  MOVHI r8,0x003A
  LD r10,r8,0
  MOVI r11,0
  MOVHI r11,0x3F80
  CMP r10,r11
  JMP[NE] @mpt_fail

  MOVI r1,0
  MOVI r10,4
  ST r10,r0,@mpt_stage
  MOVHI r1,0x003A       ; 32640 signed canonical pair flows
  MOVI r2,0
  MOVHI r2,0x0039       ; boot frozen 510 triples
  MOVI r3,510
  MOVI r4,0
  MOVHI r4,0x0038       ; private 510*32 staged record bank
  MOVI r5,0
  MOVHI r5,0x0036       ; published records (candidate-only)
  MOVI r6,7
  MOVI r7,7
  CALL @mth_mirror_triangle_field
  CMP r1,r13
  JMP[NE] @mpt_fail
  MOVI r10,510
  CMP r2,r10
  JMP[NE] @mpt_fail
  CMP r3,r0
  JMP[LE] @mpt_fail
  MOVI r8,0
  MOVHI r8,0x0036
  ; Genuine first face 3/3 HOT, masks 0b111, L=6.
  LD r10,r8,4
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,5
  CMP r10,r0
  JMP[NE] @mpt_fail
  LD r10,r8,6
  MOVI r11,3
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,9
  CMP r10,r13
  JMP[NE] @mpt_fail
  LD r10,r8,11
  MOVI r11,0
  MOVHI r11,0x40C0
  CMP r10,r11
  JMP[NE] @mpt_fail
  ; Verify actual palindromic fixed points and exact mirror addresses.
  LD r10,r8,17
  CMP r10,r0
  JMP[NE] @mpt_fail
  LD r10,r8,18
  MOVI r11,0x8001
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,19
  MOVI r11,0x4002
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,20
  MOVI r11,1
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,21
  MOVI r11,0x8000
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,22
  MOVI r11,0x8002
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,23
  MOVI r11,0x4001
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,24
  MOVI r11,0x4000
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,25
  MOVI r11,2
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,27
  MOVI r11,255
  CMP r10,r11
  JMP[NE] @mpt_fail
  ; Second local triangle carries 2/3 COLD (not assumed 3/3).
  MOVI r8,32
  MOVI r10,0
  MOVHI r10,0x0036
  ADD r8,r8,r10
  LD r10,r8,6
  CMP r10,r13
  JMP[NE] @mpt_fail
  LD r10,r8,7
  MOVI r11,2
  CMP r10,r11
  JMP[NE] @mpt_fail
  LD r10,r8,8
  MOVI r11,0xFFFF
  MOVHI r11,0xFFFF
  CMP r10,r11
  JMP[NE] @mpt_fail
  ; Local triangle(10,11,12): 3/3 COLD.
  MOVI r8,320
  MOVI r10,0
  MOVHI r10,0x0036
  ADD r8,r8,r10
  LD r10,r8,10
  CMP r10,r13
  JMP[NE] @mpt_fail
  LD r10,r8,5
  MOVI r11,7
  CMP r10,r11
  JMP[NE] @mpt_fail

  MOVI r10,5
  ST r10,r0,@mpt_stage
  ; Trainable 128D head vectors must originate from SAME native head guest.
  ST r0,r0,@mpt_index
mpt_seed_head:
  LD r9,r0,@mpt_index
  MOVI r10,3
  CMP r9,r10
  JMP[GE] @mpt_project
  MOVI r8,0
  MOVHI r8,0x003B
  SHL r11,r9,8
  ADD r8,r8,r11
  MOVI r10,0
  MOVHI r10,0x3F80
  ST r10,r8,0
  MOVI r10,0
  MOVHI r10,0x3F00
  ST r10,r8,127
  MOVI r10,64
  ST r10,r8,128
  ST r0,r8,129
  MOVI r10,1
  ST r10,r8,130
  ST r0,r8,131
  ST r10,r8,132
  MOVI r10,7
  ST r10,r8,133
  ST r10,r8,134
  ST r0,r8,135
  MOVI r10,1
  ST r10,r8,136
  MOVI r10,2
  ST r10,r8,137
  MOVI r10,0
  MOVHI r10,0x3F00
  ST r10,r8,138
  MOVI r10,1024
  ST r10,r8,139
  ADD r1,r9,r0
  CALL @mth_head16_poincare_measure
  CMP r1,r13
  JMP[NE] @mpt_fail
  LD r9,r0,@mpt_index
  ADDI r9,r9,1
  ST r9,r0,@mpt_index
  JMP @mpt_seed_head

mpt_project:
  MOVI r1,0
  MOVHI r1,0x0036  ; face0 saved measured curl +6
  MOVI r2,0
  MOVHI r2,0x003F  ; 255 native 128D head Poincare vectors
  MOVI r3,0
  MOVHI r3,0x0037  ; private src128
  MOVI r4,0x1000
  MOVHI r4,0x0037  ; private Poincare dst128
  MOVI r5,0x2000
  MOVHI r5,0x0037  ; hyperedge record8
  MOVI r6,0x3000
  MOVHI r6,0x0037  ; Poincare meta5
  MOVI r7,7
  CALL @mth_mirror_triangle_poincare128
  CMP r1,r13
  JMP[NE] @mpt_fail
  MOVI r10,128
  CMP r2,r10
  JMP[NE] @mpt_fail
  CMP r3,r13
  JMP[NE] @mpt_fail
  MOVI r8,0
  MOVHI r8,0x0036
  LD r10,r8,31
  CMP r10,r13
  JMP[NE] @mpt_fail
  LD r10,r8,28
  FCMP r10,r0
  JMP[LE] @mpt_fail
  MOVI r11,0
  MOVHI r11,0x3F80
  FCMP r10,r11
  JMP[GE] @mpt_fail
  LD r10,r8,29
  FCMP r10,r0
  JMP[LE] @mpt_fail
  LD r10,r8,30
  FCMP r10,r0
  JMP[LE] @mpt_fail

  MOVI r10,6
  ST r10,r0,@mpt_stage
  ; Corrupt only g_01: 1 -> 4, retain L=6 and trusted g_12,g_20.
  MOVI r8,0
  MOVHI r8,0x003A
  MOVI r10,0
  MOVHI r10,0x4080
  ST r10,r8,0
  MOVI r1,0
  MOVHI r1,0x0036
  MOVI r2,0
  MOVHI r2,0x003A
  MOVI r3,7
  MOVI r4,0x4000
  MOVHI r4,0x0037 ; candidate repair, not active flow
  CALL @mth_mirror_triangle_recover
  CMP r1,r13
  JMP[NE] @mpt_fail
  MOVI r10,0
  MOVHI r10,0x3F80
  CMP r2,r10        ; reconstruct exactly +1.0
  JMP[NE] @mpt_fail
  MOVI r10,0
  MOVHI r10,0x4040
  CMP r3,r10        ; residual +3.0 from corruption
  JMP[NE] @mpt_fail
  MOVI r8,0x4000
  MOVHI r8,0x0037
  LD r10,r8,0
  MOVI r11,0
  MOVHI r11,0x3F80
  CMP r10,r11
  JMP[NE] @mpt_fail
  ; Rejection on stale source keeps candidate repair unchanged.
  MOVI r11,777
  ST r11,r8,0
  MOVI r1,0
  MOVHI r1,0x0036
  MOVI r2,0
  MOVHI r2,0x003A
  MOVI r3,8
  MOVI r4,0x4000
  MOVHI r4,0x0037
  CALL @mth_mirror_triangle_recover
  CMP r1,r0
  JMP[NE] @mpt_fail
  MOVI r10,2
  CMP r4,r10
  JMP[NE] @mpt_fail
  MOVI r8,0x4000
  MOVHI r8,0x0037
  LD r10,r8,0
  MOVI r11,777
  CMP r10,r11
  JMP[NE] @mpt_fail

  MOVI r10,7
  ST r10,r0,@mpt_stage
  ; Source-generation failure does NOT publish new triangle records.
  MOVI r8,0
  MOVHI r8,0x0036
  MOVI r11,12345
  ST r11,r8,0
  MOVI r1,0
  MOVHI r1,0x003A
  MOVI r2,0
  MOVHI r2,0x0039
  MOVI r3,510
  MOVI r4,0
  MOVHI r4,0x0038
  MOVI r5,0
  MOVHI r5,0x0036
  MOVI r6,7
  MOVI r7,8
  CALL @mth_mirror_triangle_field
  CMP r1,r0
  JMP[NE] @mpt_fail
  MOVI r10,2
  CMP r4,r10
  JMP[NE] @mpt_fail
  MOVI r8,0
  MOVHI r8,0x0036
  LD r10,r8,0
  MOVI r11,12345
  CMP r10,r11
  JMP[NE] @mpt_fail
  MOVI r1,@mpt_pass
  CALL @mpt_print
  HALT
mpt_fail:
  ; Diagnostics: failed rail source pair index in four hex digits.
  LD r9,r0,@mrg_pair_index
  MOVI r8,4
mpt_debug_pair_hex:
  SHR r10,r9,12
  SHL r9,r9,4
  MOVI r11,15
  BOOL.8 r10,r10,r11
  MOVI r11,9
  CMP r10,r11
  JMP[LE] @mpt_debug_digit
  ADDI r10,r10,7
mpt_debug_digit:
  ADDI r10,r10,48
  PUTC r10
  ADDI r8,r8,-1
  CMP r8,r0
  JMP[GT] @mpt_debug_pair_hex
  MOVI r8,48
  ADD r8,r8,r4
  PUTC r8
  LD r8,r0,@mpt_stage
  MOVI r11,48
  ADD r8,r8,r11
  PUTC r8
  MOVI r1,@mpt_bad
  CALL @mpt_print
  HALT
mpt_print:
  MOVI r13,1
  MOVI r4,255
mpt_print_word:
  LD r2,r1,0
  MOVI r3,4
mpt_print_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mpt_print_byte
  ADD r1,r1,r13
  JMP @mpt_print_word
mpt_pass:
.str "MTH MIRROR PALINDROME TRIANGLE CURL RECOVERY POINCARE PASS\n"
mpt_bad:
.str "MTH MIRROR PALINDROME TRIANGLE CURL RECOVERY POINCARE FAIL\n"
mpt_random_c:
  .word 0
mpt_index:
  .word 0
mpt_stage:
  .word 0
