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
  - change (S (vm_pc vm) = S (lp_pc L)).
    rewrite Hpc. reflexivity.
  - intros i Hi.
    change (set_reg (vm_reg vm) d imm i =
            N.to_nat (lget_regN (lset_word (lp_reg L) d (N.of_nat imm)) i)
              mod 2 ^ 32).
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite set_reg_eq.
      rewrite (lget_regN_lset_word_eq (lp_reg L) d (N.of_nat imm))
        by (rewrite Hlen; lia).
      rewrite Nat2N.id.
      rewrite Nat.mod_small by exact Himm. reflexivity.
    + rewrite (set_reg_neq _ _ _ _ Hne).
      rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) i Hne).
      exact (Hregs i Hi).
  - change (set_reg (vm_reg vm) d imm 15 =
            N.to_nat (lget_regN (lset_word (lp_reg L) d (N.of_nat imm)) 15)
              mod 2 ^ 32).
    rewrite (set_reg_neq _ _ _ _ (not_eq_sym Hd15)).
    rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) 15
      (not_eq_sym Hd15)).
    exact Hreg15.
  - change (vm_link vm =
            N.to_nat (lget_regN (lset_word (lp_reg L) d (N.of_nat imm)) 15)).
    rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) 15
      (not_eq_sym Hd15)).
    exact Hlink.
  - intro a.
    change (vm_mem vm a =
            payload_word (lp_mem_at (lp_exec L (pMOVI d imm)) a)).
    rewrite lp_mem_at_lp_exec_MOVI.
    exact (Hmem a).
  - change (vm_zf vm = Nat.eqb ((lp_k L / 2) mod 2) 1).
    exact Hzf.
  - change (vm_lf vm = Nat.eqb (lp_k L mod 2) 1).
    exact Hlf.
  - change (lp_k L < 4). exact Hk.
  - change (vm_halted vm = lp_halted L). exact Hhalt.
  - intros i Hi.
    change (N.to_nat (lget_regN (lset_word (lp_reg L) d (N.of_nat imm)) i)
            < 2 ^ 32).
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite (lget_regN_lset_word_eq (lp_reg L) d (N.of_nat imm))
        by (rewrite Hlen; lia).
      rewrite Nat2N.id. exact Himm.
    + rewrite (lget_regN_lset_word_neq (lp_reg L) d (N.of_nat imm) i Hne).
      exact (Hbound i Hi).
Qed.

Print Assumptions lp_exec_MOVI_refines.

(** ** HALT *)

Theorem lp_exec_HALT_refines :
  forall L vm prog,
    Rlp L vm ->
    decode_word_p (lp_mem_at L (lp_pc L)) = Some pHALT ->
    nth_error prog (vm_pc vm) = Some pHALT ->
    Rlp (lp_exec L pHALT) (exec_instr_p prog vm).
Proof.
  intros L vm prog HR Hdec Hnth.
  unfold Rlp in *.
  destruct HR as
    (Hpc & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold lp_exec, exec_instr_p.
  rewrite Hnth. cbn.
  unfold R, lp_to_LState.
  split_conj_step.
  - change (vm_pc vm = lp_pc L). exact Hpc.
  - intros i Hi.
    change (vm_reg vm i = N.to_nat (lget_regN (lp_reg L) i) mod 2 ^ 32).
    exact (Hregs i Hi).
  - change (vm_reg vm 15 =
            N.to_nat (lget_regN (lp_reg L) 15) mod 2 ^ 32).
    exact Hreg15.
  - change (vm_link vm = N.to_nat (lget_regN (lp_reg L) 15)).
    exact Hlink.
  - intro a.
    change (vm_mem vm a = payload_word (lp_mem_at (lp_exec L pHALT) a)).
    rewrite lp_mem_at_lp_exec_HALT. exact (Hmem a).
  - change (vm_zf vm = Nat.eqb ((lp_k L / 2) mod 2) 1). exact Hzf.
  - change (vm_lf vm = Nat.eqb (lp_k L mod 2) 1). exact Hlf.
  - change (lp_k L < 4). exact Hk.
  - change (true = true). reflexivity.
  - intros i Hi.
    change (N.to_nat (lget_regN (lp_reg L) i) < 2 ^ 32).
    exact (Hbound i Hi).
Qed.

(** ** PUTC *)

Theorem lp_exec_PUTC_refines :
  forall L vm prog d,
    Rlp L vm ->
    decode_word_p (lp_mem_at L (lp_pc L)) = Some (pPUTC d) ->
    nth_error prog (vm_pc vm) = Some (pPUTC d) ->
    Rlp (lp_exec L (pPUTC d)) (exec_instr_p prog vm).
Proof.
  intros L vm prog d HR Hdec Hnth.
  unfold Rlp in *.
  destruct HR as
    (Hpc & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold lp_exec, exec_instr_p.
  rewrite Hnth. cbn.
  unfold R, lp_to_LState.
  split_conj_step.
  - change (S (vm_pc vm) = S (lp_pc L)). rewrite Hpc. reflexivity.
  - intros i Hi.
    change (vm_reg vm i = N.to_nat (lget_regN (lp_reg L) i) mod 2 ^ 32).
    exact (Hregs i Hi).
  - change (vm_reg vm 15 =
            N.to_nat (lget_regN (lp_reg L) 15) mod 2 ^ 32).
    exact Hreg15.
  - change (vm_link vm = N.to_nat (lget_regN (lp_reg L) 15)).
    exact Hlink.
  - intro a.
    change (vm_mem vm a = payload_word (lp_mem_at (lp_exec L (pPUTC d)) a)).
    rewrite lp_mem_at_lp_exec_PUTC. exact (Hmem a).
  - change (vm_zf vm = Nat.eqb ((lp_k L / 2) mod 2) 1). exact Hzf.
  - change (vm_lf vm = Nat.eqb (lp_k L mod 2) 1). exact Hlf.
  - change (lp_k L < 4). exact Hk.
  - change (vm_halted vm = lp_halted L). exact Hhalt.
  - intros i Hi.
    change (N.to_nat (lget_regN (lp_reg L) i) < 2 ^ 32).
    exact (Hbound i Hi).
Qed.

(** ** RET *)

Theorem lp_exec_RET_refines :
  forall L vm prog,
    Rlp L vm ->
    decode_word_p (lp_mem_at L (lp_pc L)) = Some pRET ->
    nth_error prog (vm_pc vm) = Some pRET ->
    Rlp (lp_exec L pRET) (exec_instr_p prog vm).
Proof.
  intros L vm prog HR Hdec Hnth.
  unfold Rlp in *.
  destruct HR as
    (Hpc & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  unfold lp_exec, exec_instr_p.
  rewrite Hnth. cbn.
  unfold R, lp_to_LState.
  split_conj_step.
  - change (vm_link vm = N.to_nat (lget_regN (lp_reg L) 15)). exact Hlink.
  - intros i Hi.
    change (vm_reg vm i = N.to_nat (lget_regN (lp_reg L) i) mod 2 ^ 32).
    exact (Hregs i Hi).
  - change (vm_reg vm 15 =
            N.to_nat (lget_regN (lp_reg L) 15) mod 2 ^ 32).
    exact Hreg15.
  - change (vm_link vm = N.to_nat (lget_regN (lp_reg L) 15)). exact Hlink.
  - intro a.
    change (vm_mem vm a = payload_word (lp_mem_at (lp_exec L pRET) a)).
    rewrite lp_mem_at_lp_exec_RET. exact (Hmem a).
  - change (vm_zf vm = Nat.eqb ((lp_k L / 2) mod 2) 1). exact Hzf.
  - change (vm_lf vm = Nat.eqb (lp_k L mod 2) 1). exact Hlf.
  - change (lp_k L < 4). exact Hk.
  - change (vm_halted vm = lp_halted L). exact Hhalt.
  - intros i Hi.
    change (N.to_nat (lget_regN (lp_reg L) i) < 2 ^ 32).
    exact (Hbound i Hi).
Qed.

Print Assumptions lp_exec_HALT_refines.
Print Assumptions lp_exec_PUTC_refines.
Print Assumptions lp_exec_RET_refines.

(** ** LD *)

Theorem lp_exec_LD_refines :
  forall L vm prog d a imm,
    Rlp L vm ->
    List.length (lp_reg L) = 16 ->
    d < 16 ->
    d <> 15 ->
    a < 16 ->
    decode_word_p (lp_mem_at L (lp_pc L)) = Some (pLD d a imm) ->
    nth_error prog (vm_pc vm) = Some (pLD d a imm) ->
    Rlp (lp_exec L (pLD d a imm)) (exec_instr_p prog vm).
Proof.
  intros L vm prog d a imm HR Hlen Hd Hd15 Ha Hdec Hnth.
  pose proof HR as HR_R.
  unfold Rlp in *.
  destruct HR as
    (Hpc & Hregs & Hreg15 & Hlink & Hmem & Hzf & Hlf & Hk & Hhalt & Hbound).
  pose proof (R_reg_eq (lp_to_LState L) vm a HR_R Ha) as Hreg_a.
  assert (Haddr : vm_reg vm a = lget_reg (lp_reg L) a).
  { unfold lget_reg. exact Hreg_a. }
  unfold lp_exec, exec_instr_p.
  rewrite Hnth. cbn.
  unfold R, lp_to_LState.
  split_conj_step.
  - change (S (vm_pc vm) = S (lp_pc L)). rewrite Hpc. reflexivity.
  - intros i Hi.
    change (set_reg (vm_reg vm) d
              (vm_mem vm (vm_reg vm a + imm)) i =
            N.to_nat
              (lget_regN
                (lset_word (lp_reg L) d
                  (word_payload
                    (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm)))) i)
              mod 2 ^ 32).
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite set_reg_eq.
      rewrite (lget_regN_lset_word_eq (lp_reg L) d
        (word_payload
          (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm))))
        by (rewrite Hlen; lia).
      rewrite Haddr.
      rewrite (Hmem (lget_reg (lp_reg L) a + imm)).
      rewrite <- (lp_mem_at_eq L (lget_reg (lp_reg L) a + imm)).
      rewrite Nat.mod_small by apply payload_word_lt_two32.
      reflexivity.
    + rewrite (set_reg_neq _ _ _ _ Hne).
      rewrite (lget_regN_lset_word_neq (lp_reg L) d
        (word_payload
          (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm))) i Hne).
      exact (Hregs i Hi).
  - change (set_reg (vm_reg vm) d
              (vm_mem vm (vm_reg vm a + imm)) 15 =
            N.to_nat
              (lget_regN
                (lset_word (lp_reg L) d
                  (word_payload
                    (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm)))) 15)
              mod 2 ^ 32).
    rewrite (set_reg_neq _ _ _ _ (not_eq_sym Hd15)).
    rewrite (lget_regN_lset_word_neq (lp_reg L) d
      (word_payload
        (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm))) 15
      (not_eq_sym Hd15)).
    exact Hreg15.
  - change (vm_link vm =
            N.to_nat
              (lget_regN
                (lset_word (lp_reg L) d
                  (word_payload
                    (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm)))) 15)).
    rewrite (lget_regN_lset_word_neq (lp_reg L) d
      (word_payload
        (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm))) 15
      (not_eq_sym Hd15)).
    exact Hlink.
  - intro x.
    change (vm_mem vm x =
            payload_word (lp_mem_at (lp_exec L (pLD d a imm)) x)).
    rewrite lp_mem_at_lp_exec_LD. exact (Hmem x).
  - change (vm_zf vm = Nat.eqb ((lp_k L / 2) mod 2) 1). exact Hzf.
  - change (vm_lf vm = Nat.eqb (lp_k L mod 2) 1). exact Hlf.
  - change (lp_k L < 4). exact Hk.
  - change (vm_halted vm = lp_halted L). exact Hhalt.
  - intros i Hi.
    change (N.to_nat
              (lget_regN
                (lset_word (lp_reg L) d
                  (word_payload
                    (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm)))) i)
            < 2 ^ 32).
    destruct (Nat.eq_dec i d) as [-> | Hne].
    + rewrite (lget_regN_lset_word_eq (lp_reg L) d
        (word_payload
          (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm))))
        by (rewrite Hlen; lia).
      apply payload_word_lt_two32.
    + rewrite (lget_regN_lset_word_neq (lp_reg L) d
        (word_payload
          (mem_get (lp_mem L) (lget_reg (lp_reg L) a + imm))) i Hne).
      exact (Hbound i Hi).
Qed.

Print Assumptions lp_exec_LD_refines.
