(** * Generic q0/q4 comparison scans for the concrete Minsky table

    These lemmas isolate the first half of a one-bit comparison: q0/q4
    pass over an already-marked prefix and consume the next 0/1 row bit.
    A matched bit moves left into q2; a mismatch moves right into q3.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry MinskyConcreteDispatch.

Definition q0_pass (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 4 \/ s = 5 \/ s = 6 \/ s = 7.

Definition cfg_ml (q : nat) (left right : list nat) : Config :=
  match left with
  | [] => entry_config q [] (2 :: right)
  | x :: xs => entry_config q xs (x :: right)
  end.

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
    cfg_ml 2 (rev marked ++ left) (2 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - cbn. unfold cfg_ml. destruct left; reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    change (run (S (length rest))
      (step (entry_config 0 left (m :: (rest ++ 0 :: tail)))) =
      cfg_ml 2 (rev (m :: rest) ++ left) (2 :: tail)).
    rewrite (q0_pass_step m left (rest ++ 0 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    cbn [rev app].
    replace ((rev rest ++ [m]) ++ left) with (rev rest ++ m :: left)
      by (rewrite <- app_assoc; reflexivity).
    unfold cfg_ml.
    destruct (rev rest ++ m :: left) as [|x xs]; reflexivity.
Qed.

Lemma q0_scan_one :
  forall marked left tail,
    Forall q0_pass marked ->
    run (S (length marked))
      (entry_config 0 left (marked ++ 1 :: tail)) =
    entry_config 3 (3 :: rev marked ++ left) tail.
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - vm_compute; reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    change (run (S (length rest))
      (step (entry_config 0 left (m :: (rest ++ 1 :: tail)))) =
      entry_config 3 (3 :: rev (m :: rest) ++ left) tail).
    rewrite (q0_pass_step m left (rest ++ 1 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    cbn [rev].
    rewrite <- app_assoc.
    reflexivity.
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
    entry_config 3 (2 :: rev marked ++ left) tail.
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - vm_compute; reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    change (run (S (length rest))
      (step (entry_config 4 left (m :: (rest ++ 0 :: tail)))) =
      entry_config 3 (2 :: rev (m :: rest) ++ left) tail).
    rewrite (q4_pass_step m left (rest ++ 0 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    cbn [rev].
    rewrite <- app_assoc.
    reflexivity.
Qed.

Lemma q4_scan_one :
  forall marked left tail,
    Forall q4_pass marked ->
    run (S (length marked))
      (entry_config 4 left (marked ++ 1 :: tail)) =
    cfg_ml 2 (rev marked ++ left) (3 :: tail).
Proof.
  induction marked as [|m rest IH]; intros left tail H.
  - cbn. unfold cfg_ml. destruct left; reflexivity.
  - inversion H as [|? ? Hm Hrest]; subst.
    change (S (length (m :: rest))) with (S (S (length rest))).
    change (run (S (length rest))
      (step (entry_config 4 left (m :: (rest ++ 1 :: tail)))) =
      cfg_ml 2 (rev (m :: rest) ++ left) (3 :: tail)).
    rewrite (q4_pass_step m left (rest ++ 1 :: tail) Hm).
    rewrite (IH (m :: left) tail Hrest).
    cbn [rev app].
    replace ((rev rest ++ [m]) ++ left) with (rev rest ++ m :: left)
      by (rewrite <- app_assoc; reflexivity).
    unfold cfg_ml.
    destruct (rev rest ++ m :: left) as [|x xs]; reflexivity.
Qed.

Lemma q3_reaches_marker :
  forall symbols prefix suffix,
    Forall dispatch_right_symbol symbols ->
    run (length symbols + 1)
      (entry_config 3 prefix (symbols ++ 4 :: suffix)) =
    step (entry_config 3 (rev symbols ++ prefix) (4 :: suffix)).
Proof.
  apply dispatch_right_reaches_marker.
Qed.

Print Assumptions q0_scan_zero.
Print Assumptions q0_scan_one.
Print Assumptions q4_scan_zero.
Print Assumptions q4_scan_one.
Print Assumptions q3_reaches_marker.

(** A matched zero bit: after the q0/q4 prefix scan the machine moves
    left into q2 and returns to the left-hand Y.  The markup split is an
    explicit hypothesis so the result can be composed by the match loop. *)
Lemma q0_match_zero_to_y :
  forall marked x remaining prefix tail,
    Forall q0_pass marked ->
    rev marked = x :: remaining ->
    Forall dispatch_left_symbol (x :: remaining) ->
    run (S (length marked) + S (length remaining))
      (entry_config 0 (5 :: prefix) (marked ++ 0 :: tail)) =
    entry_config 1 (5 :: prefix)
      (rev (x :: remaining) ++ 2 :: tail).
Proof.
  intros marked x remaining prefix tail Hmarked Hrev Hleft.
  rewrite (dispatch_run_add (S (length marked)) (S (length remaining))
    (entry_config 0 (5 :: prefix) (marked ++ 0 :: tail))).
  rewrite (q0_scan_zero marked (5 :: prefix) tail Hmarked).
  rewrite Hrev.
  cbn [cfg_ml].
  rewrite (dispatch_left_to_delimiter remaining x prefix (2 :: tail) Hleft).
  reflexivity.
Qed.

Lemma q4_match_one_to_y :
  forall marked x remaining prefix tail,
    Forall q4_pass marked ->
    rev marked = x :: remaining ->
    Forall dispatch_left_symbol (x :: remaining) ->
    run (S (length marked) + S (length remaining))
      (entry_config 4 (5 :: prefix) (marked ++ 1 :: tail)) =
    entry_config 1 (5 :: prefix)
      (rev (x :: remaining) ++ 3 :: tail).
Proof.
  intros marked x remaining prefix tail Hmarked Hrev Hleft.
  rewrite (dispatch_run_add (S (length marked)) (S (length remaining))
    (entry_config 4 (5 :: prefix) (marked ++ 1 :: tail))).
  rewrite (q4_scan_one marked (5 :: prefix) tail Hmarked).
  rewrite Hrev.
  cbn [cfg_ml].
  rewrite (dispatch_left_to_delimiter remaining x prefix (3 :: tail) Hleft).
  reflexivity.
Qed.

Print Assumptions q0_match_zero_to_y.
Print Assumptions q4_match_one_to_y.
