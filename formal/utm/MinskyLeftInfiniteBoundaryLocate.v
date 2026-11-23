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
  MinskyActionMacro MinskyHeadMoveMacro MinskyDirectionDecision
  MinskyRelocationMacro
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

Lemma app_singleton_cons :
  forall (A : Type) (l : list A) (x : A) (m : list A),
    (l ++ [x]) ++ m = l ++ x :: m.
Proof.
  intros. rewrite <- (app_assoc l [x] m). reflexivity.
Qed.


(** * Pass-aware locate chain *)

Definition book_locate_state_wide_pass
    (src : list bool) (pass : list nat) (failed rest : list book_row)
    (left tail : list nat) : Config :=
  entry_config 1 (5 :: left)
    (pass ++ map match_mark src ++ book_marked_prefix failed ++
     book_raw_tail rest ++ 5 :: tail).

Definition book_failure_clock_pass
    (pass : list nat) (failed : list book_row) (step : book_failure) : nat :=
  matched_comparison_steps (bf_good step) (length pass)
    (length (map match_mark (bf_bit step :: bf_src_rest step) ++
             (book_marked_prefix failed ++ [4]))) +
  book_mismatch_clock_gen_pass pass (bf_bit step) (bf_good step)
    (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
    (br_dir (bf_row step)) (book_marked_prefix failed ++ [4]).

Fixpoint book_failures_clock_pass
    (pass : list nat) (failed : list book_row)
    (steps : list book_failure) : nat :=
  match steps with
  | [] => 0
  | st :: rest =>
      book_failure_clock_pass pass failed st +
      book_failures_clock_pass pass (failed ++ [bf_row st]) rest
  end.

Lemma book_locate_first_failed_row_pass :
  forall (pass : list nat) (failed : list book_row) (step : book_failure)
         (next : book_row) (rest : list book_row) (left tail : list nat),
    Forall q1_pass pass ->
    run (book_failure_clock_pass pass failed step)
      (book_locate_state_wide_pass (bf_src step) pass failed
         (bf_row step :: next :: rest) left tail)
    = book_locate_state_wide_pass (bf_src step)
        (map entry_rewrite pass) (failed ++ [bf_row step])
        (next :: rest) left tail.
Proof.
  intros pass failed step next rest left tail Hpass.
  unfold book_failure_clock_pass.
  unfold book_locate_state_wide_pass.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  unfold book_raw_row.
  rewrite (bf_src_split step).
  rewrite (bf_row_split step).
  assert (Hframe1 :
    entry_config 1 (5 :: left)
      (pass ++
       map match_mark (bf_good step ++ bf_bit step :: bf_src_rest step) ++
       book_marked_prefix failed ++
       ((4 :: (((map source_bit
                   (bf_good step ++ negb (bf_bit step) :: bf_row_rest step)) ++
                 (map source_bit (br_action (bf_row step)) ++
                  [source_bit (br_dir (bf_row step))])) ++
                book_raw_tail (next :: rest))) ++ 5 :: tail))
    = entry_config 1 (5 :: left)
      (pass ++
       map match_mark (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_raw (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       [source_bit (br_dir (bf_row step))] ++
       4 :: book_raw_desc (next :: rest) ++ 5 :: tail)).
  { repeat rewrite map_app. cbn [map app].
    repeat rewrite <- app_assoc. cbn [app].
    reflexivity. }
  rewrite Hframe1.
  rewrite (dispatch_run_add
    (matched_comparison_steps (bf_good step) (length pass)
       (length (map match_mark (bf_bit step :: bf_src_rest step) ++
                (book_marked_prefix failed ++ [4]))))
    (book_mismatch_clock_gen_pass pass (bf_bit step) (bf_good step)
       (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
       (br_dir (bf_row step)) (book_marked_prefix failed ++ [4]))).
  rewrite (q1_all_matching_bits_wide (bf_good step) pass
    (map match_mark (bf_bit step :: bf_src_rest step) ++
     (book_marked_prefix failed ++ [4]))
    left
    (match_raw (negb (bf_bit step)) ::
     map source_bit (bf_row_rest step) ++
     map source_bit (br_action (bf_row step)) ++
     [source_bit (br_dir (bf_row step))] ++
     4 :: book_raw_desc (next :: rest) ++ 5 :: tail)
    Hpass (wide_mark_failure_done (bf_bit step) (bf_src_rest step) failed)).
  cbn [app].
  assert (Hframe2 :
    entry_config 1 (5 :: left)
      (pass ++ map match_raw (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       source_bit (br_dir (bf_row step)) ::
       4 :: book_raw_desc (next :: rest) ++ 5 :: tail)
    = entry_config 1 (5 :: left)
      (pass ++ map match_raw (bf_good step) ++ match_mark (bf_bit step) ::
       map match_mark (bf_src_rest step) ++
       (book_marked_prefix failed ++ [4]) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       [source_bit (br_dir (bf_row step))] ++
       4 :: book_raw_desc (next :: rest) ++ 5 :: tail)).
  { repeat rewrite map_app. cbn [map app].
    repeat rewrite <- app_assoc. cbn [app].
    reflexivity. }
  rewrite Hframe2.
  rewrite (book_q1_mismatch_restart_gen_pass pass (bf_bit step)
    (bf_good step) (bf_src_rest step) (bf_row_rest step)
    (br_action (bf_row step)) (br_dir (bf_row step))
    (book_marked_prefix failed ++ [4])
    (book_raw_desc (next :: rest) ++ 5 :: tail) left Hpass
    (Forall_wide_mark_marked_prefix_snoc failed)).
  cbn [app].
  rewrite book_marked_prefix_snoc.
  rewrite book_raw_tail_cons.
  unfold book_marked_row.
  rewrite (bf_row_split step).
  repeat rewrite <- app_assoc.
  cbn [app].
  repeat rewrite <- app_assoc.
  cbn [app].
  reflexivity.
Qed.

Print Assumptions book_locate_first_failed_row_pass.

(** ** Failed-row sequence with a stable pass *)

Lemma book_locate_failed_rows_wide_pass :
  forall (src : list bool) (pass : list nat) (failed : list book_row)
         (steps : list book_failure) (next : book_row) (rest : list book_row)
         (left tail : list nat),
    Forall q1_pass pass ->
    map entry_rewrite pass = pass ->
    Forall (fun st => bf_src st = src) steps ->
    run (book_failures_clock_pass pass failed steps)
      (book_locate_state_wide_pass src pass failed
         (map bf_row steps ++ next :: rest) left tail)
    = book_locate_state_wide_pass src pass
        (failed ++ map bf_row steps) (next :: rest) left tail.
Proof.
  intros src pass failed steps.
  revert failed.
  induction steps as [|st steps IH];
    intros failed next rest left tail Hpass Hstable Hsteps.
  - cbn [book_failures_clock_pass map app run].
    rewrite app_nil_r. reflexivity.
  - inversion Hsteps as [|? ? Hst Hrest]; subst.
    destruct steps as [|st' steps'].
    + cbn [book_failures_clock_pass map app].
      rewrite Nat.add_0_r.
      rewrite (book_locate_first_failed_row_pass pass failed st next rest
        left tail Hpass).
      rewrite Hstable. reflexivity.
    + cbn [book_failures_clock_pass map app].
      rewrite (dispatch_run_add
        (book_failure_clock_pass pass failed st)
        (book_failures_clock_pass pass (failed ++ [bf_row st])
           (st' :: steps'))).
      rewrite (book_locate_first_failed_row_pass pass failed st
        (bf_row st') (map bf_row steps' ++ next :: rest) left tail Hpass).
      rewrite Hstable.
      replace (failed ++ (bf_row st :: (bf_row st' :: map bf_row steps')))
        with ((failed ++ [bf_row st]) ++
              (bf_row st' :: map bf_row steps'))
        by (exact (@app_singleton_cons book_row failed (bf_row st)
  (bf_row st' :: map bf_row steps'))).
      change (run (book_failures_clock_pass pass (failed ++ [bf_row st])
                     (st' :: steps'))
        (book_locate_state_wide_pass (bf_src st) pass (failed ++ [bf_row st])
           (map bf_row (st' :: steps') ++ next :: rest) left tail) =
        book_locate_state_wide_pass (bf_src st) pass
          ((failed ++ [bf_row st]) ++ map bf_row (st' :: steps'))
          (next :: rest) left tail).
      rewrite (IH (failed ++ [bf_row st]) next rest left tail
        Hpass Hstable Hrest).
      cbn [map app]. repeat rewrite <- app_assoc. reflexivity.
Qed.

Print Assumptions book_locate_failed_rows_wide_pass.

(** ** q1 scan of a pass prefix *)

Lemma q1_scan_pass_left :
  forall (pass : list nat) (left rest : list nat),
    Forall q1_pass pass ->
    run (length pass) (entry_config 1 left (pass ++ rest)) =
    entry_config 1 (rev pass ++ left) rest.
Proof.
  induction pass as [|s ss IH]; intros left rest Hpass.
  - reflexivity.
  - inversion Hpass as [|? ? Hs Hss]; subst.
    cbn [length app].
    rewrite entry_run_successor.
    rewrite (q1_pass_step s left (ss ++ rest) Hs).
    rewrite (IH (s :: left) rest Hss).
    cbn [rev]. repeat rewrite <- app_assoc. reflexivity.
Qed.

Definition boundary_halt_encode_from_failed
    (extra : list nat) (failed : list book_row)
    (steps : list book_failure) (last : book_failure)
    (left tail : list nat) : Config :=
  dispatch_halt_at_y
    (rev (map source_bit (bf_row_rest last) ++
          map source_bit (br_action (bf_row last)) ++
          [source_bit (br_dir (bf_row last))]) ++
     match_mark (negb (bf_bit last)) ::
     rev (map match_mark (bf_src_rest last) ++
          ((book_marked_prefix (failed ++ map bf_row steps)) ++ [4]) ++
          map match_mark (bf_good last)) ++
     match_raw (bf_bit last) :: rev (map match_raw (bf_good last)) ++
     extra ++ 5 :: left)
    tail.

(** ** Last-row mismatch halt with a pass prefix *)

Lemma book_locate_last_mismatch_halt_wide_pass :
  forall (pass : list nat) (failed : list book_row) (step : book_failure)
         (left tail : list nat),
    Forall q1_pass pass ->
    run (matched_comparison_steps (bf_good step) (length pass)
           (length (map match_mark (bf_bit step :: bf_src_rest step) ++
                    (book_marked_prefix failed ++ [4]))) +
         (length pass +
          book_mismatch_halt_clock (bf_bit step) (bf_good step)
            (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
            (br_dir (bf_row step)) (book_marked_prefix failed ++ [4])))
      (book_locate_state_wide_pass (bf_src step) pass failed
         [bf_row step] left tail)
    = boundary_halt_encode_from_failed (rev pass) failed [] step left tail.
Proof.
  intros pass failed step left tail Hpass.
  unfold book_locate_state_wide_pass.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  cbn [book_raw_tail].
  rewrite app_nil_r.
  unfold book_raw_row.
  rewrite (bf_src_split step).
  rewrite (bf_row_split step).
  assert (Hframe1 :
    entry_config 1 (5 :: left)
      (pass ++
       map match_mark (bf_good step ++ bf_bit step :: bf_src_rest step) ++
       book_marked_prefix failed ++
       ((4 :: (map source_bit
                 (bf_good step ++ negb (bf_bit step) :: bf_row_rest step) ++
               map source_bit (br_action (bf_row step)) ++
               [source_bit (br_dir (bf_row step))])) ++ 5 :: tail))
    = entry_config 1 (5 :: left)
      (pass ++
       map match_mark (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_raw (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       [source_bit (br_dir (bf_row step))] ++ 5 :: tail)).
  { repeat rewrite map_app. cbn [map app].
    repeat rewrite <- app_assoc. cbn [app].
    reflexivity. }
  rewrite Hframe1.
  rewrite (dispatch_run_add
    (matched_comparison_steps (bf_good step) (length pass)
       (length (map match_mark (bf_bit step :: bf_src_rest step) ++
                (book_marked_prefix failed ++ [4]))))
    (length pass +
     book_mismatch_halt_clock (bf_bit step) (bf_good step)
       (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
       (br_dir (bf_row step)) (book_marked_prefix failed ++ [4]))).
  rewrite (q1_all_matching_bits_wide (bf_good step) pass
    (map match_mark (bf_bit step :: bf_src_rest step) ++
     (book_marked_prefix failed ++ [4]))
    left
    (match_raw (negb (bf_bit step)) ::
     map source_bit (bf_row_rest step) ++
     map source_bit (br_action (bf_row step)) ++
     [source_bit (br_dir (bf_row step))] ++ 5 :: tail)
    Hpass (wide_mark_failure_done (bf_bit step) (bf_src_rest step) failed)).
  cbn [app].
  assert (Hframe2 :
    entry_config 1 (5 :: left)
      (pass ++ map match_raw (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       source_bit (br_dir (bf_row step)) :: 5 :: tail)
    = entry_config 1 (5 :: left)
      (pass ++ map match_raw (bf_good step) ++ match_mark (bf_bit step) ::
       map match_mark (bf_src_rest step) ++
       (book_marked_prefix failed ++ [4]) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       [source_bit (br_dir (bf_row step))] ++ 5 :: tail)).
  { repeat rewrite map_app. cbn [map app].
    repeat rewrite <- app_assoc. cbn [app].
    reflexivity. }
  rewrite Hframe2.
  rewrite (dispatch_run_add (length pass)
    (book_mismatch_halt_clock (bf_bit step) (bf_good step)
       (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
       (br_dir (bf_row step)) (book_marked_prefix failed ++ [4]))).
  rewrite (q1_scan_pass_left pass (5 :: left)
    (map match_raw (bf_good step) ++ match_mark (bf_bit step) ::
     map match_mark (bf_src_rest step) ++
     (book_marked_prefix failed ++ [4]) ++
     map match_mark (bf_good step) ++
     match_raw (negb (bf_bit step)) ::
     map source_bit (bf_row_rest step) ++
     map source_bit (br_action (bf_row step)) ++
     [source_bit (br_dir (bf_row step))] ++ 5 :: tail) Hpass).
  rewrite (book_q1_mismatch_halt_gen_extra (bf_bit step) (bf_good step)
    (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
    (br_dir (bf_row step)) (book_marked_prefix failed ++ [4])
    (rev pass ++ 5 :: left) tail
    (Forall_wide_mark_marked_prefix_snoc failed)).
  unfold boundary_halt_encode_from_failed.
  cbn [map app].
  rewrite app_nil_r.
  reflexivity.
Qed.

Print Assumptions book_locate_last_mismatch_halt_wide_pass.

Definition book_halt_clock_pass
    (pass : list nat) (failed : list book_row) (step : book_failure) : nat :=
  matched_comparison_steps (bf_good step) (length pass)
    (length (map match_mark (bf_bit step :: bf_src_rest step) ++
             (book_marked_prefix failed ++ [4]))) +
  (length pass +
   book_mismatch_halt_clock (bf_bit step) (bf_good step)
     (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
     (br_dir (bf_row step)) (book_marked_prefix failed ++ [4])).

Theorem book_locate_rows_to_halt_wide_pass :
  forall (src : list bool) (pass : list nat) (failed : list book_row)
         (steps : list book_failure) (last : book_failure)
         (left tail : list nat),
    Forall q1_pass pass ->
    map entry_rewrite pass = pass ->
    Forall (fun st => bf_src st = src) (steps ++ [last]) ->
    run (book_failures_clock_pass pass failed steps +
         book_halt_clock_pass pass (failed ++ map bf_row steps) last)
      (book_locate_state_wide_pass src pass failed
         (map bf_row (steps ++ [last])) left tail)
    = boundary_halt_encode_from_failed (rev pass) failed steps last
        left tail.
Proof.
  intros src pass failed steps last left tail Hpass Hstable Hsteps.
  rewrite map_app. cbn [map].
  rewrite (dispatch_run_add (book_failures_clock_pass pass failed steps)
    (book_halt_clock_pass pass (failed ++ map bf_row steps) last)).
  assert (Hsteps' : Forall (fun st => bf_src st = src) steps).
  { apply Forall_app in Hsteps. destruct Hsteps as [H _]. exact H. }
  rewrite (book_locate_failed_rows_wide_pass src pass failed steps
    (bf_row last) [] left tail Hpass Hstable Hsteps').
  assert (Hlast : bf_src last = src).
  { apply Forall_app in Hsteps. destruct Hsteps as [_ H].
    apply Forall_inv in H. exact H. }
  rewrite <- Hlast.
  unfold book_halt_clock_pass.
  rewrite (book_locate_last_mismatch_halt_wide_pass pass
    (failed ++ map bf_row steps) last left tail Hpass).
  unfold boundary_halt_encode_from_failed.
  cbn [map app].
  rewrite app_nil_r.
  reflexivity.
Qed.

Print Assumptions book_locate_rows_to_halt_wide_pass.

(** ** q5 empty boundary + pass-aware locate halt *)

Theorem q5_empty_boundary_locate_halt :
  forall (h0 : bool) (t0 : list bool) (hit_w : bool)
         (data tags suffix : list nat) (target : bool)
         (steps : list book_failure) (last : book_failure)
         (rows : list book_row) (tail : list nat),
    Forall (fun st => bf_src st = t0 ++ [h0]) (steps ++ [last]) ->
    rows = map bf_row (steps ++ [last]) ->
    4 :: map q16_restore (rev tags) ++ source_bit target :: suffix =
      book_raw_tail rows ++ 5 :: tail ->
    run (S (length (map source_bit t0) + 1) +
         (book_failures_clock_pass [6] [] steps +
          book_halt_clock_pass [6] (map bf_row steps) last))
      (cfg_ml 5
        (rev (map source_bit t0) ++ 6 :: 5 ::
         source_bit hit_w :: rev data)
        (match_mark h0 :: 4 ::
         map q16_restore (rev tags) ++ source_bit target :: suffix)) =
    boundary_halt_encode_from_failed [6] [] steps last
      (source_bit hit_w :: rev data) tail.
Proof.
  intros h0 t0 hit_w data tags suffix target steps last rows tail
    Hsteps Hrows Hdesc.
  rewrite (dispatch_run_add (S (length (map source_bit t0) + 1))
    (book_failures_clock_pass [6] [] steps +
     book_halt_clock_pass [6] (map bf_row steps) last)).
  rewrite (q5_scan_empty_boundary h0 t0 hit_w data tags suffix target).
  rewrite Hdesc.
  cbn [book_marked_prefix app].
  rewrite Hrows.
  change (run (book_failures_clock_pass [6] [] steps +
               book_halt_clock_pass [6] ([] ++ map bf_row steps) last)
    (book_locate_state_wide_pass (t0 ++ [h0]) [6] []
       (map bf_row (steps ++ [last])) (source_bit hit_w :: rev data) tail) =
    boundary_halt_encode_from_failed [6] [] steps last
      (source_bit hit_w :: rev data) tail).
  rewrite (book_locate_rows_to_halt_wide_pass
    (t0 ++ [h0]) [6] [] steps last
    (source_bit hit_w :: rev data) tail
    ltac:(constructor; [unfold q1_pass; auto 10 | constructor])
    eq_refl Hsteps).
  reflexivity.
Qed.

Print Assumptions q5_empty_boundary_locate_halt.

(** ** Full empty-buffer boundary macro *)

Theorem book_q12_empty_boundary_halt :
  forall (s : nat) (remaining data : list nat) (marked : list nat)
         (mark : nat) (record_tail : list nat) (tags : list nat)
         (old : bool) (dir_head : nat) (dir_remaining : list nat)
         (bit target : bool) (between suffix : list nat)
         (t0 : list bool) (h0 : bool) (hit_w : bool)
         (steps : list book_failure) (last : book_failure)
         (rows : list book_row) (tail : list nat),
    Forall q12_pass (s :: remaining ++ 5 :: []) ->
    Forall q14_pass ([5] ++ rev remaining ++ [s]) ->
    map q14_restore (rev ([5] ++ rev remaining ++ [s])) =
      source_bit old :: dir_head :: dir_remaining ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    rev (dir_head :: dir_remaining) = 5 :: source_bit bit :: between ->
    Forall q17_pass between ->
    marked ++ mark :: record_tail = rev tags ++ source_bit target :: suffix ->
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    between = map source_bit t0 ->
    bit = h0 ->
    old = hit_w ->
    Forall (fun st => bf_src st = t0 ++ [h0]) (steps ++ [last]) ->
    rows = map bf_row (steps ++ [last]) ->
    4 :: map q16_restore (rev tags) ++ source_bit target :: suffix =
      book_raw_tail rows ++ 5 :: tail ->
    run ((S (length (s :: remaining ++ 5 :: [])) +
          S (length ([5] ++ rev remaining ++ [s]))) +
         ((S (length (rev tags)) +
           S (length (tags ++ [4])) +
           S (length (dir_head :: dir_remaining))) +
          (2 + S (length between))) +
         (S (length (map source_bit t0) + 1) +
          (book_failures_clock_pass [6] [] steps +
           book_halt_clock_pass [6] (map bf_row steps) last)))
      (cfg_ml 12
        (s :: remaining ++ 5 :: 6 :: rev data)
        (4 :: marked ++ mark :: record_tail)) =
    boundary_halt_encode_from_failed [6] [] steps last
      (source_bit hit_w :: rev data) tail.
Proof.
  intros s remaining data marked mark record_tail tags old
    dir_head dir_remaining bit target between suffix t0 h0 hit_w
    steps last rows tail H12 H14 Hrestored H21 Hsplit H17 Hright
    H15 H16 Hbetween Hbit Hold Hsteps Hrows Hdesc.
  rewrite (dispatch_run_add
    ((S (length (s :: remaining ++ 5 :: [])) +
      S (length ([5] ++ rev remaining ++ [s]))) +
     ((S (length (rev tags)) +
       S (length (tags ++ [4])) +
       S (length (dir_head :: dir_remaining))) +
      (2 + S (length between))))
    (S (length (map source_bit t0) + 1) +
     (book_failures_clock_pass [6] [] steps +
      book_halt_clock_pass [6] (map bf_row steps) last))).
  rewrite (book_q12_restore_to_q5_right_empty s remaining data marked
    mark record_tail tags old dir_head dir_remaining bit target between
    suffix H12 H14 Hrestored H21 Hsplit H17 Hright H15 H16).
  rewrite Hbetween, Hbit, Hold.
  change (run (S (length (map source_bit t0) + 1) +
               (book_failures_clock_pass [6] [] steps +
                book_halt_clock_pass [6] (map bf_row steps) last))
    (cfg_ml 5
      (rev (map source_bit t0) ++ 6 :: 5 ::
       source_bit hit_w :: rev data)
      (match_mark h0 :: 4 ::
       map q16_restore (rev tags) ++ source_bit target :: suffix)) =
    boundary_halt_encode_from_failed [6] [] steps last
      (source_bit hit_w :: rev data) tail).
  rewrite (q5_empty_boundary_locate_halt h0 t0 hit_w data tags suffix
    target steps last rows tail Hsteps Hrows Hdesc).
  reflexivity.
Qed.

Print Assumptions book_q12_empty_boundary_halt.

(** ** Relation to the boundary halt encoder without a prior failed prefix *)

Lemma boundary_halt_encode_from_failed_nil :
  forall (extra : list nat) (steps : list book_failure)
         (last : book_failure) (left tail : list nat),
    boundary_halt_encode_from_failed extra [] steps last left tail =
    boundary_halt_encode_from extra steps last left tail.
Proof.
  intros. unfold boundary_halt_encode_from_failed,
    boundary_halt_encode_from.
  cbn [app]. reflexivity.
Qed.

Print Assumptions boundary_halt_encode_from_failed_nil.
