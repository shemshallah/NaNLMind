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
  forall marked left_pre x remaining prefix tail,
    Forall q0_pass marked ->
    rev marked ++ left_pre = x :: remaining ->
    Forall dispatch_left_symbol (x :: remaining) ->
    run (S (length marked) + S (length (x :: remaining)))
      (entry_config 0 (left_pre ++ 5 :: prefix) (marked ++ 0 :: tail)) =
    entry_config 1 (5 :: prefix)
      (rev (x :: remaining) ++ 2 :: tail).
Proof.
  intros marked left_pre x remaining prefix tail Hmarked Hrev Hleft.
  rewrite (dispatch_run_add (S (length marked)) (S (length (x :: remaining)))
    (entry_config 0 (left_pre ++ 5 :: prefix) (marked ++ 0 :: tail))).
  rewrite (q0_scan_zero marked (left_pre ++ 5 :: prefix) tail Hmarked).
  rewrite app_assoc.
  rewrite Hrev.
  cbn [app].
  cbn [cfg_ml].
  rewrite (dispatch_left_to_delimiter remaining x prefix (2 :: tail) Hleft).
  reflexivity.
Qed.

Lemma q4_match_one_to_y :
  forall marked left_pre x remaining prefix tail,
    Forall q4_pass marked ->
    rev marked ++ left_pre = x :: remaining ->
    Forall dispatch_left_symbol (x :: remaining) ->
    run (S (length marked) + S (length (x :: remaining)))
      (entry_config 4 (left_pre ++ 5 :: prefix) (marked ++ 1 :: tail)) =
    entry_config 1 (5 :: prefix)
      (rev (x :: remaining) ++ 3 :: tail).
Proof.
  intros marked left_pre x remaining prefix tail Hmarked Hrev Hleft.
  rewrite (dispatch_run_add (S (length marked)) (S (length (x :: remaining)))
    (entry_config 4 (left_pre ++ 5 :: prefix) (marked ++ 1 :: tail))).
  rewrite (q4_scan_one marked (left_pre ++ 5 :: prefix) tail Hmarked).
  rewrite app_assoc.
  rewrite Hrev.
  cbn [app].
  cbn [cfg_ml].
  rewrite (dispatch_left_to_delimiter remaining x prefix (3 :: tail) Hleft).
  reflexivity.
Qed.

Print Assumptions q0_match_zero_to_y.
Print Assumptions q4_match_one_to_y.

(** q5 is the general leftward cleanup scan: it rewrites 0/1 to A/B,
    leaves every other non-Y symbol alone, and leaves on Y into q1. *)
Definition q5_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 4 \/ s = 6 \/ s = 7.

Lemma q5_pass_step :
  forall s next left right,
    q5_pass s ->
    step (entry_config 5 (next :: left) (s :: right)) =
    entry_config 5 left (next :: entry_rewrite s :: right).
Proof.
  intros s next left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma q5_cross_delimiter :
  forall left right,
    step (entry_config 5 left (5 :: right)) =
    entry_config 1 (5 :: left) right.
Proof. reflexivity. Qed.

Theorem q5_scan_unbounded :
  forall remaining s prefix suffix,
    Forall q5_pass (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 5 (remaining ++ 5 :: prefix) (s :: suffix)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix Hscan.
  - inversion Hscan as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
        (entry_config 5 (next :: (rest ++ 5 :: prefix)) (s :: suffix)) =
      entry_config 1 (5 :: prefix)
        (map entry_rewrite (rev (s :: next :: rest)) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (q5_pass_step s next (rest ++ 5 :: prefix) suffix Hs).
    rewrite (IH next prefix (entry_rewrite s :: suffix) Hrest).
    cbn [rev].
    repeat rewrite map_app.
    cbn [map].
    rewrite (append_singleton_assoc
      (map entry_rewrite (rev rest) ++ [entry_rewrite next])
      (entry_rewrite s) suffix).
    rewrite (append_singleton_assoc
      (map entry_rewrite (rev rest))
      (entry_rewrite next)
      (entry_rewrite s :: suffix)).
    reflexivity.
Qed.

Print Assumptions q5_scan_unbounded.

(** A mismatch must traverse the entire intervening rightward segment
    before the literal q3 transition on X.  These are exact native-table
    execution statements, independent of the number of scanned cells. *)
Theorem q0_mismatch_one_reaches_x :
  forall marked left symbols suffix,
    Forall q0_pass marked ->
    Forall dispatch_right_symbol symbols ->
    run (S (length marked) + (length symbols + 1))
      (entry_config 0 left (marked ++ 1 :: symbols ++ 4 :: suffix)) =
    step (entry_config 3 (rev symbols ++ 3 :: rev marked ++ left)
      (4 :: suffix)).
Proof.
  intros marked left symbols suffix Hmarked Hsymbols.
  rewrite (dispatch_run_add (S (length marked)) (length symbols + 1)
    (entry_config 0 left (marked ++ 1 :: symbols ++ 4 :: suffix))).
  rewrite (q0_scan_one marked left (symbols ++ 4 :: suffix) Hmarked).
  apply dispatch_right_reaches_marker.
  exact Hsymbols.
Qed.

Theorem q4_mismatch_zero_reaches_x :
  forall marked left symbols suffix,
    Forall q4_pass marked ->
    Forall dispatch_right_symbol symbols ->
    run (S (length marked) + (length symbols + 1))
      (entry_config 4 left (marked ++ 0 :: symbols ++ 4 :: suffix)) =
    step (entry_config 3 (rev symbols ++ 2 :: rev marked ++ left)
      (4 :: suffix)).
Proof.
  intros marked left symbols suffix Hmarked Hsymbols.
  rewrite (dispatch_run_add (S (length marked)) (length symbols + 1)
    (entry_config 4 left (marked ++ 0 :: symbols ++ 4 :: suffix))).
  rewrite (q4_scan_zero marked left (symbols ++ 4 :: suffix) Hmarked).
  apply dispatch_right_reaches_marker.
  exact Hsymbols.
Qed.

(** On X the machine moves left into q5.  If the cells between that X
    and Y contain no earlier Y, q5's general scan restores control to
    q1 at exactly the first Y.  No source-interpreter premise is used. *)
Theorem q3_marker_cleanup_to_y :
  forall scanned prefix suffix,
    scanned <> [] ->
    Forall q5_pass scanned ->
    run (S (length scanned))
      (step (entry_config 3 (scanned ++ 5 :: prefix) (4 :: suffix))) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev scanned) ++ 4 :: suffix).
Proof.
  intros [|s remaining] prefix suffix Hnonempty Hscan.
  - exfalso. apply Hnonempty. reflexivity.
  - change (step (entry_config 3
        ((s :: remaining) ++ 5 :: prefix) (4 :: suffix))) with
      (entry_config 5 (remaining ++ 5 :: prefix) (s :: 4 :: suffix)).
    apply q5_scan_unbounded.
    exact Hscan.
Qed.

Print Assumptions q0_mismatch_one_reaches_x.
Print Assumptions q4_mismatch_zero_reaches_x.
Print Assumptions q3_marker_cleanup_to_y.
Lemma q3_at_marker_step :
  forall left suffix,
    step (entry_config 3 left (4 :: suffix)) =
    cfg_ml 5 left (4 :: suffix).
Proof. intros [|z zs] suffix; reflexivity. Qed.

(** Mismatch restart: q3 reaches X, the X transition enters q5, and the
    q5 cleanup scan returns to Y.  The split at the cell immediately
    before X is explicit. *)
Lemma q3_then_q5_to_y :
  forall mark row_rest marked left_pre s remaining prefix afterX,
    Forall dispatch_right_symbol row_rest ->
    rev row_rest ++ mark :: rev marked ++ left_pre ++ 5 :: prefix =
      s :: remaining ++ 5 :: prefix ->
    Forall q5_pass (s :: remaining) ->
    run ((length row_rest + 1) + S (length (s :: remaining)))
      (entry_config 3 (mark :: rev marked ++ left_pre ++ 5 :: prefix)
        (row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ 4 :: afterX).
Proof.
  intros mark row_rest marked left_pre s remaining prefix afterX
    Hright Hsplit Hq5.
  rewrite (dispatch_run_add (length row_rest + 1)
    (S (length (s :: remaining)))
    (entry_config 3 (mark :: rev marked ++ left_pre ++ 5 :: prefix)
      (row_rest ++ 4 :: afterX))).
  rewrite (dispatch_right_reaches_marker row_rest
    (mark :: rev marked ++ left_pre ++ 5 :: prefix) afterX Hright).
  rewrite q3_at_marker_step.
  rewrite Hsplit.
  cbn [cfg_ml app].
  rewrite (q5_scan_unbounded remaining s prefix (4 :: afterX) Hq5).
  reflexivity.
Qed.

Print Assumptions q3_at_marker_step.
Print Assumptions q3_then_q5_to_y.

Lemma q0_mismatch_restart :
  forall marked row_rest left_pre s remaining prefix afterX,
    Forall q0_pass marked ->
    Forall dispatch_right_symbol row_rest ->
    rev row_rest ++ 3 :: rev marked ++ left_pre ++ 5 :: prefix =
      s :: remaining ++ 5 :: prefix ->
    Forall q5_pass (s :: remaining) ->
    run (S (length marked) +
         ((length row_rest + 1) + S (length (s :: remaining))))
      (entry_config 0 (left_pre ++ 5 :: prefix)
        (marked ++ 1 :: row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ 4 :: afterX).
Proof.
  intros marked row_rest left_pre s remaining prefix afterX
    Hmarked Hright Hsplit Hq5.
  rewrite (dispatch_run_add (S (length marked))
    ((length row_rest + 1) + S (length (s :: remaining)))
    (entry_config 0 (left_pre ++ 5 :: prefix)
      (marked ++ 1 :: row_rest ++ 4 :: afterX))).
  rewrite (q0_scan_one marked (left_pre ++ 5 :: prefix)
    (row_rest ++ 4 :: afterX) Hmarked).
  apply (q3_then_q5_to_y 3 row_rest marked left_pre s remaining prefix afterX);
    assumption.
Qed.

Lemma q4_mismatch_restart :
  forall marked row_rest left_pre s remaining prefix afterX,
    Forall q4_pass marked ->
    Forall dispatch_right_symbol row_rest ->
    rev row_rest ++ 2 :: rev marked ++ left_pre ++ 5 :: prefix =
      s :: remaining ++ 5 :: prefix ->
    Forall q5_pass (s :: remaining) ->
    run (S (length marked) +
         ((length row_rest + 1) + S (length (s :: remaining))))
      (entry_config 4 (left_pre ++ 5 :: prefix)
        (marked ++ 0 :: row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ 4 :: afterX).
Proof.
  intros marked row_rest left_pre s remaining prefix afterX
    Hmarked Hright Hsplit Hq5.
  rewrite (dispatch_run_add (S (length marked))
    ((length row_rest + 1) + S (length (s :: remaining)))
    (entry_config 4 (left_pre ++ 5 :: prefix)
      (marked ++ 0 :: row_rest ++ 4 :: afterX))).
  rewrite (q4_scan_zero marked (left_pre ++ 5 :: prefix)
    (row_rest ++ 4 :: afterX) Hmarked).
  apply (q3_then_q5_to_y 2 row_rest marked left_pre s remaining prefix afterX);
    assumption.
Qed.

Print Assumptions q0_mismatch_restart.
Print Assumptions q4_mismatch_restart.

Definition q1_pass (s : nat) : Prop := s = 0 \/ s = 1.

Lemma q1_pass_step :
  forall s left right,
    q1_pass s ->
    step (entry_config 1 left (s :: right)) =
    entry_config 1 (s :: left) right.
Proof.
  intros s left right [-> | ->]; reflexivity.
Qed.

(** q1 skips already-read 0/1 cells and picks the next A/B, or X. *)
Lemma q1_scan_pick :
  forall pass left head rest,
    Forall q1_pass pass ->
    head = 2 \/ head = 3 \/ head = 4 ->
    run (S (length pass))
      (entry_config 1 left (pass ++ head :: rest)) =
    match head with
    | 2 => entry_config 0 (0 :: rev pass ++ left) rest
    | 3 => entry_config 4 (1 :: rev pass ++ left) rest
    | _ => entry_config 6 (4 :: rev pass ++ left) rest
    end.
Proof.
  induction pass as [|p pass IH]; intros left head rest Hpass Hhead.
  - destruct Hhead as [-> | [-> | ->]]; reflexivity.
  - inversion Hpass as [|? ? Hp Hrest]; subst.
    rewrite entry_run_successor.
    cbn [app length].
    rewrite (q1_pass_step p left (pass ++ head :: rest) Hp).
    rewrite (IH (p :: left) head rest Hrest Hhead).
    cbn [rev].
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity.
Qed.
