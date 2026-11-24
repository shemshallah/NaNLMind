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

(** ** Computable action result *)

Definition action_run
    (row_addr tape_addr head : nat) (m : Mem) (row : list nat) : nat * Mem :=
  let write := nth 2 row 0 in
  let mv := nth 3 row 1 in
  let to := nth 4 row 1 in
  let halt := nth 5 row 1 in
  let m1 := set_mem m tape_addr write in
  let head' := action_new_head head mv in
  let m2 := set_mem m1 action_head_addr head' in
  let m3 := set_mem m2 action_state_addr to in
  let m4 := if Nat.eqb halt 0 then m3 else set_mem m3 action_halt_addr 1 in
  (head', m4).

Definition smoke_row : list nat := [3; 4; 7; 2; 6; 1; 0; 0].

Example action_run_smoke :
  let res := action_run 100 200 50 smoke_mem smoke_row in
  fst res = 51 /\
  snd res 200 = 7 /\
  snd res action_head_addr = 51 /\
  snd res action_state_addr = 6 /\
  snd res action_halt_addr = 1.
Proof. vm_compute. repeat split; reflexivity. Qed.

(** ** Generic one-step projections for the action block *)

Lemma action_exec_pc :
  forall (vm : VM) (pc : nat) (ins : Instr),
    vm_pc vm = pc ->
    nth_error action_block pc = Some ins ->
    vm_pc (exec_instr action_block vm) =
    match ins with
    | iJMP p target =>
        if pred_holds p (vm_zf vm) (vm_lf vm) then target else S pc
    | iCALL target => target
    | iRET => vm_link vm
    | iHALT => pc
    | _ => S pc
    end.
Proof.
  intros vm pc ins Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins.
  destruct ins; cbn; reflexivity.
Qed.

Lemma action_CMP_zf :
  forall (vm : VM) (pc a b : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iCMP a b) ->
    vm_zf (exec_instr action_block vm) =
      Nat.eqb (vm_reg vm a) (vm_reg vm b).
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity.
Qed.

Lemma action_CMP_lf :
  forall (vm : VM) (pc a b : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iCMP a b) ->
    vm_lf (exec_instr action_block vm) =
      Nat.ltb (vm_reg vm a) (vm_reg vm b).
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity.
Qed.

Lemma action_not_halted :
  forall (vm : VM) (pc : nat) (ins : Instr),
    vm_pc vm = pc ->
    nth_error action_block pc = Some ins ->
    ins <> iHALT ->
    vm_halted (exec_instr action_block vm) = vm_halted vm.
Proof.
  intros. unfold exec_instr. rewrite H, H0.
  destruct ins; try reflexivity; cbn in H1; contradiction.
Qed.

Lemma action_LD_reg :
  forall (vm : VM) (pc d a imm : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iLD d a imm) ->
    vm_reg (exec_instr action_block vm) d =
      vm_mem vm (vm_reg vm a + imm).
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma action_ST_mem :
  forall (vm : VM) (pc d a imm : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iST d a imm) ->
    vm_mem (exec_instr action_block vm) =
      set_mem (vm_mem vm) (vm_reg vm a + imm) (vm_reg vm d).
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity.
Qed.

Lemma action_MOVI_reg :
  forall (vm : VM) (pc d imm : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iMOVI d imm) ->
    vm_reg (exec_instr action_block vm) d = imm.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma action_SUB_reg :
  forall (vm : VM) (pc d a b : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iSUB d a b) ->
    vm_reg (exec_instr action_block vm) d =
      vm_reg vm a - vm_reg vm b.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma action_ADD_reg :
  forall (vm : VM) (pc d a b : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iADD d a b) ->
    vm_reg (exec_instr action_block vm) d =
      vm_reg vm a + vm_reg vm b.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma set_mem_same :
  forall (m : Mem) (a v : nat), set_mem m a v a = v.
Proof.
  intros. unfold set_mem. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma set_mem_neq :
  forall (m : Mem) (a v k : nat), k <> a -> set_mem m a v k = m k.
Proof.
  intros. unfold set_mem. rewrite (proj2 (Nat.eqb_neq k a) H). reflexivity.
Qed.

(** ** One-step register/memory preservation *)

Lemma action_reg_preserved_ST :
  forall (vm : VM) (pc d a imm k : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iST d a imm) ->
    vm_reg (exec_instr action_block vm) k = vm_reg vm k.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity.
Qed.

Lemma action_reg_preserved_CMP :
  forall (vm : VM) (pc a b k : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iCMP a b) ->
    vm_reg (exec_instr action_block vm) k = vm_reg vm k.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity.
Qed.

Lemma action_reg_preserved_JMP :
  forall (vm : VM) (pc p target k : nat) (cond : preg),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iJMP cond target) ->
    vm_reg (exec_instr action_block vm) k = vm_reg vm k.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity.
Qed.

Lemma action_reg_preserved_LD :
  forall (vm : VM) (pc d a imm k : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iLD d a imm) ->
    k <> d ->
    vm_reg (exec_instr action_block vm) k = vm_reg vm k.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. destruct (Nat.eqb k d) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma action_reg_preserved_MOVI :
  forall (vm : VM) (pc d imm k : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iMOVI d imm) ->
    k <> d ->
    vm_reg (exec_instr action_block vm) k = vm_reg vm k.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. destruct (Nat.eqb k d) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma action_reg_preserved_SUB :
  forall (vm : VM) (pc d a b k : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iSUB d a b) ->
    k <> d ->
    vm_reg (exec_instr action_block vm) k = vm_reg vm k.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. destruct (Nat.eqb k d) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma action_reg_preserved_ADD :
  forall (vm : VM) (pc d a b k : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iADD d a b) ->
    k <> d ->
    vm_reg (exec_instr action_block vm) k = vm_reg vm k.
Proof.
  intros. unfold exec_instr. rewrite H, H0. cbn.
  unfold set_reg. destruct (Nat.eqb k d) eqn:E.
  { apply Nat.eqb_eq in E. lia. }
  reflexivity.
Qed.

Lemma action_mem_preserved_LD :
  forall (vm : VM) (pc d a imm : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iLD d a imm) ->
    vm_mem (exec_instr action_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity. Qed.

Lemma action_mem_preserved_MOVI :
  forall (vm : VM) (pc d imm : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iMOVI d imm) ->
    vm_mem (exec_instr action_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity. Qed.

Lemma action_mem_preserved_CMP :
  forall (vm : VM) (pc a b : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iCMP a b) ->
    vm_mem (exec_instr action_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity. Qed.

Lemma action_mem_preserved_JMP :
  forall (vm : VM) (pc cond target : nat) (p : preg),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iJMP p target) ->
    vm_mem (exec_instr action_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity. Qed.

Lemma action_mem_preserved_SUB :
  forall (vm : VM) (pc d a b : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iSUB d a b) ->
    vm_mem (exec_instr action_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity. Qed.

Lemma action_mem_preserved_ADD :
  forall (vm : VM) (pc d a b : nat),
    vm_pc vm = pc ->
    nth_error action_block pc = Some (iADD d a b) ->
    vm_mem (exec_instr action_block vm) = vm_mem vm.
Proof. intros. unfold exec_instr. rewrite H, H0. cbn. reflexivity. Qed.
