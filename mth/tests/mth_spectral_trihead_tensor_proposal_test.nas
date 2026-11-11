; Real guest proof: weighted spectral I64 -> voted directed candidate offsets.
; Does not allocate, read, write, or promote an active hypertensor bank.
.org 0
JMP @sp_test_main
.include "../nan16/mth_hypertensor256_mirror_arena_map.nas"
.include "../nan16/mth_hypertensor256_mirror_dual_map.nas"
.include "../nan16/mth_spectral_trihead_tensor_proposal.nas"

sp_test_main:
  MOVI r0,0
  MOVI r13,1
  MOVI r9,0
sp_test_seed_head:
  MOVI r10,255
  CMP r9,r10
  JMP[GE] @sp_test_seed_votes
  ; Signed I64 +1.0 Q16: high word zero, low 65536.
  MOVI r10,@sp_test_spectral
  SHL r11,r9,1
  ADD r10,r10,r11
  MOVI r12,0
  MOVHI r12,1
  ST r12,r10,0
  ST r0,r10,1
  ; Each head points at a shared mirror identity with independent lanes.
  MOVI r10,@sp_test_pairs
  ADD r10,r10,r11
  MOVI r12,1
  ST r12,r10,0
  MOVI r12,2
  ST r12,r10,1
  MOVI r10,@sp_test_permissions
  ADD r10,r10,r9
  ST r13,r10,0
  ADDI r9,r9,1
  JMP @sp_test_seed_head
sp_test_seed_votes:
  ; Head 0 is protected until explicitly granted.
  ST r0,r0,@sp_test_permissions
  ; Head 2 reverses the pair direction, offset must be +4.
  MOVI r10,2
  ST r10,r0,@sp_test_pairs+4
  MOVI r10,1
  ST r10,r0,@sp_test_pairs+5
  MOVI r9,0
sp_test_vote_loop:
  MOVI r10,@sp_test_votes
  ADD r10,r10,r9
  MOVI r11,7
  ST r11,r10,0
  ADDI r9,r9,1
  MOVI r11,85
  CMP r9,r11
  JMP[LT] @sp_test_vote_loop

  ; Whole request assembled in native guest RAM.
  MOVI r10,@sp_test_spectral
  ST r10,r0,@sp_test_request
  MOVI r10,@sp_test_votes
  ST r10,r0,@sp_test_request+1
  MOVI r10,@sp_test_pairs
  ST r10,r0,@sp_test_request+2
  MOVI r10,@sp_test_permissions
  ST r10,r0,@sp_test_request+3
  MOVI r10,@sp_test_scratch
  ST r10,r0,@sp_test_request+4
  MOVI r10,@sp_test_output
  ST r10,r0,@sp_test_request+5
  MOVI r10,2
  ST r10,r0,@sp_test_request+6
  MOVI r10,1
  ST r10,r0,@sp_test_request+7
  ST r13,r0,@sp_test_request+8
  ST r13,r0,@sp_test_request+9
  ST r0,r0,@sp_test_request+10
  ST r0,r0,@sp_test_request+11
  MOVI r10,12345
  ST r10,r0,@sp_test_output

  ; Stale generation is a no-op.
  MOVI r1,@sp_test_request
  CALL @mth_spectral_trihead_tensor_proposal
  CMP r1,r0
  JMP[NE] @sp_test_fail
  LD r10,r0,@sp_test_output
  MOVI r11,12345
  CMP r10,r11
  JMP[NE] @sp_test_fail

  ; Fresh generation but absent meta permission is a no-op.
  MOVI r10,1
  ST r10,r0,@sp_test_request+6
  ST r0,r0,@sp_test_request+9
  MOVI r1,@sp_test_request
  CALL @mth_spectral_trihead_tensor_proposal
  CMP r1,r0
  JMP[NE] @sp_test_fail
  LD r10,r0,@sp_test_output
  MOVI r11,12345
  CMP r10,r11
  JMP[NE] @sp_test_fail
  ST r13,r0,@sp_test_request+9

  ; 42/85 approved: field must reject and leave output untouched.
  MOVI r9,42
sp_test_suppress_votes:
  MOVI r10,@sp_test_votes
  ADD r10,r10,r9
  ST r0,r10,0
  ADDI r9,r9,1
  MOVI r11,85
  CMP r9,r11
  JMP[LT] @sp_test_suppress_votes
  MOVI r1,@sp_test_request
  CALL @mth_spectral_trihead_tensor_proposal
  CMP r1,r0
  JMP[NE] @sp_test_fail
  LD r10,r0,@sp_test_output
  MOVI r11,12345
  CMP r10,r11
  JMP[NE] @sp_test_fail

  MOVI r9,42
sp_test_restore_votes:
  MOVI r10,@sp_test_votes
  ADD r10,r10,r9
  MOVI r11,7
  ST r11,r10,0
  ADDI r9,r9,1
  MOVI r11,85
  CMP r9,r11
  JMP[LT] @sp_test_restore_votes

  ; Nonzero VOID head255 spectral data is rejected before output publication.
  MOVI r10,1
  ST r10,r0,@sp_test_spectral+510
  MOVI r1,@sp_test_request
  CALL @mth_spectral_trihead_tensor_proposal
  CMP r1,r0
  JMP[NE] @sp_test_fail
  LD r10,r0,@sp_test_output
  MOVI r11,12345
  CMP r10,r11
  JMP[NE] @sp_test_fail
  ST r0,r0,@sp_test_spectral+510

  ; Valid quorum+Hodge+meta+generation yields 254 records (head0 denied).
  MOVI r1,@sp_test_request
  CALL @mth_spectral_trihead_tensor_proposal
  CMP r1,r13
  JMP[NE] @sp_test_fail
  MOVI r10,85
  CMP r2,r10
  JMP[NE] @sp_test_fail
  MOVI r10,254
  CMP r3,r10
  JMP[NE] @sp_test_fail
  CMP r4,r0
  JMP[NE] @sp_test_fail

  ; First record: head1, pair(1,2), candidate bank offset 0x04040BF8.
  LD r10,r0,@sp_test_output
  CMP r10,r13
  JMP[NE] @sp_test_fail
  LD r10,r0,@sp_test_output+1
  CMP r10,r13
  JMP[NE] @sp_test_fail
  MOVI r11,2
  LD r10,r0,@sp_test_output+2
  CMP r10,r11
  JMP[NE] @sp_test_fail
  MOVI r11,0x0BF8
  MOVHI r11,0x0404
  LD r10,r0,@sp_test_output+3
  CMP r10,r11
  JMP[NE] @sp_test_fail
  MOVI r11,0
  MOVHI r11,1
  LD r10,r0,@sp_test_output+4
  CMP r10,r11
  JMP[NE] @sp_test_fail

  ; Second record: head2 pair(2,1), reverse orientation +4.
  MOVI r11,2
  LD r10,r0,@sp_test_output+5
  CMP r10,r11
  JMP[NE] @sp_test_fail
  MOVI r11,0x0BFC
  MOVHI r11,0x0408
  LD r10,r0,@sp_test_output+8
  CMP r10,r11
  JMP[NE] @sp_test_fail

  MOVI r1,@sp_test_pass
  CALL @sp_test_puts
  HALT
sp_test_fail:
  MOVI r1,@sp_test_bad
  CALL @sp_test_puts
  HALT
sp_test_puts:
  MOVI r4,255
sp_test_puts_word:
  LD r2,r1,0
  MOVI r3,4
sp_test_puts_byte:
  BOOL.8 r5,r2,r4
  CMP r5,r0
  RET[EQ]
  PUTC r5
  SHR r2,r2,8
  SUB r3,r3,r13
  JMP[NE] @sp_test_puts_byte
  ADD r1,r1,r13
  JMP @sp_test_puts_word
sp_test_pass:
.str "MTH SPECTRAL TRIHEAD TENSOR PROPOSAL PASS\n"
sp_test_bad:
.str "MTH SPECTRAL TRIHEAD TENSOR PROPOSAL FAIL\n"

.org 30000
sp_test_request:
  .word 0,0,0,0,0,0,0,0,0,0,0,0
.org 31000
sp_test_spectral:
  .word 0
.org 32100
sp_test_votes:
  .word 0
.org 32300
sp_test_pairs:
  .word 0
.org 33000
sp_test_permissions:
  .word 0
.org 34000
sp_test_scratch:
  .word 0
.org 36000
sp_test_output:
  .word 0
