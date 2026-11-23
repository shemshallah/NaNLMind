(** * Book-layout two-row locate phase

    This module proves the first multi-row stepping stone of the book
    locate phase.  The physical tape is the one produced by the concrete
    encoder:

      ptape  M  book_buf b  Y  src_condition
        X  row1_condition  row1_action  dir1
        X  row2_condition  row2_action  dir2
        Y  0 ...

    with the head initially on the first [X = 4].  The first row
    condition shares an arbitrary prefix [good] with the source
    condition and then mismatches on one bit.  The machine

      q5  marks the source condition and returns to Y,
      q1  compares [good] against row1 (via [q1_all_matching_bits_wide]),
      q1  detects the first mismatch,
      q3/q5 walk to the [X] ending row1 and mark the whole traversed
          region, returning to Y,
      q1  compares the source condition against row2, which matches,
      q1  crosses the first [X] into q6.

    The endpoint is the exact native q6 frame, with the failed row1
    record (and its two [X] delimiters) as a marked prefix of the q6
    right tape.  That prefix is the [region] argument of
    [canonical_q6_copy_all], so this frame composes with the perform
    half through a region-general q6 adapter.

    The mismatch is *not* obtained from
    [q1_matching_prefix_then_first_mismatch] directly: that lemma's
    frame has the marked copy of the matching prefix immediately before
    the mismatching marked bit, while the book layout has the first
    [X = 4] delimiter (and the already matched marks) between the two
    copies.  The compositional replacement is

      q1_all_matching_bits_wide good [] (marks(b::rest) ++ [4])
      then q1_zero_mismatch_restart / q1_one_mismatch_restart

    with [marked = marks(rest) ++ [4] ++ marks(good)].  This is what
    [book_q1_mismatch_restart] below packages. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry MinskyConcreteDispatch
  MinskySourceEncoding MinskyMatchMacro MinskyCanonicalMatch
  MinskyActionMacro MinskyCanonicalCopy MinskyCanonicalCopyGeneral
  MinskyCanonicalDirection MinskyCanonicalInstruction MinskyBookLayout.

(** ** q5 scan with an arbitrary right-hand description

    [canonical_q5_scan] requires the first row condition to be a second
    copy of the source condition.  The locate phase needs the genuinely
    two-copy shape: the source condition on the left of [Y] and an
    arbitrary description on the right.  This is exactly
    [q5_scan_unbounded] with the scan list [4 :: rev src]. *)

Lemma q5_pass_source_bits :
  forall bits, Forall q5_pass (map source_bit bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold q5_pass, source_bit; auto 10.
    + exact IH.
Qed.

Lemma book_q5_scan_general :
  forall (src : list bool) (tbuffer data rest : list nat),
    run (length src + 2)
      (entry_config 5
        (rev (map source_bit src) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: rest)) =
    entry_config 1 (5 :: rev tbuffer ++ 6 :: rev data)
      (map match_mark src ++ 4 :: rest).
Proof.
  intros src tbuffer data rest.
  assert (Hscan : Forall q5_pass (4 :: rev (map source_bit src))).
  { constructor.
    - unfold q5_pass; auto 10.
    - apply Forall_rev, q5_pass_source_bits. }
  replace (length src + 2)
    with (S (length (4 :: rev (map source_bit src)))).
  2:{ cbn [length]. rewrite rev_length, map_length. lia. }
  rewrite (q5_scan_unbounded (rev (map source_bit src)) 4
    (rev tbuffer ++ 6 :: rev data) rest Hscan).
  cbn [rev].
  rewrite rev_involutive.
  rewrite map_app.
  cbn [map].
  rewrite map_map.
  replace (map (fun b => entry_rewrite (source_bit b)) src)
    with (map match_mark src)
    by (apply map_ext; intro b; symmetry; apply entry_rewrite_source_bit).
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

(** ** Marked-prefix bookkeeping *)

Definition book_skip_region
    (row action : list bool) (dir : bool) : list nat :=
  map match_mark row ++ map match_mark action ++ [match_mark dir] ++ [4].

Definition book_match_done
    (row action : list bool) (dir : bool) : list nat :=
  4 :: book_skip_region row action dir.

Lemma wide_mark_four : wide_mark 4.
Proof. unfold wide_mark; auto 10. Qed.

Lemma wide_mark_match_mark : forall b, wide_mark (match_mark b).
Proof. intros [|]; unfold wide_mark, match_mark; auto 10. Qed.

Lemma wide_mark_map_match_marks :
  forall bits, Forall wide_mark (map match_mark bits).
Proof. apply wide_match_mark_valid. Qed.

Lemma wide_mark_book_skip_region :
  forall row action dir,
    Forall wide_mark (book_skip_region row action dir).
Proof.
  intros row action dir.
  unfold book_skip_region.
  repeat rewrite Forall_app.
  repeat split.
  - apply wide_mark_map_match_marks.
  - apply wide_mark_map_match_marks.
  - constructor; [apply wide_mark_match_mark | constructor].
  - constructor; [apply wide_mark_four | constructor].
Qed.

Lemma wide_mark_book_match_done :
  forall row action dir,
    Forall wide_mark (book_match_done row action dir).
Proof.
  intros row action dir. unfold book_match_done.
  constructor.
  - apply wide_mark_four.
  - apply wide_mark_book_skip_region.
Qed.

(** ** First-row mismatch restart in the book frame

    Entry frame (the head is just right of [Y], [good] has already been
    matched and its raw source copies are to the left of the marked
    source block):

      Y  raws(good)  mark b  marks(rest)  X  marks(good)
         raw(negb b)  raws(row1_rest)  raws(action1)  dir1  X  afterX

    The marked block crossed by q0/q4 before the raw mismatch bit is
    [marks(rest) ++ [X] ++ marks(good)], so this is the restart lemma
    with [pass = raws(good)] and [marked = marks(rest) ++ [4] ++
    marks(good)].  The [X] is passable by q0/q4, which is why the book
    layout composes despite the delimiter between the two copies. *)

Definition book_mismatch_scan
    (b : bool) (good restbits row1_rest action1 : list bool) (dir1 : bool)
    : list nat :=
  let marked := map match_mark restbits ++ [4] ++ map match_mark good in
  let row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1] in
  rev row_rest ++ match_mark (negb b) :: rev marked ++
  match_raw b :: rev (map match_raw good).

Definition book_mismatch_clock
    (b : bool) (good restbits row1_rest action1 : list bool) (dir1 : bool)
    : nat :=
  S (length (map match_raw good)) +
  (S (length (map match_mark restbits ++ [4] ++ map match_mark good)) +
   ((length (map source_bit row1_rest ++
             map source_bit action1 ++ [source_bit dir1]) + 1) +
    S (length (book_mismatch_scan b good restbits row1_rest action1 dir1)))).

Lemma book_mismatch_scan_nonempty :
  forall b good restbits row1_rest action1 dir1,
    book_mismatch_scan b good restbits row1_rest action1 dir1 <> [].
Proof.
  intros b good restbits row1_rest action1 dir1.
  unfold book_mismatch_scan.
  intro H.
  assert (Hlen := f_equal (@length nat) H).
  rewrite app_length in Hlen.
  cbn [length] in Hlen.
  lia.
Qed.

Lemma q5_pass_match_mark : forall b, q5_pass (match_mark b).
Proof. apply q5_match_mark. Qed.

Lemma q5_pass_match_raw : forall b, q5_pass (match_raw b).
Proof. apply q5_match_raw. Qed.

Lemma q5_pass_rev_marks :
  forall bits, Forall q5_pass (rev (map match_mark bits)).
Proof. intros. apply Forall_rev, q5_marked_bits. Qed.

Lemma q5_pass_rev_source_bits :
  forall bits, Forall q5_pass (rev (map source_bit bits)).
Proof. intros. apply Forall_rev, q5_pass_source_bits. Qed.

Lemma q5_pass_rev_row_rest :
  forall row1_rest action1 (dir1 : bool),
    Forall q5_pass
      (rev (map source_bit row1_rest ++
            map source_bit action1 ++ [source_bit dir1])).
Proof.
  intros row1_rest action1 dir1.
  repeat rewrite rev_app_distr.
  cbn [rev app].
  constructor.
  - destruct dir1; unfold q5_pass, source_bit; auto 10.
  - rewrite Forall_app. split; apply q5_pass_rev_source_bits.
Qed.

Lemma q5_pass_rev_match_raws :
  forall bits, Forall q5_pass (rev (map match_raw bits)).
Proof. intros. apply Forall_rev, q5_raw_bits. Qed.

Lemma q5_pass_marked_block :
  forall restbits good,
    Forall q5_pass
      (map match_mark restbits ++ [4] ++ map match_mark good).
Proof.
  intros restbits good.
  repeat rewrite Forall_app.
  repeat split.
  - apply q5_marked_bits.
  - constructor; [unfold q5_pass; auto 10 | constructor].
  - apply q5_marked_bits.
Qed.

Lemma book_mismatch_scan_valid :
  forall b good restbits row1_rest action1 dir1,
    Forall q5_pass
      (book_mismatch_scan b good restbits row1_rest action1 dir1).
Proof.
  intros b good restbits row1_rest action1 dir1.
  unfold book_mismatch_scan.
  cbn zeta.
  rewrite Forall_app. split.
  - apply q5_pass_rev_row_rest.
  - constructor.
    + apply q5_pass_match_mark.
    + rewrite Forall_app. split.
      * apply Forall_rev, q5_pass_marked_block.
      * constructor.
        -- apply q5_pass_match_raw.
        -- apply q5_pass_rev_match_raws.
Qed.

Lemma entry_rewrite_match_raw :
  forall b, entry_rewrite (match_raw b) = match_mark b.
Proof. intros [|]; reflexivity. Qed.

Lemma entry_rewrite_match_mark :
  forall b, entry_rewrite (match_mark b) = match_mark b.
Proof. intros [|]; reflexivity. Qed.

Lemma map_entry_rewrite_source_bits :
  forall bits,
    map entry_rewrite (map source_bit bits) = map match_mark bits.
Proof.
  induction bits as [|b rest IH]; simpl.
  - reflexivity.
  - rewrite entry_rewrite_source_bit, IH. reflexivity.
Qed.

Lemma map_entry_rewrite_match_raws :
  forall bits,
    map entry_rewrite (map match_raw bits) = map match_mark bits.
Proof.
  induction bits as [|b rest IH]; simpl.
  - reflexivity.
  - rewrite entry_rewrite_match_raw, IH. reflexivity.
Qed.

Lemma map_entry_rewrite_match_marks :
  forall bits,
    map entry_rewrite (map match_mark bits) = map match_mark bits.
Proof.
  induction bits as [|b rest IH]; simpl.
  - reflexivity.
  - rewrite entry_rewrite_match_mark, IH. reflexivity.
Qed.

Lemma map_entry_rewrite_row_rest :
  forall row1_rest action1 dir1,
    map entry_rewrite
      (map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1])
    = map match_mark row1_rest ++ map match_mark action1 ++ [match_mark dir1].
Proof.
  intros row1_rest action1 dir1.
  repeat rewrite map_app.
  cbn [map].
  rewrite map_entry_rewrite_source_bits.
  rewrite map_entry_rewrite_source_bits.
  rewrite entry_rewrite_source_bit.
  reflexivity.
Qed.

(** The frame equation for the restart: the q5 cleanup rewrites every
    raw 0/1 in the traversed region, and the selected marked source bit
    is the only symbol that was first turned into a raw bit by q1. *)

Lemma map_entry_rewrite_book_mismatch_scan :
  forall b good restbits row1_rest action1 dir1,
    let marked := map match_mark restbits ++ [4] ++ map match_mark good in
    let row_rest :=
      map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1] in
    map entry_rewrite
      (rev (rev row_rest ++ match_mark (negb b) :: rev marked ++
            match_raw b :: rev (map match_raw good)))
    = map match_mark (good ++ b :: restbits) ++ [4] ++
      map match_mark (good ++ negb b :: row1_rest) ++
      map match_mark action1 ++ [match_mark dir1].
Proof.
  intros b good restbits row1_rest action1 dir1.
  cbn zeta.
  set (row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
  set (marked := map match_mark restbits ++ [4] ++ map match_mark good).
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
  rewrite map_entry_rewrite_match_marks.
  rewrite entry_rewrite_match_mark.
  unfold row_rest.
  rewrite map_entry_rewrite_row_rest.
  repeat rewrite <- app_assoc.
  cbn [app].
  reflexivity.
Qed.

Lemma book_q1_mismatch_restart :
  forall (b : bool) (good restbits row1_rest action1 : list bool) (dir1 : bool)
         (afterX prefix : list nat),
    run (book_mismatch_clock b good restbits row1_rest action1 dir1)
      (entry_config 1 (5 :: prefix)
        (map match_raw good ++ match_mark b :: map match_mark restbits ++ 4 ::
         map match_mark good ++
         match_raw (negb b) :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 4 :: afterX)) =
    entry_config 1 (5 :: prefix)
      (map match_mark (good ++ b :: restbits) ++ [4] ++
       map match_mark (good ++ negb b :: row1_rest) ++
       map match_mark action1 ++ [match_mark dir1] ++ 4 :: afterX).
Proof.
  intros b good restbits row1_rest action1 dir1 afterX prefix.
  set (row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++ [source_bit dir1]).
  set (marked := map match_mark restbits ++ [4] ++ map match_mark good).
  set (scan := rev row_rest ++ match_mark (negb b) :: rev marked ++
               match_raw b :: rev (map match_raw good)).
  assert (Hne : scan <> []).
  { subst scan. unfold row_rest, marked.
    apply book_mismatch_scan_nonempty. }
  destruct scan as [|s remaining] eqn:Hscan.
  - exfalso. apply Hne. reflexivity.
  - assert (Hq5 : Forall q5_pass (s :: remaining)).
    { rewrite <- Hscan.
      unfold scan, row_rest, marked.
      apply book_mismatch_scan_valid. }
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
      book_mismatch_clock b good restbits row1_rest action1 dir1 =
      S (length (map match_raw good)) +
      (S (length marked) +
       ((length row_rest + 1) + S (length (s :: remaining))))).
    { unfold book_mismatch_clock, book_mismatch_scan.
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
          (map match_mark restbits ++ [4] ++ map match_mark good)).
        { repeat rewrite Forall_app. repeat split.
          - apply wide_mark_map_match_marks.
          - constructor; [apply wide_mark_four | constructor].
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
         map match_mark restbits ++ 4 :: map match_mark good ++
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
        rewrite map_entry_rewrite_book_mismatch_scan.
        repeat rewrite <- app_assoc.
        cbn [app].
        reflexivity.
    + (* b = false: selected mark 2, mismatching raw 1 *)
      cbn [negb].
      assert (Hmarked : Forall q0_pass marked).
      { subst marked.
        assert (Hwide : Forall wide_mark
          (map match_mark restbits ++ [4] ++ map match_mark good)).
        { repeat rewrite Forall_app. repeat split.
          - apply wide_mark_map_match_marks.
          - constructor; [apply wide_mark_four | constructor].
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
         map match_mark restbits ++ 4 :: map match_mark good ++
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
        rewrite map_entry_rewrite_book_mismatch_scan.
        repeat rewrite <- app_assoc.
        cbn [app].
        reflexivity.
Qed.

(** ** The two-row locate theorem *)

Lemma match_raw_source_bit : forall b, match_raw b = source_bit b.
Proof. intros [|]; reflexivity. Qed.

Lemma map_match_raw_source_bit :
  forall bits, map match_raw bits = map source_bit bits.
Proof. intros. apply map_ext. apply match_raw_source_bit. Qed.

Lemma q1_scan_four_list_to_q6_cons :
  forall (pass tail left : list nat),
    Forall q1_pass pass ->
    run (length pass + 1)
      (entry_config 1 left (pass ++ 4 :: tail)) =
    entry_config 6 (4 :: rev pass ++ left) tail.
Proof.
  intros pass tail left Hpass.
  replace (length pass + 1) with (S (length pass)) by lia.
  apply q1_scan_four_list_to_q6. exact Hpass.
Qed.

(** Zero-length-pass form of the wide comparison, so frame matching does
    not have to reduce [length []]. *)
Corollary q1_all_matching_bits_wide_zero :
  forall (bits : list bool) (done prefix tail : list nat),
    Forall wide_mark done ->
    run (matched_comparison_steps bits 0 (length done))
      (entry_config 1 (5 :: prefix)
        (map match_mark bits ++ done ++ map match_raw bits ++ tail)) =
    entry_config 1 (5 :: prefix)
      (map match_raw bits ++ done ++ map match_mark bits ++ tail).
Proof.
  intros bits done prefix tail Hdone.
  apply (q1_all_matching_bits_wide bits [] done prefix tail).
  - constructor.
  - exact Hdone.
Qed.

Theorem book_locate_two_rows_to_q6 :
  forall (good restbits row1_rest action1 action2 : list bool)
         (b dir1 dir2 : bool) (buf : nat) (ptape tail : list nat),
    run ((length (good ++ b :: restbits) + 2) +
         (matched_comparison_steps good 0
            (length (map match_mark (b :: restbits) ++ [4])) +
          (book_mismatch_clock b good restbits row1_rest action1 dir1 +
           (matched_comparison_steps (good ++ b :: restbits) 0
              (length (book_match_done
                 (good ++ negb b :: row1_rest) action1 dir1)) +
            (length (good ++ b :: restbits) + 1)))))
      (entry_config 5
        (rev (map source_bit (good ++ b :: restbits)) ++
         5 :: rev (book_buf buf) ++ 6 :: rev ptape)
        (4 :: map source_bit (good ++ negb b :: row1_rest) ++
         map source_bit action1 ++ [source_bit dir1] ++
         4 :: map source_bit (good ++ b :: restbits) ++
         map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)) =
    entry_config 6
      (4 :: rev (map source_bit (good ++ b :: restbits)) ++
       5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (book_skip_region (good ++ negb b :: row1_rest) action1 dir1 ++
       map match_mark (good ++ b :: restbits) ++
       map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail).
Proof.
  intros good restbits row1_rest action1 action2 b dir1 dir2 buf ptape tail.
  rewrite (dispatch_run_add (length (good ++ b :: restbits) + 2)
    (matched_comparison_steps good 0
       (length (map match_mark (b :: restbits) ++ [4])) +
     (book_mismatch_clock b good restbits row1_rest action1 dir1 +
      (matched_comparison_steps (good ++ b :: restbits) 0
         (length (book_match_done
            (good ++ negb b :: row1_rest) action1 dir1)) +
       (length (good ++ b :: restbits) + 1))))).
  rewrite (book_q5_scan_general (good ++ b :: restbits) (book_buf buf) ptape
    (map source_bit (good ++ negb b :: row1_rest) ++
     map source_bit action1 ++ [source_bit dir1] ++
     4 :: map source_bit (good ++ b :: restbits) ++
     map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)).
  (* q5 leaves the marked source condition and the first X in front of
     the first row.  Reassociate into the comparison entry frame. *)
  assert (Hframe :
    entry_config 1 (5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (map match_mark (good ++ b :: restbits) ++ 4 ::
       map source_bit (good ++ negb b :: row1_rest) ++
       map source_bit action1 ++ [source_bit dir1] ++
       4 :: map source_bit (good ++ b :: restbits) ++
       map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)
    = entry_config 1 (5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (map match_mark good ++
       (map match_mark (b :: restbits) ++ [4]) ++
       map match_raw good ++
       match_raw (negb b) :: map source_bit row1_rest ++
       map source_bit action1 ++ [source_bit dir1] ++
       4 :: map source_bit (good ++ b :: restbits) ++
       map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)).
  { repeat rewrite map_app.
    cbn [map app].
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity. }
  rewrite Hframe.
  rewrite (dispatch_run_add
    (matched_comparison_steps good 0
       (length (map match_mark (b :: restbits) ++ [4])))
    (book_mismatch_clock b good restbits row1_rest action1 dir1 +
     (matched_comparison_steps (good ++ b :: restbits) 0
        (length (book_match_done
           (good ++ negb b :: row1_rest) action1 dir1)) +
      (length (good ++ b :: restbits) + 1)))).
  assert (Hwide1 : Forall wide_mark
    (map match_mark (b :: restbits) ++ [4])).
  { apply Forall_app. split.
    - apply wide_mark_map_match_marks.
    - constructor; [apply wide_mark_four | constructor]. }
  rewrite (q1_all_matching_bits_wide_zero good
    (map match_mark (b :: restbits) ++ [4])
    (rev (book_buf buf) ++ 6 :: rev ptape)
    (match_raw (negb b) :: map source_bit row1_rest ++
     map source_bit action1 ++ [source_bit dir1] ++
     4 :: map source_bit (good ++ b :: restbits) ++
     map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)
    Hwide1).
  cbn [app].
  (* The matching prefix of row1 is consumed; now restart on the first
     mismatching bit.  Reassociate the exit frame to the restart entry. *)
  assert (Hframe3 :
    entry_config 1 (5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (map match_raw good ++
       (map match_mark (b :: restbits) ++ [4]) ++
       map match_mark good ++
       match_raw (negb b) :: map source_bit row1_rest ++
       map source_bit action1 ++ source_bit dir1 ::
       4 :: map source_bit (good ++ b :: restbits) ++
       map source_bit action2 ++ source_bit dir2 :: 5 :: tail)
    = entry_config 1 (5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (map match_raw good ++ match_mark b :: map match_mark restbits ++
       4 :: map match_mark good ++
       match_raw (negb b) :: map source_bit row1_rest ++
       map source_bit action1 ++ [source_bit dir1] ++
       4 :: map source_bit (good ++ b :: restbits) ++
       map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)).
  { repeat rewrite map_app. cbn [map app].
    repeat rewrite <- app_assoc. cbn [app].
    reflexivity. }
  rewrite Hframe3.
  rewrite (dispatch_run_add
    (book_mismatch_clock b good restbits row1_rest action1 dir1)
    (matched_comparison_steps (good ++ b :: restbits) 0
       (length (book_match_done
          (good ++ negb b :: row1_rest) action1 dir1)) +
     (length (good ++ b :: restbits) + 1))).
  rewrite (book_q1_mismatch_restart b good restbits row1_rest action1 dir1
    (map source_bit (good ++ b :: restbits) ++
     map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)
    (rev (book_buf buf) ++ 6 :: rev ptape)).
  cbn [app].
  (* The restart marked all of row1; row2 matches all of the source
     condition. *)
  assert (Hframe2 :
    entry_config 1 (5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (map match_mark (good ++ b :: restbits) ++ 4 ::
       map match_mark (good ++ negb b :: row1_rest) ++
       map match_mark action1 ++ match_mark dir1 ::
       4 :: map source_bit (good ++ b :: restbits) ++
       map source_bit action2 ++ source_bit dir2 :: 5 :: tail)
    = entry_config 1 (5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (map match_mark (good ++ b :: restbits) ++
       book_match_done (good ++ negb b :: row1_rest) action1 dir1 ++
       map match_raw (good ++ b :: restbits) ++
       map source_bit action2 ++ source_bit dir2 :: 5 :: tail)).
  { repeat rewrite map_app.
    cbn [map app].
    unfold book_match_done, book_skip_region.
    repeat rewrite map_app.
    cbn [map app].
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity. }
  rewrite Hframe2.
  rewrite (dispatch_run_add
    (matched_comparison_steps (good ++ b :: restbits) 0
       (length (book_match_done
          (good ++ negb b :: row1_rest) action1 dir1)))
    (length (good ++ b :: restbits) + 1)).
  assert (Hwide2 : Forall wide_mark
    (book_match_done (good ++ negb b :: row1_rest) action1 dir1)).
  { apply wide_mark_book_match_done. }
  rewrite (q1_all_matching_bits_wide_zero (good ++ b :: restbits)
    (book_match_done (good ++ negb b :: row1_rest) action1 dir1)
    (rev (book_buf buf) ++ 6 :: rev ptape)
    (map source_bit action2 ++ source_bit dir2 :: 5 :: tail)
    Hwide2).
  cbn [app].
  (* Unfold the done block so the q1 scan sees the literal X = 4. *)
  unfold book_match_done.
  cbn [app].
  replace (length (good ++ b :: restbits) + 1)
    with (length (map match_raw (good ++ b :: restbits)) + 1)
    by (rewrite map_length; reflexivity).
  (* q1 now skips the restored source condition and crosses the first
     X = 4 into q6. *)
  rewrite (q1_scan_four_list_to_q6_cons
    (map match_raw (good ++ b :: restbits))
    (book_skip_region (good ++ negb b :: row1_rest) action1 dir1 ++
     map match_mark (good ++ b :: restbits) ++
     map source_bit action2 ++ source_bit dir2 :: 5 :: tail)
    (5 :: rev (book_buf buf) ++ 6 :: rev ptape)
    (match_raw_valid (good ++ b :: restbits))).
  cbn [app].
  replace (map match_raw (good ++ b :: restbits))
    with (map source_bit (good ++ b :: restbits))
    by apply map_match_raw_source_bit.
  reflexivity.
Qed.


(** ** Region-general q6 -> q12 adapter

    The locate phase reaches q6 with the failed rows (and their [X]
    delimiters) as a marked prefix before the matched row.  The stock
    [canonical_q6_copy_direction_to_q12] has no such prefix, but
    [canonical_q6_copy_all] and [canonical_q6_direction_capture] both
    accept an arbitrary q6/q7-passable region.  This is the adapter that
    consumes the output frame of [book_locate_two_rows_to_q6]. *)

Lemma q6_pass_match_mark : forall b, q6_pass (match_mark b).
Proof. intros [|]; unfold q6_pass, match_mark; auto 10. Qed.

Lemma q7_pass_match_mark : forall b, q7_pass (match_mark b).
Proof. intros [|]; unfold q7_pass, match_mark; auto 10. Qed.

Lemma Forall_q6_match_marks :
  forall bits, Forall q6_pass (map match_mark bits).
Proof. intros. apply Forall_match_mark. apply q6_pass_match_mark. Qed.

Lemma Forall_q7_match_marks :
  forall bits, Forall q7_pass (map match_mark bits).
Proof. intros. apply Forall_match_mark. apply q7_pass_match_mark. Qed.

Theorem book_q6_region_to_q12 :
  forall (region : list nat) (bits action_bits : list bool) (dir : bool)
         (tbuffer data rest : list nat),
    Forall q6_pass region ->
    Forall q7_pass region ->
    length action_bits = length bits ->
    run (copy_all_clock bits action_bits [] (region ++ map match_mark bits) +
         direction_clock
           (region ++ map match_mark bits ++ map match_mark action_bits)
           (map match_mark action_bits))
      (entry_config 6
        (4 :: rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        ((region ++ map match_mark bits) ++
         (map source_bit action_bits ++ source_bit dir :: rest))) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark action_bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
      (4 :: ((region ++ map match_mark bits) ++ map match_mark action_bits) ++
       (if dir then 3 else 2) :: rest).
Proof.
  intros region bits action_bits dir tbuffer data rest
    Hreg6 Hreg7 Hlen.
  assert (Hreg6' : Forall q6_pass (region ++ map match_mark bits)).
  { apply Forall_app. split; [exact Hreg6 | apply Forall_q6_match_marks]. }
  assert (Hreg7' : Forall q7_pass (region ++ map match_mark bits)).
  { apply Forall_app. split; [exact Hreg7 | apply Forall_q7_match_marks]. }
  rewrite dispatch_run_add.
  rewrite (canonical_q6_copy_all bits
    (4 :: rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
    ((region ++ map match_mark bits) ++
     (map source_bit action_bits ++ source_bit dir :: rest))
    [] (region ++ map match_mark bits) action_bits (source_bit dir :: rest)
    tbuffer data eq_refl eq_refl (eq_sym Hlen)
    (Forall_nil q7_pass) (Forall_nil q9_pass) Hreg6' Hreg7').
  cbn [app].
  replace (region ++ map match_mark bits ++ map match_mark action_bits)
    with ((region ++ map match_mark bits) ++ map match_mark action_bits)
    by (symmetry; apply app_assoc).
  replace ((region ++ map match_mark bits) ++
           (map match_mark action_bits ++ source_bit dir :: rest))
    with (((region ++ map match_mark bits) ++ map match_mark action_bits) ++
          (source_bit dir :: rest))
    by (symmetry; apply app_assoc).
  change (run (direction_clock
      ((region ++ map match_mark bits) ++ map match_mark action_bits)
      (map match_mark action_bits))
    (entry_config 6
      (4 :: rev (map match_mark action_bits) ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (((region ++ map match_mark bits) ++ map match_mark action_bits) ++
       source_bit dir :: rest)) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark action_bits) ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (4 :: ((region ++ map match_mark bits) ++ map match_mark action_bits) ++
       (if dir then 3 else 2) :: rest)).
  apply (canonical_q6_direction_capture
    ((region ++ map match_mark bits) ++ map match_mark action_bits)
    (map match_mark action_bits) rest tbuffer data dir).
  - apply Forall_app. split.
    + exact Hreg6'.
    + apply Forall_q6_match_marks.
  - apply Forall_app. split.
    + exact Hreg7'.
    + apply Forall_q7_match_marks.
  - apply Forall_q7_match_marks.
  - apply Forall_match_mark_q9.
Qed.

Print Assumptions book_q1_mismatch_restart.
Print Assumptions book_locate_two_rows_to_q6.
Print Assumptions book_q6_region_to_q12.

(** ** Frame compatibility with the perform half

    [book_locate_two_rows_to_q6] ends at

      region ++ marks(bits) ++ raws(action2) ++ dir2 :: 5 :: tail

    where [region = book_skip_region row1 action1 dir1].  The adapter
    [book_q6_region_to_q12] takes the same tape with the association

      (region ++ marks(bits)) ++ (raws(action2) ++ dir2 :: 5 :: tail).

    These are the two remaining interface facts for the complete
    locate -> perform composition. *)

Lemma Forall_q6_book_skip_region :
  forall row action dir,
    Forall q6_pass (book_skip_region row action dir).
Proof.
  intros row action dir.
  unfold book_skip_region.
  repeat rewrite Forall_app.
  repeat split.
  - apply Forall_q6_match_marks.
  - apply Forall_q6_match_marks.
  - constructor; [apply q6_pass_match_mark | constructor].
  - constructor; [unfold q6_pass; auto 10 | constructor].
Qed.

Lemma Forall_q7_book_skip_region :
  forall row action dir,
    Forall q7_pass (book_skip_region row action dir).
Proof.
  intros row action dir.
  unfold book_skip_region.
  repeat rewrite Forall_app.
  repeat split.
  - apply Forall_q7_match_marks.
  - apply Forall_q7_match_marks.
  - constructor; [apply q7_pass_match_mark | constructor].
  - constructor; [unfold q7_pass; auto 10 | constructor].
Qed.

Lemma book_locate_q6_region_frame :
  forall (region : list nat) (bits action2 : list bool) (dir2 : bool)
         (tail : list nat),
    region ++ map match_mark bits ++ map source_bit action2 ++
    [source_bit dir2] ++ 5 :: tail =
    (region ++ map match_mark bits) ++
    (map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail).
Proof.
  intros. apply app_assoc.
Qed.

Print Assumptions book_locate_q6_region_frame.

(** ** Composed two-row locate -> q12

    This composes the locate theorem with the region-general q6 adapter,
    so the whole q5 -> q1 -> q3/q5 restart -> q1 -> q6 -> q12 phase is one
    exact native run for the two-row description.  The q6 copy phase
    requires the action field to have the same length as the condition,
    which is the only extra well-formedness hypothesis. *)

Corollary book_locate_two_rows_to_q12 :
  forall (good restbits row1_rest action1 action2 : list bool)
         (b dir1 dir2 : bool) (buf : nat) (ptape tail : list nat),
    length action2 = length (good ++ b :: restbits) ->
    run (((length (good ++ b :: restbits) + 2) +
          (matched_comparison_steps good 0
             (length (map match_mark (b :: restbits) ++ [4])) +
           (book_mismatch_clock b good restbits row1_rest action1 dir1 +
            (matched_comparison_steps (good ++ b :: restbits) 0
               (length (book_match_done
                  (good ++ negb b :: row1_rest) action1 dir1)) +
             (length (good ++ b :: restbits) + 1))))) +
         (copy_all_clock (good ++ b :: restbits) action2 []
            (book_skip_region (good ++ negb b :: row1_rest) action1 dir1 ++
             map match_mark (good ++ b :: restbits)) +
          direction_clock
            (book_skip_region (good ++ negb b :: row1_rest) action1 dir1 ++
             map match_mark (good ++ b :: restbits) ++ map match_mark action2)
            (map match_mark action2)))
      (entry_config 5
        (rev (map source_bit (good ++ b :: restbits)) ++
         5 :: rev (book_buf buf) ++ 6 :: rev ptape)
        (4 :: map source_bit (good ++ negb b :: row1_rest) ++
         map source_bit action1 ++ [source_bit dir1] ++
         4 :: map source_bit (good ++ b :: restbits) ++
         map source_bit action2 ++ [source_bit dir2] ++ 5 :: tail)) =
    cfg_ml (if dir2 then 12 else 13)
      (rev (map match_mark action2) ++
       5 :: rev (book_buf buf) ++ 6 :: rev ptape)
      (4 :: ((book_skip_region (good ++ negb b :: row1_rest) action1 dir1 ++
              map match_mark (good ++ b :: restbits)) ++
             map match_mark action2) ++
       (if dir2 then 3 else 2) :: 5 :: tail).
Proof.
  intros good restbits row1_rest action1 action2 b dir1 dir2 buf ptape tail Hlen.
  rewrite (dispatch_run_add
    ((length (good ++ b :: restbits) + 2) +
     (matched_comparison_steps good 0
        (length (map match_mark (b :: restbits) ++ [4])) +
      (book_mismatch_clock b good restbits row1_rest action1 dir1 +
       (matched_comparison_steps (good ++ b :: restbits) 0
          (length (book_match_done
             (good ++ negb b :: row1_rest) action1 dir1)) +
        (length (good ++ b :: restbits) + 1)))))
    (copy_all_clock (good ++ b :: restbits) action2 []
       (book_skip_region (good ++ negb b :: row1_rest) action1 dir1 ++
        map match_mark (good ++ b :: restbits)) +
     direction_clock
       (book_skip_region (good ++ negb b :: row1_rest) action1 dir1 ++
        map match_mark (good ++ b :: restbits) ++ map match_mark action2)
       (map match_mark action2))).
  rewrite book_locate_two_rows_to_q6.
  rewrite book_locate_q6_region_frame.
  cbn [app].
  apply (book_q6_region_to_q12
    (book_skip_region (good ++ negb b :: row1_rest) action1 dir1)
    (good ++ b :: restbits) action2 dir2 (book_buf buf) ptape (5 :: tail)).
  - apply Forall_q6_book_skip_region.
  - apply Forall_q7_book_skip_region.
  - exact Hlen.
Qed.

Print Assumptions book_locate_two_rows_to_q12.
