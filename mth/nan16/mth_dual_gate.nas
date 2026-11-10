; Raw NaN16 two-head / three-timescale self-modification gate.
;
; Fast head: triad proposal acceptance.
; Medium gate: 43/85 field acceptance.
; Slow gate: coherence threshold.
;
; ABI:
;   r1 = fast accepted (0/1)
;   r2 = slow-head accepted (0/1)
;   r3 = medium field accepted (0/1)
;   r4 = slow coherence (Q16)
;   r5 = slow coherence threshold (Q16)
;   r6 = current mask
;   r7 = patch
; Returns:
;   r1 = commit (1 only when fast, slow, medium and slow coherence all pass)
;   r2 = new mask (current XOR patch on commit, else current)
;   r3 = fast credit delta (1/-1)
;   r4 = slow credit delta (1/-1)
;   r5 = medium credit delta (1/-1)
mth_dual_gate:
  MOVI r8,0
  MOVI r9,0
  MOVI r10,0
  CMP r1,r0
  JMP[EQ] @mth_dg_fast_no
  MOVI r8,1
  JMP @mth_dg_fast_done
mth_dg_fast_no:
  MOVI r8,0
mth_dg_fast_done:
  CMP r2,r0
  JMP[EQ] @mth_dg_slow_no
  ADDI r9,r9,1
  JMP @mth_dg_slow_done
mth_dg_slow_no:
  SUB r9,r0,r9
  ADDI r9,r9,-1
mth_dg_slow_done:
  CMP r3,r0
  JMP[EQ] @mth_dg_medium_no
  MOVI r10,1
  JMP @mth_dg_medium_done
mth_dg_medium_no:
  MOVI r10,-1
mth_dg_medium_done:

  MOVI r1,0
  CMP r8,r0
  JMP[EQ] @mth_dg_done
  CMP r2,r0
  JMP[EQ] @mth_dg_done
  CMP r3,r0
  JMP[EQ] @mth_dg_done
  CMP r4,r5
  JMP[LT] @mth_dg_done
  MOVI r1,1
mth_dg_done:
  ADD r2,r6,r0
  CMP r1,r0
  JMP[EQ] @mth_dg_mask_done
  BOOL.6 r2,r6,r7
mth_dg_mask_done:
  ADD r3,r8,r0
  ADD r4,r9,r0
  ADD r5,r10,r0
  RET
