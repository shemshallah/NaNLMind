From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM.

(** Frame conditions for the scan loop: the scan only writes r7, r8, r9 and
    never touches memory or the halted flag.  These are needed to hand the
    scan result to the action phase. *)

Lemma scan_block_length : length scan_block = 15.
Proof. reflexivity. Qed.

Lemma scan_exec_reg2 :
  forall vm, vm_reg (exec_instr scan_block vm) 2 = vm_reg vm 2.
Proof.
  intro vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]];
    try (cbn [scan_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None scan_block (S (S (S (S (S (S (S (S (S (S (S (S (S (S (S n)))))))))))))))) ltac:(rewrite scan_block_length; lia)).
  cbn. reflexivity.
Qed.

Lemma scan_exec_reg3 :
  forall vm, vm_reg (exec_instr scan_block vm) 3 = vm_reg vm 3.
Proof.
  intro vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]];
    try (cbn [scan_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None scan_block (S (S (S (S (S (S (S (S (S (S (S (S (S (S (S n)))))))))))))))) ltac:(rewrite scan_block_length; lia)).
  cbn. reflexivity.
Qed.

Lemma scan_exec_mem :
  forall vm, vm_mem (exec_instr scan_block vm) = vm_mem vm.
Proof.
  intro vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]];
    try (cbn [scan_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None scan_block (S (S (S (S (S (S (S (S (S (S (S (S (S (S (S n)))))))))))))))) ltac:(rewrite scan_block_length; lia)).
  cbn. reflexivity.
Qed.

Lemma scan_exec_halted_lt13 :
  forall vm, vm_pc vm < 13 ->
    vm_halted (exec_instr scan_block vm) = vm_halted vm.
Proof.
  intros vm H.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]];
    try lia; cbn [scan_block]; cbn; reflexivity.
Qed.

Lemma scan_exec_pc_lt15 :
  forall vm, vm_pc vm < 15 -> vm_pc (exec_instr scan_block vm) < 15.
Proof.
  intros vm H.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]].
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - destruct (vm_zf vm), (vm_lf vm);
      unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - destruct (vm_zf vm);
      unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - destruct (vm_zf vm);
      unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - unfold scan_block; cbn; unfold instr_succ; cbn; lia.
  - exfalso; lia.
Qed.

Lemma scan_run_reg2 :
  forall fuel vm,
    vm_reg (run_until fuel scan_block scan_stop vm) 2 = vm_reg vm 2.
Proof.
  induction fuel as [|fuel IH]; intro vm.
  - reflexivity.
  - rewrite run_until_succ.
    destruct (orb (scan_stop (vm_pc vm)) (vm_halted vm)).
    + reflexivity.
    + rewrite IH. apply scan_exec_reg2.
Qed.

Lemma scan_run_reg3 :
  forall fuel vm,
    vm_reg (run_until fuel scan_block scan_stop vm) 3 = vm_reg vm 3.
Proof.
  induction fuel as [|fuel IH]; intro vm.
  - reflexivity.
  - rewrite run_until_succ.
    destruct (orb (scan_stop (vm_pc vm)) (vm_halted vm)).
    + reflexivity.
    + rewrite IH. apply scan_exec_reg3.
Qed.

Lemma scan_run_mem :
  forall fuel vm,
    vm_mem (run_until fuel scan_block scan_stop vm) = vm_mem vm.
Proof.
  induction fuel as [|fuel IH]; intro vm.
  - reflexivity.
  - rewrite run_until_succ.
    destruct (orb (scan_stop (vm_pc vm)) (vm_halted vm)).
    + reflexivity.
    + rewrite IH. apply scan_exec_mem.
Qed.

Lemma scan_stop_false_lt13 :
  forall pc, pc < 15 -> scan_stop pc = false -> pc < 13.
Proof.
  intros pc Hlt H.
  unfold scan_stop in H. apply orb_false_iff in H.
  destruct H as [H13 H14].
  apply Nat.eqb_neq in H13. apply Nat.eqb_neq in H14.
  unfold scan_match_pc, scan_none_pc in H13, H14. lia.
Qed.

Lemma scan_run_halted_false :
  forall fuel vm,
    vm_pc vm < 15 ->
    vm_halted vm = false ->
    vm_halted (run_until fuel scan_block scan_stop vm) = false.
Proof.
  induction fuel as [|fuel IH]; intros vm Hpc Hhalt.
  - exact Hhalt.
  - rewrite run_until_succ.
    destruct (orb (scan_stop (vm_pc vm)) (vm_halted vm)) eqn:E.
    + exact Hhalt.
    + apply orb_false_iff in E. destruct E as [Hstop Hhalt'].
      apply IH.
      * apply scan_exec_pc_lt15. exact Hpc.
      * assert (Hpc13 : vm_pc vm < 13)
          by (apply scan_stop_false_lt13; [exact Hpc | exact Hstop]).
        rewrite (scan_exec_halted_lt13 vm Hpc13). exact Hhalt'.
Qed.

Lemma scan_exec_reg0 :
  forall vm, vm_reg (exec_instr scan_block vm) 0 = vm_reg vm 0.
Proof.
  intro vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]];
    try (cbn [scan_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None scan_block (S (S (S (S (S (S (S (S (S (S (S (S (S (S (S n)))))))))))))))) ltac:(rewrite scan_block_length; lia)).
  cbn. reflexivity.
Qed.

Lemma scan_run_reg0 :
  forall fuel vm,
    vm_reg (run_until fuel scan_block scan_stop vm) 0 = vm_reg vm 0.
Proof.
  induction fuel as [|fuel IH]; intro vm.
  - reflexivity.
  - rewrite run_until_succ.
    destruct (orb (scan_stop (vm_pc vm)) (vm_halted vm)).
    + reflexivity.
    + rewrite IH. apply scan_exec_reg0.
Qed.

Lemma scan_exec_reg13 :
  forall vm, vm_reg (exec_instr scan_block vm) 13 = vm_reg vm 13.
Proof.
  intro vm.
  unfold exec_instr.
  destruct (vm_pc vm) as
    [|[|[|[|[|[|[|[|[|[|[|[|[|[|[|n]]]]]]]]]]]]]]];
    try (cbn [scan_block]; cbn; reflexivity).
  rewrite (proj2 (nth_error_None scan_block (S (S (S (S (S (S (S (S (S (S (S (S (S (S (S n)))))))))))))))) ltac:(rewrite scan_block_length; lia)).
  cbn. reflexivity.
Qed.

Lemma scan_run_reg13 :
  forall fuel vm,
    vm_reg (run_until fuel scan_block scan_stop vm) 13 = vm_reg vm 13.
Proof.
  induction fuel as [|fuel IH]; intro vm.
  - reflexivity.
  - rewrite run_until_succ.
    destruct (orb (scan_stop (vm_pc vm)) (vm_halted vm)).
    + reflexivity.
    + rewrite IH. apply scan_exec_reg13.
Qed.
