.org 0
JMP @mth_phase_pq_main
.include "../nan16/mth_phase_pq.nas"
.include "../nan16/mth_q16_mul.nas"
.include "../nan16/mth_q16_sin_cos.nas"
.include "../nan16/mth_sparse_knn.nas"

mth_phase_pq_main:
  MOVI r13,1
  ; codebook: four 8-word Q16 rows
  MOVI r1,0x6000
  MOVI r2,0
  MOVI r3,32
mth_pp_clear_book:
  CMP r2,r3
  JMP[GE] @mth_pp_book_done
  ADD r4,r1,r2
  ST r0,r4,0
  ADDI r2,r2,1
  JMP @mth_pp_clear_book
mth_pp_book_done:
  ; row 1 = 256,0...
  MOVI r2,256
  ST r2,r1,8
  ; query 512,0... closest row2 (512)
  MOVI r1,0x6100
  MOVI r2,256
  ST r2,r1,0
  MOVI r2,0
  ST r2,r1,1
  ST r2,r1,2
  ST r2,r1,3
  ST r2,r1,4
  ST r2,r1,5
  ST r2,r1,6
  ST r2,r1,7

  MOVI r1,0x6100
  MOVI r2,0x6000
  MOVI r3,4
  MOVI r4,8
  MOVI r5,0x6200
  CALL @mth_pq_encode
  MOVI r10,0x6200
  LD r11,r10,0
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_pp_fail

  ; spectral identity: out = in
  MOVI r1,0x6300
  MOVI r2,0
  MOVI r3,64
mth_pp_clear_a:
  CMP r2,r3
  JMP[GE] @mth_pp_a_done
  ADD r4,r1,r2
  ST r0,r4,0
  ADDI r2,r2,1
  JMP @mth_pp_clear_a
mth_pp_a_done:
  MOVI r2,0
  MOVHI r2,0x0001
  ST r2,r1,0
  ST r2,r1,9
  ST r2,r1,18
  ST r2,r1,27
  ST r2,r1,36
  ST r2,r1,45
  ST r2,r1,54
  ST r2,r1,63
  MOVI r1,0x6400
  MOVI r2,0
  MOVI r3,8
  MOVI r5,8192
mth_pp_init:
  CMP r2,r3
  JMP[GE] @mth_pp_init_done
  ADD r4,r1,r2
  ST r5,r4,0
  ADDI r2,r2,1
  JMP @mth_pp_init
mth_pp_init_done:
  ; restore count 8 (r2 was overwritten above)
  MOVI r1,0x6300
  MOVI r2,0x6400
  MOVI r3,0x6500
  CALL @mth_spectral_iter
  MOVI r10,0x6500
  MOVI r2,0
  MOVI r3,8
  MOVI r5,8192
mth_pp_spectral_check:
  CMP r2,r3
  JMP[GE] @mth_pp_spectral_ok
  ADD r4,r10,r2
  LD r11,r4,0
  CMP r11,r5
  JMP[NE] @mth_pp_fail
  ADDI r2,r2,1
  JMP @mth_pp_spectral_check
mth_pp_spectral_ok:

  ; rotate by zero preserves lane 0 complex
  MOVI r1,0x6600
  MOVI r2,8192
  ST r2,r1,0
  ST r0,r1,1
  MOVI r2,0x6700
  MOVI r3,0
  MOVI r4,8
  CALL @mth_phase_rotate
  MOVI r10,0x6700
  LD r11,r10,0
  MOVI r12,8192
  CMP r11,r12
  JMP[NE] @mth_pp_fail

  ; sparse kNN: query 100, bank {0,1000}; k=1 should select index 1
  MOVI r1,0x6800
  MOVI r2,100
  ST r2,r1,0
  MOVI r2,0
  ST r2,r1,1
  ST r2,r1,2
  ST r2,r1,3
  ST r2,r1,4
  ST r2,r1,5
  ST r2,r1,6
  ST r2,r1,7
  MOVI r1,0x6900
  MOVI r2,0
  ST r2,r1,0
  MOVI r2,1000
  ST r2,r1,8
  MOVI r1,0x6800
  MOVI r2,0x6900
  MOVI r3,2
  MOVI r4,8
  MOVI r5,1
  MOVI r6,0x6A00
  MOVI r7,0x6B00
  CALL @mth_sparse_knn
  MOVI r10,0x6A00
  LD r11,r10,0
  MOVI r12,1
  CMP r11,r12
  JMP[NE] @mth_pp_fail

  MOVI r1,@mth_pp_pass
  CALL @mth_pp_puts
  HALT
mth_pp_fail:
  MOVI r1,@mth_pp_bad
  CALL @mth_pp_puts
  HALT

mth_pp_puts:
  MOVI r4,255
mth_pp_puts_word:
  LD r2,r1,0
  MOVI r3,4
mth_pp_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @mth_pp_puts_byte
  ADD r1,r1,r13
  JMP @mth_pp_puts_word

mth_pp_pass:
.str "MTH PHASE PQ SPECTRAL PASS\n"
mth_pp_bad:
.str "MTH PHASE PQ SPECTRAL FAIL\n"
