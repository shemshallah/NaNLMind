From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16Action.

Lemma action_head_state_neq : action_head_addr <> action_state_addr.
Proof. unfold action_head_addr, action_state_addr. lia. Qed.
Lemma action_head_halt_neq : action_head_addr <> action_halt_addr.
Proof. unfold action_head_addr, action_halt_addr. lia. Qed.
Lemma action_state_halt_neq : action_state_addr <> action_halt_addr.
Proof. unfold action_state_addr, action_halt_addr. lia. Qed.

Ltac run_set_mem :=
  repeat (rewrite set_mem_neq by
    (first [assumption | (symmetry; assumption) |
      (unfold action_head_addr, action_state_addr, action_halt_addr; lia)]));
  try apply set_mem_same; try reflexivity.

Lemma action_run_head :
  forall row_addr tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    fst (action_run row_addr tape_addr head m row) =
      action_new_head head (nth 3 row 1).
Proof. intros. unfold action_run. cbn. reflexivity. Qed.

Lemma action_run_tape :
  forall row_addr tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) tape_addr =
      nth 2 row 0.
Proof.
  intros. unfold action_run. cbn.
  destruct (Nat.eqb (nth 5 row 1) 0); run_set_mem.
Qed.

Lemma action_run_state :
  forall row_addr tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) action_state_addr =
      nth 4 row 1.
Proof.
  intros. unfold action_run. cbn.
  destruct (Nat.eqb (nth 5 row 1) 0); run_set_mem.
Qed.

Lemma action_run_head_cell :
  forall row_addr tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) action_head_addr =
      action_new_head head (nth 3 row 1).
Proof.
  intros. unfold action_run. cbn.
  destruct (Nat.eqb (nth 5 row 1) 0); run_set_mem.
Qed.

Lemma action_run_halt_cell :
  forall row_addr tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) action_halt_addr =
      (if Nat.eqb (nth 5 row 1) 0 then m action_halt_addr else 1).
Proof.
  intros. unfold action_run. cbn.
  destruct (Nat.eqb (nth 5 row 1) 0) eqn:E; run_set_mem;
    try (rewrite set_mem_neq by (symmetry; assumption)); reflexivity.
Qed.

Lemma action_run_frame :
  forall row_addr tape_addr head m row k,
    k <> tape_addr ->
    k <> action_head_addr ->
    k <> action_state_addr ->
    k <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) k = m k.
Proof.
  intros. unfold action_run. cbn.
  destruct (Nat.eqb (nth 5 row 1) 0); run_set_mem.
Qed.
