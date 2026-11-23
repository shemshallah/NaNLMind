(** * Generalized locate phase with an arbitrary left suffix

    The locate phase only uses the left tape through the opaque list
    [left]; the concrete buffer layout is needed only when entering the
    phase from q5.  These lemmas expose that generality so that the left
    perform output, whose buffer ends with a write bit before the q6
    delimiter, can feed the same locate/halt machinery. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry MinskyConcreteDispatch
  MinskySourceEncoding MinskyMatchMacro MinskyCanonicalMatch
  MinskyActionMacro MinskyCanonicalCopy MinskyCanonicalCopyGeneral
  MinskyCanonicalDirection MinskyCanonicalInstruction MinskyHeadMoveMacro
  MinskyCanonicalRestore MinskyDirectionDecision MinskyRelocationMacro
  MinskyBookLayout MinskyBookCycle MinskyBookLocate MinskyBookLocateRows.

Definition book_locate_state_wide
    (src : list bool) (failed rest : list book_row)
    (left : list nat) (tail : list nat) : Config :=
  entry_config 1
    (5 :: left)
    (map match_mark src ++ book_marked_prefix failed ++
     book_raw_tail rest ++ 5 :: tail).

Lemma book_locate_failed_row_wide :
  forall (failed : list book_row) (step : book_failure)
         (next : book_row) (rest : list book_row) (left tail : list nat),
    run (book_failure_clock failed step)
      (book_locate_state_wide (bf_src step) failed
         (bf_row step :: next :: rest) left tail)
    = book_locate_state_wide (bf_src step) (failed ++ [bf_row step])
        (next :: rest) left tail.
Proof.
  intros failed step next rest left tail.
  unfold book_failure_clock.
  unfold book_locate_state_wide.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  unfold book_raw_row.
  rewrite (bf_src_split step).
  rewrite (bf_row_split step).
  (* First compare the matched prefix [good]. *)
  assert (Hframe1 :
    entry_config 1 (5 :: left)
      (map match_mark (bf_good step ++ bf_bit step :: bf_src_rest step) ++
       book_marked_prefix failed ++
       ((4 :: (((map source_bit
                   (bf_good step ++ negb (bf_bit step) :: bf_row_rest step)) ++
                 (map source_bit (br_action (bf_row step)) ++
                  [source_bit (br_dir (bf_row step))])) ++
                book_raw_tail (next :: rest))) ++ 5 :: tail))
    = entry_config 1 (5 :: left)
      (map match_mark (bf_good step) ++
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
    (matched_comparison_steps (bf_good step) 0
       (length (map match_mark (bf_bit step :: bf_src_rest step) ++
                (book_marked_prefix failed ++ [4]))))
    (book_mismatch_clock_gen (bf_bit step) (bf_good step) (bf_src_rest step)
       (bf_row_rest step) (br_action (bf_row step)) (br_dir (bf_row step))
       (book_marked_prefix failed ++ [4]))).
  rewrite (q1_all_matching_bits_wide_zero (bf_good step)
    (map match_mark (bf_bit step :: bf_src_rest step) ++
     (book_marked_prefix failed ++ [4]))
    left
    (match_raw (negb (bf_bit step)) ::
     map source_bit (bf_row_rest step) ++
     map source_bit (br_action (bf_row step)) ++
     [source_bit (br_dir (bf_row step))] ++
     4 :: book_raw_desc (next :: rest) ++ 5 :: tail)
    (wide_mark_failure_done (bf_bit step) (bf_src_rest step) failed)).
  cbn [app].
  (* Now restart on the first mismatch. *)
  assert (Hframe2 :
    entry_config 1 (5 :: left)
      (map match_raw (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       source_bit (br_dir (bf_row step)) ::
       4 :: book_raw_desc (next :: rest) ++ 5 :: tail)
    = entry_config 1 (5 :: left)
      (map match_raw (bf_good step) ++ match_mark (bf_bit step) ::
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
  rewrite (book_q1_mismatch_restart_gen (bf_bit step) (bf_good step)
    (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
    (br_dir (bf_row step)) (book_marked_prefix failed ++ [4])
    (book_raw_desc (next :: rest) ++ 5 :: tail)
    left
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

Print Assumptions book_locate_failed_row_wide.

Lemma book_locate_failed_rows_wide :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (next : book_row) (rest : list book_row) (left tail : list nat),
    Forall (fun st => bf_src st = src) steps ->
    run (book_failures_clock failed steps)
      (book_locate_state_wide src failed (map bf_row steps ++ next :: rest)
         left tail)
    = book_locate_state_wide src (failed ++ map bf_row steps) (next :: rest)
        left tail.
Proof.
  intros src failed steps.
  revert failed.
  induction steps as [|st steps IH];
    intros failed next rest left tail Hsteps.
  - cbn [book_failures_clock map app run].
    rewrite app_nil_r.
    reflexivity.
  - inversion Hsteps as [|? ? Hst Hrest]; subst.
    destruct steps as [|st' steps'].
    + (* only [next] remains after the head failure *)
      cbn [book_failures_clock map app].
      rewrite Nat.add_0_r.
      rewrite (book_locate_failed_row_wide failed st next rest left tail).
      reflexivity.
    + (* another failure follows *)
      cbn [book_failures_clock map app].
      rewrite (dispatch_run_add
        (book_failure_clock failed st)
        (book_failures_clock (failed ++ [bf_row st]) (st' :: steps'))).
      rewrite (book_locate_failed_row_wide failed st (bf_row st')
        (map bf_row steps' ++ next :: rest) left tail).
      replace (failed ++ (bf_row st :: (bf_row st' :: map bf_row steps')))
        with ((failed ++ [bf_row st]) ++
              (bf_row st' :: map bf_row steps'))
        by (symmetry; apply cons_app_assoc).
      change (run (book_failures_clock (failed ++ [bf_row st])
                     (st' :: steps'))
        (book_locate_state_wide (bf_src st) (failed ++ [bf_row st])
           (map bf_row (st' :: steps') ++ next :: rest) left tail) =
        book_locate_state_wide (bf_src st)
          ((failed ++ [bf_row st]) ++ map bf_row (st' :: steps'))
          (next :: rest) left tail).
      rewrite (IH (failed ++ [bf_row st]) next rest left tail Hrest).
      cbn [map app].
      repeat rewrite <- app_assoc.
      reflexivity.
Qed.

Print Assumptions book_locate_failed_rows_wide.

Lemma book_locate_hit_row_wide :
  forall (src : list bool) (failed : list book_row) (hit : book_row)
         (after : list book_row) (left tail : list nat),
    br_cond hit = src ->
    run (book_hit_clock src failed)
      (book_locate_state_wide src failed (hit :: after) left tail)
    = entry_config 6
        (4 :: rev (map source_bit src) ++
         5 :: left)
        (tl (book_marked_prefix failed ++ [4]) ++
         map match_mark src ++
         map source_bit (br_action hit) ++
         [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail).
Proof.
  intros src failed hit after left tail Hcond.
  unfold book_hit_clock.
  unfold book_locate_state_wide.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  unfold book_raw_row.
  rewrite Hcond.
  assert (Hframe1 :
    entry_config 1 (5 :: left)
      (map match_mark src ++
       (book_marked_prefix failed ++
        ((4 :: (((map source_bit src) ++
                  (map source_bit (br_action hit) ++
                   [source_bit (br_dir hit)])) ++
                 book_raw_tail after)) ++ 5 :: tail)))
    = entry_config 1 (5 :: left)
      (map match_mark src ++ (book_marked_prefix failed ++ [4]) ++
       map match_raw src ++
       map source_bit (br_action hit) ++
       [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail)).
  { repeat rewrite map_app. cbn [map app].
    repeat rewrite <- app_assoc. cbn [app].
    reflexivity. }
  rewrite Hframe1.
  rewrite (dispatch_run_add
    (matched_comparison_steps src 0
       (length (book_marked_prefix failed ++ [4])))
    (length src + 1)).
  rewrite (q1_all_matching_bits_wide_zero src
    (book_marked_prefix failed ++ [4])
    left
    (map source_bit (br_action hit) ++
     [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail)
    (Forall_wide_mark_marked_prefix_snoc failed)).
  cbn [app].
  rewrite book_marked_done_cons.
  replace (length src + 1)
    with (length (map match_raw src) + 1)
    by (rewrite map_length; reflexivity).
  change (run (length (map match_raw src) + 1)
    (entry_config 1 (5 :: left)
       (map match_raw src ++ 4 ::
        (tl (book_marked_prefix failed ++ [4]) ++
         map match_mark src ++
         map source_bit (br_action hit) ++
         source_bit (br_dir hit) :: book_raw_tail after ++ 5 :: tail))) =
    entry_config 6
      (4 :: rev (map source_bit src) ++
       5 :: left)
      (tl (book_marked_prefix failed ++ [4]) ++
       map match_mark src ++
       map source_bit (br_action hit) ++
       source_bit (br_dir hit) :: book_raw_tail after ++ 5 :: tail)).
  rewrite (q1_scan_four_list_to_q6_cons (map match_raw src)
    (tl (book_marked_prefix failed ++ [4]) ++
     map match_mark src ++
     map source_bit (br_action hit) ++
     source_bit (br_dir hit) :: book_raw_tail after ++ 5 :: tail)
    (5 :: left)
    (match_raw_valid src)).
  cbn [app].
  replace (map match_raw src) with (map source_bit src)
    by apply map_match_raw_source_bit.
  reflexivity.
Qed.

Print Assumptions book_locate_hit_row_wide.

Theorem book_locate_rows_to_q6_wide :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (hit : book_row) (after : list book_row) (left tail : list nat),
    Forall (fun st => bf_src st = src) steps ->
    br_cond hit = src ->
    run (book_failures_clock failed steps +
         book_hit_clock src (failed ++ map bf_row steps))
      (book_locate_state_wide src failed (map bf_row steps ++ hit :: after)
         left tail)
    = entry_config 6
        (4 :: rev (map source_bit src) ++
         5 :: left)
        (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
         map match_mark src ++
         map source_bit (br_action hit) ++
         [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail).
Proof.
  intros src failed steps hit after left tail Hsteps Hcond.
  rewrite (dispatch_run_add (book_failures_clock failed steps)
    (book_hit_clock src (failed ++ map bf_row steps))).
  rewrite (book_locate_failed_rows_wide src failed steps hit after
    left tail Hsteps).
  apply (book_locate_hit_row_wide src (failed ++ map bf_row steps) hit after
    left tail Hcond).
Qed.

Print Assumptions book_locate_rows_to_q6_wide.

Lemma book_locate_last_mismatch_halt_wide :
  forall (failed : list book_row) (step : book_failure) (left tail : list nat),
    run (book_halt_clock failed step)
      (book_locate_state_wide (bf_src step) failed [bf_row step] left tail)
    = dispatch_halt_at_y
        (rev (map source_bit (bf_row_rest step) ++
              map source_bit (br_action (bf_row step)) ++
              [source_bit (br_dir (bf_row step))]) ++
         match_mark (negb (bf_bit step)) ::
         rev (map match_mark (bf_src_rest step) ++
              (book_marked_prefix failed ++ [4]) ++
              map match_mark (bf_good step)) ++
         match_raw (bf_bit step) :: rev (map match_raw (bf_good step)) ++
         5 :: left)
        tail.
Proof.
  intros failed step left tail.
  unfold book_halt_clock.
  unfold book_locate_state_wide.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  cbn [book_raw_tail].
  rewrite app_nil_r.
  unfold book_raw_row.
  rewrite (bf_src_split step).
  rewrite (bf_row_split step).
  assert (Hframe1 :
    entry_config 1 (5 :: left)
      (map match_mark (bf_good step ++ bf_bit step :: bf_src_rest step) ++
       book_marked_prefix failed ++
       ((4 :: (map source_bit
                 (bf_good step ++ negb (bf_bit step) :: bf_row_rest step) ++
               map source_bit (br_action (bf_row step)) ++
               [source_bit (br_dir (bf_row step))])) ++ 5 :: tail))
    = entry_config 1 (5 :: left)
      (map match_mark (bf_good step) ++
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
    (matched_comparison_steps (bf_good step) 0
       (length (map match_mark (bf_bit step :: bf_src_rest step) ++
                (book_marked_prefix failed ++ [4]))))
    (book_mismatch_halt_clock (bf_bit step) (bf_good step)
       (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
       (br_dir (bf_row step)) (book_marked_prefix failed ++ [4]))).
  rewrite (q1_all_matching_bits_wide_zero (bf_good step)
    (map match_mark (bf_bit step :: bf_src_rest step) ++
     (book_marked_prefix failed ++ [4]))
    left
    (match_raw (negb (bf_bit step)) ::
     map source_bit (bf_row_rest step) ++
     map source_bit (br_action (bf_row step)) ++
     [source_bit (br_dir (bf_row step))] ++ 5 :: tail)
    (wide_mark_failure_done (bf_bit step) (bf_src_rest step) failed)).
  cbn [app].
  assert (Hframe2 :
    entry_config 1 (5 :: left)
      (map match_raw (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       source_bit (br_dir (bf_row step)) :: 5 :: tail)
    = entry_config 1 (5 :: left)
      (map match_raw (bf_good step) ++ match_mark (bf_bit step) ::
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
  rewrite (book_q1_mismatch_halt_gen (bf_bit step) (bf_good step)
    (bf_src_rest step) (bf_row_rest step) (br_action (bf_row step))
    (br_dir (bf_row step)) (book_marked_prefix failed ++ [4])
    left tail
    (Forall_wide_mark_marked_prefix_snoc failed)).
  reflexivity.
Qed.

Print Assumptions book_locate_last_mismatch_halt_wide.

Theorem book_locate_rows_to_halt_wide :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (last : book_failure) (left tail : list nat),
    Forall (fun st => bf_src st = src) (steps ++ [last]) ->
    run (book_failures_clock failed steps +
         book_halt_clock (failed ++ map bf_row steps) last)
      (book_locate_state_wide src failed (map bf_row (steps ++ [last]))
         left tail)
    = dispatch_halt_at_y
        (rev (map source_bit (bf_row_rest last) ++
              map source_bit (br_action (bf_row last)) ++
              [source_bit (br_dir (bf_row last))]) ++
         match_mark (negb (bf_bit last)) ::
         rev (map match_mark (bf_src_rest last) ++
              ((book_marked_prefix (failed ++ map bf_row steps)) ++ [4]) ++
              map match_mark (bf_good last)) ++
         match_raw (bf_bit last) :: rev (map match_raw (bf_good last)) ++
         5 :: left)
        tail.
Proof.
  intros src failed steps last left tail Hsteps.
  rewrite map_app. cbn [map].
  rewrite (dispatch_run_add (book_failures_clock failed steps)
    (book_halt_clock (failed ++ map bf_row steps) last)).
  assert (Hsteps' : Forall (fun st => bf_src st = src) steps).
  { apply Forall_app in Hsteps. destruct Hsteps as [H _]. exact H. }
  assert (Hlast : bf_src last = src).
  { apply Forall_app in Hsteps. destruct Hsteps as [_ H].
    apply Forall_inv in H. exact H. }
  rewrite (book_locate_failed_rows_wide src failed steps (bf_row last) []
    left tail Hsteps').
  assert (Hsrc : src = bf_src last) by (symmetry; exact Hlast).
  rewrite Hsrc.
  apply (book_locate_last_mismatch_halt_wide (failed ++ map bf_row steps)
    last left tail).
Qed.

Print Assumptions book_locate_rows_to_halt_wide.
