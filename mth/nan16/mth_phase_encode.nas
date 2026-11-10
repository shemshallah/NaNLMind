; Streaming trig phase encoder.
;
; ABI:
;   r1 = byte array pointer (one byte per guest word)
;   r2 = byte count (0..64)
;   r3 = output pointer: 8 complex lanes = 16 Q16 words
;        [cos0, sin0, cos1, sin1, ... cos7, sin7]
;
; The guest bundles a phasor for every byte into a lane selected by
; (byte + position) mod 8 and phase (byte*257 + position*8192) mod 65536.
; All phase/trig/accumulation arithmetic is raw NaN16.
mth_phase_encode:
  MOVI r12,@mth_pe_link
  ST r15,r12,0
  MOVI r12,@mth_pe_in
  ST r1,r12,0
  MOVI r12,@mth_pe_count
  ST r2,r12,0
  MOVI r12,@mth_pe_out
  ST r3,r12,0

  ; clear 16 Q16 words
  MOVI r5,0
mth_pe_clear:
  MOVI r6,16
  CMP r5,r6
  JMP[GE] @mth_pe_clear_done
  ADD r6,r3,r5
  ST r0,r6,0
  ADDI r5,r5,1
  JMP @mth_pe_clear
mth_pe_clear_done:

  MOVI r12,@mth_pe_i
  ST r0,r12,0
mth_pe_loop:
  MOVI r12,@mth_pe_i
  LD r5,r12,0
  MOVI r12,@mth_pe_count
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pe_done

  ; byte = in[i]
  MOVI r12,@mth_pe_in
  LD r7,r12,0
  ADD r7,r7,r5
  LD r4,r7,0

  ; lane = (byte + i) mod 8
  ADD r8,r4,r5
  MOVI r9,8
  MODU r8,r8,r9
  MOVI r12,@mth_pe_lane
  ST r8,r12,0

  ; phase = (byte*257 + i*8192) mod 65536
  MOVI r9,257
  MUL r6,r4,r9
  MOVI r9,8192
  MUL r7,r5,r9
  ADD r6,r6,r7
  SHL r6,r6,16
  SHR r6,r6,16
  ADD r1,r6,r0
  CALL @mth_q16_sin_cos

  ; out[lane*2] += cos; out[lane*2+1] += sin
  MOVI r12,@mth_pe_lane
  LD r8,r12,0
  MOVI r9,2
  MUL r8,r8,r9
  MOVI r12,@mth_pe_out
  LD r9,r12,0
  ADD r10,r9,r8
  LD r11,r10,0
  ADD r11,r11,r1
  ST r11,r10,0
  ADDI r10,r10,1
  LD r11,r10,0
  ADD r11,r11,r2
  ST r11,r10,0

  MOVI r12,@mth_pe_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pe_loop
mth_pe_done:
  ; shard = sum of real lanes & 15
  MOVI r12,@mth_pe_out
  LD r9,r12,0
  MOVI r5,0
  MOVI r1,0
mth_pe_shard_loop:
  MOVI r6,8
  CMP r5,r6
  JMP[GE] @mth_pe_shard_done
  MOVI r6,2
  MUL r6,r5,r6
  ADD r6,r9,r6
  LD r7,r6,0
  ADD r1,r1,r7
  ADDI r5,r5,1
  JMP @mth_pe_shard_loop
mth_pe_shard_done:
  MOVI r6,16
  MODU r1,r1,r6
  MOVI r12,@mth_pe_link
  LD r15,r12,0
  RET

mth_pe_link:
  .word 0
mth_pe_in:
  .word 0
mth_pe_count:
  .word 0
mth_pe_out:
  .word 0
mth_pe_i:
  .word 0
mth_pe_lane:
  .word 0
