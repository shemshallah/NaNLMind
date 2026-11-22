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

Definition q1_pass (s : nat) : Prop := s = 0 \/ s = 1 \/ s = 6 \/ s = 7.

Lemma q1_pass_step :
  forall s left right,
    q1_pass s ->
    step (entry_config 1 left (s :: right)) =
    entry_config 1 (s :: left) right.
Proof.
  intros s left right [-> | [-> | [-> | ->]]]; reflexivity.
Qed.

(** q1 skips already-read 0/1 cells and stable 6/7 tags, then picks the
    next A/B, or X. *)
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

(** The binary prefix skipped by q1 can also be crossed in reverse by
    q2.  Unlike the previous matched-bit lemmas, the prefix need not be
    empty.  The scan returns to the SAME Y delimiter, so it cannot be
    mistaken for an instruction dispatch on a different source row. *)
Lemma q1_pass_rev_left :
  forall pass,
    Forall q1_pass pass ->
    Forall dispatch_left_symbol (rev pass).
Proof.
  induction pass as [|p rest IH]; intro Hpass.
  - constructor.
  - inversion Hpass as [|? ? Hp Hrest]; subst.
    simpl [rev].
    apply Forall_app; split.
    + apply IH; exact Hrest.
    + constructor.
      * destruct Hp as [-> | [-> | [-> | ->]]]; unfold dispatch_left_symbol; auto 12.
      * constructor.
Qed.

(** A selected marked zero compares against a zero and comes back to
    q1/Y in exactly 2*|pass|+4 concrete table steps.  The marked 2 is
    changed to 0 by q1, and the matching 0 is changed to 2 by q0;
    every other cell and the outer tape are preserved. *)
Theorem q1_zero_match_roundtrip :
  forall pass prefix tail,
    Forall q1_pass pass ->
    run (2 * length pass + 4)
      (entry_config 1 (5 :: prefix) (pass ++ 2 :: 0 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 0 :: 2 :: tail).
Proof.
  intros pass prefix tail Hpass.
  assert (Hhead : 2 = 2 \/ 2 = 3 \/ 2 = 4) by auto.
  assert (Hleft : Forall dispatch_left_symbol (0 :: rev pass)).
  { constructor.
    - unfold dispatch_left_symbol; auto.
    - apply q1_pass_rev_left; exact Hpass. }
  replace (2 * length pass + 4) with
    (S (length pass) + (1 + S (length (0 :: rev pass))))
    by (simpl [length]; rewrite rev_length; lia).
  rewrite (dispatch_run_add (S (length pass))
    (1 + S (length (0 :: rev pass)))
    (entry_config 1 (5 :: prefix) (pass ++ 2 :: 0 :: tail))).
  rewrite (q1_scan_pick pass (5 :: prefix) 2 (0 :: tail) Hpass Hhead).
  rewrite (dispatch_run_add 1 (S (length (0 :: rev pass)))
    (entry_config 0 (0 :: rev pass ++ 5 :: prefix) (0 :: tail))).
  change (run 1 (entry_config 0 (0 :: rev pass ++ 5 :: prefix)
    (0 :: tail))) with
    (entry_config 2 (rev pass ++ 5 :: prefix) (0 :: 2 :: tail)).
  rewrite (dispatch_left_to_delimiter (rev pass) 0 prefix (2 :: tail) Hleft).
  simpl [rev].
  rewrite rev_involutive.
  rewrite (append_singleton_assoc pass 0 (2 :: tail)).
  reflexivity.
Qed.

(** The dual marked-one case has the same exact clock.  Both directions
    are executable consequences of the frozen 23x8 table, not axioms
    about the abstract source interpreter. *)
Theorem q1_one_match_roundtrip :
  forall pass prefix tail,
    Forall q1_pass pass ->
    run (2 * length pass + 4)
      (entry_config 1 (5 :: prefix) (pass ++ 3 :: 1 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 1 :: 3 :: tail).
Proof.
  intros pass prefix tail Hpass.
  assert (Hhead : 3 = 2 \/ 3 = 3 \/ 3 = 4) by auto.
  assert (Hleft : Forall dispatch_left_symbol (1 :: rev pass)).
  { constructor.
    - unfold dispatch_left_symbol; auto.
    - apply q1_pass_rev_left; exact Hpass. }
  replace (2 * length pass + 4) with
    (S (length pass) + (1 + S (length (1 :: rev pass))))
    by (simpl [length]; rewrite rev_length; lia).
  rewrite (dispatch_run_add (S (length pass))
    (1 + S (length (1 :: rev pass)))
    (entry_config 1 (5 :: prefix) (pass ++ 3 :: 1 :: tail))).
  rewrite (q1_scan_pick pass (5 :: prefix) 3 (1 :: tail) Hpass Hhead).
  rewrite (dispatch_run_add 1 (S (length (1 :: rev pass)))
    (entry_config 4 (1 :: rev pass ++ 5 :: prefix) (1 :: tail))).
  change (run 1 (entry_config 4 (1 :: rev pass ++ 5 :: prefix)
    (1 :: tail))) with
    (entry_config 2 (rev pass ++ 5 :: prefix) (1 :: 3 :: tail)).
  rewrite (dispatch_left_to_delimiter (rev pass) 1 prefix (3 :: tail) Hleft).
  simpl [rev].
  rewrite rev_involutive.
  rewrite (append_singleton_assoc pass 1 (3 :: tail)).
  reflexivity.
Qed.

Print Assumptions q1_pass_rev_left.
Print Assumptions q1_zero_match_roundtrip.
Print Assumptions q1_one_match_roundtrip.

(** Once a comparison has consumed a bit, the corresponding data cell is
    marked A/B (2/3).  Both q0 and q4 can scan a whole block of these
    marks, and q2 can return left across them.  Restricting the block to
    A/B is essential: the broader q0_pass predicate also admits Y (5). *)
Definition comparison_mark (s : nat) : Prop := s = 2 \/ s = 3.

Lemma comparison_mark_scans :
  forall marks,
    Forall comparison_mark marks ->
    Forall q0_pass marks /\
    Forall q4_pass marks /\
    Forall dispatch_left_symbol (rev marks).
Proof.
  induction marks as [|m rest IH]; intros Hmarks.
  - repeat split; constructor.
  - inversion Hmarks as [|? ? Hm Hrest]; subst.
    destruct (IH Hrest) as [H0 [H4 Hleft]].
    repeat split.
    + constructor.
      * destruct Hm as [-> | ->]; unfold q0_pass; auto.
      * exact H0.
    + constructor.
      * destruct Hm as [-> | ->]; unfold q4_pass; auto.
      * exact H4.
    + simpl [rev].
      apply Forall_app; split.
      * exact Hleft.
      * constructor.
        -- destruct Hm as [-> | ->]; unfold dispatch_left_symbol; auto.
        -- constructor.
Qed.

(** These two concrete one-round macros permit an arbitrarily long block
    of previously marked bits between the selected A/B and the next raw
    input bit.  Both tapes and exact transition counts are quantified. *)
Theorem q1_zero_match_with_marks :
  forall pass marks prefix tail,
    Forall q1_pass pass ->
    Forall comparison_mark marks ->
    run (2 * length pass + 2 * length marks + 4)
      (entry_config 1 (5 :: prefix) (pass ++ 2 :: marks ++ 0 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 0 :: marks ++ 2 :: tail).
Proof.
  intros pass marks prefix tail Hpass Hmarks.
  destruct (comparison_mark_scans marks Hmarks) as [Hq0 [_ Hrevleft]].
  assert (Hleft : Forall dispatch_left_symbol (rev marks ++ 0 :: rev pass)).
  { apply Forall_app; split.
    - exact Hrevleft.
    - constructor.
      + unfold dispatch_left_symbol; auto.
      + apply q1_pass_rev_left; exact Hpass. }
  assert (Hsplit : exists x remaining,
    rev marks ++ 0 :: rev pass = x :: remaining).
  { destruct (rev marks) as [|x xs].
    - exists 0, (rev pass); reflexivity.
    - exists x, (xs ++ 0 :: rev pass); reflexivity. }
  destruct Hsplit as [x [remaining Hsplit]].
  rewrite Hsplit in Hleft.
  replace (2 * length pass + 2 * length marks + 4) with
    (S (length pass) + (S (length marks) + S (length (x :: remaining)))).
  2:{ rewrite <- Hsplit.
      rewrite app_length, rev_length.
      simpl [length].
      rewrite rev_length; lia. }
  rewrite (dispatch_run_add (S (length pass))
    (S (length marks) + S (length (x :: remaining)))
    (entry_config 1 (5 :: prefix) (pass ++ 2 :: marks ++ 0 :: tail))).
  rewrite (q1_scan_pick pass (5 :: prefix) 2 (marks ++ 0 :: tail)
    Hpass (or_introl eq_refl)).
  change (run (S (length marks) + S (length (x :: remaining)))
    (entry_config 0 ((0 :: rev pass) ++ 5 :: prefix)
      (marks ++ 0 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 0 :: marks ++ 2 :: tail)).
  transitivity (entry_config 1 (5 :: prefix)
    (rev (x :: remaining) ++ 2 :: tail)).
  - exact (q0_match_zero_to_y marks (0 :: rev pass) x remaining prefix tail
      Hq0 Hsplit Hleft).
  - rewrite <- Hsplit.
    rewrite rev_app_distr.
    simpl [rev].
    rewrite !rev_involutive.
    rewrite (append_singleton_assoc pass 0 marks).
    rewrite <- app_assoc.
    reflexivity.
Qed.

Theorem q1_one_match_with_marks :
  forall pass marks prefix tail,
    Forall q1_pass pass ->
    Forall comparison_mark marks ->
    run (2 * length pass + 2 * length marks + 4)
      (entry_config 1 (5 :: prefix) (pass ++ 3 :: marks ++ 1 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 1 :: marks ++ 3 :: tail).
Proof.
  intros pass marks prefix tail Hpass Hmarks.
  destruct (comparison_mark_scans marks Hmarks) as [_ [Hq4 Hrevleft]].
  assert (Hleft : Forall dispatch_left_symbol (rev marks ++ 1 :: rev pass)).
  { apply Forall_app; split.
    - exact Hrevleft.
    - constructor.
      + unfold dispatch_left_symbol; auto.
      + apply q1_pass_rev_left; exact Hpass. }
  assert (Hsplit : exists x remaining,
    rev marks ++ 1 :: rev pass = x :: remaining).
  { destruct (rev marks) as [|x xs].
    - exists 1, (rev pass); reflexivity.
    - exists x, (xs ++ 1 :: rev pass); reflexivity. }
  destruct Hsplit as [x [remaining Hsplit]].
  rewrite Hsplit in Hleft.
  replace (2 * length pass + 2 * length marks + 4) with
    (S (length pass) + (S (length marks) + S (length (x :: remaining)))).
  2:{ rewrite <- Hsplit.
      rewrite app_length, rev_length.
      simpl [length].
      rewrite rev_length; lia. }
  rewrite (dispatch_run_add (S (length pass))
    (S (length marks) + S (length (x :: remaining)))
    (entry_config 1 (5 :: prefix) (pass ++ 3 :: marks ++ 1 :: tail))).
  rewrite (q1_scan_pick pass (5 :: prefix) 3 (marks ++ 1 :: tail)
    Hpass (or_intror (or_introl eq_refl))).
  change (run (S (length marks) + S (length (x :: remaining)))
    (entry_config 4 ((1 :: rev pass) ++ 5 :: prefix)
      (marks ++ 1 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 1 :: marks ++ 3 :: tail)).
  transitivity (entry_config 1 (5 :: prefix)
    (rev (x :: remaining) ++ 3 :: tail)).
  - exact (q4_match_one_to_y marks (1 :: rev pass) x remaining prefix tail
      Hq4 Hsplit Hleft).
  - rewrite <- Hsplit.
    rewrite rev_app_distr.
    simpl [rev].
    rewrite !rev_involutive.
    rewrite (append_singleton_assoc pass 1 marks).
    rewrite <- app_assoc.
    reflexivity.
Qed.

Print Assumptions comparison_mark_scans.
Print Assumptions q1_zero_match_with_marks.
Print Assumptions q1_one_match_with_marks.

(** In the comparison phase, every selected A/B moves into the binary
    q1-pass prefix, while its matching raw input becomes the last A/B.
    This is an actual repeated execution of the same fixed native table;
    [done] contains marks produced by earlier successful comparisons. *)
Definition match_mark (b : bool) : nat := if b then 3 else 2.
Definition match_raw (b : bool) : nat := if b then 1 else 0.

Lemma match_mark_valid :
  forall bits, Forall comparison_mark (map match_mark bits).
Proof.
  induction bits as [|b rest IH]; simpl [map].
  - constructor.
  - constructor.
    + destruct b; unfold comparison_mark, match_mark; auto.
    + exact IH.
Qed.

Lemma match_raw_valid :
  forall bits, Forall q1_pass (map match_raw bits).
Proof.
  induction bits as [|b rest IH]; simpl [map].
  - constructor.
  - constructor.
    + destruct b; unfold q1_pass, match_raw; auto.
    + exact IH.
Qed.

Lemma q1_match_one_bit_with_marks :
  forall b pass marks prefix tail,
    Forall q1_pass pass ->
    Forall comparison_mark marks ->
    run (2 * length pass + 2 * length marks + 4)
      (entry_config 1 (5 :: prefix)
        (pass ++ match_mark b :: marks ++ match_raw b :: tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ match_raw b :: marks ++ match_mark b :: tail).
Proof.
  intros [|] pass marks prefix tail Hpass Hmarks; simpl [match_mark match_raw].
  - apply q1_one_match_with_marks; assumption.
  - apply q1_zero_match_with_marks; assumption.
Qed.

Fixpoint matched_comparison_steps
    (remaining : list bool) (pass_length done_length : nat) : nat :=
  match remaining with
  | [] => 0
  | _ :: rest =>
      (2 * pass_length + 2 * (length rest + done_length) + 4) +
      matched_comparison_steps rest (S pass_length) (S done_length)
  end.

Theorem q1_all_matching_bits :
  forall bits pass done prefix tail,
    Forall q1_pass pass ->
    Forall comparison_mark done ->
    run (matched_comparison_steps bits (length pass) (length done))
      (entry_config 1 (5 :: prefix)
        (pass ++ map match_mark bits ++ done ++ map match_raw bits ++ tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ map match_raw bits ++ done ++ map match_mark bits ++ tail).
Proof.
  induction bits as [|b rest IH]; intros pass done prefix tail Hpass Hdone.
  - reflexivity.
  - simpl [matched_comparison_steps map].
    assert (Hmarks : Forall comparison_mark (map match_mark rest ++ done)).
    { apply Forall_app; split.
      - apply match_mark_valid.
      - exact Hdone. }
    assert (Hpass' : Forall q1_pass (pass ++ [match_raw b])).
    { apply Forall_app; split.
      - exact Hpass.
      - constructor.
        + destruct b; unfold q1_pass, match_raw; auto.
        + constructor. }
    assert (Hdone' : Forall comparison_mark (done ++ [match_mark b])).
    { apply Forall_app; split.
      - exact Hdone.
      - constructor.
        + destruct b; unfold comparison_mark, match_mark; auto.
        + constructor. }
    rewrite dispatch_run_add.
    replace (length rest + length done) with
      (length (map match_mark rest ++ done))
      by (rewrite app_length, map_length; lia).
    replace
      (pass ++ match_mark b :: map match_mark rest ++ done ++
       match_raw b :: map match_raw rest ++ tail) with
      (pass ++ match_mark b :: (map match_mark rest ++ done) ++
       match_raw b :: (map match_raw rest ++ tail))
      by (repeat rewrite <- app_assoc; reflexivity).
    change
      (run (matched_comparison_steps rest (S (length pass)) (S (length done)))
        (run (2 * length pass +
              2 * length (map match_mark rest ++ done) + 4)
          (entry_config 1 (5 :: prefix)
            (pass ++ match_mark b :: (map match_mark rest ++ done) ++
             match_raw b :: (map match_raw rest ++ tail)))) =
       entry_config 1 (5 :: prefix)
         (pass ++ match_raw b :: map match_raw rest ++
          done ++ match_mark b :: map match_mark rest ++ tail)).
    rewrite (q1_match_one_bit_with_marks b pass
      (map match_mark rest ++ done) prefix (map match_raw rest ++ tail)
      Hpass Hmarks).
    replace
      (pass ++ match_raw b :: (map match_mark rest ++ done) ++
       match_mark b :: (map match_raw rest ++ tail)) with
      ((pass ++ [match_raw b]) ++ map match_mark rest ++
       (done ++ [match_mark b]) ++ map match_raw rest ++ tail)
      by (repeat rewrite <- app_assoc; cbn [app]; reflexivity).
    replace (S (length pass)) with (length (pass ++ [match_raw b]))
      by (rewrite app_length; simpl; lia).
    replace (S (length done)) with (length (done ++ [match_mark b]))
      by (rewrite app_length; simpl; lia).
    rewrite (IH (pass ++ [match_raw b]) (done ++ [match_mark b])
      prefix tail Hpass' Hdone').
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity.
Qed.

Lemma matched_comparison_steps_closed :
  forall bits pass_length done_length,
    matched_comparison_steps bits pass_length done_length =
    2 * length bits * pass_length +
    3 * length bits * length bits +
    (2 * done_length + 1) * length bits.
Proof.
  induction bits as [|b rest IH]; intros pass_length done_length.
  - simpl [matched_comparison_steps length]. nia.
  - simpl [matched_comparison_steps length].
    rewrite (IH (S pass_length) (S done_length)).
    nia.
Qed.

Corollary q1_all_matching_bits_exact_clock :
  forall bits pass prefix tail,
    Forall q1_pass pass ->
    run (2 * length bits * length pass +
         3 * length bits * length bits + length bits)
      (entry_config 1 (5 :: prefix)
        (pass ++ map match_mark bits ++ map match_raw bits ++ tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ map match_raw bits ++ map match_mark bits ++ tail).
Proof.
  intros bits pass prefix tail Hpass.
  replace (2 * length bits * length pass +
           3 * length bits * length bits + length bits) with
    (matched_comparison_steps bits (length pass) 0).
  2:{ rewrite matched_comparison_steps_closed.
      cbn [Nat.add Nat.mul].
      repeat rewrite Nat.add_0_r.
      reflexivity. }
  change (run (matched_comparison_steps bits (length pass) 0)
    (entry_config 1 (5 :: prefix)
      (pass ++ map match_mark bits ++ [] ++ map match_raw bits ++ tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ map match_raw bits ++ [] ++ map match_mark bits ++ tail)).
  apply (q1_all_matching_bits bits pass [] prefix tail Hpass).
  constructor.
Qed.

Print Assumptions q1_match_one_bit_with_marks.
Print Assumptions q1_all_matching_bits.
Print Assumptions q1_all_matching_bits_exact_clock.

(** A failed bit comparison is also compositional from q1/Y: q1 first
    skips an arbitrary finite binary prefix and selects A/B, q0/q4
    detects the opposite raw bit, q3 reaches X, and q5 returns to Y.
    The q5 scan invariant explicitly excludes intervening Y delimiters.
    We do not assume that the resulting tape is a next-instruction state;
    that stronger restart invariant remains a separate obligation. *)
Theorem q1_zero_mismatch_restart :
  forall pass marked row_rest s remaining prefix afterX,
    Forall q1_pass pass ->
    Forall q0_pass marked ->
    Forall dispatch_right_symbol row_rest ->
    rev row_rest ++ 3 :: rev marked ++ 0 :: rev pass ++ 5 :: prefix =
      s :: remaining ++ 5 :: prefix ->
    Forall q5_pass (s :: remaining) ->
    run (S (length pass) +
         (S (length marked) +
           ((length row_rest + 1) + S (length (s :: remaining)))))
      (entry_config 1 (5 :: prefix)
        (pass ++ 2 :: marked ++ 1 :: row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ 4 :: afterX).
Proof.
  intros pass marked row_rest s remaining prefix afterX
    Hpass Hmarked Hright Hsplit Hq5.
  rewrite (dispatch_run_add (S (length pass))
    (S (length marked) +
      ((length row_rest + 1) + S (length (s :: remaining))))
    (entry_config 1 (5 :: prefix)
      (pass ++ 2 :: marked ++ 1 :: row_rest ++ 4 :: afterX))).
  rewrite (q1_scan_pick pass (5 :: prefix) 2
    (marked ++ 1 :: row_rest ++ 4 :: afterX)
    Hpass (or_introl eq_refl)).
  apply (q0_mismatch_restart marked row_rest (0 :: rev pass)
    s remaining prefix afterX); assumption.
Qed.

Theorem q1_one_mismatch_restart :
  forall pass marked row_rest s remaining prefix afterX,
    Forall q1_pass pass ->
    Forall q4_pass marked ->
    Forall dispatch_right_symbol row_rest ->
    rev row_rest ++ 2 :: rev marked ++ 1 :: rev pass ++ 5 :: prefix =
      s :: remaining ++ 5 :: prefix ->
    Forall q5_pass (s :: remaining) ->
    run (S (length pass) +
         (S (length marked) +
           ((length row_rest + 1) + S (length (s :: remaining)))))
      (entry_config 1 (5 :: prefix)
        (pass ++ 3 :: marked ++ 0 :: row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ 4 :: afterX).
Proof.
  intros pass marked row_rest s remaining prefix afterX
    Hpass Hmarked Hright Hsplit Hq5.
  rewrite (dispatch_run_add (S (length pass))
    (S (length marked) +
      ((length row_rest + 1) + S (length (s :: remaining))))
    (entry_config 1 (5 :: prefix)
      (pass ++ 3 :: marked ++ 0 :: row_rest ++ 4 :: afterX))).
  rewrite (q1_scan_pick pass (5 :: prefix) 3
    (marked ++ 0 :: row_rest ++ 4 :: afterX)
    Hpass (or_intror (or_introl eq_refl))).
  apply (q4_mismatch_restart marked row_rest (1 :: rev pass)
    s remaining prefix afterX); assumption.
Qed.

Print Assumptions q1_zero_mismatch_restart.
Print Assumptions q1_one_mismatch_restart.

(** A complete first-failed-bit comparison: any finite successful prefix
    can precede the mismatching marked bit.  The unsuccessful bit is the
    opposite raw bit, and the q3/q5 cleanup is the literal table run.
    This is a single native-table episode, not yet a source instruction.

    The rightward scan and its Y-free cleanup region are explicit: they
    prevent an accidental crossing of an instruction delimiter. *)
Theorem q1_matching_prefix_then_first_mismatch :
  forall bits bad pass row_rest s remaining prefix afterX,
    Forall q1_pass pass ->
    Forall dispatch_right_symbol row_rest ->
    rev row_rest ++ match_mark (negb bad) ::
      rev (map match_mark bits) ++ match_raw bad ::
      rev (pass ++ map match_raw bits) ++ 5 :: prefix =
      s :: remaining ++ 5 :: prefix ->
    Forall q5_pass (s :: remaining) ->
    run
      (matched_comparison_steps bits (length pass) 1 +
       (S (length (pass ++ map match_raw bits)) +
        (S (length (map match_mark bits)) +
         ((length row_rest + 1) + S (length (s :: remaining))))))
      (entry_config 1 (5 :: prefix)
        (pass ++ map match_mark bits ++ [match_mark bad] ++
         map match_raw bits ++
         match_raw (negb bad) :: row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ 4 :: afterX).
Proof.
  intros bits bad pass row_rest s remaining prefix afterX
    Hpass Hright Hsplit Hq5.
  assert (Hdone : Forall comparison_mark [match_mark bad]).
  { constructor.
    - destruct bad; unfold comparison_mark, match_mark; auto.
    - constructor. }
  assert (Hpass' : Forall q1_pass (pass ++ map match_raw bits)).
  { apply Forall_app; split.
    - exact Hpass.
    - apply match_raw_valid. }
  assert (Hmarks : Forall comparison_mark (map match_mark bits)).
  { apply match_mark_valid. }
  destruct (comparison_mark_scans (map match_mark bits) Hmarks)
    as [Hq0 [Hq4 _]].
  rewrite dispatch_run_add.
  replace (matched_comparison_steps bits (length pass) 1) with
    (matched_comparison_steps bits (length pass)
      (length [match_mark bad])) by reflexivity.
  rewrite (q1_all_matching_bits bits pass [match_mark bad] prefix
    (match_raw (negb bad) :: row_rest ++ 4 :: afterX)
    Hpass Hdone).
  replace
    (pass ++ map match_raw bits ++ [match_mark bad] ++
      map match_mark bits ++
      match_raw (negb bad) :: row_rest ++ 4 :: afterX)
    with
    ((pass ++ map match_raw bits) ++
      match_mark bad :: map match_mark bits ++
      match_raw (negb bad) :: row_rest ++ 4 :: afterX)
    by (repeat rewrite <- app_assoc; reflexivity).
  destruct bad; simpl [match_mark match_raw negb] in *.
  - apply (q1_one_mismatch_restart
      (pass ++ map match_raw bits) (map match_mark bits)
      row_rest s remaining prefix afterX); assumption.
  - apply (q1_zero_mismatch_restart
      (pass ++ map match_raw bits) (map match_mark bits)
      row_rest s remaining prefix afterX); assumption.
Qed.

Print Assumptions q1_matching_prefix_then_first_mismatch.

(** For a canonical comparison layout the cleanup guard is automatic.
    All cells crossed by q3 and q5 are in their permitted symbol classes;
    the only Y is the delimiter to which q5 must return. *)
Lemma q5_pass_reverse :
  forall cells,
    Forall q5_pass cells -> Forall q5_pass (rev cells).
Proof.
  intros cells Hcells.
  induction Hcells as [|s rest Hs Hrest IH]; simpl.
  - constructor.
  - apply Forall_app; split.
    + exact IH.
    + constructor; [exact Hs | constructor].
Qed.

Lemma q5_pass_from_q1 :
  forall cells, Forall q1_pass cells -> Forall q5_pass cells.
Proof.
  intros cells Hcells.
  induction Hcells as [|s rest Hs Hrest IH].
  - constructor.
  - constructor.
    + destruct Hs as [-> | [-> | [-> | ->]]]; unfold q5_pass; auto 12.
    + exact IH.
Qed.

Lemma q5_pass_from_right :
  forall cells,
    Forall dispatch_right_symbol cells -> Forall q5_pass cells.
Proof.
  intros cells Hcells.
  induction Hcells as [|s rest Hs Hrest IH].
  - constructor.
  - constructor.
    + destruct Hs as [-> | [-> | [-> | [-> | [-> | ->]]]]];
        unfold q5_pass; auto 10.
    + exact IH.
Qed.

Lemma q5_match_mark : forall b, q5_pass (match_mark b).
Proof. intros []; unfold q5_pass, match_mark; auto. Qed.

Lemma q5_match_raw : forall b, q5_pass (match_raw b).
Proof. intros []; unfold q5_pass, match_raw; auto. Qed.

Lemma q5_marked_bits :
  forall bits, Forall q5_pass (map match_mark bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor; [apply q5_match_mark | exact IH].
Qed.

Lemma q5_raw_bits :
  forall bits, Forall q5_pass (map match_raw bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor; [apply q5_match_raw | exact IH].
Qed.

Lemma q5_first_mismatch_segment_valid :
  forall bits bad pass row_rest,
    Forall q1_pass pass ->
    Forall dispatch_right_symbol row_rest ->
    Forall q5_pass
      (rev row_rest ++ match_mark (negb bad) ::
       rev (map match_mark bits) ++ match_raw bad ::
       rev (pass ++ map match_raw bits)).
Proof.
  intros bits bad pass row_rest Hpass Hright.
  apply Forall_app; split.
  - apply q5_pass_reverse, q5_pass_from_right; exact Hright.
  - constructor.
    + apply q5_match_mark.
    + apply Forall_app; split.
      * apply q5_pass_reverse, q5_marked_bits.
      * constructor.
        -- apply q5_match_raw.
        -- apply q5_pass_reverse.
           apply Forall_app; split.
           ++ apply q5_pass_from_q1; exact Hpass.
           ++ apply q5_raw_bits.
Qed.

(** Keep the delimiter frame intact when two marked cells interrupt the
    rightward list.  The nested cons/append form is proved structurally
    so the concrete cleanup split does not depend on rewrite heuristics. *)
Lemma append_frame_two_marks :
  forall (a b c suffix : list nat) x y,
    (a ++ x :: b ++ y :: c) ++ suffix =
    a ++ x :: b ++ y :: c ++ suffix.
Proof.
  induction a as [|ah a_rest IH]; intros b c suffix x y.
  - simpl [app].
    f_equal.
    induction b as [|bh bt IHb].
    + reflexivity.
    + simpl [app]. f_equal. exact IHb.
  - simpl [app]. f_equal. apply IH.
Qed.

Theorem q1_first_mismatch_canonical_layout :
  forall bits bad pass row_rest prefix afterX,
    Forall q1_pass pass ->
    Forall dispatch_right_symbol row_rest ->
    let scanned :=
      rev row_rest ++ match_mark (negb bad) ::
      rev (map match_mark bits) ++ match_raw bad ::
      rev (pass ++ map match_raw bits) in
    run
      (matched_comparison_steps bits (length pass) 1 +
       (S (length (pass ++ map match_raw bits)) +
        (S (length (map match_mark bits)) +
         ((length row_rest + 1) + S (length scanned)))))
      (entry_config 1 (5 :: prefix)
        (pass ++ map match_mark bits ++ [match_mark bad] ++
         map match_raw bits ++
         match_raw (negb bad) :: row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev scanned) ++ 4 :: afterX).
Proof.
  intros bits bad pass row_rest prefix afterX Hpass Hright.
  cbn zeta.
  set (scanned := rev row_rest ++ match_mark (negb bad) ::
    rev (map match_mark bits) ++ match_raw bad ::
    rev (pass ++ map match_raw bits)).
  assert (Hq5 : Forall q5_pass scanned).
  { unfold scanned.
    apply q5_first_mismatch_segment_valid; assumption. }
  assert (Hnonempty : exists s remaining, scanned = s :: remaining).
  { unfold scanned.
    destruct (rev row_rest) as [|s rest].
    - exists (match_mark (negb bad)).
      exists (rev (map match_mark bits) ++
        match_raw bad :: rev (pass ++ map match_raw bits)).
      reflexivity.
    - exists s.
      exists (rest ++ match_mark (negb bad) ::
        rev (map match_mark bits) ++
        match_raw bad :: rev (pass ++ map match_raw bits)).
      reflexivity. }
  destruct Hnonempty as [s [remaining Hshape]].
  rewrite Hshape in Hq5.
  rewrite Hshape.
  eapply q1_matching_prefix_then_first_mismatch.
  - exact Hpass.
  - exact Hright.
  - change
      (rev row_rest ++ match_mark (negb bad) ::
        rev (map match_mark bits) ++ match_raw bad ::
        rev (pass ++ map match_raw bits) ++ 5 :: prefix =
       (s :: remaining) ++ 5 :: prefix).
    rewrite <- Hshape.
    unfold scanned.
    symmetry.
    apply append_frame_two_marks.
  - exact Hq5.
Qed.

Print Assumptions q5_first_mismatch_segment_valid.
Print Assumptions q1_first_mismatch_canonical_layout.

(** The first failed comparison is quadratic only in the length of the
    preceding successful prefix; the rightward row scan contributes
    linearly.  The extra 7n accounts for keeping the failed marker among
    already processed matching bits and for the final cleanup pass. *)
Lemma first_mismatch_clock_polynomial :
  forall bits bad pass row_rest,
    matched_comparison_steps bits (length pass) 1 +
      (S (length (pass ++ map match_raw bits)) +
       (S (length (map match_mark bits)) +
        ((length row_rest + 1) +
         S (length
           (rev row_rest ++ match_mark (negb bad) ::
            rev (map match_mark bits) ++ match_raw bad ::
            rev (pass ++ map match_raw bits)))))) =
    3 * length bits * length bits +
      2 * length bits * length pass +
      7 * length bits + 2 * length pass +
      2 * length row_rest + 6.
Proof.
  intros bits bad pass row_rest.
  rewrite matched_comparison_steps_closed.
  repeat first [rewrite app_length | rewrite rev_length |
                rewrite map_length | progress (simpl [length])].
  nia.
Qed.

Corollary q1_first_mismatch_exact_clock :
  forall bits bad pass row_rest prefix afterX,
    Forall q1_pass pass ->
    Forall dispatch_right_symbol row_rest ->
    run
      (3 * length bits * length bits +
       2 * length bits * length pass +
       7 * length bits + 2 * length pass +
       2 * length row_rest + 6)
      (entry_config 1 (5 :: prefix)
        (pass ++ map match_mark bits ++ [match_mark bad] ++
         map match_raw bits ++
         match_raw (negb bad) :: row_rest ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite
        (rev
          (rev row_rest ++ match_mark (negb bad) ::
           rev (map match_mark bits) ++ match_raw bad ::
           rev (pass ++ map match_raw bits))) ++ 4 :: afterX).
Proof.
  intros bits bad pass row_rest prefix afterX Hpass Hright.
  pose proof (q1_first_mismatch_canonical_layout
    bits bad pass row_rest prefix afterX Hpass Hright) as Hrun.
  cbn zeta in Hrun.
  rewrite first_mismatch_clock_polynomial in Hrun.
  exact Hrun.
Qed.

Print Assumptions first_mismatch_clock_polynomial.
Print Assumptions q1_first_mismatch_exact_clock.
