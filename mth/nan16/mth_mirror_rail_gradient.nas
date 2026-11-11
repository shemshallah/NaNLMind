; Native NaN16 bridge from the physical two directed S+/S- mirror rails
; to the SAME signed simplicial 1-form consumed by Hodge/triangle curl.
; S+[pair]=W[lo->hi], S-[pair]=W[hi->lo] are independent stored
; floats on ONE mirror-pair cell. For lo<hi, g_lo,hi = S+ - S-;
; reverse g_hi,lo = -g_lo,hi. This is a measured antisymmetric edge
; gradient, not a new transformer, model or third tensor bank.
;
; The controller must transport an authenticated frozen physical rail
; snapshot into input[32640][2]; this kernel refuses invalid/VOID rails
; and never touches active weights. Neither direction is inferred from
; the other in storage: only this derived EDGE OBSERVATION is antisymmetric.
;
; ABI r1=source_rails[32640*2] F32, r2=stage_flows[32640] F32,
; r3=publish_flows[32640] F32, r4=expected_epoch, r5=current_epoch,
; r6=report[4] U32 (HOT pairs,COLD pairs,FLAT pairs,epoch).
; return r1=1,r2=32640,r3=HOT nonzero pair count,r4=0;
; rejection r1=r2=r3=0,r4=1 invalid/2 stale/3 source/out-of-bound.
; All sources and g are F32 finite and |each|<=8; VOID255 rails must be
; zero. Only after all 32640 checks does the kernel publish flows.
mth_mirror_rail_gradient:
  MOVI r0,0
  ST r15,r0,@mrg_link
  ST r1,r0,@mrg_source
  ST r2,r0,@mrg_stage
  ST r3,r0,@mrg_publish
  ST r4,r0,@mrg_epoch
  ST r6,r0,@mrg_report
  CMP r1,r0
  JMP[EQ] @mrg_bad
  CMP r2,r0
  JMP[EQ] @mrg_bad
  CMP r3,r0
  JMP[EQ] @mrg_bad
  CMP r6,r0
  JMP[EQ] @mrg_bad
  CMP r1,r2
  JMP[EQ] @mrg_bad
  CMP r1,r3
  JMP[EQ] @mrg_bad
  CMP r2,r3
  JMP[EQ] @mrg_bad
  CMP r4,r5
  JMP[NE] @mrg_stale
  ST r0,r0,@mrg_pair_index
  ST r0,r0,@mrg_u
  ST r0,r0,@mrg_hot
  ST r0,r0,@mrg_cold
  ST r0,r0,@mrg_flat
mrg_row:
  LD r8,r0,@mrg_u
  MOVI r10,255
  CMP r8,r10
  JMP[GE] @mrg_publish_begin
  ADDI r9,r8,1
  ST r9,r0,@mrg_v
mrg_column:
  LD r8,r0,@mrg_v
  MOVI r9,256
  CMP r8,r9
  JMP[GE] @mrg_next_row
  LD r9,r0,@mrg_pair_index
  SHL r10,r9,1
  LD r11,r0,@mrg_source
  ADD r10,r10,r11
  LD r8,r10,0     ; S+ W[lo->hi]
  LD r9,r10,1     ; S- W[hi->lo]
  ADD r11,r8,r0
  CALL @mrg_bound_f32
  CMP r12,r0
  JMP[NE] @mrg_bad_source
  ADD r11,r9,r0
  CALL @mrg_bound_f32
  CMP r12,r0
  JMP[NE] @mrg_bad_source
  LD r10,r0,@mrg_v
  MOVI r11,255
  CMP r10,r11
  JMP[NE] @mrg_active
  FCMP r8,r0
  JMP[NE] @mrg_bad_source
  FCMP r9,r0
  JMP[NE] @mrg_bad_source
mrg_active:
  FSUB r10,r8,r9
  ADD r11,r10,r0
  CALL @mrg_bound_f32
  CMP r12,r0
  JMP[NE] @mrg_bad_source
  LD r11,r0,@mrg_stage
  LD r12,r0,@mrg_pair_index
  ADD r11,r11,r12
  ST r10,r11,0
  FCMP r10,r0
  JMP[GT] @mrg_hot_inc
  JMP[LT] @mrg_cold_inc
  LD r11,r0,@mrg_flat
  ADDI r11,r11,1
  ST r11,r0,@mrg_flat
  JMP @mrg_next_pair
mrg_hot_inc:
  LD r11,r0,@mrg_hot
  ADDI r11,r11,1
  ST r11,r0,@mrg_hot
  JMP @mrg_next_pair
mrg_cold_inc:
  LD r11,r0,@mrg_cold
  ADDI r11,r11,1
  ST r11,r0,@mrg_cold
mrg_next_pair:
  LD r9,r0,@mrg_pair_index
  ADDI r9,r9,1
  ST r9,r0,@mrg_pair_index
  LD r9,r0,@mrg_v
  ADDI r9,r9,1
  ST r9,r0,@mrg_v
  JMP @mrg_column
mrg_next_row:
  LD r8,r0,@mrg_u
  ADDI r8,r8,1
  ST r8,r0,@mrg_u
  JMP @mrg_row

mrg_publish_begin:
  LD r9,r0,@mrg_pair_index
  MOVI r10,32640
  CMP r9,r10
  JMP[NE] @mrg_bad_source
  MOVI r8,0
mrg_publish:
  MOVI r9,32640
  CMP r8,r9
  JMP[GE] @mrg_publish_report
  LD r10,r0,@mrg_stage
  ADD r10,r10,r8
  LD r11,r10,0
  LD r10,r0,@mrg_publish
  ADD r10,r10,r8
  ST r11,r10,0
  ADDI r8,r8,1
  JMP @mrg_publish
mrg_publish_report:
  LD r10,r0,@mrg_report
  LD r11,r0,@mrg_hot
  ST r11,r10,0
  LD r11,r0,@mrg_cold
  ST r11,r10,1
  LD r11,r0,@mrg_flat
  ST r11,r10,2
  LD r11,r0,@mrg_epoch
  ST r11,r10,3
  MOVI r1,1
  MOVI r2,32640
  LD r3,r0,@mrg_hot
  MOVI r4,0
  JMP @mrg_return

; Input r11 F32 bits; return r12=0 valid finite |x|<=8, else 1.
; r8,r9,r10 untouched; call safe through retained main return link.
mrg_bound_f32:
  MOVI r12,0xFFFF
  MOVHI r12,0x7FFF
  BOOL.8 r11,r11,r12
  MOVI r12,0
  MOVHI r12,0x7F80
  BOOL.8 r14,r11,r12
  CMP r14,r12
  JMP[EQ] @mrg_bound_bad
  MOVI r12,0
  MOVHI r12,0x4100
  CMP r11,r12
  JMP[GT] @mrg_bound_bad
  MOVI r12,0
  RET
mrg_bound_bad:
  MOVI r12,1
  RET

mrg_bad:
  MOVI r4,1
  JMP @mrg_reject
mrg_stale:
  MOVI r4,2
  JMP @mrg_reject
mrg_bad_source:
  MOVI r4,3
mrg_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
mrg_return:
  MOVI r13,1
  LD r15,r0,@mrg_link
  RET
mrg_link:
  .word 0
mrg_source:
  .word 0
mrg_stage:
  .word 0
mrg_publish:
  .word 0
mrg_epoch:
  .word 0
mrg_report:
  .word 0
mrg_pair_index:
  .word 0
mrg_u:
  .word 0
mrg_v:
  .word 0
mrg_hot:
  .word 0
mrg_cold:
  .word 0
mrg_flat:
  .word 0
