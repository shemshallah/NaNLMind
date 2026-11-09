; Raw NaN16 hot-head -> auto-mapped trihead grouping.
;
; ABI:
;   r1 = pointer to 255 signed head credits
;   r2 = hot-head threshold (credit > threshold)
; Returns:
;   r1 = number of hot heads
;   r2 = number of complete hot triads (hot_count / 3)
;   r3 = 1 when the field gate is met (>= 43 complete hot triads)
;   r4 = 255 mapped heads
;
; Output mapping is written as 85 triads x 3 heads at 0x8000.  Hot heads are
; placed first in scan order, then cold heads fill the remaining slots.  Every
; mapped head is unique.  The first floor(hot_count/3) triads are therefore
; triads made from three hot individual heads; the global field flag is emitted
; at the 43/85 threshold.  The host commits the mapping only after checking
; the raw result.
;
; Scratch:
;   0x7800 hot list, 0x7900 cold list, 0x7A00 used flags, 0x8000 mapping.

mth_hot_trihead:
  MOVI r12,@mth_ht_link
  ST r15,r12,0
  MOVI r12,@mth_ht_input
  ST r1,r12,0
  MOVI r12,@mth_ht_threshold
  ST r2,r12,0

  MOVI r8,0x7A00          ; used[0..254] = 0
  MOVI r2,0
  MOVI r11,0
mth_ht_clear_used:
  ADD r10,r8,r2
  ST r11,r10,0
  ADDI r2,r2,1
  MOVI r9,255
  CMP r2,r9
  JMP[LT] @mth_ht_clear_used

  MOVI r5,0x7000          ; input credits
  MOVI r6,0x7800          ; hot list
  MOVI r3,0               ; hot count
  MOVI r2,0               ; head index
  MOVI r9,255
  MOVI r12,@mth_ht_threshold
  LD r1,r12,0
mth_ht_hot_scan:
  CMP r2,r9
  JMP[GE] @mth_ht_hot_done
  ADD r10,r5,r2
  LD r11,r10,0
  CMP r11,r1
  JMP[LE] @mth_ht_not_hot
  ADD r10,r6,r3
  ST r2,r10,0
  ADD r10,r8,r2
  MOVI r11,1
  ST r11,r10,0
  ADDI r3,r3,1
mth_ht_not_hot:
  ADDI r2,r2,1
  JMP @mth_ht_hot_scan

mth_ht_hot_done:
  MOVI r7,0x7900          ; cold list
  MOVI r4,0               ; cold count
  MOVI r2,0
mth_ht_cold_scan:
  CMP r2,r9
  JMP[GE] @mth_ht_cold_done
  ADD r10,r8,r2
  LD r11,r10,0
  CMP r11,r0
  JMP[NE] @mth_ht_cold_skip
  ADD r10,r7,r4
  ST r2,r10,0
  ADDI r4,r4,1
mth_ht_cold_skip:
  ADDI r2,r2,1
  JMP @mth_ht_cold_scan

mth_ht_cold_done:
  ; Copy hot heads first, then cold heads, into the 255-slot mapping.
  MOVI r10,0x8000
  MOVI r2,0
mth_ht_copy_hot:
  CMP r2,r3
  JMP[GE] @mth_ht_copy_hot_done
  ADD r11,r6,r2
  LD r12,r11,0
  ADD r11,r10,r2
  ST r12,r11,0
  ADDI r2,r2,1
  JMP @mth_ht_copy_hot

mth_ht_copy_hot_done:
  MOVI r2,0
mth_ht_copy_cold:
  CMP r2,r4
  JMP[GE] @mth_ht_copy_done
  ADD r11,r7,r2
  LD r12,r11,0
  ADD r11,r3,r2         ; destination = hot_count + cold_index
  ADD r11,r10,r11
  ST r12,r11,0
  ADDI r2,r2,1
  JMP @mth_ht_copy_cold

mth_ht_copy_done:
  ; floor(hot_count / 3) complete hot triads.
  ADD r1,r3,r0
  MOVI r10,3
  DIV r2,r1,r10
  MOVI r10,43
  CMP r2,r10
  MOVI r3,0
  JMP[LT] @mth_ht_field_done
  MOVI r3,1
mth_ht_field_done:
  MOVI r4,255
  MOVI r13,1
  MOVI r12,@mth_ht_link
  LD r15,r12,0
  RET

mth_ht_link:
  .word 0
mth_ht_input:
  .word 0
mth_ht_threshold:
  .word 0
