(** * First generic comparison macros for the concrete Minsky table

    These lemmas isolate the q0/q4 scan over an already-marked prefix.
    They are literal [MinskyTable.run] facts, not source-interpreter
    substitutions.  The full instruction macro is still to be built on
    top of them.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry.

Definition q0_pass (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q0_pass_step :
  forall s left right,
    q0_pass s ->
    step (entry_config 0 left (s :: right)) =
    entry_config 0 (s :: left) right.
Proof.
  intros s left right H; destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q0_scan_zero :
  forall marked left tail,
    Forall q0_pass marked ->
    run (S (length marked))
      (entry_config 0 left (marked ++ 0 :: tail)) =
    entry_config 2 (rev marked ++ left) (2 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    rewrite entry_run_successor.
    rewrite (q0_pass_step m left (rest ++ 0 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    simpl; reflexivity.
Qed.

Lemma q0_scan_one :
  forall marked left tail,
    Forall q0_pass marked ->
    run (S (length marked))
      (entry_config 0 left (marked ++ 1 :: tail)) =
    entry_config 3 (rev marked ++ left) (3 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    rewrite entry_run_successor.
    rewrite (q0_pass_step m left (rest ++ 1 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    simpl; reflexivity.
Qed.

Definition q4_pass (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q4_pass_step :
  forall s left right,
    q4_pass s ->
    step (entry_config 4 left (s :: right)) =
    entry_config 4 (s :: left) right.
Proof.
  intros s left right H; destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q4_scan_zero :
  forall marked left tail,
    Forall q4_pass marked ->
    run (S (length marked))
      (entry_config 4 left (marked ++ 0 :: tail)) =
    entry_config 3 (rev marked ++ left) (2 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    rewrite entry_run_successor.
    rewrite (q4_pass_step m left (rest ++ 0 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    simpl; reflexivity.
Qed.

Lemma q4_scan_one :
  forall marked left tail,
    Forall q4_pass marked ->
    run (S (length marked))
      (entry_config 4 left (marked ++ 1 :: tail)) =
    entry_config 2 (rev marked ++ left) (3 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    rewrite entry_run_successor.
    rewrite (q4_pass_step m left (rest ++ 1 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    simpl; reflexivity.
Qed.

Print Assumptions q0_scan_zero.
Print Assumptions q0_scan_one.
Print Assumptions q4_scan_zero.
Print Assumptions q4_scan_one.
