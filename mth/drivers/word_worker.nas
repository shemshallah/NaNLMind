; Raw NaN16 word-projection worker.
;
; Command block 0x4000:
;   [0] mode 1 = build counts: 0x4001=N, 0x4002=V, 0x4003=token base
;   [0] mode 2 = top-5:       0x4001=target, 0x4002=context ID,
;                             0x4003=V, 0x4004=N
; Results 0x4010..0x4015 = top1..top5 word IDs, target natural-log loss.
JMP @word_worker_entry

.include "../nan16/mth_word_projection.nas"

word_worker_entry:
  MOVI r13,1
  CALL @word_worker_main
  HALT

word_worker_main:
  MOVI r12,@word_worker_link
  ST r15,r12,0
  MOVI r10,0x4000
  LD r1,r10,0
  MOVI r2,1
  CMP r1,r2
  JMP[EQ] @word_worker_build
  MOVI r2,2
  CMP r1,r2
  JMP[EQ] @word_worker_top5
  JMP @word_worker_return

word_worker_build:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  CALL @mth_word_build
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @word_worker_return

word_worker_top5:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_word_top5
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  ST r5,r10,4
  ST r6,r10,5
  JMP @word_worker_return

word_worker_return:
  MOVI r10,@word_worker_link
  LD r15,r10,0
  RET

word_worker_link:
  .word 0
