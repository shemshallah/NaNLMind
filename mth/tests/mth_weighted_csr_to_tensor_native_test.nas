; Cross-repository NATIVE NaN16 weighted CSR -> heads -> triheads ->
; directed C(256,2) hypertensor CANDIDATE proposal. No host-side math.
; The canonical weighted v2 implementation is INCLUDED from NaNROUTER/main
; checked out at nanrouter/. It is NOT copied/forked into NaNLMind.
; The source digest and ABI are verified by the accompanying CI job.
.org 0
JMP @wct_main
.include "../../nanrouter/mth/nan16/mth_sparse_weighted_graph_laplacian_v2.nas"
.include "../nan16/mth_hypertensor256_mirror_arena_map.nas"
.include "../nan16/mth_hypertensor256_mirror_dual_map.nas"
.include "../nan16/mth_spectral_trihead_tensor_proposal.nas"

wct_main:
  MOVI r0,0
  MOVI r13,1
  ; One undirected edge 0<->1, represented as symmetric CSR with two
  ; directed slots. x0=0, x1=1 Q16, weight=1.
  MOVI r10,@wct_offsets
  ST r0,r10,0
  MOVI r11,1
  ST r11,r10,1
  MOVI r11,2
  MOVI r9,2
wct_offsets_loop:
  ADD r12,r10,r9
  ST r11,r12,0
  ADDI r9,r9,1
  MOVI r12,257
  CMP r9,r12
  JMP[LT] @wct_offsets_loop
  MOVI r10,1
  ST r10,r0,@wct_neighbors
  ST r0,r0,@wct_neighbors+1
  ST r10,r0,@wct_weights
  ST r10,r0,@wct_weights+1
  MOVI r10,0
  MOVHI r10,1
  ST r10,r0,@wct_x+1
  MOVI r1,@wct_offsets
  MOVI r2,@wct_neighbors
  MOVI r3,@wct_weights
  MOVI r4,@wct_x
  MOVI r5,@wct_spectral
  MOVI r6,2
  MOVI r7,@wct_csr_scratch
  CALL @mth_sparse_weighted_graph_laplacian_q16_16_i64_v2
  CMP r1,r13
  JMP[NE] @wct_fail
  ; Lw*x = [-65536, +65536, 0,...0] as exact signed I64.
  MOVI r10,0
  MOVHI r10,0xFFFF
  LD r11,r0,@wct_spectral
  CMP r11,r10
  JMP[NE] @wct_fail
  MOVI r10,0xFFFF
  MOVHI r10,0xFFFF
  LD r11,r0,@wct_spectral+1
  CMP r11,r10
  JMP[NE] @wct_fail
  MOVI r10,0
  MOVHI r10,1
  LD r11,r0,@wct_spectral+2
  CMP r11,r10
  JMP[NE] @wct_fail
  LD r11,r0,@wct_spectral+3
  CMP r11,r0
  JMP[NE] @wct_fail
  LD r11,r0,@wct_spectral+510
  CMP r11,r0
  JMP[NE] @wct_fail
  LD r11,r0,@wct_spectral+511
  CMP r11,r0
  JMP[NE] @wct_fail

  ; Every triad accepts a 2-of-3 vote, but only explicitly authorized
  ; head1 can generate a record. Root head0 has nonzero -1 spectral
  ; evidence and is still forbidden by its missing writer capability.
  MOVI r9,0
wct_votes_loop:
  MOVI r10,@wct_votes
  ADD r10,r10,r9
  MOVI r11,7
  ST r11,r10,0
  ADDI r9,r9,1
  MOVI r11,85
  CMP r9,r11
  JMP[LT] @wct_votes_loop
  MOVI r10,1
  ST r10,r0,@wct_writer+1
  ST r10,r0,@wct_pairs+2
  MOVI r10,2
  ST r10,r0,@wct_pairs+3

  MOVI r10,@wct_spectral
  ST r10,r0,@wct_request
  MOVI r10,@wct_votes
  ST r10,r0,@wct_request+1
  MOVI r10,@wct_pairs
  ST r10,r0,@wct_request+2
  MOVI r10,@wct_writer
  ST r10,r0,@wct_request+3
  MOVI r10,@wct_scratch
  ST r10,r0,@wct_request+4
  MOVI r10,@wct_output
  ST r10,r0,@wct_request+5
  MOVI r10,31
  ST r10,r0,@wct_request+6
  ST r10,r0,@wct_request+7
  ST r13,r0,@wct_request+8
  ST r13,r0,@wct_request+9
  ST r0,r0,@wct_request+10
  ST r0,r0,@wct_request+11
  MOVI r1,@wct_request
  CALL @mth_spectral_trihead_tensor_proposal
  CMP r1,r13
  JMP[NE] @wct_fail
  MOVI r10,85
  CMP r2,r10
  JMP[NE] @wct_fail
  CMP r3,r13
  JMP[NE] @wct_fail
  LD r10,r0,@wct_output
  CMP r10,r13
  JMP[NE] @wct_fail
  LD r10,r0,@wct_output+1
  CMP r10,r13
  JMP[NE] @wct_fail
  MOVI r11,2
  LD r10,r0,@wct_output+2
  CMP r10,r11
  JMP[NE] @wct_fail
  ; Exact candidate byte offset for h=1,a=1,b=2: 0x04040BF8.
  MOVI r11,0x0BF8
  MOVHI r11,0x0404
  LD r10,r0,@wct_output+3
  CMP r10,r11
  JMP[NE] @wct_fail
  MOVI r11,0
  MOVHI r11,1
  LD r10,r0,@wct_output+4
  CMP r10,r11
  JMP[NE] @wct_fail

  ; A stale generation fails closed and leaves already published records
  ; unchanged. No active-bank address was ever issued or written.
  MOVI r10,30
  ST r10,r0,@wct_request+7
  MOVI r1,@wct_request
  CALL @mth_spectral_trihead_tensor_proposal
  CMP r1,r0
  JMP[NE] @wct_fail
  MOVI r11,0x0BF8
  MOVHI r11,0x0404
  LD r10,r0,@wct_output+3
  CMP r10,r11
  JMP[NE] @wct_fail
  MOVI r1,@wct_pass
  CALL @wct_puts
  HALT

wct_fail:
  MOVI r1,@wct_bad
  CALL @wct_puts
  HALT
wct_puts:
  MOVI r4,255
wct_puts_word:
  LD r2,r1,0
  MOVI r3,4
wct_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @wct_puts_byte
  ADD r1,r1,r13
  JMP @wct_puts_word
wct_pass:
.str "MTH WEIGHTED CSR TO MIRRORED TENSOR PASS\n"
wct_bad:
.str "MTH WEIGHTED CSR TO MIRRORED TENSOR FAIL\n"

.org 8192
wct_offsets:
  .word 0
.org 8500
wct_neighbors:
  .word 0,0
.org 8520
wct_weights:
  .word 0,0
.org 8550
wct_x:
  .word 0
.org 9000
wct_spectral:
  .word 0
.org 9600
wct_csr_scratch:
  .word 0
.org 9700
wct_votes:
  .word 0
.org 9850
wct_pairs:
  .word 0
.org 10380
wct_writer:
  .word 0
.org 10800
wct_scratch:
  .word 0
.org 12200
wct_output:
  .word 0
.org 14000
wct_request:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
