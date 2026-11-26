(** * First literal-executor step refinement: MOVI

    This module starts the [LPState] -> Coq VM one-step simulation.  It
    proves the register-file update lemmas and the MOVI case, with no
    memory normalization: [lp_mem_at] is opaque and the MOVI memory
    preservation is a separate checked equality. *)

From Coq Require Import List Arith Bool Lia NArith String.
Import ListNotations.
Open Scope nat_scope.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16LiteralMachine
  MinskyNaN16LiteralDecode MinskyNaN16LiteralPuts MinskyNaN16LiteralExec
  MinskyNaN16LiteralBridge.

(** ** Register-file update lemmas *)

Lemma lset_word_length :
  forall r i v, List.length (lset_word r i v) = List.length r.
Proof.
  intros r. induction r as [|x xs IH]; intros i v.
  - reflexivity.
  - destruct i; simpl; [reflexivity|rewrite IH; reflexivity].
Qed.

Lemma lget_regN_lset_word_eq :
  forall r i v,
    i < List.length r ->
    lget_regN (lset_word r i v) i = v.
Proof.
  intros r. induction r as [|x xs IH]; intros i v Hi.
  - simpl in Hi. lia.
  - destruct i as [|i].
    + reflexivity.
    + simpl. apply IH. simpl in Hi. lia.
Qed.

Lemma lget_regN_lset_word_neq :
  forall r i v j,
    j <> i ->
    lget_regN (lset_word r i v) j = lget_regN r j.
Proof.
  intros r. induction r as [|x xs IH]; intros i v j Hneq.
  - destruct i, j; simpl; reflexivity.
  - destruct i as [|i], j as [|j].
    + exfalso. apply Hneq. reflexivity.
    + reflexivity.
    + reflexivity.
    + simpl. apply IH. intro H. apply Hneq. now f_equal.
Qed.

Ltac split_conj_step := repeat match goal with |- _ /\ _ => split end.

(** ** MOVI one-step refinement *)

Theorem lp_exec_MOVI_refines :
  forall L vm prog d imm,
    Rlp L vm ->
    List.length (lp_reg L) = 16 ->
    d < 16 ->
    d <> 15 ->
    imm < 2 ^ 32 ->
    decode_word_p (lp_mem_at L (lp_pc L)) = Some (pMOVI d imm) ->
    nth_error prog (vm_pc vm) = Some (pMOVI d imm) ->
    Rlp (lp_exec L (pMOVI d imm)) (exec_instr_p prog vm).
Proof.
  intros L vm prog d imm HR Hlen Hd Hd15 Himm Hdec Hnth.
  unfold Rlp in *.
  destruct HR as
    (Hpc & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold lp_exec, exec_instr_p.
  rewrite Hnth.
  cbn.
  unfold R, lp_to_LState.
  split_conj_step.
  - unfold instr_succ. rewrite Hpc. reflexivity.
  - intros i Hi.
    match goal with |- ?G => idtac "REGS_GOAL:" G end.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite set_reg_eq.
      rewrite (lget_regN_lset_word_eq (lp_reg L) d (N.of_nat imm))
        by (rewrite Hlen; lia).
      rewrite N2Nat.id.
      apply Nat.mod_small. exact Himm.
    + rewrite (set_reg_neq _ _ _ _ Hne).
      rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) i Hne).
      exact (Hregs i Hi).
  - rewrite (set_reg_neq _ _ _ _ (not_eq_sym Hd15)).
    rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) 15
      (not_eq_sym Hd15)).
    exact Hreg15.
  - rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) 15
      (not_eq_sym Hd15)).
    exact Hlink.
  - rewrite lp_mem_at_lp_exec_MOVI.
    exact Hmem.
  - exact Hzf.
  - exact Hlf.
  - exact Hk.
  - exact Hhalt.
  - intros i Hi.
    match goal with |- ?G => idtac "REGS_GOAL:" G end.
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite (lget_regN_lset_word_eq (lp_reg L) d (N.of_nat imm))
        by (rewrite Hlen; lia).
      rewrite N2Nat.id. exact Himm.
    + rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) i Hne).
      exact (Hbound i Hi).
Qed.

Print Assumptions lp_exec_MOVI_refines.
