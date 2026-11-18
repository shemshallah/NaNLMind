(** * Canonical direction-bit capture

    After [canonical_q6_copy_all] the condition bits have all been moved
    left of Y and the corresponding next-state/write bits have been marked.
    The next raw record bit is the direction bit.  q6 captures it, q7/q8
    return to Y, and q9/q10 scan over the copied record marks to X=4,
    entering q12/q13.  The direction bit is then the 2/3 mark carried in
    the right-hand frame.

    This is still a macro phase, not a source-step theorem.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyConcreteDispatch
  MinskyActionMacro MinskyCanonicalMatch MinskyCanonicalCopy
  MinskyCanonicalCopyGeneral.

Lemma Forall_match_mark_q9 :
  forall bits,
    Forall q9_pass (map match_mark bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold q9_pass, match_mark; auto 10.
    + exact IH.
Qed.

Lemma q9_scan_marked_to_q12 :
  forall scanned left tail,
    Forall q9_pass scanned ->
    run (S (length scanned))
      (entry_config 9 left (scanned ++ 4 :: tail)) =
    cfg_ml 12 (rev scanned ++ left) (4 :: tail).
Proof.
  intros scanned.
  induction scanned as [|s rest IH]; intros left tail Hscan.
  - cbn [length rev app run].
    vm_compute.
    destruct left as [|x xs]; reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length rest)))
      (entry_config 9 left (s :: (rest ++ 4 :: tail))) =
      cfg_ml 12 (rev (s :: rest) ++ left) (4 :: tail)).
    rewrite entry_run_successor.
    rewrite (q9_pass_step s left (rest ++ 4 :: tail) Hs).
    rewrite (IH (s :: left) tail Hrest).
    cbn [rev].
    rewrite <- app_assoc.
    reflexivity.
Qed.

Lemma q10_scan_marked_to_q13 :
  forall scanned left tail,
    Forall q9_pass scanned ->
    run (S (length scanned))
      (entry_config 10 left (scanned ++ 4 :: tail)) =
    cfg_ml 13 (rev scanned ++ left) (4 :: tail).
Proof.
  intros scanned.
  induction scanned as [|s rest IH]; intros left tail Hscan.
  - cbn [length rev app run].
    vm_compute.
    destruct left as [|x xs]; reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length rest)))
      (entry_config 10 left (s :: (rest ++ 4 :: tail))) =
      cfg_ml 13 (rev (s :: rest) ++ left) (4 :: tail)).
    rewrite entry_run_successor.
    rewrite (q10_pass_step s left (rest ++ 4 :: tail) Hs).
    rewrite (IH (s :: left) tail Hrest).
    cbn [rev].
    rewrite <- app_assoc.
    reflexivity.
Qed.

Lemma q8_reversed_frame :
  forall record_marks marked x tail,
    ((record_marks ++ [4]) ++ marked) ++ x :: tail =
    record_marks ++ 4 :: marked ++ x :: tail.
Proof.
  intros record_marks marked x tail.
  rewrite (app_cons_singleton record_marks 4 (marked ++ x :: tail)).
  rewrite app_assoc.
  reflexivity.
Qed.

Theorem canonical_q6_direction_capture :
  forall marked record_marks record_tail tbuffer data (dir : bool),
    Forall q6_pass marked ->
    Forall q7_pass marked ->
    Forall q7_pass record_marks ->
    Forall q9_pass record_marks ->
    run (S (length marked) +
         (S (length (rev marked ++ [4] ++ rev record_marks)) +
          S (length record_marks)))
      (entry_config 6
        (4 :: rev record_marks ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (marked ++ source_bit dir :: record_tail)) =
    cfg_ml (if dir then 13 else 12)
      (rev record_marks ++ 5 :: rev tbuffer ++ 6 :: rev data)
      (4 :: marked ++ (if dir then 3 else 2) :: record_tail).
Proof.
  intros marked record_marks record_tail tbuffer data dir
    Hmarked6 Hmarked7 Hrec7 Hrec9.
  set (xs := rev marked ++ [4] ++ rev record_marks).
  assert (Hxs7 : Forall q7_pass xs).
  { unfold xs. rewrite Forall_app. split.
    - apply Forall_rev. exact Hmarked7.
    - rewrite Forall_app. split.
      + constructor; [unfold q7_pass; auto 10 | constructor].
      + apply Forall_rev. exact Hrec7. }
  assert (Hne : xs <> []).
  { intro H.
    assert (Hlen : length xs = 0) by (rewrite H; reflexivity).
    unfold xs in Hlen.
    repeat rewrite app_length in Hlen.
    cbn [length] in Hlen.
    lia. }
  assert (Hscan : Forall q8_pass (hd 2 xs :: tl xs)).
  { apply Forall_q7_to_q8. apply Forall_hd_tl; [exact Hne | exact Hxs7]. }
  replace (S (length marked) +
           (S (length xs) + S (length record_marks)))
    with (S (length marked) + (S (length xs) + S (length record_marks)))
    by reflexivity.
  rewrite dispatch_run_add.
  destruct dir; cbn [source_bit].
  - rewrite (q6_scan_one marked
      (4 :: rev record_marks ++ 5 :: rev tbuffer ++ 6 :: rev data)
      record_tail Hmarked6).
    replace (cfg_ml 7 (rev marked ++
        4 :: rev record_marks ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (3 :: record_tail))
      with (cfg_ml 7 (xs ++ 5 :: (rev tbuffer ++ 6 :: rev data))
        (3 :: record_tail)).
    2:{ unfold xs. repeat rewrite <- app_assoc. reflexivity. }
    rewrite (cfg_ml_left_scan 7 xs (rev tbuffer ++ 6 :: rev data)
      3 record_tail Hne).
    rewrite <- (length_hd_tl xs Hne).
    rewrite dispatch_run_add.
    rewrite (q7_scan_to_y (tl xs) (hd 2 xs)
      (rev tbuffer ++ 6 :: rev data) (3 :: record_tail) Hscan).
    rewrite (rev_hd_tl xs Hne).
    unfold xs.
    rewrite rev_app_distr. cbn [rev]. rewrite rev_involutive.
    cbn [app].
    rewrite q8_reversed_frame.
    rewrite (q9_scan_marked_to_q12 record_marks
      (5 :: rev tbuffer ++ 6 :: rev data)
      (marked ++ 3 :: record_tail) Hrec9).
    repeat rewrite <- app_assoc.
    reflexivity.
  - rewrite (q6_scan_zero marked
      (4 :: rev record_marks ++ 5 :: rev tbuffer ++ 6 :: rev data)
      record_tail Hmarked6).
    replace (cfg_ml 8 (rev marked ++
        4 :: rev record_marks ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (2 :: record_tail))
      with (cfg_ml 8 (xs ++ 5 :: (rev tbuffer ++ 6 :: rev data))
        (2 :: record_tail)).
    2:{ unfold xs. repeat rewrite <- app_assoc. reflexivity. }
    rewrite (cfg_ml_left_scan 8 xs (rev tbuffer ++ 6 :: rev data)
      2 record_tail Hne).
    rewrite <- (length_hd_tl xs Hne).
    rewrite dispatch_run_add.
    rewrite (q8_scan_to_y (tl xs) (hd 2 xs)
      (rev tbuffer ++ 6 :: rev data) (2 :: record_tail) Hscan).
    rewrite (rev_hd_tl xs Hne).
    unfold xs.
    rewrite rev_app_distr. cbn [rev]. rewrite rev_involutive.
    cbn [app].
    rewrite q8_reversed_frame.
    rewrite (q10_scan_marked_to_q13 record_marks
      (5 :: rev tbuffer ++ 6 :: rev data)
      (marked ++ 2 :: record_tail) Hrec9).
    repeat rewrite <- app_assoc.
    reflexivity.
Qed.

Print Assumptions q9_scan_marked_to_q12.
Print Assumptions q10_scan_marked_to_q13.
Print Assumptions canonical_q6_direction_capture.
