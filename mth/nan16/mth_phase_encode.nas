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

; Wide streaming trig phase encoder.
; ABI:
;   r1 = byte array pointer (one byte per guest word)
;   r2 = byte count (0..64)
;   r3 = lane count D (1..64)
;   r4 = output complex[D] address (2*D Q16 words)
; Returns r1 = shard 0..15
mth_phase_encode_wide:
  MOVI r12,@mth_pw_link
  ST r15,r12,0
  MOVI r12,@mth_pw_in
  ST r1,r12,0
  MOVI r12,@mth_pw_count
  ST r2,r12,0
  MOVI r12,@mth_pw_d
  ST r3,r12,0
  MOVI r12,@mth_pw_out
  ST r4,r12,0

  MOVI r5,0
mth_pw_clear:
  MOVI r12,@mth_pw_d
  LD r6,r12,0
  MOVI r7,2
  MUL r6,r6,r7
  CMP r5,r6
  JMP[GE] @mth_pw_clear_done
  ADD r6,r4,r5
  ST r0,r6,0
  ADDI r5,r5,1
  JMP @mth_pw_clear
mth_pw_clear_done:
  MOVI r12,@mth_pw_i
  ST r0,r12,0
mth_pw_loop:
  MOVI r12,@mth_pw_i
  LD r5,r12,0
  MOVI r12,@mth_pw_count
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pw_done
  MOVI r12,@mth_pw_in
  LD r6,r12,0
  ADD r6,r6,r5
  LD r4,r6,0
  ; lane = (byte + i) mod D
  ADD r6,r4,r5
  MOVI r12,@mth_pw_d
  LD r7,r12,0
  MODU r6,r6,r7
  MOVI r12,@mth_pw_lane
  ST r6,r12,0
  ; phase = (byte*257 + i*8192) mod 65536
  MOVI r7,257
  MUL r6,r4,r7
  MOVI r7,8192
  MUL r7,r5,r7
  ADD r6,r6,r7
  SHL r6,r6,16
  SHR r6,r6,16
  ADD r1,r6,r0
  CALL @mth_q16_sin_cos
  MOVI r12,@mth_pw_lane
  LD r6,r12,0
  MOVI r7,2
  MUL r6,r6,r7
  MOVI r12,@mth_pw_out
  LD r7,r12,0
  ADD r8,r7,r6
  LD r9,r8,0
  ADD r9,r9,r1
  ST r9,r8,0
  ADDI r8,r8,1
  LD r9,r8,0
  ADD r9,r9,r2
  ST r9,r8,0
  MOVI r12,@mth_pw_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pw_loop
mth_pw_done:
  MOVI r12,@mth_pw_out
  LD r8,r12,0
  MOVI r5,0
  MOVI r1,0
  MOVI r12,@mth_pw_d
  LD r6,r12,0
mth_pw_shard:
  CMP r5,r6
  JMP[GE] @mth_pw_shard_done
  MOVI r7,2
  MUL r7,r5,r7
  ADD r7,r8,r7
  LD r7,r7,0
  ADD r1,r1,r7
  ADDI r5,r5,1
  JMP @mth_pw_shard
mth_pw_shard_done:
  MOVI r6,16
  MODU r1,r1,r6
  MOVI r12,@mth_pw_link
  LD r15,r12,0
  RET

mth_pw_link:
  .word 0
mth_pw_in:
  .word 0
mth_pw_count:
  .word 0
mth_pw_d:
  .word 0
mth_pw_out:
  .word 0
mth_pw_i:
  .word 0
mth_pw_lane:
  .word 0

; Batch phase encode: r1=count, r2=byte windows, r3=W, r4=D, r5=out complex.
; Returns r1=processed count. The guest calls mth_phase_encode_wide for each
; window; only the output pointer changes.
mth_phase_encode_batch:
  MOVI r12,@mth_pb_link
  ST r15,r12,0
  MOVI r12,@mth_pb_count
  ST r1,r12,0
  MOVI r12,@mth_pb_in
  ST r2,r12,0
  MOVI r12,@mth_pb_w
  ST r3,r12,0
  MOVI r12,@mth_pb_d
  ST r4,r12,0
  MOVI r12,@mth_pb_out
  ST r5,r12,0
  MOVI r12,@mth_pb_i
  ST r0,r12,0
mth_pb_loop:
  MOVI r12,@mth_pb_i
  LD r5,r12,0
  MOVI r12,@mth_pb_count
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_pb_done
  MOVI r12,@mth_pb_w
  LD r7,r12,0
  MUL r7,r7,r5
  MOVI r12,@mth_pb_in
  LD r8,r12,0
  ADD r8,r8,r7
  MOVI r12,@mth_pb_d
  LD r9,r12,0
  ADD r10,r9,r9
  MUL r10,r10,r5
  MOVI r12,@mth_pb_out
  LD r11,r12,0
  ADD r11,r11,r10
  ADD r1,r8,r0
  MOVI r12,@mth_pb_w
  LD r2,r12,0
  ADD r3,r9,r0
  ADD r4,r11,r0
  CALL @mth_phase_encode_wide_table
  MOVI r12,@mth_pb_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pb_loop
mth_pb_done:
  MOVI r12,@mth_pb_count
  LD r1,r12,0
  MOVI r12,@mth_pb_link
  LD r15,r12,0
  RET

mth_pb_link:
  .word 0
mth_pb_count:
  .word 0
mth_pb_in:
  .word 0
mth_pb_w:
  .word 0
mth_pb_d:
  .word 0
mth_pb_out:
  .word 0
mth_pb_i:
  .word 0

; One-time raw phase lookup table. 256 bins, Q16 cos/sin pairs at 0x3000.
mth_phase_table_init:
  MOVI r12,@mth_pt_link
  ST r15,r12,0
  MOVI r12,@mth_pt_i
  ST r0,r12,0
mth_pt_loop:
  MOVI r12,@mth_pt_i
  LD r5,r12,0
  MOVI r6,256
  CMP r5,r6
  JMP[GE] @mth_pt_done
  MOVI r7,256
  MUL r1,r5,r7
  MOVI r10,0x3000
  MOVI r11,2
  MUL r11,r5,r11
  ADD r11,r10,r11
  CALL @mth_q16_sin_cos
  ST r1,r11,0
  ADDI r11,r11,1
  ST r2,r11,0
  MOVI r12,@mth_pt_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_pt_loop
mth_pt_done:
  MOVI r12,@mth_pt_link
  LD r15,r12,0
  RET

mth_pt_link:
  .word 0
mth_pt_i:
  .word 0

; Wide phase encoder using the precomputed 256-bin Q16 table.
; ABI: r1=bytes, r2=count, r3=D, r4=out complex[D]. Returns shard 0..15.
mth_phase_encode_wide_table:
  MOVI r12,@mth_ptt_link
  ST r15,r12,0
  MOVI r12,@mth_ptt_in
  ST r1,r12,0
  MOVI r12,@mth_ptt_count
  ST r2,r12,0
  MOVI r12,@mth_ptt_d
  ST r3,r12,0
  MOVI r12,@mth_ptt_out
  ST r4,r12,0
  MOVI r5,0
mth_ptt_clear:
  MOVI r12,@mth_ptt_d
  LD r6,r12,0
  MOVI r7,2
  MUL r6,r6,r7
  CMP r5,r6
  JMP[GE] @mth_ptt_clear_done
  ADD r6,r4,r5
  ST r0,r6,0
  ADDI r5,r5,1
  JMP @mth_ptt_clear
mth_ptt_clear_done:
  MOVI r12,@mth_ptt_i
  ST r0,r12,0
mth_ptt_loop:
  MOVI r12,@mth_ptt_i
  LD r5,r12,0
  MOVI r12,@mth_ptt_count
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_ptt_done
  MOVI r12,@mth_ptt_in
  LD r6,r12,0
  ADD r6,r6,r5
  LD r4,r6,0
  ; phase bin = ((byte*257 + i*8192) & 0xffff) >> 8
  MOVI r7,257
  MUL r6,r4,r7
  MOVI r7,8192
  MUL r7,r5,r7
  ADD r6,r6,r7
  SHL r6,r6,16
  SHR r6,r6,16
  SHR r6,r6,8
  ; table at 0x3000: cos, sin
  MOVI r7,0x3000
  MOVI r8,2
  MUL r8,r6,r8
  ADD r7,r7,r8
  LD r9,r7,0
  ADDI r7,r7,1
  LD r10,r7,0
  ; lane = (byte + i) % D
  MOVI r12,@mth_ptt_d
  LD r6,r12,0
  ADD r11,r4,r5
  MODU r11,r11,r6
  ; output[lane]
  MOVI r12,@mth_ptt_out
  LD r6,r12,0
  MOVI r7,2
  MUL r7,r11,r7
  ADD r8,r6,r7
  LD r7,r8,0
  ADD r7,r7,r9
  ST r7,r8,0
  ADDI r8,r8,1
  LD r7,r8,0
  ADD r7,r7,r10
  ST r7,r8,0
  MOVI r12,@mth_ptt_i
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_ptt_loop
mth_ptt_done:
  MOVI r12,@mth_ptt_out
  LD r8,r12,0
  MOVI r5,0
  MOVI r1,0
  MOVI r12,@mth_ptt_d
  LD r6,r12,0
mth_ptt_shard:
  CMP r5,r6
  JMP[GE] @mth_ptt_shard_done
  MOVI r7,2
  MUL r7,r5,r7
  ADD r7,r8,r7
  LD r7,r7,0
  ADD r1,r1,r7
  ADDI r5,r5,1
  JMP @mth_ptt_shard
mth_ptt_shard_done:
  MOVI r6,16
  MODU r1,r1,r6
  MOVI r12,@mth_ptt_link
  LD r15,r12,0
  RET

mth_ptt_link:
  .word 0
mth_ptt_in:
  .word 0
mth_ptt_count:
  .word 0
mth_ptt_d:
  .word 0
mth_ptt_out:
  .word 0
mth_ptt_i:
  .word 0
