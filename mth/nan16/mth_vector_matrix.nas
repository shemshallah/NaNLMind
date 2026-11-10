; Raw NaN16 C(256,2) vector-code observer.
;
; The 32,640 unordered head-pair cells live at guest word 0x300000 as signed
; Q16 accumulators. The host may read them after the guest updates them; no
; host pair-index or matrix arithmetic is used.
;
; Pair index, a < b:
;   a*255 - a*(a-1)/2 + (b-a-1)
; Equal heads return the 32640 sentinel.

; r1=a, r2=b -> r1=index (32640 if a==b)
mth_vm_pair:
  CMP r1,r2
  JMP[LT] @mth_vm_pair_ordered
  MOVI r3,0
  ADD r3,r1,r0
  ADD r1,r2,r0
  ADD r2,r3,r0
mth_vm_pair_ordered:
  CMP r1,r2
  JMP[EQ] @mth_vm_pair_same
  MOVI r4,255
  MUL r5,r1,r4
  MOVI r4,1
  SUB r6,r1,r4
  MUL r6,r6,r1
  SHR r6,r6,1
  SUB r5,r5,r6
  SUB r4,r2,r1
  MOVI r6,1
  SUB r4,r4,r6
  ADD r1,r5,r4
  RET
mth_vm_pair_same:
  MOVI r1,32640
  RET

; Clear all 32,640 pair cells.
mth_vm_reset:
  MOVI r10,0x0000
  MOVHI r10,0x0030
  MOVI r11,32640
  MOVI r12,0
mth_vm_reset_loop:
  CMP r12,r11
  JMP[GE] @mth_vm_reset_done
  ADD r13,r10,r12
  ST r0,r13,0
  ADDI r12,r12,1
  JMP @mth_vm_reset_loop
mth_vm_reset_done:
  MOVI r1,32640
  RET

; r1=a, r2=b, r3=delta -> r1=index, r2=new value.
mth_vm_accum:
  MOVI r12,@mth_vm_link
  ST r15,r12,0
  MOVI r12,@mth_vm_delta
  ST r3,r12,0
  CALL @mth_vm_pair
  MOVI r12,@mth_vm_index
  ST r1,r12,0
  MOVI r12,32640
  CMP r1,r12
  JMP[EQ] @mth_vm_accum_same
  MOVI r10,0x0000
  MOVHI r10,0x0030
  ADD r10,r10,r1
  LD r11,r10,0
  MOVI r12,@mth_vm_delta
  LD r3,r12,0
  ADD r11,r11,r3
  ST r11,r10,0
  MOVI r12,@mth_vm_index
  LD r1,r12,0
  ADD r2,r11,r0
  MOVI r12,@mth_vm_link
  LD r15,r12,0
  RET
mth_vm_accum_same:
  MOVI r2,0
  MOVI r12,@mth_vm_link
  LD r15,r12,0
  RET

; r1=head a, r2=threshold -> r1=best third head (-1 if none), r2=score.
mth_vm_probe:
  MOVI r12,@mth_vm_probe_link
  ST r15,r12,0
  MOVI r12,@mth_vm_probe_a
  ST r1,r12,0
  MOVI r12,@mth_vm_probe_threshold
  ST r2,r12,0
  MOVI r12,@mth_vm_probe_best_score
  ST r0,r12,0
  MOVI r12,@mth_vm_probe_best_head
  MOVI r13,0xFFFF
  MOVHI r13,0xFFFF
  ST r13,r12,0
  MOVI r12,@mth_vm_probe_b
  ST r0,r12,0
mth_vm_probe_loop:
  MOVI r12,@mth_vm_probe_b
  LD r5,r12,0
  MOVI r12,256
  CMP r5,r12
  JMP[GE] @mth_vm_probe_done
  MOVI r12,@mth_vm_probe_a
  LD r6,r12,0
  CMP r5,r6
  JMP[EQ] @mth_vm_probe_next
  ADD r1,r6,r0
  ADD r2,r5,r0
  CALL @mth_vm_pair
  MOVI r12,32640
  CMP r1,r12
  JMP[EQ] @mth_vm_probe_next
  MOVI r10,0x0000
  MOVHI r10,0x0030
  ADD r10,r10,r1
  LD r8,r10,0
  MOVI r12,@mth_vm_probe_threshold
  LD r9,r12,0
  CMP r8,r9
  JMP[LT] @mth_vm_probe_next
  MOVI r12,@mth_vm_probe_best_score
  LD r9,r12,0
  CMP r8,r9
  JMP[LE] @mth_vm_probe_next
  ST r8,r12,0
  MOVI r12,@mth_vm_probe_best_head
  MOVI r13,@mth_vm_probe_b
  LD r13,r13,0
  ST r13,r12,0
mth_vm_probe_next:
  MOVI r12,@mth_vm_probe_b
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_vm_probe_loop
mth_vm_probe_done:
  MOVI r12,@mth_vm_probe_best_head
  LD r1,r12,0
  MOVI r12,@mth_vm_probe_best_score
  LD r2,r12,0
  MOVI r12,@mth_vm_probe_link
  LD r15,r12,0
  RET

mth_vm_link:
  .word 0
mth_vm_index:
  .word 0
mth_vm_delta:
  .word 0
mth_vm_probe_link:
  .word 0
mth_vm_probe_a:
  .word 0
mth_vm_probe_threshold:
  .word 0
mth_vm_probe_b:
  .word 0
mth_vm_probe_best_head:
  .word 0
mth_vm_probe_best_score:
  .word 0
