(** * Native NaN16 action phase (the match block)

    This module starts the action half of [mth/tests/mth_minsky_test.nas]:
    after the scan exits at [pc = 14], the native program writes the
    selected row's write symbol, applies the direction, stores the new
    head and state, and sets the halt flag.

    The block is modelled at the .nas mnemonic level, like
    [MinskyNaN16VM].  The address constants are parameters; the
    transcription gate links them to the literal source layout. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM.

Open Scope nat_scope.

(** ** Action program *)

Definition action_head_addr : nat := 300.
Definition action_state_addr : nat := 301.
Definition action_halt_addr : nat := 302.

Definition action_block : list Instr :=
  [ iLD 9 7 2;              (* 0: write symbol *)
    iST 9 3 0;              (* 1: tape[head] := write *)
    iLD 9 7 3;              (* 2: move+1 *)
    iMOVI 10 0;             (* 3 *)
    iCMP 9 10;              (* 4 *)
    iJMP pEQ 10;            (* 5: move+1 = 0 -> left *)
    iMOVI 10 2;             (* 6 *)
    iCMP 9 10;              (* 7 *)
    iJMP pEQ 12;            (* 8: move+1 = 2 -> right *)
    iJMP pALWAYS 14;        (* 9: no move -> done *)
    iSUB 2 2 13;            (* 10: left *)
    iJMP pALWAYS 14;        (* 11 *)
    iADD 2 2 13;            (* 12: right *)
    iJMP pALWAYS 14;        (* 13 *)
    iST 2 0 action_head_addr;   (* 14: done: store head *)
    iLD 9 7 4;              (* 15: target state *)
    iST 9 0 action_state_addr;  (* 16: store state *)
    iLD 9 7 5;              (* 17: halt field *)
    iCMP 9 0;               (* 18 *)
    iJMP pEQ 22;            (* 19: halt=0 -> ret *)
    iMOVI 9 1;              (* 20 *)
    iST 9 0 action_halt_addr;   (* 21: halt := 1 *)
    iRET ].                 (* 22 *)

Definition action_stop (pc : nat) : bool := Nat.eqb pc 22.

Definition action_init (vm : VM) : VM :=
  {| vm_pc := 0; vm_reg := vm_reg vm; vm_mem := vm_mem vm;
     vm_zf := vm_zf vm; vm_lf := vm_lf vm; vm_halted := vm_halted vm;
     vm_link := vm_link vm |}.

(** ** Concrete smoke test *)

Definition smoke_mem : Mem :=
  fun k =>
    if Nat.eqb k 100 then 3 else
    if Nat.eqb k 101 then 4 else
    if Nat.eqb k 102 then 7 else
    if Nat.eqb k 103 then 2 else
    if Nat.eqb k 104 then 6 else
    if Nat.eqb k 105 then 1 else
    if Nat.eqb k 200 then 5 else
    0.

Definition smoke_vm : VM :=
  {| vm_pc := 0;
     vm_reg := fun x =>
       if Nat.eqb x 2 then 50 else
       if Nat.eqb x 3 then 200 else
       if Nat.eqb x 7 then 100 else
       if Nat.eqb x 13 then 1 else 0;
     vm_mem := smoke_mem;
     vm_zf := false; vm_lf := false; vm_halted := false; vm_link := 900 |}.

Eval vm_compute in
  (let vm := run_until 24 action_block action_stop smoke_vm in
   (vm_pc vm, vm_reg vm 2, vm_reg vm 9, vm_reg vm 7,
    vm_mem vm 200, vm_mem vm action_head_addr,
    vm_mem vm action_state_addr, vm_mem vm action_halt_addr)).

(** ** Action invariant and specification *)

Definition row_at (addr : nat) (row : list nat) (m : Mem) : Prop :=
  forall f, f < length row -> m (addr + f) = nth f row 0.

Definition set_mem (m : Mem) (a v : nat) : Mem :=
  fun k => if Nat.eqb k a then v else m k.

Definition action_ready
    (vm : VM) (row_addr tape_addr head : nat) (m : Mem) : Prop :=
  vm_pc vm = 0 /\
  vm_reg vm 0 = 0 /\
  vm_reg vm 2 = head /\
  vm_reg vm 3 = tape_addr /\
  vm_reg vm 7 = row_addr /\
  vm_reg vm 13 = 1 /\
  vm_mem vm = m /\
  vm_halted vm = false.

Definition action_new_head (head mv : nat) : nat :=
  if Nat.eqb mv 0 then head - 1
  else if Nat.eqb mv 2 then head + 1 else head.
