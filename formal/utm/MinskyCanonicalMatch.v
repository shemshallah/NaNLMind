(** * Canonical q5 match scan to q6 for the frozen 23x8 table

    This module generalizes the q1 comparison macros so that the route
    X=4 delimiter may occur inside the already-marked prefix.  That is
    exactly what the canonical compiler layout requires: after the q5
    left scan, the marked condition bits and the raw record bits are
    separated by the record's X=4.

    The main result starts at the canonical q5 entry with the source
    condition to the left of Y, runs the q5 left scan, compares all
    condition bits against the record's current-state/read prefix, and
    reaches q6.  It is a concrete native-table phase composition, not a
    source-instruction theorem or a universality claim.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyMatchMacro MinskyConcreteDispatch.

(** Marked cells that may be crossed by the q0/q4 comparison scan.  This
    is [comparison_mark] plus the record delimiter X=4.  It still excludes
    Y=5, which would terminate the left dispatch instead of being crossed. *)
Definition wide_mark (s : nat) : Prop :=
  s = 2 \/ s = 3 \/ s = 4 \/ s = 6 \/ s = 7.

Lemma wide_match_mark_valid :
  forall bits, Forall wide_mark (map match_mark bits).
Proof.
  induction bits as [|b rest IH]; simpl [map].
  - constructor.
  - constructor.
    + destruct b; unfold wide_mark, match_mark; auto.
    + exact IH.
Qed.


Lemma wide_mark_scans :
  forall marks,
    Forall wide_mark marks ->
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
      * destruct Hm as [-> | [-> | [-> | [-> | ->]]]]; unfold q0_pass; auto 10.
      * exact H0.
    + constructor.
      * destruct Hm as [-> | [-> | [-> | [-> | ->]]]]; unfold q4_pass; auto 10.
      * exact H4.
    + simpl [rev].
      apply Forall_app; split.
      * exact Hleft.
      * constructor.
        -- destruct Hm as [-> | [-> | [-> | [-> | ->]]]]; unfold dispatch_left_symbol; auto 10.
        -- constructor.
Qed.

(** These two concrete one-round macros permit an arbitrarily long block
    of previously marked bits between the selected A/B and the next raw
    input bit.  Both tapes and exact transition counts are quantified. *)
Theorem q1_zero_match_with_wide_marks :
  forall pass marks prefix tail,
    Forall q1_pass pass ->
    Forall wide_mark marks ->
    run (2 * length pass + 2 * length marks + 4)
      (entry_config 1 (5 :: prefix) (pass ++ 2 :: marks ++ 0 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 0 :: marks ++ 2 :: tail).
Proof.
  intros pass marks prefix tail Hpass Hmarks.
  destruct (wide_mark_scans marks Hmarks) as [Hq0 [_ Hrevleft]].
  assert (Hleft : Forall dispatch_left_symbol (rev marks ++ 0 :: rev pass)).
  { apply Forall_app; split.
    - exact Hrevleft.
    - constructor.
      + unfold dispatch_left_symbol; auto 10.
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

Theorem q1_one_match_with_wide_marks :
  forall pass marks prefix tail,
    Forall q1_pass pass ->
    Forall wide_mark marks ->
    run (2 * length pass + 2 * length marks + 4)
      (entry_config 1 (5 :: prefix) (pass ++ 3 :: marks ++ 1 :: tail)) =
    entry_config 1 (5 :: prefix) (pass ++ 1 :: marks ++ 3 :: tail).
Proof.
  intros pass marks prefix tail Hpass Hmarks.
  destruct (wide_mark_scans marks Hmarks) as [_ [Hq4 Hrevleft]].
  assert (Hleft : Forall dispatch_left_symbol (rev marks ++ 1 :: rev pass)).
  { apply Forall_app; split.
    - exact Hrevleft.
    - constructor.
      + unfold dispatch_left_symbol; auto 10.
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

Print Assumptions wide_mark_scans.
Print Assumptions q1_zero_match_with_wide_marks.
Print Assumptions q1_one_match_with_wide_marks.

Lemma q1_match_one_bit_with_wide_marks :
  forall b pass marks prefix tail,
    Forall q1_pass pass ->
    Forall wide_mark marks ->
    run (2 * length pass + 2 * length marks + 4)
      (entry_config 1 (5 :: prefix)
        (pass ++ match_mark b :: marks ++ match_raw b :: tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ match_raw b :: marks ++ match_mark b :: tail).
Proof.
  intros [|] pass marks prefix tail Hpass Hmarks; simpl [match_mark match_raw].
  - apply q1_one_match_with_wide_marks; assumption.
  - apply q1_zero_match_with_wide_marks; assumption.
Qed.

Theorem q1_all_matching_bits_wide :
  forall bits pass done prefix tail,
    Forall q1_pass pass ->
    Forall wide_mark done ->
    run (matched_comparison_steps bits (length pass) (length done))
      (entry_config 1 (5 :: prefix)
        (pass ++ map match_mark bits ++ done ++ map match_raw bits ++ tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ map match_raw bits ++ done ++ map match_mark bits ++ tail).
Proof.
  induction bits as [|b rest IH]; intros pass done prefix tail Hpass Hdone.
  - reflexivity.
  - simpl [matched_comparison_steps map].
    assert (Hmarks : Forall wide_mark (map match_mark rest ++ done)).
    { apply Forall_app; split.
      - apply wide_match_mark_valid.
      - exact Hdone. }
    assert (Hpass' : Forall q1_pass (pass ++ [match_raw b])).
    { apply Forall_app; split.
      - exact Hpass.
      - constructor.
        + destruct b; unfold q1_pass, match_raw; auto.
        + constructor. }
    assert (Hdone' : Forall wide_mark (done ++ [match_mark b])).
    { apply Forall_app; split.
      - exact Hdone.
      - constructor.
        + destruct b; unfold wide_mark, match_mark; auto.
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
    rewrite (q1_match_one_bit_with_wide_marks b pass
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


Lemma entry_rewrite_source_bit :
  forall b,
    entry_rewrite (source_bit b) = match_mark b.
Proof. intros []; reflexivity. Qed.

(** The canonical q5 phase.  The head starts on the first record X=4;
    the source condition (state bits and read bit) is immediately to its
    left, followed by Y=5, the t-buffer, M=6 and the data tape.  q5 scans
    left over the condition to Y and returns q1 with the condition
    rewritten 0->2 / 1->3 on the right of the record X. *)
Theorem canonical_q5_scan :
  forall bits tbuffer data record_tail,
    run (length bits + 2)
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++ record_tail)) =
    entry_config 1
      (5 :: rev tbuffer ++ 6 :: rev data)
      (map match_mark bits ++ [4] ++ map source_bit bits ++ record_tail).
Proof.
  intros bits tbuffer data record_tail.
  assert (Hscan : Forall entry_scan_symbol
    (4 :: rev (map source_bit bits))).
  {
    constructor.
    - unfold entry_scan_symbol; auto 10.
    - apply Forall_rev.
      induction bits as [|b rest IH]; simpl.
      + constructor.
      + constructor.
        * destruct b; unfold entry_scan_symbol, source_bit; auto 10.
        * exact IH.
  }
  replace (length bits + 2)
    with (S (length (4 :: rev (map source_bit bits))))
    by (cbn [length]; rewrite rev_length, map_length; lia).
  rewrite (entry_scan_unbounded (rev (map source_bit bits)) 4
    (rev tbuffer ++ 6 :: rev data)
    (map source_bit bits ++ record_tail) Hscan).
  cbn [rev].
  rewrite rev_involutive.
  rewrite map_app.
  cbn [map].
  rewrite map_map.
  replace (map (fun b => entry_rewrite (source_bit b)) bits)
    with (map match_mark bits)
    by (apply map_ext; intro b; symmetry; apply entry_rewrite_source_bit).
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma q1_all_matching_bits_wide_nil :
  forall bits done prefix tail,
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

Lemma q1_all_matching_bits_wide_four :
  forall bits prefix tail,
    run (matched_comparison_steps bits 0 1)
      (entry_config 1 (5 :: prefix)
        (map match_mark bits ++ [4] ++ map match_raw bits ++ tail)) =
    entry_config 1 (5 :: prefix)
      (map match_raw bits ++ [4] ++ map match_mark bits ++ tail).
Proof.
  intros bits prefix tail.
  change (run (matched_comparison_steps bits 0 (length [4]))
    (entry_config 1 (5 :: prefix)
      (map match_mark bits ++ [4] ++ map match_raw bits ++ tail)) =
    entry_config 1 (5 :: prefix)
      (map match_raw bits ++ [4] ++ map match_mark bits ++ tail)).
  apply q1_all_matching_bits_wide_nil.
  constructor; [unfold wide_mark; auto 10 | constructor].
Qed.

Lemma q1_scan_four_list_to_q6 :
  forall pass tail left,
    Forall q1_pass pass ->
    run (S (length pass))
      (entry_config 1 left (pass ++ [4] ++ tail)) =
    entry_config 6 (4 :: rev pass ++ left) tail.
Proof.
  intros pass tail left Hpass.
  change (run (S (length pass))
    (entry_config 1 left (pass ++ 4 :: tail)) =
    entry_config 6 (4 :: rev pass ++ left) tail).
  apply q1_scan_pick.
  - exact Hpass.
  - right; right; reflexivity.
Qed.

Print Assumptions canonical_q5_scan.

(** The canonical first instruction-match phase.  The q5 scan is followed
    by the q1 all-match comparison against the record's current-state and
    read prefix, then q1 skips the restored condition and crosses X=4 into
    q6.  The X=4 sits inside [wide_mark], which is why the comparison
    macros are generalized in this module.

    The theorem starts at the literal canonical q5 entry and ends at the
    literal q6 entry with the data/t-buffer untouched.  It does not yet
    prove source-row selection, writeback, movement, or halting. *)
Theorem canonical_q5_match_to_q6 :
  forall bits tbuffer data tail,
    run ((length bits + 2) +
         (matched_comparison_steps bits 0 1 + (length bits + 1)))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++ tail)) =
    entry_config 6
      (4 :: rev (map match_raw bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
      (map match_mark bits ++ tail).
Proof.
  intros bits tbuffer data tail.
  replace ((length bits + 2) +
           (matched_comparison_steps bits 0 1 + (length bits + 1)))
    with ((length bits + 2) +
          (matched_comparison_steps bits 0 1 +
           S (length (map match_raw bits))))
    by (rewrite map_length; lia).
  rewrite dispatch_run_add.
  rewrite canonical_q5_scan.
  cbn [app].
  replace (map source_bit bits) with (map match_raw bits)
    by (apply map_ext; intro b; reflexivity).
  rewrite dispatch_run_add.
  replace (map match_mark bits ++ 4 :: map match_raw bits ++ tail)
    with (map match_mark bits ++ [4] ++ map match_raw bits ++ tail)
    by (repeat rewrite <- app_assoc; reflexivity).
  rewrite (q1_all_matching_bits_wide_four bits
    (rev tbuffer ++ 6 :: rev data) tail).
  rewrite (q1_scan_four_list_to_q6 (map match_raw bits)
    (map match_mark bits ++ tail)
    (5 :: rev tbuffer ++ 6 :: rev data) (match_raw_valid bits)).
  reflexivity.
Qed.

Print Assumptions canonical_q5_match_to_q6.
