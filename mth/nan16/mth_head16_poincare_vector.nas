; Native NaN16 independently scratched, self-modifying Boolean/trig head.
; 255 writable heads 0..254; global physical NOW/VOID head255 excluded.
; NOT 255 separate models: independent head scratch + one global chart/field.
; Each head h owns 256 U32 cells at 0x3B0000+h*256, and independent 128D
; Poincare vector output at 0x3F0000+h*256 (the latter cannot hold code).
; Input head scratch:
;   [0..127] SOURCE measured 128D F32 vector (must be genuinely sourced);
;   [128] learned 16-bit Boolean operator mask; [129] candidate XOR patch;
;   [130] Boolean A, [131] Boolean B; [132] explicit writer lease bit;
;   [133] expected generation, [134] current generation;
;   [135..137] real oriented hyperedge head IDs (a,b,c) distinct <255;
;   [138] native Hodge curl F32; [139] phase turn offset U16.
; Candidate OUTPUT at scratch:
;   [140] Boolean vote 0/1, [141] selected truth-function 0..15,
;   [142] radial Poincare depth F32, [143] curl*radius F32,
;   [144,145] CORDIC cos/sin Q16, [146] candidate 16-function mask,
;   [147] 1 if geometric measurement accepted,
;   [160..167] local hyperedge record; [168..172] local Poincare metadata.
; Active Boolean mask [128] remains UNMODIFIED; the XOR rule patch is a
; candidate staged at [146] after native math succeeds. Controller/lease
; decides later if that patch becomes persistent. No active tensor writes.
; No host Boolean/trig/Poincare arithmetic. Guest self modifying BOOL slot
; is reprogrammed per call; the durable rule and candidate mask are PRIVATE.
;
; ABI r1=head id, r13=1; success r1=1,r2=head,r3=hotvote,r4=0.
; Rejection r1=0,r2=0,r3=0,r4=1 coordinate/2 capability/3 stale/
;                                   4 invalid mask/5 hyperbolic source.
; Serialized within canonical NaN0S runner: shared instruction slot cannot
; execute concurrently; heads have separate retained scratch, not threads.
mth_head16_poincare_measure:
  MOVI r0,0
  MOVI r9,255
  CMP r1,r9
  JMP[GE] @h16_invalid
  CMPS r1,r0
  JMP[LT] @h16_invalid
  MOVI r8,0
  MOVHI r8,0x003B
  SHL r9,r1,8
  ADD r8,r8,r9
  ST r15,r8,190
  ST r1,r8,191
  MOVI r10,1
  LD r11,r8,132
  CMP r11,r10
  JMP[NE] @h16_denied
  LD r10,r8,133
  LD r11,r8,134
  CMP r10,r11
  JMP[NE] @h16_stale
  LD r11,r8,128
  LD r12,r8,129
  BOOL.6 r11,r11,r12   ; independent proposed self modification
  MOVI r12,0xFFFF
  BOOL.8 r11,r11,r12
  CMP r11,r0
  JMP[EQ] @h16_bad_mask
  ST r11,r8,180        ; scratch, not persistent selected mask
  ADD r1,r11,r0
  CALL @mth_bool_lowbit
  ; r2 selected rule; mth_bool_eval rewrites one shared NaN16 BOOL opcode.
  MOVI r8,0
  MOVHI r8,0x003B
  LD r9,r8,191         ; use saved head elsewhere? see reload below
  ; Reconstruct from a separate retained head number, not from r9.
  LD r9,r0,@h16_head
  SHL r8,r9,8
  MOVI r10,0
  MOVHI r10,0x003B
  ADD r8,r8,r10
  ST r2,r8,181
  LD r6,r8,130
  LD r7,r8,131
  ADD r1,r2,r0
  CALL @mth_bool_eval
  LD r9,r0,@h16_head
  SHL r8,r9,8
  MOVI r10,0
  MOVHI r10,0x003B
  ADD r8,r8,r10
  ST r5,r8,182
  ; Angular phase depends on h, locally selected Boolean operator, and
  ; input phase; the same CORDIC that powers the existing NaNLMind phase.
  LD r1,r8,139
  MOVI r10,257
  MUL r11,r9,r10
  ADD r1,r1,r11
  LD r11,r8,181
  SHL r11,r11,12
  ADD r1,r1,r11
  MOVI r10,0xFFFF
  BOOL.8 r1,r1,r10
  CALL @mth_q16_sin_cos
  LD r9,r0,@h16_head
  SHL r8,r9,8
  MOVI r10,0
  MOVHI r10,0x003B
  ADD r8,r8,r10
  ST r1,r8,183
  ST r2,r8,184
  ; Disjoint head-local hyperedge record; native curl source is supplied
  ; by Hodge evidence, never recomputed or fabricated in this primitive.
  LD r10,r8,135
  ST r10,r8,160
  LD r10,r8,136
  ST r10,r8,161
  LD r10,r8,137
  ST r10,r8,162
  LD r10,r8,138
  ST r10,r8,163
  LD r10,r8,133
  ST r10,r8,164
  LD r10,r8,134
  ST r10,r8,165
  MOVI r10,255
  ST r10,r8,166
  MOVI r10,1
  ST r10,r8,167
  MOVI r1,0
  MOVHI r1,0x003B
  SHL r11,r9,8
  ADD r1,r1,r11
  MOVI r2,0
  MOVHI r2,0x003F
  ADD r2,r2,r11
  ADDI r3,r8,160
  ADDI r4,r8,168
  CALL @mth_hyperedge_poincare128_curl
  MOVI r13,1
  CMP r1,r13
  JMP[NE] @h16_bad_measure

  ; Rotate the first two Poincare vector coordinates by the local
  ; Boolean-selected phase, preserving radial geometry to roundoff.
  LD r9,r0,@h16_head
  SHL r8,r9,8
  MOVI r10,0
  MOVHI r10,0x003B
  ADD r8,r8,r10
  MOVI r10,0
  MOVHI r10,0x003F
  SHL r11,r9,8
  ADD r10,r10,r11
  LD r1,r8,183
  CVTIF r1,r1
  MOVI r12,0
  MOVHI r12,0x4780
  FDIV r1,r1,r12       ; cos Q16 => float
  LD r2,r8,184
  CVTIF r2,r2
  FDIV r2,r2,r12       ; sin Q16 => float
  LD r3,r10,0
  LD r4,r10,1
  FMUL r5,r3,r1
  FMUL r6,r4,r2
  FSUB r5,r5,r6
  FMUL r6,r3,r2
  FMUL r7,r4,r1
  FADD r6,r6,r7
  ST r5,r10,0
  ST r6,r10,1
  LD r11,r8,182
  ST r11,r8,140
  LD r11,r8,181
  ST r11,r8,141
  LD r11,r8,168
  ST r11,r8,185  ; actual radius, debug
  LD r11,r8,169
  ST r11,r8,142  ; depth
  LD r11,r8,170
  ST r11,r8,143  ; signed curl feedback
  LD r11,r8,183
  ST r11,r8,144
  LD r11,r8,184
  ST r11,r8,145
  LD r11,r8,180
  ST r11,r8,146  ; candidate truth mask
  MOVI r11,1
  ST r11,r8,147
  LD r15,r8,190
  MOVI r1,1
  ADD r2,r9,r0
  LD r3,r8,140
  MOVI r4,0
  RET
h16_invalid:
  MOVI r4,1
  JMP @h16_reject_early
h16_denied:
  MOVI r4,2
  JMP @h16_reject
h16_stale:
  MOVI r4,3
  JMP @h16_reject
h16_bad_mask:
  MOVI r4,4
  JMP @h16_reject
h16_bad_measure:
  MOVI r4,5
h16_reject:
  LD r9,r0,@h16_head
  SHL r8,r9,8
  MOVI r10,0
  MOVHI r10,0x003B
  ADD r8,r8,r10
  LD r15,r8,190
h16_reject_early:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
  RET
h16_head:
  .word 0
