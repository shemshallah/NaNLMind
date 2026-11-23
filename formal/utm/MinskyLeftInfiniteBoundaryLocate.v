(** * Pass-aware q1 mismatch restart

    The empty-buffer boundary reaches q1 with a leading q5 marker [6].
    This file proves the mismatch restart with an arbitrary [q1_pass]
    prefix.  The primitive q4/q0 restart lemmas already accept an
    arbitrary left prefix, so the pass is scanned forward by q1 and then
    treated as part of the q4/q0 left prefix. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyConcreteEntry
  MinskyConcreteDispatch MinskyMatchMacro MinskyCanonicalMatch
  MinskyBookLayout MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyLeftInfiniteBoundary.

Local Open Scope nat_scope.

Lemma q1_pass_q5_pass :
  forall s, q1_pass s -> q5_pass s.
Proof.
  intros s [ -> | [ -> | [ -> | -> ] ] ]; unfold q5_pass; auto 10.
Qed.

Lemma forall_q5_pass_rev_q1 :
  forall pass,
    Forall q1_pass pass ->
    Forall q5_pass (rev pass).
Proof.
  intros pass Hpass. apply Forall_rev.
  induction Hpass as [|s rest Hs Hrest IH]; simpl.
  - constructor.
  - constructor; [apply q1_pass_q5_pass; exact Hs|exact IH].
Qed.

Lemma forall_q1_pass_app_raw :
  forall (pass : list nat) (good : list bool),
    Forall q1_pass pass ->
    Forall q1_pass (pass ++ map match_raw good).
Proof.
  intros pass good Hpass.
  apply Forall_app. split; [exact Hpass|apply match_raw_valid].
Qed.

Definition book_mismatch_clock_gen_pass
    (pass : list nat) (b : bool) (good restbits row1_rest action1 : list bool)
    (dir1 : bool) (done : list nat) : nat :=
  2 * length pass +
  book_mismatch_clock_gen b good restbits row1_rest action1 dir1 done.

Lemma book_q1_mismatch_restart_gen_pass :
  forall (pass : list nat) (b : bool)
         (good restbits row1_rest action1 : list bool) (dir1 : bool)
         (done afterX prefix : list nat),
    Forall q1_pass pass ->
    Forall wide_mark done ->
    run (book_mismatch_clock_gen_pass pass b good restbits row1_rest
           action1 dir1 done)
      (entry_config 1 (5 :: prefix)
        (pass ++ map match_raw good ++ match_mark b ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw (negb b) :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite pass ++
       map match_mark (good ++ b :: restbits) ++ done ++
       map match_mark (good ++ negb b :: row1_rest) ++
       map match_mark action1 ++ [match_mark dir1] ++ 4 :: afterX).
Proof.
  intros pass b good restbits row1_rest action1 dir1 done afterX prefix
    Hpass Hdone.
  set (row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
  set (marked := map match_mark restbits ++ done ++ map match_mark good).
  set (scan0 := rev row_rest ++ match_mark (negb b) :: rev marked ++
                match_raw b :: rev (map match_raw good)).
  set (scan := scan0 ++ rev pass).
  assert (Hne : scan <> []).
  { subst scan scan0. intro H.
    apply app_eq_nil in H. destruct H as [H0 _].
    exact (book_mismatch_scan_gen_nonempty b good restbits row1_rest
      action1 dir1 done H0). }
  destruct scan as [|s remaining] eqn:Hscan.
  - exfalso. apply Hne. reflexivity.
  - assert (Hq5 : Forall q5_pass (s :: remaining)).
    { rewrite <- Hscan. subst scan.
      apply Forall_app. split.
      - subst scan0. apply book_mismatch_scan_gen_valid. exact Hdone.
      - apply forall_q5_pass_rev_q1. exact Hpass. }
    assert (Hsplit :
      rev row_rest ++ match_mark (negb b) :: rev marked ++
      (match_raw b :: rev (pass ++ map match_raw good)) ++
      5 :: prefix = (s :: remaining) ++ 5 :: prefix).
    { rewrite <- Hscan. subst scan scan0.
      rewrite rev_app_distr.
      rewrite cons_app_assoc.
      rewrite cons_app_assoc.
      rewrite cons_app_assoc.
      rewrite cons_app_assoc.
      simpl. reflexivity. }
    assert (Hclock :
      book_mismatch_clock_gen b good restbits row1_rest action1 dir1 done =
      S (length (map match_raw good)) +
      (S (length marked) +
       ((length row_rest + 1) + S (length scan0)))).
    { unfold book_mismatch_clock_gen, book_mismatch_scan_gen.
      cbn zeta. fold marked. fold row_rest. fold scan0. reflexivity. }
    assert (Hclock_pass :
      2 * length pass +
      book_mismatch_clock_gen b good restbits row1_rest action1 dir1 done =
      S (length (pass ++ map match_raw good)) +
      (S (length marked) +
       ((length row_rest + 1) + S (length (s :: remaining))))).
    { rewrite Hclock. rewrite <- Hscan.
      subst scan. rewrite length_app. rewrite length_app.
      rewrite length_rev, length_map. lia. }
    unfold book_mismatch_clock_gen_pass.
    rewrite Hclock_pass.
    destruct b.
    + cbn [negb].
      assert (Hmarked : Forall q4_pass marked).
      { subst marked.
        assert (Hwide : Forall wide_mark
          (map match_mark restbits ++ done ++ map match_mark good)).
        { repeat rewrite Forall_app. repeat split.
          - apply wide_mark_map_match_marks.
          - exact Hdone.
          - apply wide_mark_map_match_marks. }
        exact (proj1 (proj2 (wide_mark_scans _ Hwide))). }
      assert (Hright : Forall dispatch_right_symbol row_rest).
      { subst row_rest.
        repeat rewrite Forall_app. repeat split.
        - apply source_bit_list_is_right_scannable.
        - apply source_bit_list_is_right_scannable.
        - constructor;
            [apply source_bit_is_right_symbol | constructor]. }
      assert (Hentry :
        (pass ++ map match_raw good ++ match_mark true ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw false :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 4 :: afterX)
        = (pass ++ map match_raw good ++ 3 :: marked ++
           0 :: row_rest ++ 4 :: afterX)).
      { cbn [match_mark match_raw]. unfold marked, row_rest.
        repeat rewrite <- app_assoc. cbn [app].
        repeat rewrite <- app_assoc. cbn [app].
        reflexivity. }
      rewrite Hentry.
      replace (pass ++ map match_raw good ++ 3 :: marked ++
               0 :: row_rest ++ 4 :: afterX)
        with ((pass ++ map match_raw good) ++ 3 :: marked ++
              0 :: row_rest ++ 4 :: afterX)
        by (rewrite app_assoc; reflexivity).
      rewrite (dispatch_run_add (S (length (pass ++ map match_raw good)))
        (S (length marked) +
         ((length row_rest + 1) + S (length (s :: remaining))))).
      rewrite (q1_scan_pick (pass ++ map match_raw good) (5 :: prefix) 3
        (marked ++ 0 :: row_rest ++ 4 :: afterX)
        (forall_q1_pass_app_raw pass good Hpass)
        (or_intror (or_introl eq_refl))).
      rewrite app_comm_cons.
      rewrite (q4_mismatch_restart marked row_rest
        (1 :: rev (pass ++ map match_raw good)) s remaining prefix afterX
        Hmarked Hright ltac:(cbn [negb]; exact Hsplit) Hq5).
      rewrite <- Hscan. subst scan.
      rewrite rev_app_distr, rev_involutive, map_app.
      subst scan0 row_rest marked.
      rewrite map_entry_rewrite_book_mismatch_scan_gen by exact Hdone.
      repeat rewrite <- app_assoc.
      reflexivity.
    + cbn [negb].
      assert (Hmarked : Forall q0_pass marked).
      { subst marked.
        assert (Hwide : Forall wide_mark
          (map match_mark restbits ++ done ++ map match_mark good)).
        { repeat rewrite Forall_app. repeat split.
          - apply wide_mark_map_match_marks.
          - exact Hdone.
          - apply wide_mark_map_match_marks. }
        exact (proj1 (wide_mark_scans _ Hwide)). }
      assert (Hright : Forall dispatch_right_symbol row_rest).
      { subst row_rest.
        repeat rewrite Forall_app. repeat split.
        - apply source_bit_list_is_right_scannable.
        - apply source_bit_list_is_right_scannable.
        - constructor;
            [apply source_bit_is_right_symbol | constructor]. }
      assert (Hentry :
        (pass ++ map match_raw good ++ match_mark false ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw true :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 4 :: afterX)
        = (pass ++ map match_raw good ++ 2 :: marked ++
           1 :: row_rest ++ 4 :: afterX)).
      { cbn [match_mark match_raw]. unfold marked, row_rest.
        repeat rewrite <- app_assoc. cbn [app].
        repeat rewrite <- app_assoc. cbn [app].
        reflexivity. }
      rewrite Hentry.
      replace (pass ++ map match_raw good ++ 2 :: marked ++
               1 :: row_rest ++ 4 :: afterX)
        with ((pass ++ map match_raw good) ++ 2 :: marked ++
              1 :: row_rest ++ 4 :: afterX)
        by (rewrite app_assoc; reflexivity).
      rewrite (dispatch_run_add (S (length (pass ++ map match_raw good)))
        (S (length marked) +
         ((length row_rest + 1) + S (length (s :: remaining))))).
      rewrite (q1_scan_pick (pass ++ map match_raw good) (5 :: prefix) 2
        (marked ++ 1 :: row_rest ++ 4 :: afterX)
        (forall_q1_pass_app_raw pass good Hpass)
        (or_introl eq_refl)).
      rewrite app_comm_cons.
      rewrite (q0_mismatch_restart marked row_rest
        (0 :: rev (pass ++ map match_raw good)) s remaining prefix afterX
        Hmarked Hright ltac:(cbn [negb]; exact Hsplit) Hq5).
      rewrite <- Hscan. subst scan.
      rewrite rev_app_distr, rev_involutive, map_app.
      subst scan0 row_rest marked.
      rewrite map_entry_rewrite_book_mismatch_scan_gen by exact Hdone.
      repeat rewrite <- app_assoc.
      reflexivity.
Qed.

Print Assumptions book_q1_mismatch_restart_gen_pass.
