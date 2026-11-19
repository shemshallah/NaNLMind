(** * Canonical instruction: q5 fetch through q16 decision

    This module composes

      q5 match  ->  q6 action copy  ->  q9/q10 direction capture
      ->  q12/q13 restore  ->  q15 scan across the next X=4
      ->  q16 decision.

    The result is the exact q21/q22 entry for one wide record.  It is
    still a macro phase: writeback, relocation, halt and the whole-source
    representation invariant remain open.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyConcreteDispatch MinskyMatchMacro
  MinskyActionMacro MinskyHeadMoveMacro MinskyDirectionDecision
  MinskyCanonicalMatch
  MinskyCanonicalCopy MinskyCanonicalCopyGeneral MinskyCanonicalDirection
  MinskyCanonicalRestore MinskyCanonicalDecision MinskyCanonicalFetch.

Definition fetch_clock (bits action_bits : list bool) : nat :=
  ((length bits + 2) +
   (matched_comparison_steps bits 0 1 + (length bits + 1))) +
  copy_all_clock bits action_bits [] (map match_mark bits).

Definition direction_clock
    (marked record_marks : list nat) : nat :=
  S (length marked) +
  (S (length (rev marked ++ [4] ++ rev record_marks)) +
   S (length record_marks)).

Definition restore_clock
    (s : nat) (remaining tbuffer : list nat) : nat :=
  S (length (s :: remaining ++ 5 :: rev tbuffer)) +
  S (length (tbuffer ++ [5] ++ rev remaining ++ [s])).

Definition instruction_marked (bits action_bits : list bool) : list nat :=
  map match_mark bits ++ map match_mark action_bits.

Lemma q12_mark : forall b, q12_pass (match_mark b).
Proof.
  intros b. destruct b; unfold q12_pass, match_mark; auto 10.
Qed.

Lemma q14_mark : forall b, q14_pass (match_mark b).
Proof.
  intros b. destruct b; unfold q14_pass, match_mark; auto 10.
Qed.

Lemma q15_mark : forall b, q15_pass (match_mark b).
Proof.
  intros b. destruct b; unfold q15_pass, match_mark; auto 10.
Qed.

Lemma rev_match_mark_snoc :
  forall (init : list bool) b,
    rev (map match_mark (init ++ [b])) =
    match_mark b :: rev (map match_mark init).
Proof.
  intros init b.
  rewrite map_app. rewrite rev_app_distr. cbn [rev].
  reflexivity.
Qed.

Theorem canonical_q5_fetch_to_q16_decision :
  forall bits action_init tbuffer data (b dir : bool) bit tail,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    run ((fetch_clock bits (action_init ++ [b]) +
          direction_clock
            (instruction_marked bits (action_init ++ [b]))
            (map match_mark (action_init ++ [b]))) +
         ((restore_clock (match_mark b)
             (rev (map match_mark action_init)) tbuffer +
           S (length
             (instruction_marked bits (action_init ++ [b]) ++
              [(if dir then 3 else 2)] ++ [4]))) +
          S (length
            (4 :: rev
              (instruction_marked bits (action_init ++ [b]) ++
               [(if dir then 3 else 2)]) ++ [4]))))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit dir :: 4 :: source_bit bit :: tail)) =
    cfg_ml (if b then 22 else 21)
      (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer) ++
       (if dir then 3 else 2) :: rev data)
      (7 :: map q16_restore
        (rev
          (4 :: rev
            (instruction_marked bits (action_init ++ [b]) ++
             [(if dir then 3 else 2)]) ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data b dir bit tail Hlen H12t H14t.
  assert (H12 : Forall q12_pass
      (match_mark b :: rev (map match_mark action_init) ++
       5 :: rev tbuffer)).
  {
    constructor.
    - apply q12_mark.
    - rewrite Forall_app. split.
      + apply Forall_rev. apply Forall_match_mark. intros x. apply q12_mark.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_rev. exact H12t.
  }
  assert (H14 : Forall q14_pass
      (tbuffer ++ [5] ++ rev (rev (map match_mark action_init)) ++
       [match_mark b])).
  {
    rewrite rev_involutive.
    rewrite Forall_app. split. { exact H14t. }
    rewrite Forall_app. split.
    { constructor.
      - unfold q14_pass; auto 10.
      - constructor. }
    rewrite Forall_app. split.
    { apply Forall_match_mark. intros x. apply q14_mark. }
    { constructor.
      - apply q14_mark.
      - constructor. }
  }
  assert (H15_3 : Forall q15_pass
      (instruction_marked bits (action_init ++ [b]) ++ [3] ++ [4])).
  {
    unfold instruction_marked.
    rewrite Forall_app. split.
    { rewrite Forall_app. split.
      + apply Forall_match_mark. intros x. apply q15_mark.
      + apply Forall_match_mark. intros x. apply q15_mark. }
    rewrite Forall_app. split.
    { constructor.
      - unfold q15_pass; auto 10.
      - constructor. }
    { constructor.
      - unfold q15_pass; auto 10.
      - constructor. }
  }
  assert (H15_2 : Forall q15_pass
      (instruction_marked bits (action_init ++ [b]) ++ [2] ++ [4])).
  {
    unfold instruction_marked.
    rewrite Forall_app. split.
    { rewrite Forall_app. split.
      + apply Forall_match_mark. intros x. apply q15_mark.
      + apply Forall_match_mark. intros x. apply q15_mark. }
    rewrite Forall_app. split.
    { constructor.
      - unfold q15_pass; auto 10.
      - constructor. }
    { constructor.
      - unfold q15_pass; auto 10.
      - constructor. }
  }
  destruct dir.
  - rewrite dispatch_run_add.
    unfold fetch_clock, direction_clock, restore_clock, instruction_marked.
    rewrite (canonical_q5_match_copy_direction bits (action_init ++ [b])
      tbuffer data true (4 :: source_bit bit :: tail) Hlen).
    rewrite rev_match_mark_snoc.
    apply (canonical_q12_restore_q16_decision_next
      (rev (map match_mark action_init)) tbuffer data
      (map match_mark bits ++ map match_mark (action_init ++ [b]))
      b bit tail H12 H14 H15_3).
  - rewrite dispatch_run_add.
    unfold fetch_clock, direction_clock, restore_clock, instruction_marked.
    rewrite (canonical_q5_match_copy_direction bits (action_init ++ [b])
      tbuffer data false (4 :: source_bit bit :: tail) Hlen).
    rewrite rev_match_mark_snoc.
    apply (canonical_q13_restore_q16_decision_next
      (rev (map match_mark action_init)) tbuffer data
      (map match_mark bits ++ map match_mark (action_init ++ [b]))
      b bit tail H12 H14 H15_2).
Qed.

Print Assumptions canonical_q5_fetch_to_q16_decision.

Lemma Forall_q14_restore_q21 :
  forall l, Forall q14_pass l -> Forall q21_pass (map q14_restore l).
Proof.
  induction l as [|x xs IH]; intros H.
  - constructor.
  - inversion H as [|? ? Hx Hxs]; subst.
    constructor.
    + destruct Hx as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
        unfold q14_restore, q21_pass; auto 10.
    + apply IH. exact Hxs.
Qed.

(** The instruction result reaches q19 (right, marker 3). *)
Theorem canonical_q5_instruction_to_q19 :
  forall bits action_init tbuffer data b bit tail,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    run (((fetch_clock bits (action_init ++ [b]) +
           direction_clock
             (instruction_marked bits (action_init ++ [b]))
             (map match_mark (action_init ++ [b]))) +
          ((restore_clock (match_mark b)
              (rev (map match_mark action_init)) tbuffer +
            S (length
              (instruction_marked bits (action_init ++ [b]) ++ [3] ++ [4]))) +
           S (length
             (4 :: rev
               (instruction_marked bits (action_init ++ [b]) ++ [3]) ++ [4])))) +
         S (length
           (map q14_restore
             (rev (map match_mark action_init) ++ 5 :: rev tbuffer))))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit true :: 4 :: source_bit bit :: tail)) =
    entry_config 19 (source_bit b :: rev data)
      (rev (map q14_restore
             (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) ++
       7 :: map q16_restore
              (rev (4 :: rev
                (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
               [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data b bit tail Hlen H12t H14t.
  assert (Hq21D : Forall q21_pass
      (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer))).
  {
    rewrite Forall_app. split.
    - apply Forall_q14_restore_q21. apply Forall_rev.
      apply Forall_match_mark.
      intros x. destruct x; unfold q14_pass, match_mark; auto 10.
    - rewrite Forall_app. split.
      + constructor.
        * unfold q21_pass; auto 10.
        * constructor.
      + apply Forall_q14_restore_q21. apply Forall_rev. exact H14t.
  }
  assert (Hq : (if b then 22 else 21) = 21 \/
               (if b then 22 else 21) = 22)
    by (destruct b; simpl; auto).
  rewrite dispatch_run_add.
  rewrite (canonical_q5_fetch_to_q16_decision bits action_init tbuffer
    data b true bit tail Hlen H12t H14t).
  destruct (map q14_restore
    (rev (map match_mark action_init) ++ 5 :: rev tbuffer))
    as [|s D'] eqn:HD2.
  - rewrite HD2 in Hq21D. cbn [length].
    change (step
      (entry_config (if b then 22 else 21) (rev data)
        (3 :: 7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                [4])) ++ source_bit bit :: tail)) =
      entry_config 19 (source_bit b :: rev data)
        (7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                [4])) ++ source_bit bit :: tail)).
    apply q21_cross_right. exact Hq.
  - cbn [length].
    change (run (S (length (s :: D')))
      (entry_config (if b then 22 else 21) (D' ++ 3 :: rev data)
        (s :: 7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                [4])) ++ source_bit bit :: tail)) =
      entry_config 19 (source_bit b :: rev data)
        (rev (s :: D') ++
         7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                [4])) ++ source_bit bit :: tail)).
    assert (Hscan : Forall q21_pass (s :: D')).
    { rewrite HD2 in Hq21D. exact Hq21D. }
    rewrite (q21_scan_to_right_direction D' s
      (if b then 22 else 21) (rev data)
      (7 :: map q16_restore
             (rev (4 :: rev
               (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
              [4])) ++ source_bit bit :: tail) Hq Hscan).
    destruct b; reflexivity.
Qed.

(** The instruction result reaches q20 (left, marker 2). *)
Theorem canonical_q5_instruction_to_q20 :
  forall bits action_init tbuffer data b bit tail,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    run (((fetch_clock bits (action_init ++ [b]) +
           direction_clock
             (instruction_marked bits (action_init ++ [b]))
             (map match_mark (action_init ++ [b]))) +
          ((restore_clock (match_mark b)
              (rev (map match_mark action_init)) tbuffer +
            S (length
              (instruction_marked bits (action_init ++ [b]) ++ [2] ++ [4]))) +
           S (length
             (4 :: rev
               (instruction_marked bits (action_init ++ [b]) ++ [2]) ++ [4])))) +
         S (length
           (map q14_restore
             (rev (map match_mark action_init) ++ 5 :: rev tbuffer))))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit false :: 4 :: source_bit bit :: tail)) =
    cfg_ml 20 (rev data)
      (source_bit b ++
       rev (map q14_restore
             (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) ++
       7 :: map q16_restore
              (rev (4 :: rev
                (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
               [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data b bit tail Hlen H12t H14t.
  assert (Hq21D : Forall q21_pass
      (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer))).
  {
    rewrite Forall_app. split.
    - apply Forall_q14_restore_q21. apply Forall_rev.
      apply Forall_match_mark.
      intros x. destruct x; unfold q14_pass, match_mark; auto 10.
    - rewrite Forall_app. split.
      + constructor.
        * unfold q21_pass; auto 10.
        * constructor.
      + apply Forall_q14_restore_q21. apply Forall_rev. exact H14t.
  }
  assert (Hq : (if b then 22 else 21) = 21 \/
               (if b then 22 else 21) = 22)
    by (destruct b; simpl; auto).
  rewrite dispatch_run_add.
  rewrite (canonical_q5_fetch_to_q16_decision bits action_init tbuffer
    data b false bit tail Hlen H12t H14t).
  destruct (map q14_restore
    (rev (map match_mark action_init) ++ 5 :: rev tbuffer))
    as [|s D'] eqn:HD2.
  - rewrite HD2 in Hq21D. cbn [length].
    change (step
      (entry_config (if b then 22 else 21) (rev data)
        (2 :: 7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
                [4])) ++ source_bit bit :: tail)) =
      cfg_ml 20 (rev data)
        (source_bit b ::
         7 :: map q16_restore
                (rev (4 :: rev
                  (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
                 [4])) ++ source_bit bit :: tail)).
    apply q21_cross_left. exact Hq.
  - cbn [length].
    change (run (S (length (s :: D')))
      (entry_config (if b then 22 else 21) (D' ++ 2 :: rev data)
        (s :: 7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
                [4])) ++ source_bit bit :: tail)) =
      cfg_ml 20 (rev data)
        (source_bit b :: rev (s :: D') ++
         7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
                [4])) ++ source_bit bit :: tail)).
    assert (Hscan : Forall q21_pass (s :: D')).
    { rewrite HD2 in Hq21D. exact Hq21D. }
    rewrite (q21_scan_to_left_direction D' s
      (if b then 22 else 21) (rev data)
      (7 :: map q16_restore
             (rev (4 :: rev
               (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
              [4])) ++ source_bit bit :: tail) Hq Hscan).
    destruct b; reflexivity.
Qed.

Print Assumptions canonical_q5_instruction_to_q19.
Print Assumptions canonical_q5_instruction_to_q20.
