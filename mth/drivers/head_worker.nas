; Dedicated raw NaN16 head-worker image.
;
; The main field driver lives near the 0x4000 command block and is nearly
; full.  This image is loaded into its own RawFieldVM, starts at word 0, and
; owns the native six-token head block.  It is still one NaN16 state space:
; the host only transports page bytes, the input vectors and the command
; result.  No host arithmetic.
;
; Command block (same host ABI shape as the main driver):
;   0x4000 = 122
;   0x4001 = input f32[T][128]
;   0x4002 = output f32[T][128]
;   0x4003 = page slot 0..15
;   0x4004 = T 1..6
;   0x4010..0x4013 = accepted, T*128, slot, reason
.org 0
JMP @hw_entry

hw_entry:
  MOVI r13,1
  CALL @hw_main
  HALT

hw_main:
  MOVI r10,@hw_link
  ST r15,r10,0
  MOVI r10,0x4000
  LD r2,r10,0
  MOVI r3,122
  CMP r2,r3
  JMP[EQ] @hw_block6
  MOVI r3,123
  CMP r2,r3
  JMP[EQ] @hw_readout
  MOVI r3,124
  CMP r2,r3
  JMP[EQ] @hw_train
  MOVI r3,125
  CMP r2,r3
  JMP[EQ] @hw_page_train
  MOVI r3,126
  CMP r2,r3
  JMP[EQ] @hw_page_train_wo
  MOVI r3,127
  CMP r2,r3
  JMP[EQ] @hw_page_train_w1
  MOVI r3,128
  CMP r2,r3
  JMP[EQ] @hw_page_train_wv
  MOVI r3,129
  CMP r2,r3
  JMP[EQ] @hw_page_train_qk
  MOVI r3,130
  CMP r2,r3
  JMP[EQ] @hw_page_train_l1w2
  JMP @hw_return
hw_block6:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_head_block6
  JMP @hw_store
hw_readout:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  CALL @mth_head_state_readout
  JMP @hw_store
hw_train:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_head_state_readout_train
  JMP @hw_store
hw_page_train:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_head_page_train
  JMP @hw_store
hw_page_train_wo:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_head_page_train_wo
  JMP @hw_store
hw_page_train_w1:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_head_page_train_w1
  JMP @hw_store
hw_page_train_wv:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_head_page_train_wv
  JMP @hw_store
hw_page_train_qk:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_head_page_train_qk
  JMP @hw_store
hw_page_train_l1w2:
  MOVI r10,0x4001
  LD r1,r10,0
  LD r2,r10,1
  LD r3,r10,2
  LD r4,r10,3
  LD r5,r10,4
  LD r6,r10,5
  CALL @mth_head_page_train_l1w2
hw_store:
  MOVI r10,0x4010
  ST r1,r10,0
  ST r2,r10,1
  ST r3,r10,2
  ST r4,r10,3
hw_return:
  MOVI r10,@hw_link
  LD r15,r10,0
  RET

hw_link:
  .word 0

.include "../nan16/mth_head_block6.nas"
.include "../nan16/mth_head_state_readout.nas"
.include "../nan16/mth_head_state_readout_train.nas"
.include "../nan16/mth_head_page_train.nas"
.include "../nan16/mth_head_page_train_wo.nas"
.include "../nan16/mth_head_page_train_w1.nas"
.include "../nan16/mth_head_page_train_wv.nas"
.include "../nan16/mth_head_page_train_qk.nas"
.include "../nan16/mth_head_page_train_l1w2.nas"
