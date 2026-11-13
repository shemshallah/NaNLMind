; Raw NaN16 full-vocabulary token-projection worker.
;
; Command block 0x4000:
;   mode1 build: 0x4001=N, 0x4002=V, 0x4003=rows, 0x4004=token base,
;                 0x4005=rowmap base, 0x4006=previous token or -1
;   mode2 top5:  0x4001=target, 0x4002=row, 0x4003=V, 0x4004=N
; Results 0x4010..0x4015 = top1..top5 IDs, target natural-log loss.
JMP @token_worker_entry

.include "../nan16/mth_token_projection.nas"

token_worker_entry:
  MOVI r13,1
  CALL @token_worker_main
  HALT

token_worker_main:
  MOVI r12,@token_worker_link
  ST r15,r12,0
  MOVI r10,0x4000
  LD r1,r10,0
  MOVI r2,1
  CMP r1,r2
  JMP[EQ] @token_worker_build
  MOVI r2,2
  CMP r1,r2
  JMP[EQ] @token_worker_top5
  JMP @token_worker_return

token_worker_build:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_token_build
  MOVI r10,0x4010
  ST r1,r10,0
  JMP @token_worker_return

token_worker_top5:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_token_top5
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
  ST r5,r10,4
  ST r6,r10,5
  JMP @token_worker_return

token_worker_return:
  MOVI r10,@token_worker_link
  LD r15,r10,0
  RET

token_worker_link:
  .word 0
