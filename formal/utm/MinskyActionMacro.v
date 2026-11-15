(** * First action-copy macros for the concrete Minsky table

    q6 scans over an already-marked prefix to the first unmarked action
    bit; q7/q8 return left to Y carrying the copied bit.  These are
    literal [MinskyTable.run] facts.  The q9/q10 write-back and q11
    return are separate obligations; no universality claim is made.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyMatchMacro.

Definition q6_pass (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q6_pass_step :
  forall s left right,
    q6_pass s ->
    step (entry_config 6 left (s :: right)) =
    entry_config 6 (s :: left) right.
Proof.
  intros s left right H;
    destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Lemma q6_scan_zero :
  forall marked left tail,
    Forall q6_pass marked ->
    run (S (length marked))
      (entry_config 6 left (marked ++ 0 :: tail)) =
    cfg_ml 8 (rev marked ++ left) (2 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - cbn. unfold cfg_ml. destruct left; reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    change (run (S (length rest))
      (step (entry_config 6 left (m :: (rest ++ 0 :: tail)))) =
      cfg_ml 8 (rev (m :: rest) ++ left) (2 :: tail)).
    rewrite (q6_pass_step m left (rest ++ 0 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    cbn [rev app]. unfold cfg_ml.
    destruct (rev rest ++ m :: left) as [|x xs]; reflexivity.
Qed.

Lemma q6_scan_one :
  forall marked left tail,
    Forall q6_pass marked ->
    run (S (length marked))
      (entry_config 6 left (marked ++ 1 :: tail)) =
    cfg_ml 7 (rev marked ++ left) (3 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - cbn. unfold cfg_ml. destruct left; reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    change (run (S (length rest))
      (step (entry_config 6 left (m :: (rest ++ 1 :: tail)))) =
      cfg_ml 7 (rev (m :: rest) ++ left) (3 :: tail)).
    rewrite (q6_pass_step m left (rest ++ 1 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    cbn [rev app]. unfold cfg_ml.
    destruct (rev rest ++ m :: left) as [|x xs]; reflexivity.
Qed.

Definition q7_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 4 \/ s = 6 \/ s = 7.

Lemma q7_pass_step :
  forall s next left right,
    q7_pass s ->
    step (entry_config 7 (next :: left) (s :: right)) =
    entry_config 7 left (next :: s :: right).
Proof.
  intros s next left right H;
    destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q7_cross_delimiter :
  forall left right,
    step (entry_config 7 left (5 :: right)) =
    entry_config 9 (5 :: left) right.
Proof. reflexivity. Qed.

Theorem q7_scan_to_y :
  forall remaining s prefix suffix,
    Forall q7_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 7 (remaining ++ 5 :: prefix) (s :: suffix)) =
    entry_config 9 (5 :: prefix)
      (rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix H.
  - inversion H as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion H as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 7 (next :: (rest ++ 5 :: prefix)) (s :: suffix)) =
      entry_config 9 (5 :: prefix)
        (rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q7_pass_step s next (rest ++ 5 :: prefix) suffix Hs).
    rewrite (IH next prefix (s :: suffix) Hrest).
    cbn [rev]. rewrite append_singleton_assoc. reflexivity.
Qed.

Print Assumptions q6_scan_zero.
Print Assumptions q6_scan_one.
Print Assumptions q7_scan_to_y.
