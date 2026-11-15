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
    cbn [rev app].
    rewrite (append_singleton_assoc (rev rest) m left).
    unfold cfg_ml.
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
    cbn [rev app].
    rewrite (append_singleton_assoc (rev rest) m left).
    unfold cfg_ml.
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
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

Print Assumptions q6_scan_zero.
Print Assumptions q6_scan_one.
Print Assumptions q7_scan_to_y.

Definition q8_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 4 \/ s = 6 \/ s = 7.

Lemma q8_pass_step :
  forall s next left right,
    q8_pass s ->
    step (entry_config 8 (next :: left) (s :: right)) =
    entry_config 8 left (next :: s :: right).
Proof.
  intros s next left right H;
    destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q8_cross_delimiter :
  forall left right,
    step (entry_config 8 left (5 :: right)) =
    entry_config 10 (5 :: left) right.
Proof. reflexivity. Qed.

Theorem q8_scan_to_y :
  forall remaining s prefix suffix,
    Forall q8_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 8 (remaining ++ 5 :: prefix) (s :: suffix)) =
    entry_config 10 (5 :: prefix)
      (rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix H.
  - inversion H as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion H as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 8 (next :: (rest ++ 5 :: prefix)) (s :: suffix)) =
      entry_config 10 (5 :: prefix)
        (rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q8_pass_step s next (rest ++ 5 :: prefix) suffix Hs).
    rewrite (IH next prefix (s :: suffix) Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

Print Assumptions q8_scan_to_y.

Definition q9_pass (s : nat) : Prop := s = 2 \/ s = 3.

Lemma q9_pass_step :
  forall s left right,
    q9_pass s ->
    step (entry_config 9 left (s :: right)) =
    entry_config 9 (s :: left) right.
Proof. intros s left right [-> | ->]; reflexivity. Qed.

Lemma q10_pass_step :
  forall s left right,
    q9_pass s ->
    step (entry_config 10 left (s :: right)) =
    entry_config 10 (s :: left) right.
Proof. intros s left right [-> | ->]; reflexivity. Qed.

Lemma q9_write_bit :
  forall written bit rest prefix,
    Forall q9_pass written ->
    run (S (length written))
      (entry_config 9 (5 :: prefix) (written ++ bit :: rest)) =
    entry_config 11 (3 :: rev written ++ 5 :: prefix) rest.
Proof.
  induction written as [|m ms IH]; intros bit rest prefix H.
  - cbn. reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: ms))) with (S (S (length ms))).
    change (run (S (length ms))
      (step (entry_config 9 (5 :: prefix) (m :: (ms ++ bit :: rest)))) =
      entry_config 11 (3 :: rev (m :: ms) ++ 5 :: prefix) rest).
    rewrite (q9_pass_step m (5 :: prefix) (ms ++ bit :: rest) Hm).
    rewrite (IH bit rest (m :: 5 :: prefix) Hrest).
    cbn [rev]. rewrite (append_singleton_assoc (rev ms) m (5::prefix)).
    reflexivity.
Qed.

Lemma q10_write_bit :
  forall written bit rest prefix,
    Forall q9_pass written ->
    run (S (length written))
      (entry_config 10 (5 :: prefix) (written ++ bit :: rest)) =
    entry_config 11 (2 :: rev written ++ 5 :: prefix) rest.
Proof.
  induction written as [|m ms IH]; intros bit rest prefix H.
  - cbn. reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: ms))) with (S (S (length ms))).
    change (run (S (length ms))
      (step (entry_config 10 (5 :: prefix) (m :: (ms ++ bit :: rest)))) =
      entry_config 11 (2 :: rev (m :: ms) ++ 5 :: prefix) rest).
    rewrite (q10_pass_step m (5 :: prefix) (ms ++ bit :: rest) Hm).
    rewrite (IH bit rest (m :: 5 :: prefix) Hrest).
    cbn [rev]. rewrite (append_singleton_assoc (rev ms) m (5::prefix)).
    reflexivity.
Qed.

Definition q11_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q11_pass_step :
  forall s left right,
    q11_pass s ->
    step (entry_config 11 left (s :: right)) =
    entry_config 11 (s :: left) right.
Proof.
  intros s left right H;
    destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q11_cross_marker :
  forall left right,
    step (entry_config 11 left (4 :: right)) =
    entry_config 6 (4 :: left) right.
Proof. reflexivity. Qed.

Theorem q11_scan_to_marker :
  forall remaining s prefix suffix,
    Forall q11_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 11 (remaining ++ 4 :: prefix) (s :: suffix)) =
    entry_config 6 (4 :: rev (s :: remaining) ++ prefix) suffix.
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix H.
  - inversion H as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion H as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 11 (next :: (rest ++ 4 :: prefix)) (s :: suffix)) =
      entry_config 6 (4 :: rev (s :: next :: rest) ++ prefix) suffix).
    rewrite entry_run_successor.
    rewrite (q11_pass_step s next (rest ++ 4 :: prefix) suffix Hs).
    rewrite (IH next prefix (s :: suffix) Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) next (4 :: prefix)).
    reflexivity.
Qed.

Print Assumptions q9_write_bit.
Print Assumptions q10_write_bit.
Print Assumptions q11_scan_to_marker.
