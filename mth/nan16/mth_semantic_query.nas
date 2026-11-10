; Raw NaN16 bounded semantic graph query.
;
; Memory:
;   0x7000 ISA edges: E pairs (src,dst)
;   0x7100 negative ISA claims: Q pairs (src,dst)
;   0x7200 ability claims: A triples (subject,action,positive)
;   0x7300 query: type (1 ISA, 2 ability), subject, object/action
;   0x4001 E, 0x4002 Q, 0x4003 A
; Scratch: 0x7400 queue[32], 0x7500 dist[32], 0x7600 parent[32]
; Returns r1 state bits (1 support, 2 refute), r2 depth/best distance.
mth_semantic_query:
  MOVI r12,@mth_sq_link
  ST r15,r12,0

  ; dist[0..31] = -1
  MOVI r10,0x7500
  MOVI r11,0
  MOVI r9,0
  SUB r9,r0,r13            ; -1
  MOVI r12,32
mth_sq_init:
  CMP r11,r12
  JMP[GE] @mth_sq_bfs_init
  ADD r14,r10,r11
  ST r9,r14,0
  ADDI r11,r11,1
  JMP @mth_sq_init

mth_sq_bfs_init:
  MOVI r10,0x7300
  LD r5,r10,1             ; subject
  MOVI r10,0x7400
  ST r5,r10,0
  MOVI r10,0x7500
  ADD r10,r10,r5
  ST r0,r10,0             ; dist[subject]=0
  MOVI r10,@mth_sq_head
  ST r0,r10,0
  MOVI r10,@mth_sq_tail
  ST r13,r10,0

mth_sq_bfs:
  MOVI r10,@mth_sq_head
  LD r3,r10,0
  MOVI r10,@mth_sq_tail
  LD r4,r10,0
  CMP r3,r4
  JMP[GE] @mth_sq_query
  MOVI r10,0x7400
  ADD r10,r10,r3
  LD r5,r10,0             ; u
  ADDI r3,r3,1
  MOVI r10,@mth_sq_head
  ST r3,r10,0
  MOVI r6,0               ; edge index
mth_sq_edges:
  MOVI r10,0x4001
  LD r7,r10,0
  CMP r6,r7
  JMP[GE] @mth_sq_bfs
  MOVI r10,2
  MUL r10,r6,r10
  MOVI r11,0x7000
  ADD r11,r11,r10
  LD r8,r11,0             ; src
  CMP r8,r5
  JMP[NE] @mth_sq_edge_next
  ADDI r11,r11,1
  LD r8,r11,0             ; dst
  MOVI r10,0x7500
  ADD r10,r10,r8
  LD r9,r10,0
  MOVI r12,0
  SUB r12,r0,r13
  CMPS r9,r12
  JMP[GE] @mth_sq_edge_next
  ; dist[dst] = dist[u]+1
  MOVI r12,0x7500
  ADD r12,r12,r5
  LD r9,r12,0
  ADDI r9,r9,1
  ST r9,r10,0
  MOVI r10,0x7400
  MOVI r11,@mth_sq_tail
  LD r12,r11,0
  ADD r10,r10,r12
  ST r8,r10,0
  ADDI r12,r12,1
  ST r12,r11,0
mth_sq_edge_next:
  ADDI r6,r6,1
  JMP @mth_sq_edges

mth_sq_query:
  MOVI r10,0x7300
  LD r1,r10,0             ; type
  MOVI r11,1
  CMP r1,r11
  JMP[EQ] @mth_sq_isa
  MOVI r11,2
  CMP r1,r11
  JMP[EQ] @mth_sq_ability
  MOVI r1,0
  MOVI r2,0
  JMP @mth_sq_out

mth_sq_isa:
  MOVI r3,1               ; support
  MOVI r4,0               ; refute
  MOVI r10,0x7300
  LD r5,r10,1
  LD r6,r10,2
  MOVI r10,0x7500
  ADD r10,r10,r6
  LD r7,r10,0             ; dist[object]
  MOVI r12,0
  SUB r12,r0,r13
  CMPS r7,r12
  JMP[LT] @mth_sq_isa_depth
  MOVI r2,0
  ADD r2,r7,r0
  JMP @mth_sq_isa_neg
mth_sq_isa_depth:
  MOVI r3,0
  MOVI r2,0
mth_sq_isa_neg:
  MOVI r6,0
mth_sq_isa_neg_loop:
  MOVI r10,0x4002
  LD r7,r10,0
  CMP r6,r7
  JMP[GE] @mth_sq_isa_out
  MOVI r10,2
  MUL r10,r6,r10
  MOVI r11,0x7100
  ADD r11,r11,r10
  LD r8,r11,0
  MOVI r10,0x7300
  LD r9,r10,1
  CMP r8,r9
  JMP[NE] @mth_sq_isa_neg_next
  ADDI r11,r11,1
  LD r8,r11,0
  LD r9,r10,2
  CMP r8,r9
  JMP[NE] @mth_sq_isa_neg_next
  MOVI r4,2
mth_sq_isa_neg_next:
  ADDI r6,r6,1
  JMP @mth_sq_isa_neg_loop
mth_sq_isa_out:
  ADD r1,r3,r4
  JMP @mth_sq_out

mth_sq_ability:
  MOVI r3,0               ; support
  MOVI r4,0               ; refute
  MOVI r2,0               ; best distance
  MOVI r5,0               ; best set flag
  MOVI r6,0
mth_sq_ab_loop:
  MOVI r10,0x4003
  LD r7,r10,0
  CMP r6,r7
  JMP[GE] @mth_sq_ab_out
  MOVI r10,3
  MUL r10,r6,r10
  MOVI r11,0x7200
  ADD r11,r11,r10
  LD r8,r11,0             ; claim subject
  MOVI r10,0x7300
  LD r9,r10,2             ; query action
  ADDI r11,r11,1
  LD r10,r11,0
  CMP r10,r9
  JMP[NE] @mth_sq_ab_next
  MOVI r10,0x7500
  ADD r10,r10,r8
  LD r9,r10,0             ; dist claim subject
  MOVI r10,0
  SUB r10,r0,r13
  CMPS r9,r10
  JMP[LT] @mth_sq_ab_next
  CMP r5,r0
  JMP[EQ] @mth_sq_ab_first
  CMP r9,r2
  JMP[GT] @mth_sq_ab_next
  CMP r9,r2
  JMP[LT] @mth_sq_ab_reset
  JMP @mth_sq_ab_add
mth_sq_ab_first:
  ADD r5,r13,r0
  ADD r2,r9,r0
  JMP @mth_sq_ab_add
mth_sq_ab_reset:
  MOVI r3,0
  MOVI r4,0
  ADD r2,r9,r0
mth_sq_ab_add:
  MOVI r10,0x7200
  MOVI r11,3
  MUL r11,r6,r11
  ADD r10,r10,r11
  ADDI r10,r10,2
  LD r9,r10,0             ; positive
  CMP r9,r0
  JMP[EQ] @mth_sq_ab_neg
  MOVI r3,1
  JMP @mth_sq_ab_next
mth_sq_ab_neg:
  MOVI r4,2
mth_sq_ab_next:
  ADDI r6,r6,1
  JMP @mth_sq_ab_loop
mth_sq_ab_out:
  ADD r1,r3,r4
  JMP @mth_sq_out

mth_sq_out:
  MOVI r13,1
  MOVI r12,@mth_sq_link
  LD r15,r12,0
  RET
mth_sq_link:
  .word 0
mth_sq_head:
  .word 0
mth_sq_tail:
  .word 0
