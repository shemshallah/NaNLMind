From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action.

(** The literal step prelude from the .nas fixture, with the table base as an
    immediate.  The prelude ends at pc 11, which is the scan entry in the
    combined step program.  [tape_base_addr] is the literal [tbase] cell at
    word 99; the cell contains the tape image base 4096. *)

Definition tape_base_addr : nat := 99.

Definition prelude_block (table_base : nat) : list Instr :=
  [ iLD 1 0 action_halt_addr;    (* 0 *)
    iCMP 1 0;                    (* 1 *)
    iJMP pNE 11;                 (* 2: already halted -> return *)
    iLD 1 0 action_state_addr;   (* 3 *)
    iLD 2 0 action_head_addr;    (* 4 *)
    iLD 3 0 tape_base_addr;      (* 5 *)
    iADD 3 3 2;                  (* 6: tape address = base + head *)
    iLD 4 3 0;                   (* 7: read symbol *)
    iMOVI 5 table_base;          (* 8 *)
    iMOVI 6 184;                 (* 9 *)
    iMOVI 8 0 ].                 (* 10 *)

Lemma prelude_exec_pc :
  forall (table_base : nat) (vm : VM) (pc : nat) (ins : Instr),
    vm_pc vm = pc ->
    nth_error (prelude_block table_base) pc = Some ins ->
    vm_pc (exec_instr (prelude_block table_base) vm) =
    match ins with
    | iJMP p target =>
        if pred_holds p (vm_zf vm) (vm_lf vm) then target else S pc
    | iCALL target => target
    | iRET => vm_link vm
    | iHALT => pc
    | _ => S pc
    end.
Proof.
  intros table_base vm pc ins Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins.
  destruct ins; cbn; reflexivity.
Qed.

Lemma prelude_not_halted :
  forall (table_base : nat) (vm : VM) (pc : nat) (ins : Instr),
    vm_pc vm = pc ->
    nth_error (prelude_block table_base) pc = Some ins ->
    ins <> iHALT ->
    vm_halted (exec_instr (prelude_block table_base) vm) = vm_halted vm.
Proof.
  intros table_base vm pc ins Hpc Hins Hne.
  unfold exec_instr. rewrite Hpc, Hins.
  destruct ins; try reflexivity; cbn in Hne; contradiction.
Qed.

Lemma prelude_LD_reg :
  forall (table_base : nat) (vm : VM) (pc d a imm : nat),
    vm_pc vm = pc ->
    nth_error (prelude_block table_base) pc = Some (iLD d a imm) ->
    vm_reg (exec_instr (prelude_block table_base) vm) d =
      vm_mem vm (vm_reg vm a + imm).
Proof.
  intros table_base vm pc d a imm Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins. cbn.
  unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma prelude_ADD_reg :
  forall (table_base : nat) (vm : VM) (pc d a b : nat),
    vm_pc vm = pc ->
    nth_error (prelude_block table_base) pc = Some (iADD d a b) ->
    vm_reg (exec_instr (prelude_block table_base) vm) d =
      vm_reg vm a + vm_reg vm b.
Proof.
  intros table_base vm pc d a b Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins. cbn.
  unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma prelude_MOVI_reg :
  forall (table_base : nat) (vm : VM) (pc d imm : nat),
    vm_pc vm = pc ->
    nth_error (prelude_block table_base) pc = Some (iMOVI d imm) ->
    vm_reg (exec_instr (prelude_block table_base) vm) d = imm.
Proof.
  intros table_base vm pc d imm Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins. cbn.
  unfold set_reg. rewrite Nat.eqb_refl. reflexivity.
Qed.

Lemma prelude_CMP_zf :
  forall (table_base : nat) (vm : VM) (pc a b : nat),
    vm_pc vm = pc ->
    nth_error (prelude_block table_base) pc = Some (iCMP a b) ->
    vm_zf (exec_instr (prelude_block table_base) vm) =
      Nat.eqb (vm_reg vm a) (vm_reg vm b).
Proof.
  intros table_base vm pc a b Hpc Hins.
  unfold exec_instr. rewrite Hpc, Hins. cbn. reflexivity.
Qed.


Lemma prelude_block_length : forall table_base,
  length (prelude_block table_base) = 11.
Proof. intro; reflexivity. Qed.

Lemma prelude_exec_mem :
  forall table_base vm,
    vm_mem (exec_instr (prelude_block table_base) vm) = vm_mem vm.
Proof.
  intros table_base vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]];
    try (cbn [prelude_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None (prelude_block table_base)
    (S (S (S (S (S (S (S (S (S (S (S n)))))))))))) ltac:(rewrite prelude_block_length; lia)).
  cbn. reflexivity.
Qed.

Lemma prelude_exec_reg0 :
  forall table_base vm,
    vm_reg (exec_instr (prelude_block table_base) vm) 0 = vm_reg vm 0.
Proof.
  intros table_base vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]];
    try (cbn [prelude_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None (prelude_block table_base)
    (S (S (S (S (S (S (S (S (S (S (S n)))))))))))) ltac:(rewrite prelude_block_length; lia)).
  cbn. reflexivity.
Qed.

Lemma prelude_exec_reg13 :
  forall table_base vm,
    vm_reg (exec_instr (prelude_block table_base) vm) 13 = vm_reg vm 13.
Proof.
  intros table_base vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]];
    try (cbn [prelude_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None (prelude_block table_base)
    (S (S (S (S (S (S (S (S (S (S (S n)))))))))))) ltac:(rewrite prelude_block_length; lia)).
  cbn. reflexivity.
Qed.

