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

(** General left-frame induction: the scan moves each marker in front of
    the entire old left zipper, not in front of a fixed Y delimiter. *)
Lemma q9_write_bit_unframed :
  forall written bit rest left,
    (bit = 0 \/ bit = 1) ->
    Forall q9_pass written ->
    run (S (length written))
      (entry_config 9 left (written ++ bit :: rest)) =
    entry_config 11 (3 :: rev written ++ left) rest.
Proof.
  induction written as [|m ms IH]; intros bit rest left Hbit Hscan.
  - destruct Hbit as [-> | ->]; reflexivity.
  - inversion Hscan as [|? ? Hm Hrest]; subst.
    change (run (S (length ms))
      (step (entry_config 9 left (m :: ms ++ bit :: rest))) =
      entry_config 11 (3 :: rev (m :: ms) ++ left) rest).
    rewrite (q9_pass_step m left (ms ++ bit :: rest) Hm).
    rewrite (IH bit rest (m :: left) Hbit Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev ms) m left).
    reflexivity.
Qed.

Lemma q10_write_bit_unframed :
  forall written bit rest left,
    (bit = 0 \/ bit = 1) ->
    Forall q9_pass written ->
    run (S (length written))
      (entry_config 10 left (written ++ bit :: rest)) =
    entry_config 11 (2 :: rev written ++ left) rest.
Proof.
  induction written as [|m ms IH]; intros bit rest left Hbit Hscan.
  - destruct Hbit as [-> | ->]; reflexivity.
  - inversion Hscan as [|? ? Hm Hrest]; subst.
    change (run (S (length ms))
      (step (entry_config 10 left (m :: ms ++ bit :: rest))) =
      entry_config 11 (2 :: rev (m :: ms) ++ left) rest).
    rewrite (q10_pass_step m left (ms ++ bit :: rest) Hm).
    rewrite (IH bit rest (m :: left) Hbit Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev ms) m left).
    reflexivity.
Qed.

Lemma q9_write_bit :
  forall written bit rest prefix,
    (bit = 0 \/ bit = 1) ->
    Forall q9_pass written ->
    run (S (length written))
      (entry_config 9 (5 :: prefix) (written ++ bit :: rest)) =
    entry_config 11 (3 :: rev written ++ 5 :: prefix) rest.
Proof.
  intros written bit rest prefix Hbit Hscan.
  apply q9_write_bit_unframed; assumption.
Qed.

Lemma q10_write_bit :
  forall written bit rest prefix,
    (bit = 0 \/ bit = 1) ->
    Forall q9_pass written ->
    run (S (length written))
      (entry_config 10 (5 :: prefix) (written ++ bit :: rest)) =
    entry_config 11 (2 :: rev written ++ 5 :: prefix) rest.
Proof.
  intros written bit rest prefix Hbit Hscan.
  apply q10_write_bit_unframed; assumption.
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

(** q11 is a RIGHT-moving scan.  X must therefore occur in the right
    suffix after the scanned cells; placing X in the left zipper would
    state an incorrect theorem for arbitrary surrounding tape. *)
Theorem q11_scan_to_marker :
  forall scanned left tail,
    Forall q11_pass scanned ->
    run (S (length scanned))
      (entry_config 11 left (scanned ++ 4 :: tail)) =
    entry_config 6 (4 :: rev scanned ++ left) tail.
Proof.
  induction scanned as [|s rest IH]; intros left tail Hscan.
  - reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (length rest))
      (step (entry_config 11 left (s :: rest ++ 4 :: tail))) =
      entry_config 6 (4 :: rev (s :: rest) ++ left) tail).
    rewrite (q11_pass_step s left (rest ++ 4 :: tail) Hs).
    rewrite (IH (s :: left) tail Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) s left).
    reflexivity.
Qed.

Print Assumptions q9_write_bit.
Print Assumptions q10_write_bit.
Print Assumptions q11_scan_to_marker.

Definition q12_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 7.

Lemma q12_pass_step :
  forall s next left right,
    q12_pass s ->
    step (entry_config 12 (next :: left) (s :: right)) =
    entry_config 12 left (next :: s :: right).
Proof.
  intros s next left right H;
    destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q12_cross_marker :
  forall left right,
    step (entry_config 12 left (6 :: right)) =
    entry_config 14 (3 :: left) right.
Proof. reflexivity. Qed.

Theorem q12_scan_to_m :
  forall remaining s prefix suffix,
    Forall q12_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 12 (remaining ++ 6 :: prefix) (s :: suffix)) =
    entry_config 14 (3 :: prefix) (rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix H.
  - inversion H as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion H as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 12 (next :: (rest ++ 6 :: prefix)) (s :: suffix)) =
      entry_config 14 (3 :: prefix) (rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q12_pass_step s next (rest ++ 6 :: prefix) suffix Hs).
    rewrite (IH next prefix (s :: suffix) Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

Definition q13_pass (s : nat) : Prop := q12_pass s.

Lemma q13_pass_step :
  forall s next left right,
    q13_pass s ->
    step (entry_config 13 (next :: left) (s :: right)) =
    entry_config 13 left (next :: s :: right).
Proof.
  intros s next left right H;
    destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q13_cross_marker :
  forall left right,
    step (entry_config 13 left (6 :: right)) =
    entry_config 14 (2 :: left) right.
Proof. reflexivity. Qed.

Theorem q13_scan_to_m :
  forall remaining s prefix suffix,
    Forall q13_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 13 (remaining ++ 6 :: prefix) (s :: suffix)) =
    entry_config 14 (2 :: prefix) (rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix H.
  - inversion H as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion H as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 13 (next :: (rest ++ 6 :: prefix)) (s :: suffix)) =
      entry_config 14 (2 :: prefix) (rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q13_pass_step s next (rest ++ 6 :: prefix) suffix Hs).
    rewrite (IH next prefix (s :: suffix) Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

Print Assumptions q12_scan_to_m.
Print Assumptions q13_scan_to_m.

Definition q14_restore (s : nat) : nat :=
  match s with 2 => 0 | 3 => 1 | _ => s end.

Definition q14_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 5 \/ s = 6 \/ s = 7.

Lemma q14_pass_step :
  forall s left right,
    q14_pass s ->
    step (entry_config 14 left (s :: right)) =
    entry_config 14 (q14_restore s :: left) right.
Proof.
  intros s left right H;
    destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Theorem q14_scan_to_x :
  forall scanned left tail,
    Forall q14_pass scanned ->
    run (S (length scanned))
      (entry_config 14 left (scanned ++ 4 :: tail)) =
    entry_config 15 (4 :: map q14_restore (rev scanned) ++ left) tail.
Proof.
  induction scanned as [|s rest IH]; intros left tail H.
  - cbn. reflexivity.
  - inversion H as [|? ? Hs Hrest]; subst.
    change (S (length (s :: rest))) with (S (S (length rest))).
    change (run (S (length rest))
      (step (entry_config 14 left (s :: (rest ++ 4 :: tail)))) =
      entry_config 15 (4 :: map q14_restore (rev (s :: rest)) ++ left) tail).
    rewrite (q14_pass_step s left (rest ++ 4 :: tail) Hs).
    rewrite (IH (q14_restore s :: left) tail Hrest).
    cbn [rev map].
    rewrite <- (append_singleton_assoc (map q14_restore (rev rest)) (q14_restore s) left).
    reflexivity.
Qed.

Print Assumptions q14_scan_to_x.
