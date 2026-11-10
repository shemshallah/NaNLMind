; Raw NaN16 byte n-gram trainer and top-K selector for orders 1..4.
;
; Byte stream tables (hashed, two words per bucket):
;   0x240000  unigram table, 65536 buckets
;   0x260000  bigram table
;   0x280000  trigram table
;   0x2A0000  quadrigram table
; A bucket is [packed_ngram_key, count]. A collision in the same bucket is
; ignored; this is a fixed-memory count table, not a host sort.
;
; Top-K output:
;   0x2D0000 + (order-1)*0x800  keys[256]
;   0x2D2000 + (order-1)*0x800  counts[256]

; r1=text, r2=pos, r3=n -> r1=packed n-gram key
mth_ngram_key:
  MOVI r4,0
  MOVI r5,0
mth_ng_key_loop:
  CMP r5,r3
  JMP[GE] @mth_ng_key_done
  MOVI r6,0
  ADD r6,r2,r5
  ADD r6,r1,r6
  LD r6,r6,0
  SHL r4,r4,8
  ADD r4,r4,r6
  ADDI r5,r5,1
  JMP @mth_ng_key_loop
mth_ng_key_done:
  ADD r1,r4,r0
  RET

mth_ngram_reset:
  MOVI r10,0x0000
  MOVHI r10,0x0024
  MOVI r11,0
  MOVI r12,0x0000
  MOVHI r12,0x0008
mth_ng_reset_loop:
  CMP r11,r12
  JMP[GE] @mth_ng_reset_done
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  JMP @mth_ng_reset_loop
mth_ng_reset_done:
  MOVI r1,4
  RET

; r1=text, r2=length; returns r1=bytes processed
mth_ngram_train:
  MOVI r12,@mth_ng_link
  ST r15,r12,0
  MOVI r12,@mth_ng_text
  ST r1,r12,0
  MOVI r12,@mth_ng_len
  ST r2,r12,0
  MOVI r12,@mth_ng_pos
  ST r0,r12,0
mth_ng_pos_loop:
  MOVI r12,@mth_ng_pos
  LD r5,r12,0
  MOVI r12,@mth_ng_len
  LD r6,r12,0
  CMP r5,r6
  JMP[GE] @mth_ng_train_done
  MOVI r12,@mth_ng_n
  MOVI r7,1
  ST r7,r12,0
mth_ng_n_loop:
  MOVI r12,@mth_ng_n
  LD r7,r12,0
  MOVI r8,4
  CMP r7,r8
  JMP[GT] @mth_ng_pos_next
  MOVI r12,@mth_ng_pos
  LD r5,r12,0
  ADD r8,r5,r7
  MOVI r12,@mth_ng_len
  LD r6,r12,0
  CMP r8,r6
  JMP[GT] @mth_ng_pos_next
  MOVI r12,@mth_ng_text
  LD r1,r12,0
  ADD r2,r5,r0
  ADD r3,r7,r0
  CALL @mth_ngram_key
  MOVI r12,@mth_ng_key
  ST r1,r12,0
  ; bucket = key & 0xffff
  MOVI r8,0x0000
  MOVHI r8,0x0001
  MODU r8,r1,r8
  MOVI r12,@mth_ng_bucket
  ST r8,r12,0
  ; table = 0x240000 + (n-1)*0x20000
  MOVI r9,0x0000
  MOVHI r9,0x0024
  SUB r10,r7,r7
  ADDI r10,r7,-1
  MOVI r11,0x0000
  MOVHI r11,0x0002
  MUL r10,r10,r11
  ADD r9,r9,r10
  MOVI r11,2
  MUL r8,r8,r11
  ADD r9,r9,r8
  LD r11,r9,0
  MOVI r12,@mth_ng_oldkey
  ST r11,r12,0
  LD r10,r9,1
  CMP r10,r0
  JMP[EQ] @mth_ng_insert
  MOVI r12,@mth_ng_key
  LD r8,r12,0
  CMP r11,r8
  JMP[NE] @mth_ng_n_next
mth_ng_insert:
  MOVI r12,@mth_ng_key
  LD r8,r12,0
  ST r8,r9,0
  ADDI r10,r10,1
  ST r10,r9,1
mth_ng_n_next:
  MOVI r12,@mth_ng_n
  LD r7,r12,0
  ADDI r7,r7,1
  ST r7,r12,0
  JMP @mth_ng_n_loop
mth_ng_pos_next:
  MOVI r12,@mth_ng_pos
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_ng_pos_loop
mth_ng_train_done:
  MOVI r12,@mth_ng_len
  LD r1,r12,0
  MOVI r12,@mth_ng_link
  LD r15,r12,0
  RET

; Select top 64 entries per order from four 8,192-bucket tables.
mth_ngram_topk:
  MOVI r12,@mth_ng_link2
  ST r15,r12,0
  ; clear 0x2D0000..0x2D07FF (keys and counts)
  MOVI r10,0x0000
  MOVHI r10,0x002D
  MOVI r11,0
  MOVI r12,0x0800
mth_ng_top_clear:
  CMP r11,r12
  JMP[GE] @mth_ng_top_start
  ADD r13,r10,r11
  ST r0,r13,0
  ADDI r11,r11,1
  JMP @mth_ng_top_clear
mth_ng_top_start:
  MOVI r12,@mth_ng_order
  MOVI r7,1
  ST r7,r12,0
mth_ng_top_order:
  MOVI r12,@mth_ng_order
  LD r7,r12,0
  MOVI r8,4
  CMP r7,r8
  JMP[GT] @mth_ng_top_done
  ; table base = 0x240000 + (order-1)*0x4000
  MOVI r9,0x0000
  MOVHI r9,0x0024
  ADDI r8,r7,-1
  MOVI r10,0x0000
  MOVHI r10,0x0002
  MUL r8,r8,r10
  ADD r9,r9,r8
  MOVI r12,@mth_ng_table
  ST r9,r12,0
  MOVI r12,@mth_ng_bucket
  ST r0,r12,0
mth_ng_top_bucket:
  MOVI r12,@mth_ng_bucket
  LD r5,r12,0
  MOVI r8,0x0000
  MOVHI r8,0x0001
  CMP r5,r8
  JMP[GE] @mth_ng_top_order_next
  MOVI r12,@mth_ng_table
  LD r9,r12,0
  MOVI r8,2
  MUL r10,r5,r8
  ADD r10,r9,r10
  MOVI r12,@mth_ng_entry
  ST r10,r12,0
  LD r11,r10,1
  MOVI r12,@mth_ng_cand
  ST r11,r12,0
  CMP r11,r0
  JMP[EQ] @mth_ng_top_bucket_next
  ; find minimum among 64 slots
  MOVI r12,@mth_ng_scan
  ST r0,r12,0
  MOVI r12,@mth_ng_mincount
  MOVI r13,0xFFFF
  MOVHI r13,0x7FFF
  ST r13,r12,0
  MOVI r12,@mth_ng_minindex
  ST r0,r12,0
mth_ng_top_scan:
  MOVI r12,@mth_ng_scan
  LD r5,r12,0
  MOVI r8,64
  CMP r5,r8
  JMP[GE] @mth_ng_top_insert
  MOVI r12,@mth_ng_order
  LD r7,r12,0
  MOVI r9,0x1000
  MOVHI r9,0x002D
  ADDI r8,r7,-1
  MOVI r10,0x0100
  MUL r8,r8,r10
  ADD r9,r9,r8
  ADD r9,r9,r5
  LD r11,r9,0
  MOVI r12,@mth_ng_mincount
  LD r8,r12,0
  CMP r11,r8
  JMP[GE] @mth_ng_top_scan_next
  ST r11,r12,0
  MOVI r12,@mth_ng_minindex
  ST r5,r12,0
mth_ng_top_scan_next:
  MOVI r12,@mth_ng_scan
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_ng_top_scan
mth_ng_top_insert:
  MOVI r12,@mth_ng_cand
  LD r11,r12,0
  MOVI r12,@mth_ng_mincount
  LD r8,r12,0
  CMP r11,r8
  JMP[LE] @mth_ng_top_bucket_next
  MOVI r12,@mth_ng_minindex
  LD r6,r12,0
  ; keys base = 0x2D0000 + (order-1)*0x100 + slot
  MOVI r9,0x0000
  MOVHI r9,0x002D
  MOVI r12,@mth_ng_order
  LD r7,r12,0
  ADDI r8,r7,-1
  MOVI r10,0x0100
  MUL r8,r8,r10
  ADD r9,r9,r8
  ADD r9,r9,r6
  MOVI r12,@mth_ng_entry
  LD r10,r12,0
  LD r10,r10,0
  ST r10,r9,0
  ; counts base = 0x2D1000 + (order-1)*0x100 + slot
  MOVI r9,0x1000
  MOVHI r9,0x002D
  ADDI r8,r7,-1
  MOVI r10,0x0100
  MUL r8,r8,r10
  ADD r9,r9,r8
  ADD r9,r9,r6
  ST r11,r9,0
mth_ng_top_bucket_next:
  MOVI r12,@mth_ng_bucket
  LD r5,r12,0
  ADDI r5,r5,1
  ST r5,r12,0
  JMP @mth_ng_top_bucket
mth_ng_top_order_next:
  MOVI r12,@mth_ng_order
  LD r7,r12,0
  ADDI r7,r7,1
  ST r7,r12,0
  JMP @mth_ng_top_order
mth_ng_top_done:
  MOVI r1,4
  MOVI r12,@mth_ng_link2
  LD r15,r12,0
  RET

mth_ng_link:
  .word 0
mth_ng_link2:
  .word 0
mth_ng_text:
  .word 0
mth_ng_len:
  .word 0
mth_ng_pos:
  .word 0
mth_ng_n:
  .word 0
mth_ng_key:
  .word 0
mth_ng_oldkey:
  .word 0
mth_ng_bucket:
  .word 0
mth_ng_table:
  .word 0
mth_ng_order:
  .word 0
mth_ng_scan:
  .word 0
mth_ng_slot:
  .word 0
mth_ng_mincount:
  .word 0
mth_ng_entry:
  .word 0
mth_ng_cand:
  .word 0
mth_ng_minindex:
  .word 0
