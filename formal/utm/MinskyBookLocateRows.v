(** * Book-layout multi-row locate phase

    This module generalizes [book_locate_two_rows_to_q6] from
    [MinskyBookLocate.v] to arbitrary finite row lists.

    A description row is

      X  condition  action  direction

    and the raw description after the first [X] is

      raw_row r1  X  raw_row r2  X  ...  raw_row rn  Y  tail.

    The state

      book_locate_state src failed rest buf ptape tail

    is the q1 locate state after the rows in [failed] have been tried and
    marked.  Its tape is

      ptape  M  book_buf buf  Y  marks(src)
        [X marked_row r1] ... [X marked_row rk]
        X raw_row r_{k+1} ... X raw_row rn  Y  tail

    where [failed] = [r1;...;rk] and [rest] = [r_{k+1};...;rn].
    The head is on the first cell after [Y], i.e. on [marks(src)].

    Two transitions are proved:

    - [book_locate_failed_row]: the head row of [rest] mismatches after
      an arbitrary matching prefix.  q1/q0/q4 reach the X after that
      row, q3/q5 mark the whole traversed region and return to q1.
      The state becomes [book_locate_state src (failed ++ [row]) rest'].

    - [book_locate_hit_row]: the head row matches [src].  q1/q0/q4
      match it across all failed-row marks, q1 crosses the first X and
      enters q6.

    Iterating the first transition over a list of failures and then
    applying the second gives [book_locate_rows_to_q6].  If the *last*
    row mismatches, q3 reaches the final [Y] directly and the machine
    halts; this is [book_locate_rows_to_halt].

    A separate adapter [book_q5_steady_to_locate_state] consumes the
    steady-state q5 frame produced by the perform cycle
    [book_q6_to_q5_right] and returns the same q1 locate state. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry MinskyConcreteDispatch
  MinskySourceEncoding MinskyMatchMacro MinskyCanonicalMatch
  MinskyActionMacro MinskyCanonicalCopy MinskyCanonicalCopyGeneral
  MinskyCanonicalDirection MinskyCanonicalInstruction MinskyHeadMoveMacro
  MinskyBookLayout MinskyBookCycle MinskyBookLocate.

(** ** Row-list frames *)

Record book_row : Type := {
  br_cond : list bool;
  br_action : list bool;
  br_dir : bool
}.

Definition book_marked_row (r : book_row) : list nat :=
  map match_mark (br_cond r) ++ map match_mark (br_action r) ++
  [match_mark (br_dir r)].

Definition book_raw_row (r : book_row) : list nat :=
  map source_bit (br_cond r) ++ map source_bit (br_action r) ++
  [source_bit (br_dir r)].

(** Marked rows with the [X] that precedes each row.  Thus
    [book_marked_prefix [r1;r2]] = X marked(r1) X marked(r2). *)
Fixpoint book_marked_prefix (rows : list book_row) : list nat :=
  match rows with
  | [] => []
  | r :: rest => 4 :: book_marked_row r ++ book_marked_prefix rest
  end.

(** Raw rows with the [X] that precedes each row *after the first*.
    [book_raw_desc [r1;r2]] = raw(r1) X raw(r2). *)
Fixpoint book_raw_desc (rows : list book_row) : list nat :=
  match rows with
  | [] => []
  | r :: rest =>
      book_raw_row r ++
      match rest with
      | [] => []
      | _ => 4 :: book_raw_desc rest
      end
  end.

(** The [X] preceding the rows of [rows], when nonempty. *)
Definition book_raw_tail (rows : list book_row) : list nat :=
  match rows with
  | [] => []
  | _ => 4 :: book_raw_desc rows
  end.

Lemma book_raw_desc_cons :
  forall r rest,
    book_raw_desc (r :: rest) = book_raw_row r ++ book_raw_tail rest.
Proof.
  intros r rest. simpl. destruct rest; reflexivity.
Qed.

Lemma book_raw_tail_cons :
  forall r rest,
    book_raw_tail (r :: rest) = 4 :: book_raw_desc (r :: rest).
Proof. intros. reflexivity. Qed.

Definition book_locate_state
    (src : list bool) (failed rest : list book_row)
    (buf : nat) (ptape tail : list nat) : Config :=
  entry_config 1
    (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
    (map match_mark src ++ book_marked_prefix failed ++
     book_raw_tail rest ++ 5 :: tail).

(** ** Passability of the marked prefix *)

Lemma q5_pass_wide :
  forall s, wide_mark s -> q5_pass s.
Proof.
  intros s [-> | [-> | [-> | [-> | ->]]]];
    unfold q5_pass; auto 12.
Qed.

Lemma Forall_q5_pass_wide :
  forall l, Forall wide_mark l -> Forall q5_pass l.
Proof.
  intros l H. induction H as [|s rest Hs Hrest IH].
  - constructor.
  - constructor; [apply q5_pass_wide; exact Hs | exact IH].
Qed.

Lemma entry_rewrite_wide :
  forall s, wide_mark s -> entry_rewrite s = s.
Proof.
  intros s [-> | [-> | [-> | [-> | ->]]]]; reflexivity.
Qed.

Lemma map_entry_rewrite_wide :
  forall l, Forall wide_mark l -> map entry_rewrite l = l.
Proof.
  intros l H. induction H as [|s rest Hs Hrest IH].
  - reflexivity.
  - simpl. rewrite entry_rewrite_wide by exact Hs. rewrite IH. reflexivity.
Qed.

Lemma wide_mark_book_marked_row :
  forall r, Forall wide_mark (book_marked_row r).
Proof.
  intros r. unfold book_marked_row.
  repeat rewrite Forall_app. repeat split.
  - apply wide_mark_map_match_marks.
  - apply wide_mark_map_match_marks.
  - constructor; [apply wide_mark_match_mark | constructor].
Qed.

Lemma wide_mark_book_marked_prefix :
  forall rows, Forall wide_mark (book_marked_prefix rows).
Proof.
  induction rows as [|r rest IH]; simpl.
  - constructor.
  - constructor.
    + apply wide_mark_four.
    + apply Forall_app. split.
      * apply wide_mark_book_marked_row.
      * exact IH.
Qed.

Lemma q5_pass_book_marked_prefix :
  forall rows, Forall q5_pass (book_marked_prefix rows).
Proof.
  intros. apply Forall_q5_pass_wide, wide_mark_book_marked_prefix.
Qed.

(** ** Generalized first-row mismatch restart

    [done] is the already-marked region before the current row, including
    the [X] that precedes it.  The only requirement is that it is built
    from [wide_mark] symbols (2/3/4/6/7), which is true for every marked
    failed-row prefix. *)

Definition book_mismatch_scan_gen
    (b : bool) (good restbits row1_rest action1 : list bool)
    (dir1 : bool) (done : list nat) : list nat :=
  let marked := map match_mark restbits ++ done ++ map match_mark good in
  let row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1] in
  rev row_rest ++ match_mark (negb b) :: rev marked ++
  match_raw b :: rev (map match_raw good).

Definition book_mismatch_clock_gen
    (b : bool) (good restbits row1_rest action1 : list bool)
    (dir1 : bool) (done : list nat) : nat :=
  S (length (map match_raw good)) +
  (S (length (map match_mark restbits ++ done ++ map match_mark good)) +
   ((length (map source_bit row1_rest ++
             map source_bit action1 ++ [source_bit dir1]) + 1) +
    S (length (book_mismatch_scan_gen b good restbits row1_rest action1 dir1 done)))).

Lemma book_mismatch_scan_gen_nonempty :
  forall b good restbits row1_rest action1 dir1 done,
    book_mismatch_scan_gen b good restbits row1_rest action1 dir1 done <> [].
Proof.
  intros b good restbits row1_rest action1 dir1 done.
  unfold book_mismatch_scan_gen.
  intro H.
  assert (Hlen := f_equal (@length nat) H).
  rewrite app_length in Hlen.
  cbn [length] in Hlen.
  lia.
Qed.

Lemma q5_pass_rev_wide :
  forall l, Forall wide_mark l -> Forall q5_pass (rev l).
Proof.
  intros l H. apply Forall_rev, Forall_q5_pass_wide. exact H.
Qed.

Lemma q5_pass_row_rest :
  forall row1_rest action1 (dir1 : bool),
    Forall q5_pass
      (map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
Proof.
  intros row1_rest action1 dir1.
  repeat rewrite Forall_app.
  repeat split.
  - apply q5_pass_source_bits.
  - apply q5_pass_source_bits.
  - destruct dir1; unfold q5_pass, source_bit; auto 10.
Qed.

Lemma rev_book_mismatch_scan_gen :
  forall b good restbits row1_rest action1 dir1 done,
    rev (book_mismatch_scan_gen b good restbits row1_rest action1 dir1 done)
    = map match_raw good ++ match_raw b ::
      (map match_mark restbits ++ done ++ map match_mark good) ++
      match_mark (negb b) ::
      (map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
Proof.
  intros b good restbits row1_rest action1 dir1 done.
  unfold book_mismatch_scan_gen.
  cbn zeta.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  rewrite !rev_involutive.
  cbn [rev app].
  repeat rewrite <- app_assoc.
  cbn [app].
  reflexivity.
Qed.

Lemma book_mismatch_scan_gen_valid :
  forall b good restbits row1_rest action1 dir1 done,
    Forall wide_mark done ->
    Forall q5_pass
      (book_mismatch_scan_gen b good restbits row1_rest action1 dir1 done).
Proof.
  intros b good restbits row1_rest action1 dir1 done Hdone.
  rewrite <- rev_involutive.
  apply Forall_rev.
  rewrite rev_book_mismatch_scan_gen.
  apply Forall_app. split.
  - apply q5_raw_bits.
  - constructor.
    + apply q5_pass_match_raw.
    + apply Forall_app. split.
      * apply Forall_app. split.
        -- apply q5_marked_bits.
        -- apply Forall_app. split.
           ++ apply Forall_q5_pass_wide. exact Hdone.
           ++ apply q5_marked_bits.
      * constructor.
        -- apply q5_pass_match_mark.
        -- apply q5_pass_row_rest.
Qed.

Lemma entry_rewrite_wide_cons :
  forall s l, wide_mark s ->
    map entry_rewrite (s :: l) = s :: map entry_rewrite l.
Proof.
  intros s l Hs. simpl. rewrite entry_rewrite_wide by exact Hs. reflexivity.
Qed.

Lemma map_entry_rewrite_book_mismatch_scan_gen :
  forall b good restbits row1_rest action1 dir1 done,
    Forall wide_mark done ->
    let marked := map match_mark restbits ++ done ++ map match_mark good in
    let row_rest :=
      map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1] in
    map entry_rewrite
      (rev (rev row_rest ++ match_mark (negb b) :: rev marked ++
            match_raw b :: rev (map match_raw good)))
    = map match_mark (good ++ b :: restbits) ++ done ++
      map match_mark (good ++ negb b :: row1_rest) ++
      map match_mark action1 ++ [match_mark dir1].
Proof.
  intros b good restbits row1_rest action1 dir1 done Hdone.
  cbn zeta.
  set (row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
  set (marked := map match_mark restbits ++ done ++ map match_mark good).
  rewrite rev_app_distr.
  cbn [rev].
  rewrite rev_involutive.
  rewrite rev_app_distr.
  cbn [rev].
  rewrite rev_involutive.
  repeat rewrite map_app.
  cbn [map].
  rewrite !rev_involutive.
  rewrite map_entry_rewrite_match_raws.
  rewrite entry_rewrite_match_raw.
  unfold marked.
  repeat rewrite map_app.
  cbn [map].
  rewrite map_entry_rewrite_match_marks.
  rewrite map_entry_rewrite_wide by exact Hdone.
  rewrite map_entry_rewrite_match_marks.
  rewrite entry_rewrite_match_mark.
  unfold row_rest.
  rewrite map_entry_rewrite_row_rest.
  repeat rewrite <- app_assoc.
  cbn [app].
  reflexivity.
Qed.

Lemma book_q1_mismatch_restart_gen :
  forall (b : bool) (good restbits row1_rest action1 : list bool) (dir1 : bool)
         (done : list nat) (afterX prefix : list nat),
    Forall wide_mark done ->
    run (book_mismatch_clock_gen b good restbits row1_rest action1 dir1 done)
      (entry_config 1 (5 :: prefix)
        (map match_raw good ++ match_mark b ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw (negb b) :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map match_mark (good ++ b :: restbits) ++ done ++
       map match_mark (good ++ negb b :: row1_rest) ++
       map match_mark action1 ++ [match_mark dir1] ++ 4 :: afterX).
Proof.
  intros b good restbits row1_rest action1 dir1 done afterX prefix Hdone.
  set (row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
  set (marked := map match_mark restbits ++ done ++ map match_mark good).
  set (scan := rev row_rest ++ match_mark (negb b) :: rev marked ++
               match_raw b :: rev (map match_raw good)).
  assert (Hne : scan <> []).
  { subst scan. unfold row_rest, marked.
    apply book_mismatch_scan_gen_nonempty. }
  destruct scan as [|s remaining] eqn:Hscan.
  - exfalso. apply Hne. reflexivity.
  - assert (Hq5 : Forall q5_pass (s :: remaining)).
    { rewrite <- Hscan.
      unfold scan, row_rest, marked.
      apply book_mismatch_scan_gen_valid. exact Hdone. }
    assert (Hsplit :
      rev row_rest ++ match_mark (negb b) :: rev marked ++
      match_raw b :: rev (map match_raw good) ++ 5 :: prefix =
      (s :: remaining) ++ 5 :: prefix).
    { rewrite <- Hscan.
      unfold scan.
      cbn [rev app].
      repeat rewrite <- app_assoc.
      cbn [app].
      repeat rewrite <- app_assoc.
      cbn [app].
      reflexivity. }
    assert (Hclock :
      book_mismatch_clock_gen b good restbits row1_rest action1 dir1 done =
      S (length (map match_raw good)) +
      (S (length marked) +
       ((length row_rest + 1) + S (length (s :: remaining))))).
    { unfold book_mismatch_clock_gen, book_mismatch_scan_gen.
      cbn zeta.
      fold marked. fold row_rest. fold scan.
      rewrite Hscan. reflexivity. }
    rewrite Hclock.
    destruct b.
    + (* b = true: selected mark 3, mismatching raw 0 *)
      cbn [negb].
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
        repeat rewrite Forall_app.
        repeat split.
        - apply source_bit_list_is_right_scannable.
        - apply source_bit_list_is_right_scannable.
        - constructor;
            [apply source_bit_is_right_symbol | constructor]. }
      assert (Hentry :
        (map match_raw good ++ match_mark true ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw false :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 4 :: afterX)
        = (map match_raw good ++ 3 :: marked ++
           0 :: row_rest ++ 4 :: afterX)).
      { cbn [match_mark match_raw]. unfold marked, row_rest.
        repeat rewrite <- app_assoc. cbn [app].
        repeat rewrite <- app_assoc. cbn [app].
        reflexivity. }
      rewrite Hentry.
      eapply eq_trans.
      * eapply (q1_one_mismatch_restart
          (map match_raw good) marked row_rest s remaining prefix afterX).
        -- apply match_raw_valid.
        -- exact Hmarked.
        -- exact Hright.
        -- cbn [negb]. exact Hsplit.
        -- exact Hq5.
      * rewrite <- Hscan.
        unfold scan, row_rest, marked.
        rewrite map_entry_rewrite_book_mismatch_scan_gen by exact Hdone.
        repeat rewrite <- app_assoc.
        cbn [app].
        reflexivity.
    + (* b = false: selected mark 2, mismatching raw 1 *)
      cbn [negb].
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
        repeat rewrite Forall_app.
        repeat split.
        - apply source_bit_list_is_right_scannable.
        - apply source_bit_list_is_right_scannable.
        - constructor;
            [apply source_bit_is_right_symbol | constructor]. }
      assert (Hentry :
        (map match_raw good ++ match_mark false ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw true :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 4 :: afterX)
        = (map match_raw good ++ 2 :: marked ++
           1 :: row_rest ++ 4 :: afterX)).
      { cbn [match_mark match_raw]. unfold marked, row_rest.
        repeat rewrite <- app_assoc. cbn [app].
        repeat rewrite <- app_assoc. cbn [app].
        reflexivity. }
      rewrite Hentry.
      eapply eq_trans.
      * eapply (q1_zero_mismatch_restart
          (map match_raw good) marked row_rest s remaining prefix afterX).
        -- apply match_raw_valid.
        -- exact Hmarked.
        -- exact Hright.
        -- cbn [negb]. exact Hsplit.
        -- exact Hq5.
      * rewrite <- Hscan.
        unfold scan, row_rest, marked.
        rewrite map_entry_rewrite_book_mismatch_scan_gen by exact Hdone.
        repeat rewrite <- app_assoc.
        cbn [app].
        reflexivity.
Qed.

Print Assumptions book_q1_mismatch_restart_gen.

(** ** Generalized last-row mismatch -> halt

    If the mismatching row is the last row, the q3 dispatch reaches the
    final [Y] instead of an [X].  The table's [q3/Y] entry is the unique
    halting transition, so the run ends in [dispatch_halt_at_y]. *)

Definition book_mismatch_halt_clock
    (b : bool) (good restbits row1_rest action1 : list bool)
    (dir1 : bool) (done : list nat) : nat :=
  S (length (map match_raw good)) +
  (S (length (map match_mark restbits ++ done ++ map match_mark good)) +
   (length (map source_bit row1_rest ++
           map source_bit action1 ++ [source_bit dir1]) + 1)).

Lemma book_q1_mismatch_halt_gen :
  forall (b : bool) (good restbits row1_rest action1 : list bool)
         (dir1 : bool) (done : list nat) (prefix tail : list nat),
    Forall wide_mark done ->
    run (book_mismatch_halt_clock b good restbits row1_rest action1 dir1 done)
      (entry_config 1 (5 :: prefix)
        (map match_raw good ++ match_mark b ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw (negb b) :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 5 :: tail)) =
    dispatch_halt_at_y
      (rev (map source_bit row1_rest ++ map source_bit action1 ++
            [source_bit dir1]) ++
       match_mark (negb b) ::
       rev (map match_mark restbits ++ done ++ map match_mark good) ++
       match_raw b :: rev (map match_raw good) ++ 5 :: prefix) tail.
Proof.
  intros b good restbits row1_rest action1 dir1 done prefix tail Hdone.
  set (row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
  set (marked := map match_mark restbits ++ done ++ map match_mark good).
  assert (Hwide : Forall wide_mark marked).
  { subst marked. repeat rewrite Forall_app. repeat split.
    - apply wide_mark_map_match_marks.
    - exact Hdone.
    - apply wide_mark_map_match_marks. }
  assert (Hq0 : Forall q0_pass marked).
  { exact (proj1 (wide_mark_scans _ Hwide)). }
  assert (Hq4 : Forall q4_pass marked).
  { exact (proj1 (proj2 (wide_mark_scans _ Hwide))). }
  assert (Hright : Forall dispatch_right_symbol row_rest).
  { subst row_rest.
    repeat rewrite Forall_app.
    repeat split.
    - apply source_bit_list_is_right_scannable.
    - apply source_bit_list_is_right_scannable.
    - constructor; [apply source_bit_is_right_symbol | constructor]. }
  assert (Hclock :
    book_mismatch_halt_clock b good restbits row1_rest action1 dir1 done =
    S (length (map match_raw good)) +
    (S (length marked) + (length row_rest + 1))).
  { unfold book_mismatch_halt_clock.
    fold marked. fold row_rest. reflexivity. }
  rewrite Hclock.
  destruct b.
  + (* b = true: q1 picks 3, q4 sees raw 0, q3 halts at Y *)
    cbn [negb].
    assert (Hentry :
      (map match_raw good ++ match_mark true ::
       map match_mark restbits ++ done ++ map match_mark good ++
       match_raw false :: map source_bit row1_rest ++
       map source_bit action1 ++ [source_bit dir1] ++ 5 :: tail)
      = (map match_raw good ++ 3 :: marked ++
         0 :: row_rest ++ 5 :: tail)).
    { cbn [match_mark match_raw]. unfold marked, row_rest.
      repeat rewrite <- app_assoc. cbn [app].
      repeat rewrite <- app_assoc. cbn [app].
      reflexivity. }
    rewrite Hentry.
    rewrite (dispatch_run_add (S (length (map match_raw good)))
      (S (length marked) + (length row_rest + 1))
      (entry_config 1 (5 :: prefix)
        (map match_raw good ++ 3 :: marked ++ 0 :: row_rest ++ 5 :: tail))).
    rewrite (q1_scan_pick (map match_raw good) (5 :: prefix) 3
      (marked ++ 0 :: row_rest ++ 5 :: tail)
      (match_raw_valid good) (or_intror (or_introl eq_refl))).
    rewrite (dispatch_run_add (S (length marked)) (length row_rest + 1)
      (entry_config 4 (1 :: rev (map match_raw good) ++ 5 :: prefix)
        (marked ++ 0 :: row_rest ++ 5 :: tail))).
    rewrite (q4_scan_zero marked
      (1 :: rev (map match_raw good) ++ 5 :: prefix)
      (row_rest ++ 5 :: tail) Hq4).
    rewrite (dispatch_right_halts_at_delimiter row_rest
      (2 :: rev marked ++ 1 :: rev (map match_raw good) ++ 5 :: prefix)
      tail Hright).
    reflexivity.
  + (* b = false: q1 picks 2, q0 sees raw 1, q3 halts at Y *)
    cbn [negb].
    assert (Hentry :
      (map match_raw good ++ match_mark false ::
       map match_mark restbits ++ done ++ map match_mark good ++
       match_raw true :: map source_bit row1_rest ++
       map source_bit action1 ++ [source_bit dir1] ++ 5 :: tail)
      = (map match_raw good ++ 2 :: marked ++
         1 :: row_rest ++ 5 :: tail)).
    { cbn [match_mark match_raw]. unfold marked, row_rest.
      repeat rewrite <- app_assoc. cbn [app].
      repeat rewrite <- app_assoc. cbn [app].
      reflexivity. }
    rewrite Hentry.
    rewrite (dispatch_run_add (S (length (map match_raw good)))
      (S (length marked) + (length row_rest + 1))
      (entry_config 1 (5 :: prefix)
        (map match_raw good ++ 2 :: marked ++ 1 :: row_rest ++ 5 :: tail))).
    rewrite (q1_scan_pick (map match_raw good) (5 :: prefix) 2
      (marked ++ 1 :: row_rest ++ 5 :: tail)
      (match_raw_valid good) (or_introl eq_refl)).
    rewrite (dispatch_run_add (S (length marked)) (length row_rest + 1)
      (entry_config 0 (0 :: rev (map match_raw good) ++ 5 :: prefix)
        (marked ++ 1 :: row_rest ++ 5 :: tail))).
    rewrite (q0_scan_one marked
      (0 :: rev (map match_raw good) ++ 5 :: prefix)
      (row_rest ++ 5 :: tail) Hq0).
    rewrite (dispatch_right_halts_at_delimiter row_rest
      (3 :: rev marked ++ 0 :: rev (map match_raw good) ++ 5 :: prefix)
      tail Hright).
    reflexivity.
Qed.

Print Assumptions book_q1_mismatch_halt_gen.

(** ** Failure witness and one-row step *)

Record book_failure : Type := {
  bf_src : list bool;
  bf_row : book_row;
  bf_good : list bool;
  bf_bit : bool;
  bf_src_rest : list bool;
  bf_row_rest : list bool;
  bf_src_split : bf_src = bf_good ++ bf_bit :: bf_src_rest;
  bf_row_split : br_cond bf_row = bf_good ++ negb bf_bit :: bf_row_rest
}.

Definition book_failure_clock
    (failed : list book_row) (step : book_failure) : nat :=
  matched_comparison_steps (bf_good step) 0
    (length (map match_mark (bf_bit step :: bf_src_rest step) ++
             (book_marked_prefix failed ++ [4]))) +
  book_mismatch_clock_gen (bf_bit step) (bf_good step) (bf_src_rest step)
    (bf_row_rest step) (br_action (bf_row step)) (br_dir (bf_row step))
    (book_marked_prefix failed ++ [4]).

Lemma book_marked_prefix_snoc :
  forall rows r,
    book_marked_prefix (rows ++ [r]) =
    book_marked_prefix rows ++ 4 :: book_marked_row r.
Proof.
  induction rows as [|r rest IH]; intros r0.
  - cbn [book_marked_prefix app]. rewrite app_nil_r. reflexivity.
  - change (book_marked_prefix (r :: (rest ++ [r0])) =
            (4 :: book_marked_row r ++ book_marked_prefix rest) ++
            4 :: book_marked_row r0).
    cbn [book_marked_prefix].
    rewrite IH.
    repeat rewrite <- app_assoc.
    cbn [app].
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity.
Qed.

Lemma Forall_wide_mark_marked_prefix_snoc :
  forall (rows : list book_row),
    Forall wide_mark (book_marked_prefix rows ++ [4]).
Proof.
  intros. apply Forall_app. split.
  - apply wide_mark_book_marked_prefix.
  - constructor; [apply wide_mark_four | constructor].
Qed.

Lemma wide_mark_failure_done :
  forall (b : bool) (src_rest : list bool) (failed : list book_row),
    Forall wide_mark
      (map match_mark (b :: src_rest) ++
       (book_marked_prefix failed ++ [4])).
Proof.
  intros. apply Forall_app. split.
  - apply wide_mark_map_match_marks.
  - apply Forall_wide_mark_marked_prefix_snoc.
Qed.

Lemma book_locate_failed_row :
  forall (failed : list book_row) (step : book_failure)
         (next : book_row) (rest : list book_row) (buf : nat)
         (ptape tail : list nat),
    run (book_failure_clock failed step)
      (book_locate_state (bf_src step) failed
         (bf_row step :: next :: rest) buf ptape tail)
    = book_locate_state (bf_src step) (failed ++ [bf_row step])
        (next :: rest) buf ptape tail.
Proof.
  intros failed step next rest buf ptape tail.
  unfold book_failure_clock.
  unfold book_locate_state.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  unfold book_raw_row.
  rewrite (bf_src_split step).
  rewrite (bf_row_split step).
  (* First compare the matched prefix [good]. *)
  assert (Hframe1 :
    entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
      (map match_mark (bf_good step ++ bf_bit step :: bf_src_rest step) ++
       book_marked_prefix failed ++
       ((4 :: (((map source_bit
                   (bf_good step ++ negb (bf_bit step) :: bf_row_rest step)) ++
                 (map source_bit (br_action (bf_row step)) ++
                  [source_bit (br_dir (bf_row step))])) ++
                book_raw_tail (next :: rest))) ++ 5 :: tail))
    = entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
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
    (rev (book_buf buf) ++ 6 :: rev ptape)
    (match_raw (negb (bf_bit step)) ::
     map source_bit (bf_row_rest step) ++
     map source_bit (br_action (bf_row step)) ++
     [source_bit (br_dir (bf_row step))] ++
     4 :: book_raw_desc (next :: rest) ++ 5 :: tail)
    (wide_mark_failure_done (bf_bit step) (bf_src_rest step) failed)).
  cbn [app].
  (* Now restart on the first mismatch. *)
  assert (Hframe2 :
    entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
      (map match_raw (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       source_bit (br_dir (bf_row step)) ::
       4 :: book_raw_desc (next :: rest) ++ 5 :: tail)
    = entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
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
    (rev (book_buf buf) ++ 6 :: rev ptape)
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

Print Assumptions book_locate_failed_row.

(** ** Iterating the failure step *)

Fixpoint book_failures_clock
    (failed : list book_row) (steps : list book_failure) : nat :=
  match steps with
  | [] => 0
  | st :: rest =>
      book_failure_clock failed st +
      book_failures_clock (failed ++ [bf_row st]) rest
  end.

Lemma cons_app_assoc :
  forall (l : list book_row) r (rest : list book_row),
    l ++ r :: rest = (l ++ [r]) ++ rest.
Proof.
  intros. change (l ++ ([r] ++ rest) = (l ++ [r]) ++ rest).
  rewrite app_assoc. reflexivity.
Qed.

Lemma book_locate_failed_rows :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (next : book_row) (rest : list book_row) (buf : nat)
         (ptape tail : list nat),
    Forall (fun st => bf_src st = src) steps ->
    run (book_failures_clock failed steps)
      (book_locate_state src failed (map bf_row steps ++ next :: rest)
         buf ptape tail)
    = book_locate_state src (failed ++ map bf_row steps) (next :: rest)
        buf ptape tail.
Proof.
  intros src failed steps.
  revert failed.
  induction steps as [|st steps IH];
    intros failed next rest buf ptape tail Hsteps.
  - cbn [book_failures_clock map app run].
    rewrite app_nil_r.
    reflexivity.
  - inversion Hsteps as [|? ? Hst Hrest]; subst.
    destruct steps as [|st' steps'].
    + (* only [next] remains after the head failure *)
      cbn [book_failures_clock map app].
      rewrite Nat.add_0_r.
      rewrite (book_locate_failed_row failed st next rest buf ptape tail).
      reflexivity.
    + (* another failure follows *)
      cbn [book_failures_clock map app].
      rewrite (dispatch_run_add
        (book_failure_clock failed st)
        (book_failures_clock (failed ++ [bf_row st]) (st' :: steps'))).
      rewrite (book_locate_failed_row failed st (bf_row st')
        (map bf_row steps' ++ next :: rest) buf ptape tail).
      replace (failed ++ (bf_row st :: (bf_row st' :: map bf_row steps')))
        with ((failed ++ [bf_row st]) ++
              (bf_row st' :: map bf_row steps'))
        by (symmetry; apply cons_app_assoc).
      change (run (book_failures_clock (failed ++ [bf_row st])
                     (st' :: steps'))
        (book_locate_state (bf_src st) (failed ++ [bf_row st])
           (map bf_row (st' :: steps') ++ next :: rest) buf ptape tail) =
        book_locate_state (bf_src st)
          ((failed ++ [bf_row st]) ++ map bf_row (st' :: steps'))
          (next :: rest) buf ptape tail).
      rewrite (IH (failed ++ [bf_row st]) next rest buf ptape tail Hrest).
      cbn [map app].
      repeat rewrite <- app_assoc.
      reflexivity.
Qed.

Print Assumptions book_locate_failed_rows.

(** ** Successful match step and the row-list locate theorem *)

Lemma book_marked_done_cons :
  forall failed,
    book_marked_prefix failed ++ [4] =
    4 :: tl (book_marked_prefix failed ++ [4]).
Proof.
  intros failed. destruct failed as [|r rest]; reflexivity.
Qed.

Definition book_hit_clock (src : list bool) (failed : list book_row) : nat :=
  matched_comparison_steps src 0
    (length (book_marked_prefix failed ++ [4])) +
  (length src + 1).

Lemma book_locate_hit_row :
  forall (src : list bool) (failed : list book_row) (hit : book_row)
         (after : list book_row) (buf : nat) (ptape tail : list nat),
    br_cond hit = src ->
    run (book_hit_clock src failed)
      (book_locate_state src failed (hit :: after) buf ptape tail)
    = entry_config 6
        (4 :: rev (map source_bit src) ++
         5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
        (tl (book_marked_prefix failed ++ [4]) ++
         map match_mark src ++
         map source_bit (br_action hit) ++
         [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail).
Proof.
  intros src failed hit after buf ptape tail Hcond.
  unfold book_hit_clock.
  unfold book_locate_state.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  unfold book_raw_row.
  rewrite Hcond.
  assert (Hframe1 :
    entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
      (map match_mark src ++
       (book_marked_prefix failed ++
        ((4 :: (((map source_bit src) ++
                  (map source_bit (br_action hit) ++
                   [source_bit (br_dir hit)])) ++
                 book_raw_tail after)) ++ 5 :: tail)))
    = entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
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
    (rev (book_buf buf) ++ 6 :: rev ptape)
    (map source_bit (br_action hit) ++
     [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail)
    (Forall_wide_mark_marked_prefix_snoc failed)).
  cbn [app].
  rewrite book_marked_done_cons.
  replace (length src + 1)
    with (length (map match_raw src) + 1)
    by (rewrite map_length; reflexivity).
  change (run (length (map match_raw src) + 1)
    (entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
       (map match_raw src ++ 4 ::
        (tl (book_marked_prefix failed ++ [4]) ++
         map match_mark src ++
         map source_bit (br_action hit) ++
         source_bit (br_dir hit) :: book_raw_tail after ++ 5 :: tail))) =
    entry_config 6
      (4 :: rev (map source_bit src) ++
       5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
      (tl (book_marked_prefix failed ++ [4]) ++
       map match_mark src ++
       map source_bit (br_action hit) ++
       source_bit (br_dir hit) :: book_raw_tail after ++ 5 :: tail)).
  rewrite (q1_scan_four_list_to_q6_cons (map match_raw src)
    (tl (book_marked_prefix failed ++ [4]) ++
     map match_mark src ++
     map source_bit (br_action hit) ++
     source_bit (br_dir hit) :: book_raw_tail after ++ 5 :: tail)
    (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
    (match_raw_valid src)).
  cbn [app].
  replace (map match_raw src) with (map source_bit src)
    by apply map_match_raw_source_bit.
  reflexivity.
Qed.

Print Assumptions book_locate_hit_row.

Theorem book_locate_rows_to_q6 :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (hit : book_row) (after : list book_row) (buf : nat)
         (ptape tail : list nat),
    Forall (fun st => bf_src st = src) steps ->
    br_cond hit = src ->
    run (book_failures_clock failed steps +
         book_hit_clock src (failed ++ map bf_row steps))
      (book_locate_state src failed (map bf_row steps ++ hit :: after)
         buf ptape tail)
    = entry_config 6
        (4 :: rev (map source_bit src) ++
         5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
        (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
         map match_mark src ++
         map source_bit (br_action hit) ++
         [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail).
Proof.
  intros src failed steps hit after buf ptape tail Hsteps Hcond.
  rewrite (dispatch_run_add (book_failures_clock failed steps)
    (book_hit_clock src (failed ++ map bf_row steps))).
  rewrite (book_locate_failed_rows src failed steps hit after
    buf ptape tail Hsteps).
  apply (book_locate_hit_row src (failed ++ map bf_row steps) hit after
    buf ptape tail Hcond).
Qed.

Print Assumptions book_locate_rows_to_q6.

(** ** Last-row mismatch and the no-match halt theorem *)

Definition book_halt_clock
    (failed : list book_row) (step : book_failure) : nat :=
  matched_comparison_steps (bf_good step) 0
    (length (map match_mark (bf_bit step :: bf_src_rest step) ++
             (book_marked_prefix failed ++ [4]))) +
  book_mismatch_halt_clock (bf_bit step) (bf_good step) (bf_src_rest step)
    (bf_row_rest step) (br_action (bf_row step)) (br_dir (bf_row step))
    (book_marked_prefix failed ++ [4]).

Lemma book_locate_last_mismatch_halt :
  forall (failed : list book_row) (step : book_failure) (buf : nat)
         (ptape tail : list nat),
    run (book_halt_clock failed step)
      (book_locate_state (bf_src step) failed [bf_row step] buf ptape tail)
    = dispatch_halt_at_y
        (rev (map source_bit (bf_row_rest step) ++
              map source_bit (br_action (bf_row step)) ++
              [source_bit (br_dir (bf_row step))]) ++
         match_mark (negb (bf_bit step)) ::
         rev (map match_mark (bf_src_rest step) ++
              (book_marked_prefix failed ++ [4]) ++
              map match_mark (bf_good step)) ++
         match_raw (bf_bit step) :: rev (map match_raw (bf_good step)) ++
         5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
        tail.
Proof.
  intros failed step buf ptape tail.
  unfold book_halt_clock.
  unfold book_locate_state.
  rewrite book_raw_tail_cons.
  rewrite book_raw_desc_cons.
  cbn [book_raw_tail].
  rewrite app_nil_r.
  unfold book_raw_row.
  rewrite (bf_src_split step).
  rewrite (bf_row_split step).
  assert (Hframe1 :
    entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
      (map match_mark (bf_good step ++ bf_bit step :: bf_src_rest step) ++
       book_marked_prefix failed ++
       ((4 :: (map source_bit
                 (bf_good step ++ negb (bf_bit step) :: bf_row_rest step) ++
               map source_bit (br_action (bf_row step)) ++
               [source_bit (br_dir (bf_row step))])) ++ 5 :: tail))
    = entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
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
    (rev (book_buf buf) ++ 6 :: rev ptape)
    (match_raw (negb (bf_bit step)) ::
     map source_bit (bf_row_rest step) ++
     map source_bit (br_action (bf_row step)) ++
     [source_bit (br_dir (bf_row step))] ++ 5 :: tail)
    (wide_mark_failure_done (bf_bit step) (bf_src_rest step) failed)).
  cbn [app].
  assert (Hframe2 :
    entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
      (map match_raw (bf_good step) ++
       (map match_mark (bf_bit step :: bf_src_rest step) ++
        (book_marked_prefix failed ++ [4])) ++
       map match_mark (bf_good step) ++
       match_raw (negb (bf_bit step)) ::
       map source_bit (bf_row_rest step) ++
       map source_bit (br_action (bf_row step)) ++
       source_bit (br_dir (bf_row step)) :: 5 :: tail)
    = entry_config 1 (5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
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
    (rev (book_buf buf) ++ 6 :: rev ptape) tail
    (Forall_wide_mark_marked_prefix_snoc failed)).
  reflexivity.
Qed.

Print Assumptions book_locate_last_mismatch_halt.

Theorem book_locate_rows_to_halt :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (last : book_failure) (buf : nat) (ptape tail : list nat),
    Forall (fun st => bf_src st = src) (steps ++ [last]) ->
    run (book_failures_clock failed steps +
         book_halt_clock (failed ++ map bf_row steps) last)
      (book_locate_state src failed (map bf_row (steps ++ [last]))
         buf ptape tail)
    = dispatch_halt_at_y
        (rev (map source_bit (bf_row_rest last) ++
              map source_bit (br_action (bf_row last)) ++
              [source_bit (br_dir (bf_row last))]) ++
         match_mark (negb (bf_bit last)) ::
         rev (map match_mark (bf_src_rest last) ++
              ((book_marked_prefix (failed ++ map bf_row steps)) ++ [4]) ++
              map match_mark (bf_good last)) ++
         match_raw (bf_bit last) :: rev (map match_raw (bf_good last)) ++
         5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
        tail.
Proof.
  intros src failed steps last buf ptape tail Hsteps.
  rewrite map_app. cbn [map].
  rewrite (dispatch_run_add (book_failures_clock failed steps)
    (book_halt_clock (failed ++ map bf_row steps) last)).
  assert (Hsteps' : Forall (fun st => bf_src st = src) steps).
  { apply Forall_app in Hsteps. destruct Hsteps as [H _]. exact H. }
  assert (Hlast : bf_src last = src).
  { apply Forall_app in Hsteps. destruct Hsteps as [_ H].
    apply Forall_inv in H. exact H. }
  rewrite (book_locate_failed_rows src failed steps (bf_row last) []
    buf ptape tail Hsteps').
  assert (Hsrc : src = bf_src last) by (symmetry; exact Hlast).
  rewrite Hsrc.
  apply (book_locate_last_mismatch_halt (failed ++ map bf_row steps)
    last buf ptape tail).
Qed.

Print Assumptions book_locate_rows_to_halt.

(** ** Steady-state q5 entry from the perform cycle *)

Lemma book_q5_steady_to_q1 :
  forall (init : list bool) (w : bool) (prefix rest : list nat),
    run (S (length init))
      (cfg_ml 5 (rev (map source_bit init) ++ 5 :: prefix)
              (match_mark w :: 4 :: rest))
    = entry_config 1 (5 :: prefix)
        (map match_mark (init ++ [w]) ++ 4 :: rest).
Proof.
  intros init w prefix rest.
  destruct init as [|i is].
  - cbn [rev map cfg_ml run]. reflexivity.
  - remember (rev (map source_bit (i :: is))) as r eqn:Hr.
    destruct r as [|s remaining].
    + exfalso. assert (Hlen := f_equal (@length nat) Hr).
      rewrite rev_length in Hlen. rewrite map_length in Hlen.
      simpl in Hlen. discriminate Hlen.
    + assert (Hscan : Forall q5_pass (s :: remaining)).
      { rewrite Hr. apply Forall_rev, q5_pass_source_bits. }
      cbn [app cfg_ml].
      replace (S (length (i :: is))) with (S (length (s :: remaining)))
        by (rewrite Hr; rewrite rev_length, map_length; reflexivity).
      rewrite (q5_scan_unbounded remaining s prefix
        (match_mark w :: 4 :: rest) Hscan).
      cbn [app].
      rewrite Hr.
      rewrite rev_involutive.
      rewrite map_entry_rewrite_source_bits.
      cbn [map app].
      rewrite map_app.
      repeat rewrite <- app_assoc.
      cbn [app].
      reflexivity.
Qed.

Print Assumptions book_q5_steady_to_q1.

Lemma book_buf_pred_rev :
  forall b, 1 <= b -> rev (book_buf (b - 1)) = rev (tl (book_buf b)).
Proof.
  intros b Hb. destruct b as [|b']; [lia|].
  replace (S b' - 1) with b' by lia.
  unfold book_buf. cbn [tl]. reflexivity.
Qed.

Lemma rev_ptape_source_bit :
  forall (ptape : list nat) (w : bool),
    rev (ptape ++ [source_bit w]) = source_bit w :: rev ptape.
Proof.
  intros. rewrite rev_app_distr. cbn [rev]. reflexivity.
Qed.

Lemma book_q5_steady_to_locate_state :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (rows : list book_row),
    1 <= b ->
    rows <> [] ->
    run (S (length init))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape)
        (match_mark w :: 4 :: book_raw_desc rows ++ 5 :: tail))
    = book_locate_state (init ++ [w]) [] rows (b-1) (ptape ++ [source_bit w]) tail.
Proof.
  intros init w b ptape tail rows Hb Hrows.
  replace (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
           6 :: source_bit w :: rev ptape)
    with (rev (map source_bit init) ++ 5 ::
          (rev (tl (book_buf b)) ++ 6 :: source_bit w :: rev ptape)).
  2:{ rewrite rev_app_distr. cbn [rev].
      rewrite rev_app_distr. cbn [rev].
      repeat rewrite <- app_assoc. reflexivity. }
  rewrite (book_q5_steady_to_q1 init w
    (rev (tl (book_buf b)) ++ 6 :: source_bit w :: rev ptape)
    (book_raw_desc rows ++ 5 :: tail)).
  destruct rows as [|r rest]; [contradiction|].
  unfold book_locate_state.
  cbn [book_marked_prefix app].
  rewrite book_raw_tail_cons.
  rewrite book_buf_pred_rev by exact Hb.
  rewrite rev_ptape_source_bit.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions book_q5_steady_to_locate_state.

(** ** Composition with the q6 -> q12 adapter *)

Lemma Forall_q6_book_marked_row :
  forall r, Forall q6_pass (book_marked_row r).
Proof.
  intros r. unfold book_marked_row.
  repeat rewrite Forall_app. repeat split.
  - apply Forall_q6_match_marks.
  - apply Forall_q6_match_marks.
  - constructor; [apply q6_pass_match_mark | constructor].
Qed.

Lemma Forall_q7_book_marked_row :
  forall r, Forall q7_pass (book_marked_row r).
Proof.
  intros r. unfold book_marked_row.
  repeat rewrite Forall_app. repeat split.
  - apply Forall_q7_match_marks.
  - apply Forall_q7_match_marks.
  - constructor; [apply q7_pass_match_mark | constructor].
Qed.

Lemma Forall_q6_book_marked_prefix :
  forall rows, Forall q6_pass (book_marked_prefix rows).
Proof.
  induction rows as [|r rest IH]; simpl.
  - constructor.
  - constructor.
    + unfold q6_pass; auto 10.
    + apply Forall_app. split.
      * apply Forall_q6_book_marked_row.
      * exact IH.
Qed.

Lemma Forall_q7_book_marked_prefix :
  forall rows, Forall q7_pass (book_marked_prefix rows).
Proof.
  induction rows as [|r rest IH]; simpl.
  - constructor.
  - constructor.
    + unfold q7_pass; auto 10.
    + apply Forall_app. split.
      * apply Forall_q7_book_marked_row.
      * exact IH.
Qed.

Lemma Forall_q6_tl_marked_done :
  forall failed,
    Forall q6_pass (tl (book_marked_prefix failed ++ [4])).
Proof.
  intros. destruct failed as [|r rest].
  - cbn. constructor.
  - cbn [book_marked_prefix tl].
    apply Forall_app. split.
    + apply Forall_app. split.
      * apply Forall_q6_book_marked_row.
      * apply Forall_q6_book_marked_prefix.
    + constructor; [unfold q6_pass; auto 10 | constructor].
Qed.

Lemma Forall_q7_tl_marked_done :
  forall failed,
    Forall q7_pass (tl (book_marked_prefix failed ++ [4])).
Proof.
  intros. destruct failed as [|r rest].
  - cbn. constructor.
  - cbn [book_marked_prefix tl].
    apply Forall_app. split.
    + apply Forall_app. split.
      * apply Forall_q7_book_marked_row.
      * apply Forall_q7_book_marked_prefix.
    + constructor; [unfold q7_pass; auto 10 | constructor].
Qed.

Lemma book_locate_q6_region_frame_gen :
  forall (region : list nat) (bits action : list bool) (dir : bool)
         (rest : list nat),
    region ++ map match_mark bits ++ map source_bit action ++
    [source_bit dir] ++ rest =
    (region ++ map match_mark bits) ++
    (map source_bit action ++ [source_bit dir] ++ rest).
Proof.
  intros. apply app_assoc.
Qed.

Theorem book_locate_rows_to_q12 :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (hit : book_row) (after : list book_row) (buf : nat)
         (ptape tail : list nat),
    Forall (fun st => bf_src st = src) steps ->
    br_cond hit = src ->
    length (br_action hit) = length src ->
    run (book_failures_clock failed steps +
         book_hit_clock src (failed ++ map bf_row steps) +
         (copy_all_clock src (br_action hit) []
            (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
             map match_mark src) +
          direction_clock
            (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
             map match_mark src ++ map match_mark (br_action hit))
            (map match_mark (br_action hit))))
      (book_locate_state src failed (map bf_row steps ++ hit :: after)
         buf ptape tail)
    = cfg_ml (if br_dir hit then 12 else 13)
        (rev (map match_mark (br_action hit)) ++
         5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
        (4 :: ((tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
                map match_mark src) ++
               map match_mark (br_action hit)) ++
         (if br_dir hit then 3 else 2) :: book_raw_tail after ++ 5 :: tail).
Proof.
  intros src failed steps hit after buf ptape tail
    Hsteps Hcond Hlen.
  rewrite (dispatch_run_add
    (book_failures_clock failed steps +
     book_hit_clock src (failed ++ map bf_row steps))
    (copy_all_clock src (br_action hit) []
       (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
        map match_mark src) +
     direction_clock
       (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
        map match_mark src ++ map match_mark (br_action hit))
       (map match_mark (br_action hit)))).
  rewrite (book_locate_rows_to_q6 src failed steps hit after
    buf ptape tail Hsteps Hcond).
  rewrite book_locate_q6_region_frame_gen.
  apply (book_q6_region_to_q12
    (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]))
    src (br_action hit) (br_dir hit) (book_buf buf) ptape
    (book_raw_tail after ++ 5 :: tail)).
  - apply Forall_q6_tl_marked_done.
  - apply Forall_q7_tl_marked_done.
  - exact Hlen.
Qed.

Print Assumptions book_locate_rows_to_q12.

(** ** Passability of the failed-row region for the perform half

    These are the two side conditions needed to feed the q12 frame of
    [book_locate_rows_to_q12] into the q12 -> q5 perform adapter.  The
    remaining perform gap is the region-general version of
    [book_q6_to_q5_right]: the q12 right tape has

      marked = (region ++ marks(bits)) ++ marks(action)
      mark   = direction mark
      record_tail = rest

    and [book_q12_restore_to_q5_right] already accepts an arbitrary
    marked prefix.  The q15/q16 passability of that prefix is proved
    here; the q15 scan's trailing raw bit is the first raw bit of the
    next row (or needs a separate stop-at-Y variant for the last row). *)

Lemma q15_pass_match_mark : forall b, q15_pass (match_mark b).
Proof. intros [|]; unfold q15_pass, match_mark; auto 10. Qed.

Lemma q16_pass_match_mark : forall b, q16_pass (match_mark b).
Proof. intros [|]; unfold q16_pass, match_mark; auto 10. Qed.

Lemma Forall_q15_match_marks :
  forall bits, Forall q15_pass (map match_mark bits).
Proof. intros. apply Forall_match_mark. apply q15_pass_match_mark. Qed.

Lemma Forall_q16_match_marks :
  forall bits, Forall q16_pass (map match_mark bits).
Proof. intros. apply Forall_match_mark. apply q16_pass_match_mark. Qed.

Lemma Forall_q15_book_marked_row :
  forall r, Forall q15_pass (book_marked_row r).
Proof.
  intros r. unfold book_marked_row.
  repeat rewrite Forall_app. repeat split.
  - apply Forall_q15_match_marks.
  - apply Forall_q15_match_marks.
  - constructor; [apply q15_pass_match_mark | constructor].
Qed.

Lemma Forall_q16_book_marked_row :
  forall r, Forall q16_pass (book_marked_row r).
Proof.
  intros r. unfold book_marked_row.
  repeat rewrite Forall_app. repeat split.
  - apply Forall_q16_match_marks.
  - apply Forall_q16_match_marks.
  - constructor; [apply q16_pass_match_mark | constructor].
Qed.

Lemma Forall_q15_book_marked_prefix :
  forall rows, Forall q15_pass (book_marked_prefix rows).
Proof.
  induction rows as [|r rest IH]; simpl.
  - constructor.
  - constructor.
    + unfold q15_pass; auto 10.
    + apply Forall_app. split.
      * apply Forall_q15_book_marked_row.
      * exact IH.
Qed.

Lemma Forall_q16_book_marked_prefix :
  forall rows, Forall q16_pass (book_marked_prefix rows).
Proof.
  induction rows as [|r rest IH]; simpl.
  - constructor.
  - constructor.
    + unfold q16_pass; auto 10.
    + apply Forall_app. split.
      * apply Forall_q16_book_marked_row.
      * exact IH.
Qed.

Lemma Forall_q15_tl_marked_done :
  forall failed,
    Forall q15_pass (tl (book_marked_prefix failed ++ [4])).
Proof.
  intros. destruct failed as [|r rest].
  - cbn. constructor.
  - cbn [book_marked_prefix tl].
    apply Forall_app. split.
    + apply Forall_app. split.
      * apply Forall_q15_book_marked_row.
      * apply Forall_q15_book_marked_prefix.
    + constructor; [unfold q15_pass; auto 10 | constructor].
Qed.

Lemma Forall_q16_tl_marked_done :
  forall failed,
    Forall q16_pass (tl (book_marked_prefix failed ++ [4])).
Proof.
  intros. destruct failed as [|r rest].
  - cbn. constructor.
  - cbn [book_marked_prefix tl].
    apply Forall_app. split.
    + apply Forall_app. split.
      * apply Forall_q16_book_marked_row.
      * apply Forall_q16_book_marked_prefix.
    + constructor; [unfold q16_pass; auto 10 | constructor].
Qed.

Print Assumptions book_q5_steady_to_q1.
Print Assumptions book_q5_steady_to_locate_state.
Print Assumptions book_locate_rows_to_q6.
Print Assumptions book_locate_rows_to_halt.
Print Assumptions book_locate_rows_to_q12.

Lemma app_cons_book_row_neq_nil :
  forall (l : list book_row) (r : book_row) (rest : list book_row),
    l ++ r :: rest <> [].
Proof.
  intros l. induction l as [|x xs IH]; intros r rest; simpl; discriminate 1.
Qed.

Corollary book_steady_q5_locate_to_q12 :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row) (after : list book_row),
    1 <= b ->
    Forall (fun st => bf_src st = init ++ [w]) steps ->
    br_cond hit = init ++ [w] ->
    length (br_action hit) = length (init ++ [w]) ->
    run (S (length init) +
         (book_failures_clock [] steps +
          book_hit_clock (init ++ [w]) (map bf_row steps) +
          (copy_all_clock (init ++ [w]) (br_action hit) []
             (tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
              map match_mark (init ++ [w])) +
           direction_clock
             (tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
              map match_mark (init ++ [w]) ++
              map match_mark (br_action hit))
             (map match_mark (br_action hit)))))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape)
        (match_mark w :: 4 ::
         book_raw_desc (map bf_row steps ++ hit :: after) ++ 5 :: tail))
    = cfg_ml (if br_dir hit then 12 else 13)
        (rev (map match_mark (br_action hit)) ++
         5 :: rev (book_buf (b-1)) ++
         6 :: rev (ptape ++ [source_bit w]))
        (4 :: ((tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
                map match_mark (init ++ [w])) ++
               map match_mark (br_action hit)) ++
         (if br_dir hit then 3 else 2) :: book_raw_tail after ++ 5 :: tail).
Proof.
  intros init w b ptape tail steps hit after Hb Hsteps Hcond Hlen.
  rewrite (dispatch_run_add (S (length init))
    (book_failures_clock [] steps +
     book_hit_clock (init ++ [w]) (map bf_row steps) +
     (copy_all_clock (init ++ [w]) (br_action hit) []
        (tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
         map match_mark (init ++ [w])) +
      direction_clock
        (tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
         map match_mark (init ++ [w]) ++
         map match_mark (br_action hit))
        (map match_mark (br_action hit))))).
  rewrite (book_q5_steady_to_locate_state init w b ptape tail
    (map bf_row steps ++ hit :: after) Hb
    (app_cons_book_row_neq_nil (map bf_row steps) hit after)).
  cbn [app].
  apply (book_locate_rows_to_q12 (init ++ [w]) [] steps hit after (b-1)
    (ptape ++ [source_bit w]) tail Hsteps Hcond Hlen).
Qed.

Print Assumptions book_steady_q5_locate_to_q12.
