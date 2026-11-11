; Native candidate-only erasure recovery from a RETAINED oriented loop sum.
; Valid only when recorded L and other two freshly measured edges remain
; trusted. A flatness assumption is never imposed: nonzero L is retained.
; For triangle (i,j,k): g_ij_hat=L_saved-g_jk(current)-g_ki(current).
; Residual is g_ij(current)-g_ij_hat. The reverse mirror address is
; -g_ij_hat; the controller may stage both through its candidate gate.
; No ACTIVE tensor or raw S+/S- pair is ever modified.
;
; ABI r1=saved record[32],r2=current signed canonical pair_flow[32640],
;     r3=expected source generation,r4=output[4] U32.
; Returns r1=1,r2=repaired g_ij F32 bits,r3=residual F32 bits,r4=0.
; Reject r1=r2=r3=0,r4=1 input/2 stale/3 nonfinite observed edge.
; Output [repaired,observed,residual,epoch] published only on success.
mth_mirror_triangle_recover:
  MOVI r0,0
  ST r15,r0,@mtr_link
  ST r1,r0,@mtr_saved
  ST r2,r0,@mtr_flow
  ST r3,r0,@mtr_epoch
  ST r4,r0,@mtr_dest
  CMP r1,r0
  JMP[EQ] @mtr_bad
  CMP r2,r0
  JMP[EQ] @mtr_bad
  CMP r4,r0
  JMP[EQ] @mtr_bad
  LD r9,r1,26
  CMP r9,r3
  JMP[NE] @mtr_stale
  LD r8,r1,0
  LD r9,r1,1
  LD r10,r1,2
  MOVI r11,255
  CMP r8,r11
  JMP[GE] @mtr_bad
  CMP r9,r11
  JMP[GE] @mtr_bad
  CMP r10,r11
  JMP[GE] @mtr_bad
  CMP r8,r9
  JMP[EQ] @mtr_bad
  CMP r8,r10
  JMP[EQ] @mtr_bad
  CMP r9,r10
  JMP[EQ] @mtr_bad
  LD r11,r1,11
  ST r11,r0,@mtr_loop
  CALL @mtr_check_f32
  CMP r12,r0
  JMP[NE] @mtr_bad_source

  LD r10,r0,@mtr_saved
  LD r8,r10,1
  LD r9,r10,2
  CALL @mtr_edge
  ST r10,r0,@mtr_bc
  ADD r11,r10,r0
  CALL @mtr_check_f32
  CMP r12,r0
  JMP[NE] @mtr_bad_source
  LD r10,r0,@mtr_saved
  LD r8,r10,2
  LD r9,r10,0
  CALL @mtr_edge
  ST r10,r0,@mtr_ca
  ADD r11,r10,r0
  CALL @mtr_check_f32
  CMP r12,r0
  JMP[NE] @mtr_bad_source
  LD r10,r0,@mtr_loop
  LD r11,r0,@mtr_bc
  FSUB r10,r10,r11
  LD r11,r0,@mtr_ca
  FSUB r10,r10,r11
  ST r10,r0,@mtr_repair
  ADD r11,r10,r0
  CALL @mtr_check_f32
  CMP r12,r0
  JMP[NE] @mtr_bad_source

  LD r10,r0,@mtr_saved
  LD r8,r10,0
  LD r9,r10,1
  CALL @mtr_edge
  ST r10,r0,@mtr_actual
  ADD r11,r10,r0
  CALL @mtr_check_f32
  CMP r12,r0
  JMP[NE] @mtr_bad_source
  LD r11,r0,@mtr_repair
  FSUB r10,r10,r11
  ST r10,r0,@mtr_residual
  ADD r11,r10,r0
  CALL @mtr_check_f32
  CMP r12,r0
  JMP[NE] @mtr_bad_source
  LD r11,r0,@mtr_dest
  LD r10,r0,@mtr_repair
  ST r10,r11,0
  LD r10,r0,@mtr_actual
  ST r10,r11,1
  LD r10,r0,@mtr_residual
  ST r10,r11,2
  LD r10,r0,@mtr_epoch
  ST r10,r11,3
  MOVI r1,1
  LD r2,r0,@mtr_repair
  LD r3,r0,@mtr_residual
  MOVI r4,0
  JMP @mtr_return

; r11=float32 bits => r12=0 good/1 NaN or Inf.
mtr_check_f32:
  MOVI r12,0xFFFF
  MOVHI r12,0x7FFF
  BOOL.8 r11,r11,r12
  MOVI r12,0
  MOVHI r12,0x7F80
  BOOL.8 r11,r11,r12
  CMP r11,r12
  JMP[NE] @mtr_finite
  MOVI r12,1
  RET
mtr_finite:
  MOVI r12,0
  RET

; r8=u,r9=v, signed scalar ->r10; same exact C(256,2) index as Hodge.
mtr_edge:
  MOVI r11,0
  CMP r8,r9
  JMP[LT] @mtr_sorted
  ADD r12,r8,r0
  ADD r8,r9,r0
  ADD r9,r12,r0
  MOVI r11,1
mtr_sorted:
  MOVI r12,511
  SUB r12,r12,r8
  MUL r12,r12,r8
  SHR r12,r12,1
  SUB r14,r9,r8
  ADDI r14,r14,-1
  ADD r12,r12,r14
  LD r14,r0,@mtr_flow
  ADD r14,r14,r12
  LD r10,r14,0
  CMP r11,r0
  JMP[EQ] @mtr_edge_done
  FSUB r10,r0,r10
mtr_edge_done:
  RET

mtr_bad:
  MOVI r4,1
  JMP @mtr_reject
mtr_stale:
  MOVI r4,2
  JMP @mtr_reject
mtr_bad_source:
  MOVI r4,3
mtr_reject:
  MOVI r1,0
  MOVI r2,0
  MOVI r3,0
mtr_return:
  MOVI r13,1
  LD r15,r0,@mtr_link
  RET
mtr_link:
  .word 0
mtr_saved:
  .word 0
mtr_flow:
  .word 0
mtr_epoch:
  .word 0
mtr_dest:
  .word 0
mtr_loop:
  .word 0
mtr_bc:
  .word 0
mtr_ca:
  .word 0
mtr_actual:
  .word 0
mtr_repair:
  .word 0
mtr_residual:
  .word 0
