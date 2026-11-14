; mth_minsky_test.nas - native NaN16 Minsky 23x8 table execution.
; The table is generated from tests/minsky_table.inc; host only loads the
; assembled image.  Tape base 4096, logical position 0 at base+128.
main:
MOVI r13,1
MOVI r1,5
ST r1,r0,@state
MOVI r1,166
ST r1,r0,@head
ST r0,r0,@halt
CALL @run100
LD r1,r0,@state
MOVI r2,2
CMP r1,r2
JMP[NE] @fail
LD r1,r0,@head
MOVI r2,166
CMP r1,r2
JMP[NE] @fail
MOVI r3,4224
MOVI r4,@expected
MOVI r5,73
vloop:
LD r1,r3,0
LD r2,r4,0
CMP r1,r2
JMP[NE] @fail
ADD r3,r3,r13
ADD r4,r4,r13
SUB r5,r5,r13
JMP[NE] @vloop
MOVI r1,@s_pass
CALL @puts
HALT

run100:
ST r15,r0,@rlink
MOVI r11,100
rloop:
CALL @step
SUB r11,r11,r13
JMP[NE] @rloop
LD r15,r0,@rlink
RET

; One step in the C++ order: write, update state/head, then halt flag.
step:
LD r1,r0,@halt
CMP r1,r0
JMP[NE] @step_ret
LD r1,r0,@state
LD r2,r0,@head
LD r3,r0,@tbase
ADD r3,r3,r2
LD r4,r3,0
LD r5,r0,@table
MOVI r6,184
MOVI r8,0
scan:
CMP r8,r6
JMP[GE] @no_trans
SHL r7,r8,3
ADD r7,r7,r5
LD r9,r7,0
CMP r9,r1
JMP[NE] @next
LD r9,r7,1
CMP r9,r4
JMP[NE] @next
LD r9,r7,2
ST r9,r3,0
LD r9,r7,3
MOVI r10,0
CMP r9,r10
JMP[EQ] @mleft
MOVI r10,2
CMP r9,r10
JMP[EQ] @mright
JMP @mdone
mleft:
SUB r2,r2,r13
JMP @mdone
mright:
ADD r2,r2,r13
mdone:
ST r2,r0,@head
LD r9,r7,4
ST r9,r0,@state
LD r9,r7,5
CMP r9,r0
JMP[EQ] @step_ret
MOVI r9,1
ST r9,r0,@halt
step_ret:
RET
next:
ADD r8,r8,r13
JMP @scan
no_trans:
MOVI r9,1
ST r9,r0,@halt
RET

puts:
MOVI r4,255
p1:
LD r2,r1,0
MOVI r3,4
p2:
BOOL.8 r5,r2,r4
CMP r5,r0
RET[EQ]
PUTC r5
SHR r2,r2,8
SUB r3,r3,r13
JMP[NE] @p2
ADD r1,r1,r13
JMP @p1
fail:
MOVI r1,@s_fail
CALL @puts
HALT

tbase:
  .word 4096
state:
  .word 0
head:
  .word 0
halt:
  .word 0
rlink:
  .word 0

table:
  .word 0,0,2,0,2,0,0,0
  .word 0,1,3,2,3,0,0,0
  .word 0,2,2,2,0,0,0,0
  .word 0,3,3,2,0,0,0,0
  .word 0,4,4,2,0,0,0,0
  .word 0,5,5,2,0,0,0,0
  .word 0,6,6,2,0,0,0,0
  .word 0,7,7,2,0,0,0,0
  .word 1,0,0,2,1,0,0,0
  .word 1,1,1,2,1,0,0,0
  .word 1,2,0,2,0,0,0,0
  .word 1,3,1,2,4,0,0,0
  .word 1,4,4,2,6,0,0,0
  .word 1,5,5,2,1,0,0,0
  .word 1,6,6,2,1,0,0,0
  .word 1,7,7,2,1,0,0,0
  .word 2,0,0,0,2,0,0,0
  .word 2,1,1,0,2,0,0,0
  .word 2,2,2,0,2,0,0,0
  .word 2,3,3,0,2,0,0,0
  .word 2,4,4,0,2,0,0,0
  .word 2,5,5,2,1,0,0,0
  .word 2,6,6,0,2,0,0,0
  .word 2,7,7,0,2,0,0,0
  .word 3,0,0,2,3,0,0,0
  .word 3,1,1,2,3,0,0,0
  .word 3,2,2,2,3,0,0,0
  .word 3,3,3,2,3,0,0,0
  .word 3,4,4,0,5,0,0,0
  .word 3,5,5,1,0,1,0,0
  .word 3,6,6,2,3,0,0,0
  .word 3,7,7,2,3,0,0,0
  .word 4,0,2,2,3,0,0,0
  .word 4,1,3,0,2,0,0,0
  .word 4,2,2,2,4,0,0,0
  .word 4,3,3,2,4,0,0,0
  .word 4,4,4,2,4,0,0,0
  .word 4,5,5,2,4,0,0,0
  .word 4,6,6,2,4,0,0,0
  .word 4,7,7,2,4,0,0,0
  .word 5,0,2,0,5,0,0,0
  .word 5,1,3,0,5,0,0,0
  .word 5,2,2,0,5,0,0,0
  .word 5,3,3,0,5,0,0,0
  .word 5,4,4,0,5,0,0,0
  .word 5,5,5,2,1,0,0,0
  .word 5,6,6,0,5,0,0,0
  .word 5,7,7,0,5,0,0,0
  .word 6,0,2,0,8,0,0,0
  .word 6,1,3,0,7,0,0,0
  .word 6,2,2,2,6,0,0,0
  .word 6,3,3,2,6,0,0,0
  .word 6,4,4,2,6,0,0,0
  .word 6,5,5,2,6,0,0,0
  .word 6,6,6,2,6,0,0,0
  .word 6,7,7,2,6,0,0,0
  .word 7,0,0,0,7,0,0,0
  .word 7,1,1,0,7,0,0,0
  .word 7,2,2,0,7,0,0,0
  .word 7,3,3,0,7,0,0,0
  .word 7,4,4,0,7,0,0,0
  .word 7,5,5,2,9,0,0,0
  .word 7,6,6,0,7,0,0,0
  .word 7,7,7,0,7,0,0,0
  .word 8,0,0,0,8,0,0,0
  .word 8,1,1,0,8,0,0,0
  .word 8,2,2,0,8,0,0,0
  .word 8,3,3,0,8,0,0,0
  .word 8,4,4,0,8,0,0,0
  .word 8,5,5,2,10,0,0,0
  .word 8,6,6,0,8,0,0,0
  .word 8,7,7,0,8,0,0,0
  .word 9,0,3,2,11,0,0,0
  .word 9,1,3,2,11,0,0,0
  .word 9,2,2,2,9,0,0,0
  .word 9,3,3,2,9,0,0,0
  .word 9,4,4,0,12,0,0,0
  .word 9,5,5,2,9,0,0,0
  .word 9,6,6,2,9,0,0,0
  .word 9,7,7,2,9,0,0,0
  .word 10,0,2,2,11,0,0,0
  .word 10,1,2,2,11,0,0,0
  .word 10,2,2,2,10,0,0,0
  .word 10,3,3,2,10,0,0,0
  .word 10,4,4,0,13,0,0,0
  .word 10,5,5,2,10,0,0,0
  .word 10,6,6,2,10,0,0,0
  .word 10,7,7,2,10,0,0,0
  .word 11,0,0,2,11,0,0,0
  .word 11,1,1,2,11,0,0,0
  .word 11,2,2,2,11,0,0,0
  .word 11,3,3,2,11,0,0,0
  .word 11,4,4,2,6,0,0,0
  .word 11,5,5,2,11,0,0,0
  .word 11,6,6,2,11,0,0,0
  .word 11,7,7,2,11,0,0,0
  .word 12,0,0,0,12,0,0,0
  .word 12,1,1,0,12,0,0,0
  .word 12,2,2,0,12,0,0,0
  .word 12,3,3,0,12,0,0,0
  .word 12,4,4,0,12,0,0,0
  .word 12,5,5,0,12,0,0,0
  .word 12,6,3,2,14,0,0,0
  .word 12,7,7,0,12,0,0,0
  .word 13,0,0,0,13,0,0,0
  .word 13,1,1,0,13,0,0,0
  .word 13,2,2,0,13,0,0,0
  .word 13,3,3,0,13,0,0,0
  .word 13,4,4,0,13,0,0,0
  .word 13,5,5,0,13,0,0,0
  .word 13,6,2,2,14,0,0,0
  .word 13,7,7,0,13,0,0,0
  .word 14,0,0,2,14,0,0,0
  .word 14,1,1,2,14,0,0,0
  .word 14,2,0,2,14,0,0,0
  .word 14,3,1,2,14,0,0,0
  .word 14,4,4,2,15,0,0,0
  .word 14,5,5,2,14,0,0,0
  .word 14,6,6,2,14,0,0,0
  .word 14,7,7,2,14,0,0,0
  .word 15,0,0,0,16,0,0,0
  .word 15,1,1,0,16,0,0,0
  .word 15,2,2,2,15,0,0,0
  .word 15,3,3,2,15,0,0,0
  .word 15,4,4,2,15,0,0,0
  .word 15,5,5,2,15,0,0,0
  .word 15,6,6,2,15,0,0,0
  .word 15,7,7,2,15,0,0,0
  .word 16,0,7,0,21,0,0,0
  .word 16,1,7,0,22,0,0,0
  .word 16,2,0,0,16,0,0,0
  .word 16,3,1,0,16,0,0,0
  .word 16,4,4,0,16,0,0,0
  .word 16,5,5,0,16,0,0,0
  .word 16,6,6,0,16,0,0,0
  .word 16,7,7,0,16,0,0,0
  .word 17,0,0,2,17,0,0,0
  .word 17,1,1,2,17,0,0,0
  .word 17,2,2,2,17,0,0,0
  .word 17,3,3,2,17,0,0,0
  .word 17,4,4,2,17,0,0,0
  .word 17,5,5,2,17,0,0,0
  .word 17,6,6,2,17,0,0,0
  .word 17,7,2,0,5,0,0,0
  .word 18,0,0,2,18,0,0,0
  .word 18,1,1,2,18,0,0,0
  .word 18,2,2,2,18,0,0,0
  .word 18,3,3,2,18,0,0,0
  .word 18,4,4,2,18,0,0,0
  .word 18,5,5,2,18,0,0,0
  .word 18,6,6,2,18,0,0,0
  .word 18,7,3,0,5,0,0,0
  .word 19,0,6,2,17,0,0,0
  .word 19,1,6,2,18,0,0,0
  .word 19,2,2,2,19,0,0,0
  .word 19,3,3,2,19,0,0,0
  .word 19,4,4,2,19,0,0,0
  .word 19,5,5,2,19,0,0,0
  .word 19,6,6,2,19,0,0,0
  .word 19,7,7,2,19,0,0,0
  .word 20,0,6,2,17,0,0,0
  .word 20,1,6,2,18,0,0,0
  .word 20,2,2,0,20,0,0,0
  .word 20,3,3,0,20,0,0,0
  .word 20,4,4,0,20,0,0,0
  .word 20,5,5,0,20,0,0,0
  .word 20,6,6,0,20,0,0,0
  .word 20,7,7,0,20,0,0,0
  .word 21,0,0,0,21,0,0,0
  .word 21,1,1,0,21,0,0,0
  .word 21,2,0,0,20,0,0,0
  .word 21,3,0,2,19,0,0,0
  .word 21,4,4,0,21,0,0,0
  .word 21,5,5,0,21,0,0,0
  .word 21,6,6,0,21,0,0,0
  .word 21,7,7,0,21,0,0,0
  .word 22,0,0,0,22,0,0,0
  .word 22,1,1,0,22,0,0,0
  .word 22,2,1,0,20,0,0,0
  .word 22,3,1,2,19,0,0,0
  .word 22,4,4,0,22,0,0,0
  .word 22,5,5,0,22,0,0,0
  .word 22,6,6,0,22,0,0,0
  .word 22,7,7,0,22,0,0,0

expected:
  .word 0
  .word 0
  .word 1
  .word 1
  .word 1
  .word 1
  .word 5
  .word 3
  .word 2
  .word 2
  .word 4
  .word 2
  .word 2
  .word 2
  .word 2
  .word 2
  .word 2
  .word 2
  .word 4
  .word 2
  .word 2
  .word 3
  .word 2
  .word 2
  .word 2
  .word 2
  .word 7
  .word 6
  .word 0
  .word 0
  .word 0
  .word 0
  .word 0
  .word 0
  .word 5
  .word 0
  .word 0
  .word 3
  .word 4
  .word 2
  .word 2
  .word 2
  .word 2
  .word 2
  .word 2
  .word 3
  .word 4
  .word 2
  .word 2
  .word 1
  .word 0
  .word 1
  .word 1
  .word 0
  .word 4
  .word 0
  .word 1
  .word 0
  .word 0
  .word 0
  .word 1
  .word 1
  .word 4
  .word 0
  .word 1
  .word 1
  .word 0
  .word 1
  .word 0
  .word 0
  .word 5
  .word 0
  .word 0

.org 4096
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 0,0,1,1,1,1,5,3,2,2,4,2,2,2,2,2
  .word 2,2,4,2,2,3,2,2,2,2,7,6,0,0,0,0
  .word 0,0,5,0,0,1,4,0,0,0,0,0,0,1,4,0
  .word 0,1,0,1,1,0,4,0,1,0,0,0,1,1,4,0
  .word 1,1,0,1,0,0,5,0,0,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
  .word 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
s_pass:
  .str "MTH MINSKY NATIVE PASS"
  .word 0
s_fail:
  .str "MTH MINSKY NATIVE FAIL"
  .word 0
