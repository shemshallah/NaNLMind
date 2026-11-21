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
  MinskyActionMacro MinskyHeadMoveMacro MinskyRelocationMacro
  MinskyDirectionDecision MinskyCanonicalMatch
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
    rewrite map_app.
    rewrite Forall_app. split.
    - apply Forall_q14_restore_q21. apply Forall_rev.
      apply Forall_match_mark.
      intros x. destruct x; unfold q14_pass, match_mark; auto 10.
    - cbn [map]. constructor.
      + unfold q21_pass; auto 10.
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
  - destruct b.
    + cbn [length run cfg_ml].
      apply q21_cross_right. auto.
    + cbn [length run cfg_ml].
      apply q21_cross_right. auto.
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
    { exact Hq21D. }
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
      (source_bit b ::
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
    rewrite map_app.
    rewrite Forall_app. split.
    - apply Forall_q14_restore_q21. apply Forall_rev.
      apply Forall_match_mark.
      intros x. destruct x; unfold q14_pass, match_mark; auto 10.
    - cbn [map]. constructor.
      + unfold q21_pass; auto 10.
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
  - destruct b.
    + cbn [length run cfg_ml].
      apply q21_cross_left. auto.
    + cbn [length run cfg_ml].
      apply q21_cross_left. auto.
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
    { exact Hq21D. }
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

Definition raw_or_pass (x : nat) : Prop :=
  x = 0 \/ x = 1 \/ q15_pass x.

Lemma q14_restore_raw_or_pass :
  forall x, q14_pass x -> raw_or_pass (q14_restore x).
Proof.
  intros x Hx.
  destruct Hx as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    unfold raw_or_pass, q14_restore, q15_pass; auto 10.
Qed.

Lemma Forall_map_q14_restore_raw :
  forall l, Forall q14_pass l -> Forall raw_or_pass (map q14_restore l).
Proof.
  induction l as [|x xs IH]; intros H.
  - constructor.
  - inversion H as [|? ? Hx Hxs]; subst.
    constructor.
    + apply q14_restore_raw_or_pass. exact Hx.
    + apply IH. exact Hxs.
Qed.

Lemma Forall_map_source_bit_raw :
  forall l, Forall raw_or_pass (map source_bit l).
Proof.
  induction l as [|x xs IH].
  - constructor.
  - constructor.
    + destruct x; unfold raw_or_pass, source_bit; auto.
    + exact IH.
Qed.

Lemma first_raw_decomp :
  forall l,
    Forall raw_or_pass l ->
    (exists x, In x l /\ (x = 0 \/ x = 1)) ->
    exists pre (bit : bool) post,
      l = pre ++ source_bit bit :: post /\ Forall q15_pass pre.
Proof.
  induction l as [|x xs IH]; intros Hraw Hsome.
  - destruct Hsome as [y [Hin _]]. inversion Hin.
  - inversion Hraw as [|? ? Hx Hxs]; subst.
    destruct Hx as [-> | [-> | Hxp]].
    + exists [], false, xs. split.
      * reflexivity.
      * constructor.
    + exists [], true, xs. split.
      * reflexivity.
      * constructor.
    + destruct Hsome as [y [Hy Hrawy]].
      destruct Hy as [-> | Hy].
      * exfalso.
        destruct Hrawy as [-> | ->];
          destruct Hxp as [H | [H | [H | [H | [H | H]]]]];
          discriminate H.
      * destruct (IH Hxs (ex_intro _ y (conj Hy Hrawy)))
          as [pre [bit [post [Heq Hpre]]]].
        exists (x :: pre), bit, post. split.
        -- cbn [app]. rewrite Heq. reflexivity.
        -- constructor; assumption.
Qed.

Lemma rev_restored_action_block :
  forall (action : list bool) (tbuffer : list nat),
    rev (map q14_restore
      (rev (map match_mark action) ++ 5 :: rev tbuffer)) =
    map q14_restore tbuffer ++ [5] ++ map source_bit action.
Proof.
  intros action tbuffer.
  rewrite <- map_rev.
  rewrite rev_app_distr.
  cbn [rev].
  repeat rewrite rev_involutive.
  rewrite map_app. cbn [map].
  rewrite map_app.
  rewrite map_map.
  replace (map (fun x => q14_restore (match_mark x)) action)
    with (map source_bit action)
    by (apply map_ext; intro x; destruct x; reflexivity).
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Definition instruction_q19_clock
    (bits action_init : list bool) (tbuffer : list nat) (b : bool) : nat :=
  ((fetch_clock bits (action_init ++ [b]) +
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
      (rev (map match_mark action_init) ++ 5 :: rev tbuffer))).

(** If the restored action block contains a raw 0/1 cell, q19's first
    relocation target is that cell, before the 7 written by q16. *)
Theorem canonical_q5_instruction_q19_hits_restored_raw :
  forall bits action_init tbuffer data b bit tail,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    (exists x,
      In x (rev (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) /\
      (x = 0 \/ x = 1)) ->
    exists pre (hit : bool) post,
      rev (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) =
        pre ++ source_bit hit :: post /\
      Forall q15_pass pre /\
      run (instruction_q19_clock bits action_init tbuffer b +
           S (length pre))
        (entry_config 5
          (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
          (4 :: map source_bit bits ++
           map source_bit (action_init ++ [b]) ++
           source_bit true :: 4 :: source_bit bit :: tail)) =
      entry_config (if hit then 18 else 17)
        (6 :: rev pre ++ source_bit b :: rev data)
        (post ++
         7 :: map q16_restore
                (rev (4 :: rev
                  (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                 [4])) ++
         source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data b bit tail Hlen H12t H14t HrawIn.
  assert (Hraw : Forall raw_or_pass
      (rev (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))).
  {
    rewrite rev_restored_action_block.
    repeat rewrite Forall_app. repeat split.
    - apply Forall_map_q14_restore_raw. exact H14t.
    - constructor.
      + unfold raw_or_pass, q15_pass; auto 10.
      + constructor.
    - apply Forall_map_source_bit_raw.
  }
  destruct (first_raw_decomp
    (rev (map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))
    Hraw HrawIn) as [pre [hit [post [Heq Hpre]]]].
  exists pre, hit, post. split.
  { exact Heq. }
  split.
  { exact Hpre. }
  rewrite dispatch_run_add.
  unfold instruction_q19_clock.
  rewrite (canonical_q5_instruction_to_q19 bits action_init tbuffer
    data b bit tail Hlen H12t H14t).
  rewrite Heq.
  replace ((pre ++ source_bit hit :: post) ++
           7 :: map q16_restore
                  (rev (4 :: rev
                    (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                   [4])) ++
           source_bit bit :: tail)
    with (pre ++ source_bit hit ::
           (post ++
            7 :: map q16_restore
                   (rev (4 :: rev
                     (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                    [4])) ++
            source_bit bit :: tail))
    by (rewrite <- app_assoc; reflexivity).
  rewrite (q19_scan_to_m pre hit (source_bit b :: rev data)
    (post ++
     7 :: map q16_restore
            (rev (4 :: rev
              (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
             [4])) ++
     source_bit bit :: tail) Hpre).
  reflexivity.
Qed.

Print Assumptions canonical_q5_instruction_q19_hits_restored_raw.

Lemma rev_restored_action_block_has_raw :
  forall (action : list bool) (tbuffer : list nat),
    action <> [] ->
    exists x,
      In x (rev (map q14_restore
        (rev (map match_mark action) ++ 5 :: rev tbuffer))) /\
      (x = 0 \/ x = 1).
Proof.
  intros action tbuffer Hne.
  rewrite rev_restored_action_block.
  destruct action as [|a rest].
  - contradiction.
  - exists (source_bit a). split.
    + apply in_or_app. right. apply in_or_app. right.
      simpl. auto.
    + destruct a; simpl; auto.
Qed.

(** For any nonempty action prefix, the canonical q19 collision is
    unconditional: q19 captures a restored action cell before the 7. *)
Corollary canonical_q5_instruction_q19_hits_restored_raw_nonempty :
  forall bits action_init tbuffer data b bit tail,
    action_init <> [] ->
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    exists pre (hit : bool) post,
      rev (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) =
        pre ++ source_bit hit :: post /\
      Forall q15_pass pre /\
      run (instruction_q19_clock bits action_init tbuffer b +
           S (length pre))
        (entry_config 5
          (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
          (4 :: map source_bit bits ++
           map source_bit (action_init ++ [b]) ++
           source_bit true :: 4 :: source_bit bit :: tail)) =
      entry_config (if hit then 18 else 17)
        (6 :: rev pre ++ source_bit b :: rev data)
        (post ++
         7 :: map q16_restore
                (rev (4 :: rev
                  (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                 [4])) ++
         source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data b bit tail Hne Hlen H12t H14t.
  apply canonical_q5_instruction_q19_hits_restored_raw; auto.
  apply rev_restored_action_block_has_raw. exact Hne.
Qed.

Print Assumptions canonical_q5_instruction_q19_hits_restored_raw_nonempty.

Definition instruction_q20_clock
    (bits action_init : list bool) (tbuffer : list nat) (b : bool) : nat :=
  ((fetch_clock bits (action_init ++ [b]) +
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
      (rev (map match_mark action_init) ++ 5 :: rev tbuffer))).

(** In the raw canonical frame the q20 head is the current source cell.
    Since `q15_pass` excludes raw 0/1, q20 does not scan left; it applies
    its raw-step immediately and writes 6 on the current cell. *)
Theorem canonical_q5_instruction_left_branch_hits_current_cell :
  forall bits action_init tbuffer data data' b bit tail (d : bool),
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev data = source_bit d :: rev data' ->
    run (instruction_q20_clock bits action_init tbuffer b + 1)
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit false :: 4 :: source_bit bit :: tail)) =
    entry_config (if d then 18 else 17)
      (6 :: rev data')
      (source_bit b ::
       rev (map q14_restore
         (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) ++
       7 :: map q16_restore
              (rev (4 :: rev
                (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
               [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data data' b bit tail d
    Hlen H12t H14t Hdata.
  rewrite dispatch_run_add.
  unfold instruction_q20_clock.
  rewrite (canonical_q5_instruction_to_q20 bits action_init tbuffer
    data b bit tail Hlen H12t H14t).
  rewrite Hdata.
  cbn [run cfg_ml].
  apply q20_raw_to_m.
Qed.

Print Assumptions canonical_q5_instruction_left_branch_hits_current_cell.

(** The left q5/q1 gate is deterministic only for a sacrificial false
    bit.  q1 rewrites the returned old-bit mark and branches:
    2 -> q0 (the intended gate), 3 -> q4 (mismatch path). *)
Theorem canonical_left_gate_branches_on_old_bit :
  forall (old : bool) (left tail : list nat),
    step (entry_config 1 left
      (entry_rewrite (source_bit old) :: tail)) =
    if old
    then entry_config 4 (1 :: left) tail
    else entry_config 0 (0 :: left) tail.
Proof.
  intros old left tail.
  destruct old; reflexivity.
Qed.

Print Assumptions canonical_left_gate_branches_on_old_bit.

(** q3's two reentry/halt exits: on X=4 it enters q5 (already
    `q3_at_marker_step`), and on Y=5 it halts.  This is the native halt
    hook for a source-program end marker. *)
Lemma q3_five_halts :
  forall left tail,
    c_halted (step (entry_config 3 left (5 :: tail))) = true.
Proof.
  intros left tail. reflexivity.
Qed.

Print Assumptions q3_five_halts.

Definition q3_halt_pass (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 6 \/ s = 7.

Lemma q3_halt_pass_step :
  forall s left right,
    q3_halt_pass s ->
    step (entry_config 3 left (s :: right)) =
    entry_config 3 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

(** q3 scans any passable tail to the Y=5 end marker and halts. *)
Theorem q3_scan_to_five_halts :
  forall scanned left tail,
    Forall q3_halt_pass scanned ->
    c_halted
      (run (S (length scanned))
        (entry_config 3 left (scanned ++ 5 :: tail))) = true.
Proof.
  induction scanned as [|s rest IH];
    intros left tail Hscan.
  - cbn [length app run].
    apply q3_five_halts.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    cbn [length app].
    change (c_halted
      (run (S (length rest))
        (step (entry_config 3 left
          (s :: rest ++ 5 :: tail)))) = true).
    rewrite (q3_halt_pass_step s left (rest ++ 5 :: tail) Hs).
    apply IH. exact Hrest.
Qed.

Print Assumptions q3_scan_to_five_halts.

(** Symbol collision for pre-existing tags: 6 is the q12/q13 M
    delimiter, not a passable control tag.  A 6 in the q12/q13 scan
    immediately writes the restored X bit and enters q14. *)
Lemma q12_six_exits_to_q14 :
  forall left tail,
    step (entry_config 12 left (6 :: tail)) =
    entry_config 14 (3 :: left) tail.
Proof. intros left tail. reflexivity. Qed.

Lemma q13_six_exits_to_q14 :
  forall left tail,
    step (entry_config 13 left (6 :: tail)) =
    entry_config 14 (2 :: left) tail.
Proof. intros left tail. reflexivity. Qed.

Print Assumptions q12_six_exits_to_q14.
Print Assumptions q13_six_exits_to_q14.

(** The canonical q14 frame has a leading 4 before the tagged delimiter.
    q16 can absorb that 4 as an extra scanned cell and still stop at the
    raw old delimiter.  This is the checkpoint bridge between the
    canonical restore frame and the tagged movement frame. *)
Theorem q15_q16_four_prefix_roundtrip :
  forall (old target : bool) (tags left suffix : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    run (S (length (rev tags)) + S (length (tags ++ [4])))
      (entry_config 15 (4 :: source_bit old :: left)
        (rev tags ++ source_bit target :: suffix)) =
    cfg_ml (if old then 22 else 21) left
      (7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit target :: suffix).
Proof.
  intros old target tags left suffix H15 H16.
  rewrite dispatch_run_add.
  rewrite (q15_scan_to_raw (rev tags) target
    (4 :: source_bit old :: left) suffix H15).
  rewrite rev_involutive.
  replace (tags ++ 4 :: source_bit old :: left)
    with ((tags ++ [4]) ++ source_bit old :: left)
    by (rewrite <- app_assoc; reflexivity).
  destruct (tags ++ [4]) as [|s remaining] eqn:H.
  - assert (Hlen : length ([] : list nat) = length (tags ++ [4]))
      by (rewrite H; reflexivity).
    rewrite app_length in Hlen. cbn [length] in Hlen. lia.
  - assert (H16' : Forall q16_pass (s :: remaining)) by exact H16.
    cbn [app cfg_ml].
    rewrite (q16_restore_to_raw remaining s old left
      (source_bit target :: suffix) H16').
    reflexivity.
Qed.

Print Assumptions q15_q16_four_prefix_roundtrip.

(** The canonical leading X=4 is carried through the native q15/q16
    scan, then through the q21/q22 direction selector.  This extends
    the bridge beyond q16 without assuming a symbolic direction step.
    Neither branch assumes anything about the outer stored tape. *)
Theorem q15_q16_four_prefix_right_direction :
  forall (old target : bool) (tags : list nat)
         dir_head dir_remaining outer suffix,
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run ((S (length (rev tags)) + S (length (tags ++ [4]))) +
         S (length (dir_head :: dir_remaining)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++ 3 :: outer)
        (rev tags ++ source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit target :: suffix).
Proof.
  intros old target tags dir_head dir_remaining outer suffix H15 H16 H21.
  rewrite dispatch_run_add.
  rewrite (q15_q16_four_prefix_roundtrip old target tags
    (dir_head :: dir_remaining ++ 3 :: outer) suffix H15 H16).
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 3 :: outer)
      (dir_head :: 7 :: map q16_restore
        (rev (tags ++ [4])) ++ source_bit target :: suffix)) =
    entry_config 19 (source_bit old :: outer)
      (rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit target :: suffix)).
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22).
  { destruct old; simpl; auto. }
  rewrite (q21_scan_to_right_direction dir_remaining dir_head
    (if old then 22 else 21) outer
    (7 :: map q16_restore (rev (tags ++ [4])) ++
     source_bit target :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Theorem q15_q16_four_prefix_left_direction :
  forall (old next target : bool) (tags : list nat)
         dir_head dir_remaining outer suffix,
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    run ((S (length (rev tags)) + S (length (tags ++ [4]))) +
         S (length (dir_head :: dir_remaining)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         2 :: source_bit target :: outer)
        (rev tags ++ source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix).
Proof.
  intros old next target tags dir_head dir_remaining outer suffix
    H15 H16 H21.
  rewrite dispatch_run_add.
  rewrite (q15_q16_four_prefix_roundtrip old next tags
    (dir_head :: dir_remaining ++ 2 :: source_bit target :: outer)
    suffix H15 H16).
  change (run (S (length (dir_head :: dir_remaining)))
    (entry_config (if old then 22 else 21)
      (dir_remaining ++ 2 :: source_bit target :: outer)
      (dir_head :: 7 :: map q16_restore
        (rev (tags ++ [4])) ++ source_bit next :: suffix)) =
    cfg_ml 20 (source_bit target :: outer)
      (source_bit old :: rev (dir_head :: dir_remaining) ++
       7 :: map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix)).
  assert (Hq : (if old then 22 else 21) = 21 \/
               (if old then 22 else 21) = 22).
  { destruct old; simpl; auto. }
  rewrite (q21_scan_to_left_direction dir_remaining dir_head
    (if old then 22 else 21) (source_bit target :: outer)
    (7 :: map q16_restore (rev (tags ++ [4])) ++
     source_bit next :: suffix) Hq H21).
  destruct old; reflexivity.
Qed.

Print Assumptions q15_q16_four_prefix_right_direction.
Print Assumptions q15_q16_four_prefix_left_direction.

(** The 4-prefix is the natural next-instruction entry: q1 crosses X=4
    into q6, exactly the canonical action-copy entry. *)
Lemma q1_four_to_q6 :
  forall left tail,
    step (entry_config 1 left (4 :: tail)) =
    entry_config 6 (4 :: left) tail.
Proof. intros left tail. reflexivity. Qed.

Print Assumptions q1_four_to_q6.

(** ** Canonical collision-to-q5 cycles

    The q5 instruction phase always restores the copied action block to
    raw 0/1 cells.  q19 therefore stops at the first restored action bit,
    not at the later source bit.  That first hit is the state-register
    comparison for the next row: q17/q18 relocate it to q5.  The two
    theorems below make this exact native path explicit.  They require
    the post-hit restored tail (right branch) or the whole restored block
    (left branch) to be 7-free, so q17/q18 stop at the 7 written by q16. *)

Theorem canonical_q5_instruction_q19_collision_to_q5 :
  forall bits action_init tbuffer data b bit tail pre hit post,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev (map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) =
      pre ++ source_bit hit :: post ->
    Forall q15_pass pre ->
    Forall q17_pass post ->
    run (instruction_q19_clock bits action_init tbuffer b +
         S (length pre) + S (length post))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit true :: 4 :: source_bit bit :: tail)) =
    cfg_ml 5
      (rev post ++ 6 :: rev pre ++ source_bit b :: rev data)
      ((if hit then 3 else 2) ::
       map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
          [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data b bit tail pre hit post
    Hlen H12t H14t Hdecomp Hpre Hpost.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      (instruction_q19_clock bits action_init tbuffer b +
       (S (length pre) + S (length post))) by lia;
    rewrite (dispatch_run_add
      (instruction_q19_clock bits action_init tbuffer b)
      (S (length pre) + S (length post)) start)
  end.
  unfold instruction_q19_clock.
  rewrite (canonical_q5_instruction_to_q19 bits action_init tbuffer
    data b bit tail Hlen H12t H14t).
  rewrite Hdecomp.
  replace ((pre ++ source_bit hit :: post) ++
      7 :: map q16_restore
             (rev (4 :: rev
               (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
              [4])) ++
      source_bit bit :: tail)
    with (pre ++ source_bit hit ::
      (post ++
       7 :: map q16_restore
              (rev (4 :: rev
                (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
               [4])) ++
       source_bit bit :: tail))
    by (rewrite <- app_assoc; reflexivity).
  rewrite dispatch_run_add.
  rewrite (q19_scan_to_m pre hit (source_bit b :: rev data)
    (post ++
     7 :: map q16_restore
            (rev (4 :: rev
              (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
             [4])) ++
     source_bit bit :: tail) Hpre).
  destruct hit.
  - apply (q18_scan_to_marker post
      (6 :: rev pre ++ source_bit b :: rev data)
      (map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
          [4])) ++ source_bit bit :: tail) Hpost).
  - apply (q17_scan_to_marker post
      (6 :: rev pre ++ source_bit b :: rev data)
      (map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
          [4])) ++ source_bit bit :: tail) Hpost).
Qed.

Print Assumptions canonical_q5_instruction_q19_collision_to_q5.

Theorem canonical_q5_instruction_left_collision_to_q5 :
  forall bits action_init tbuffer data data' b bit tail (d : bool),
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev data = source_bit d :: rev data' ->
    Forall q17_pass
      (source_bit b ::
       rev (map q14_restore
         (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ->
    run (instruction_q20_clock bits action_init tbuffer b + 1 +
         S (length
           (source_bit b ::
            rev (map q14_restore
              (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit false :: 4 :: source_bit bit :: tail)) =
    cfg_ml 5
      (rev (source_bit b ::
        rev (map q14_restore
          (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ++
       6 :: rev data')
      ((if d then 3 else 2) ::
       map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
          [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data data' b bit tail d
    Hlen H12t H14t Hdata Hpost.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      ((instruction_q20_clock bits action_init tbuffer b + 1) +
       S (length
         (source_bit b ::
          rev (map q14_restore
            (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))))
      by reflexivity;
    rewrite (dispatch_run_add
      (instruction_q20_clock bits action_init tbuffer b + 1)
      (S (length
        (source_bit b ::
         rev (map q14_restore
           (rev (map match_mark action_init) ++ 5 :: rev tbuffer))))) start)
  end.
  rewrite (canonical_q5_instruction_left_branch_hits_current_cell
    bits action_init tbuffer data data' b bit tail d
    Hlen H12t H14t Hdata).
  destruct d.
  - apply (q18_scan_to_marker
      (source_bit b ::
       rev (map q14_restore
         (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))
      (6 :: rev data')
      (map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
          [4])) ++ source_bit bit :: tail) Hpost).
  - apply (q17_scan_to_marker
      (source_bit b ::
       rev (map q14_restore
         (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))
      (6 :: rev data')
      (map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
          [4])) ++ source_bit bit :: tail) Hpost).
Qed.

Print Assumptions canonical_q5_instruction_left_collision_to_q5.

(** ** q5 -> q1 scan after the canonical collision cycle

    The q5 frame produced by the collision cycle has the restored rail on
    its left and the next record on its right.  q5 scans left to the first
    Y=5 delimiter and enters q1, with the rewritten rail on the right.
    This is the next-row match entry. *)

Definition canonical_q5_return_pass (symbol : nat) : Prop :=
  symbol = 0 \/ symbol = 1 \/ symbol = 2 \/ symbol = 3 \/
  symbol = 4 \/ symbol = 6 \/ symbol = 7.

Lemma canonical_q5_return_pass_step :
  forall symbol next left right,
    canonical_q5_return_pass symbol ->
    step (entry_config 5 (next :: left) (symbol :: right)) =
    entry_config 5 left (next :: entry_rewrite symbol :: right).
Proof.
  intros symbol next left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Theorem canonical_q5_return_scan_to_first_five :
  forall remaining symbol prefix suffix,
    Forall canonical_q5_return_pass (symbol :: remaining) ->
    run (S (length (symbol :: remaining)))
      (entry_config 5 (remaining ++ 5 :: prefix) (symbol :: suffix)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (symbol :: remaining)) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH];
    intros symbol prefix suffix Hscan.
  - inversion Hscan as [|? ? Hsymbol _]; subst.
    destruct Hsymbol as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion Hscan as [|? ? Hsymbol Hrest]; subst.
    change (run (S (S (length (next :: rest))))
        (entry_config 5 (next :: (rest ++ 5 :: prefix))
          (symbol :: suffix)) =
      entry_config 1 (5 :: prefix)
        (map entry_rewrite (rev (symbol :: next :: rest)) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (canonical_q5_return_pass_step symbol next
      (rest ++ 5 :: prefix) suffix Hsymbol).
    rewrite (IH next prefix (entry_rewrite symbol :: suffix) Hrest).
    cbn [rev].
    repeat rewrite map_app.
    cbn [map].
    rewrite (append_singleton_assoc
      (map entry_rewrite (rev rest) ++ [entry_rewrite next])
      (entry_rewrite symbol) suffix).
    reflexivity.
Qed.

Print Assumptions canonical_q5_return_scan_to_first_five.

Theorem canonical_q5_instruction_q19_collision_to_q1 :
  forall bits action_init tbuffer data b bit tail pre hit post
         prefix symbol remaining,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev (map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) =
      pre ++ source_bit hit :: post ->
    Forall q15_pass pre ->
    Forall q17_pass post ->
    rev post ++ 6 :: rev pre ++ source_bit b :: rev data =
      (symbol :: remaining) ++ 5 :: prefix ->
    Forall canonical_q5_return_pass (symbol :: remaining) ->
    run (instruction_q19_clock bits action_init tbuffer b +
         S (length pre) + S (length post) +
         S (length (symbol :: remaining)))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit true :: 4 :: source_bit bit :: tail)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (symbol :: remaining)) ++
       (if hit then 3 else 2) ::
       map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
          [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data b bit tail pre hit post
    prefix symbol remaining Hlen H12t H14t Hdecomp
    Hpre Hpost Hleft Hscan.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      ((instruction_q19_clock bits action_init tbuffer b +
        S (length pre) + S (length post)) +
       S (length (symbol :: remaining))) by reflexivity;
    rewrite (dispatch_run_add
      (instruction_q19_clock bits action_init tbuffer b +
       S (length pre) + S (length post))
      (S (length (symbol :: remaining))) start)
  end.
  rewrite (canonical_q5_instruction_q19_collision_to_q5
    bits action_init tbuffer data b bit tail pre hit post
    Hlen H12t H14t Hdecomp Hpre Hpost).
  rewrite Hleft.
  cbn [cfg_ml].
  apply (canonical_q5_return_scan_to_first_five remaining symbol prefix
    ((if hit then 3 else 2) ::
     map q16_restore
       (rev (4 :: rev
         (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
        [4])) ++
     source_bit bit :: tail) Hscan).
Qed.

Print Assumptions canonical_q5_instruction_q19_collision_to_q1.

Theorem canonical_q5_instruction_left_collision_to_q1 :
  forall bits action_init tbuffer data data' b bit tail (d : bool)
         prefix symbol remaining,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev data = source_bit d :: rev data' ->
    Forall q17_pass
      (source_bit b ::
       rev (map q14_restore
         (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ->
    rev (source_bit b ::
      rev (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ++
      6 :: rev data' = (symbol :: remaining) ++ 5 :: prefix ->
    Forall canonical_q5_return_pass (symbol :: remaining) ->
    run (instruction_q20_clock bits action_init tbuffer b + 1 +
         S (length
           (source_bit b ::
            rev (map q14_restore
              (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))) +
         S (length (symbol :: remaining)))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit false :: 4 :: source_bit bit :: tail)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (symbol :: remaining)) ++
       (if d then 3 else 2) ::
       map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
          [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data data' b bit tail d
    prefix symbol remaining Hlen H12t H14t Hdata Hpost
    Hleft Hscan.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      ((instruction_q20_clock bits action_init tbuffer b + 1 +
        S (length
          (source_bit b ::
           rev (map q14_restore
             (rev (map match_mark action_init) ++ 5 :: rev tbuffer))))) +
       S (length (symbol :: remaining))) by reflexivity;
    rewrite (dispatch_run_add
      (instruction_q20_clock bits action_init tbuffer b + 1 +
       S (length
         (source_bit b ::
          rev (map q14_restore
            (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))))
      (S (length (symbol :: remaining))) start)
  end.
  rewrite (canonical_q5_instruction_left_collision_to_q5
    bits action_init tbuffer data data' b bit tail d
    Hlen H12t H14t Hdata Hpost).
  rewrite Hleft.
  cbn [cfg_ml].
  apply (canonical_q5_return_scan_to_first_five remaining symbol prefix
    ((if d then 3 else 2) ::
     map q16_restore
       (rev (4 :: rev
         (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
        [4])) ++
     source_bit bit :: tail) Hscan).
Qed.

Print Assumptions canonical_q5_instruction_left_collision_to_q1.

(** ** q5 -> q1 -> matched q1

    The q5 -> q1 cycles return the next-row q1 rail.  If that rail is
    decomposed as [pass] ++ marked bits ++ [done] ++ raw bits, the
    canonical wide-mark match theorem consumes the raw bits and rewrites
    the marked ones.  This isolates the encoder's rail invariant as an
    explicit premise. *)

Theorem canonical_q5_instruction_q19_collision_to_match :
  forall bits action_init tbuffer data b bit tail pre hit post
         prefix symbol remaining bits' pass done,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev (map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) =
      pre ++ source_bit hit :: post ->
    Forall q15_pass pre ->
    Forall q17_pass post ->
    rev post ++ 6 :: rev pre ++ source_bit b :: rev data =
      (symbol :: remaining) ++ 5 :: prefix ->
    Forall canonical_q5_return_pass (symbol :: remaining) ->
    map entry_rewrite (rev (symbol :: remaining)) ++
      (if hit then 3 else 2) ::
      map q16_restore
        (rev (4 :: rev
          (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
         [4])) ++
      source_bit bit :: tail =
      pass ++ map match_mark bits' ++ done ++ map match_raw bits' ++ tail ->
    Forall q1_pass pass ->
    Forall wide_mark done ->
    run (instruction_q19_clock bits action_init tbuffer b +
         S (length pre) + S (length post) +
         S (length (symbol :: remaining)) +
         matched_comparison_steps bits' (length pass) (length done))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit true :: 4 :: source_bit bit :: tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ map match_raw bits' ++ done ++
       map match_mark bits' ++ tail).
Proof.
  intros bits action_init tbuffer data b bit tail pre hit post
    prefix symbol remaining bits' pass done Hlen H12t H14t Hdecomp
    Hpre Hpost Hleft Hscan Hrail Hpass Hdone.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      ((instruction_q19_clock bits action_init tbuffer b +
        S (length pre) + S (length post) +
        S (length (symbol :: remaining))) +
       matched_comparison_steps bits' (length pass) (length done))
      by reflexivity;
    rewrite (dispatch_run_add
      (instruction_q19_clock bits action_init tbuffer b +
       S (length pre) + S (length post) +
       S (length (symbol :: remaining)))
      (matched_comparison_steps bits' (length pass) (length done)) start)
  end.
  rewrite (canonical_q5_instruction_q19_collision_to_q1
    bits action_init tbuffer data b bit tail pre hit post
    prefix symbol remaining Hlen H12t H14t Hdecomp Hpre Hpost
    Hleft Hscan).
  rewrite Hrail.
  apply (q1_all_matching_bits_wide bits' pass done prefix tail
    Hpass Hdone).
Qed.

Print Assumptions canonical_q5_instruction_q19_collision_to_match.

Theorem canonical_q5_instruction_left_collision_to_match :
  forall bits action_init tbuffer data data' b bit tail (d : bool)
         prefix symbol remaining bits' pass done,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev data = source_bit d :: rev data' ->
    Forall q17_pass
      (source_bit b ::
       rev (map q14_restore
         (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ->
    rev (source_bit b ::
      rev (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ++
      6 :: rev data' = (symbol :: remaining) ++ 5 :: prefix ->
    Forall canonical_q5_return_pass (symbol :: remaining) ->
    map entry_rewrite (rev (symbol :: remaining)) ++
      (if d then 3 else 2) ::
      map q16_restore
        (rev (4 :: rev
          (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
         [4])) ++
      source_bit bit :: tail =
      pass ++ map match_mark bits' ++ done ++ map match_raw bits' ++ tail ->
    Forall q1_pass pass ->
    Forall wide_mark done ->
    run (instruction_q20_clock bits action_init tbuffer b + 1 +
         S (length
           (source_bit b ::
            rev (map q14_restore
              (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))) +
         S (length (symbol :: remaining)) +
         matched_comparison_steps bits' (length pass) (length done))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit false :: 4 :: source_bit bit :: tail)) =
    entry_config 1 (5 :: prefix)
      (pass ++ map match_raw bits' ++ done ++
       map match_mark bits' ++ tail).
Proof.
  intros bits action_init tbuffer data data' b bit tail d
    prefix symbol remaining bits' pass done Hlen H12t H14t Hdata
    Hpost Hleft Hscan Hrail Hpass Hdone.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      ((instruction_q20_clock bits action_init tbuffer b + 1 +
        S (length
          (source_bit b ::
           rev (map q14_restore
             (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))) +
        S (length (symbol :: remaining))) +
       matched_comparison_steps bits' (length pass) (length done))
      by reflexivity;
    rewrite (dispatch_run_add
      (instruction_q20_clock bits action_init tbuffer b + 1 +
       S (length
         (source_bit b ::
          rev (map q14_restore
            (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))) +
       S (length (symbol :: remaining)))
      (matched_comparison_steps bits' (length pass) (length done)) start)
  end.
  rewrite (canonical_q5_instruction_left_collision_to_q1
    bits action_init tbuffer data data' b bit tail d
    prefix symbol remaining Hlen H12t H14t Hdata Hpost
    Hleft Hscan).
  rewrite Hrail.
  apply (q1_all_matching_bits_wide bits' pass done prefix tail
    Hpass Hdone).
Qed.

Print Assumptions canonical_q5_instruction_left_collision_to_match.

(** ** q5 -> q6: the next-instruction action-copy entry

    The matched q1 rail is followed by the record's X=4.  q1 crosses it
    into q6, the canonical action-copy entry for the next instruction.
    This composes the q5 -> matched q1 theorem with the native q1->q6
    scan. *)

Theorem canonical_q5_instruction_q19_collision_to_q6 :
  forall bits action_init tbuffer data b bit tail pre hit post
         prefix symbol remaining bits' pass,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev (map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev tbuffer)) =
      pre ++ source_bit hit :: post ->
    Forall q15_pass pre ->
    Forall q17_pass post ->
    rev post ++ 6 :: rev pre ++ source_bit b :: rev data =
      (symbol :: remaining) ++ 5 :: prefix ->
    Forall canonical_q5_return_pass (symbol :: remaining) ->
    map entry_rewrite (rev (symbol :: remaining)) ++
      (if hit then 3 else 2) ::
      map q16_restore
        (rev (4 :: rev
          (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
         [4])) ++
      source_bit bit :: tail =
      pass ++ map match_mark bits' ++ [4] ++ map match_raw bits' ++ tail ->
    Forall q1_pass pass ->
    run (instruction_q19_clock bits action_init tbuffer b +
         S (length pre) + S (length post) +
         S (length (symbol :: remaining)) +
         matched_comparison_steps bits' (length pass) (length [4]) +
         S (length (pass ++ map match_raw bits')))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit true :: 4 :: source_bit bit :: tail)) =
    entry_config 6
      (4 :: rev (pass ++ map match_raw bits') ++ 5 :: prefix)
      (map match_mark bits' ++ tail).
Proof.
  intros bits action_init tbuffer data b bit tail pre hit post
    prefix symbol remaining bits' pass Hlen H12t H14t Hdecomp
    Hpre Hpost Hleft Hscan Hrail Hpass.
  assert (H4 : Forall wide_mark [4]).
  { constructor; [unfold wide_mark; auto 10 | constructor]. }
  rewrite dispatch_run_add.
  rewrite (canonical_q5_instruction_q19_collision_to_match
    bits action_init tbuffer data b bit tail pre hit post
    prefix symbol remaining bits' pass [4]
    Hlen H12t H14t Hdecomp Hpre Hpost Hleft Hscan Hrail Hpass H4).
  replace (pass ++ map match_raw bits' ++ [4] ++
           map match_mark bits' ++ tail)
    with ((pass ++ map match_raw bits') ++ [4] ++
          map match_mark bits' ++ tail)
    by (repeat rewrite <- app_assoc; reflexivity).
  apply (q1_scan_four_list_to_q6
    (pass ++ map match_raw bits')
    (map match_mark bits' ++ tail) (5 :: prefix)).
  rewrite Forall_app. split.
  - exact Hpass.
  - apply match_raw_valid.
Qed.

Print Assumptions canonical_q5_instruction_q19_collision_to_q6.

Theorem canonical_q5_instruction_left_collision_to_q6 :
  forall bits action_init tbuffer data data' b bit tail (d : bool)
         prefix symbol remaining bits' pass,
    length (action_init ++ [b]) = length bits ->
    Forall q12_pass tbuffer ->
    Forall q14_pass tbuffer ->
    rev data = source_bit d :: rev data' ->
    Forall q17_pass
      (source_bit b ::
       rev (map q14_restore
         (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ->
    rev (source_bit b ::
      rev (map q14_restore
        (rev (map match_mark action_init) ++ 5 :: rev tbuffer))) ++
      6 :: rev data' = (symbol :: remaining) ++ 5 :: prefix ->
    Forall canonical_q5_return_pass (symbol :: remaining) ->
    map entry_rewrite (rev (symbol :: remaining)) ++
      (if d then 3 else 2) ::
      map q16_restore
        (rev (4 :: rev
          (instruction_marked bits (action_init ++ [b]) ++ [2]) ++
         [4])) ++
      source_bit bit :: tail =
      pass ++ map match_mark bits' ++ [4] ++ map match_raw bits' ++ tail ->
    Forall q1_pass pass ->
    run (instruction_q20_clock bits action_init tbuffer b + 1 +
         S (length
           (source_bit b ::
            rev (map q14_restore
              (rev (map match_mark action_init) ++ 5 :: rev tbuffer)))) +
         S (length (symbol :: remaining)) +
         matched_comparison_steps bits' (length pass) (length [4]) +
         S (length (pass ++ map match_raw bits')))
      (entry_config 5
        (rev (map source_bit bits) ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: map source_bit bits ++
         map source_bit (action_init ++ [b]) ++
         source_bit false :: 4 :: source_bit bit :: tail)) =
    entry_config 6
      (4 :: rev (pass ++ map match_raw bits') ++ 5 :: prefix)
      (map match_mark bits' ++ tail).
Proof.
  intros bits action_init tbuffer data data' b bit tail d
    prefix symbol remaining bits' pass Hlen H12t H14t Hdata
    Hpost Hleft Hscan Hrail Hpass.
  assert (H4 : Forall wide_mark [4]).
  { constructor; [unfold wide_mark; auto 10 | constructor]. }
  rewrite dispatch_run_add.
  rewrite (canonical_q5_instruction_left_collision_to_match
    bits action_init tbuffer data data' b bit tail d
    prefix symbol remaining bits' pass [4]
    Hlen H12t H14t Hdata Hpost Hleft Hscan Hrail Hpass H4).
  replace (pass ++ map match_raw bits' ++ [4] ++
           map match_mark bits' ++ tail)
    with ((pass ++ map match_raw bits') ++ [4] ++
          map match_mark bits' ++ tail)
    by (repeat rewrite <- app_assoc; reflexivity).
  apply (q1_scan_four_list_to_q6
    (pass ++ map match_raw bits')
    (map match_mark bits' ++ tail) (5 :: prefix)).
  rewrite Forall_app. split.
  - exact Hpass.
  - apply match_raw_valid.
Qed.

Print Assumptions canonical_q5_instruction_left_collision_to_q6.

(** ** q6 -> q12/q13: action copy and direction capture

    The q5 -> q6 entry has the matched condition marks on the right and
    the raw action bits after them.  q6 copies the action bits into
    marks, q9/q10 capture the direction bit, and q12/q13 is reached.
    This is the first half of the q6 -> q5 movement cycle. *)

Theorem canonical_q6_copy_direction_to_q12 :
  forall bits action_bits tbuffer data (dir : bool) rest,
    length action_bits = length bits ->
    run (copy_all_clock bits action_bits [] (map match_mark bits) +
         direction_clock
           (map match_mark bits ++ map match_mark action_bits)
           (map match_mark action_bits))
      (entry_config 6
        (4 :: rev (map source_bit bits) ++
         5 :: rev tbuffer ++ 6 :: rev data)
        (map match_mark bits ++ map source_bit action_bits ++
         source_bit dir :: rest)) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark action_bits) ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (4 :: (map match_mark bits ++ map match_mark action_bits) ++
            (if dir then 3 else 2) :: rest).
Proof.
  intros bits action_bits tbuffer data dir rest Hlen.
  assert (Hbits6 : Forall q6_pass (map match_mark bits)).
  { apply Forall_match_mark.
    intros b. destruct b; unfold q6_pass, match_mark; auto 10. }
  assert (Hbits7 : Forall q7_pass (map match_mark bits)).
  { apply Forall_match_mark.
    intros b. destruct b; unfold q7_pass, match_mark; auto 10. }
  assert (Hact6 : Forall q6_pass (map match_mark action_bits)).
  { apply Forall_match_mark.
    intros b. destruct b; unfold q6_pass, match_mark; auto 10. }
  assert (Hact7 : Forall q7_pass (map match_mark action_bits)).
  { apply Forall_match_mark.
    intros b. destruct b; unfold q7_pass, match_mark; auto 10. }
  assert (Hact9 : Forall q9_pass (map match_mark action_bits)).
  { apply Forall_match_mark.
    intros b. destruct b; unfold q9_pass, match_mark; auto 10. }
  assert (Hmarked6 : Forall q6_pass
      (map match_mark bits ++ map match_mark action_bits)).
  { apply Forall_app; split; [exact Hbits6 | exact Hact6]. }
  assert (Hmarked7 : Forall q7_pass
      (map match_mark bits ++ map match_mark action_bits)).
  { apply Forall_app; split; [exact Hbits7 | exact Hact7]. }
  rewrite dispatch_run_add.
  rewrite (canonical_q6_copy_all bits
    (4 :: rev (map source_bit bits) ++
     5 :: rev tbuffer ++ 6 :: rev data)
    (map match_mark bits ++ map source_bit action_bits ++
     source_bit dir :: rest)
    [] (map match_mark bits) action_bits (source_bit dir :: rest)
    tbuffer data eq_refl eq_refl (eq_sym Hlen)
    (Forall_nil q7_pass) (Forall_nil q9_pass) Hbits6 Hbits7).
  change (run (direction_clock
      (map match_mark bits ++ map match_mark action_bits)
      (map match_mark action_bits))
    (entry_config 6
      (4 :: rev (map match_mark action_bits) ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (map match_mark bits ++ map match_mark action_bits ++
       source_bit dir :: rest)) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark action_bits) ++
       5 :: rev tbuffer ++ 6 :: rev data)
      (4 :: (map match_mark bits ++ map match_mark action_bits) ++
            (if dir then 3 else 2) :: rest)).
  replace (map match_mark bits ++ map match_mark action_bits ++
           source_bit dir :: rest)
    with ((map match_mark bits ++ map match_mark action_bits) ++
          source_bit dir :: rest)
    by (rewrite <- app_assoc; reflexivity).
  unfold direction_clock.
  apply (canonical_q6_direction_capture
    (map match_mark bits ++ map match_mark action_bits)
    (map match_mark action_bits) rest tbuffer data dir
    Hmarked6 Hmarked7 Hact7 Hact9).
Qed.

Print Assumptions canonical_q6_copy_direction_to_q12.


(** ** q21/q22 -> q5 after the q16 decision

    This is the post-q16 half of the canonical movement.  q21/q22 scans
    left to the direction marker 3, q19 relocates the first raw cell after
    q16, and q17/q18 return to the next 7. *)

Theorem canonical_q21_decision_to_q5 :
  forall (bits action_init : list bool) (tbuffer data tail : list nat)
         (b bit : bool) (s : nat) (remaining pre post : list nat)
         (hit : bool),
    Forall q21_pass (s :: remaining) ->
    rev (s :: remaining) = pre ++ source_bit hit :: post ->
    Forall q15_pass pre ->
    Forall q17_pass post ->
    run (S (length (s :: remaining)) + S (length pre) + S (length post))
      (entry_config (if b then 22 else 21)
        (remaining ++ 3 :: rev data)
        (s :: 7 :: map q16_restore
               (rev (4 :: rev
                 (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
                [4])) ++
         source_bit bit :: tail)) =
    cfg_ml 5
      (rev post ++ 6 :: rev pre ++ source_bit b :: rev data)
      ((if hit then 3 else 2) ::
       map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
          [4])) ++
       source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data tail b bit s remaining
    pre post hit H21 Hdecomp Hpre Hpost.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      (S (length (s :: remaining)) +
       (S (length pre) + S (length post))) by lia;
    rewrite (dispatch_run_add
      (S (length (s :: remaining)))
      (S (length pre) + S (length post)) start)
  end.
  assert (Hq : (if b then 22 else 21) = 21 \/
               (if b then 22 else 21) = 22)
    by (destruct b; simpl; auto).
  rewrite (q21_scan_to_right_direction remaining s
    (if b then 22 else 21) (rev data)
    (7 :: map q16_restore
           (rev (4 :: rev
             (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
            [4])) ++
     source_bit bit :: tail) Hq H21).
  replace (q21_written (if b then 22 else 21)) with (source_bit b)
    by (destruct b; reflexivity).
  rewrite Hdecomp.
  replace ((pre ++ source_bit hit :: post) ++
      7 :: map q16_restore
             (rev (4 :: rev
               (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
              [4])) ++
      source_bit bit :: tail)
    with (pre ++ source_bit hit ::
      (post ++
       7 :: map q16_restore
              (rev (4 :: rev
                (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
               [4])) ++
       source_bit bit :: tail))
    by (rewrite <- app_assoc; reflexivity).
  rewrite dispatch_run_add.
  rewrite (q19_scan_to_m pre hit (source_bit b :: rev data)
    (post ++
     7 :: map q16_restore
            (rev (4 :: rev
              (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
             [4])) ++
     source_bit bit :: tail) Hpre).
  destruct hit.
  - apply (q18_scan_to_marker post
      (6 :: rev pre ++ source_bit b :: rev data)
      (map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
          [4])) ++ source_bit bit :: tail) Hpost).
  - apply (q17_scan_to_marker post
      (6 :: rev pre ++ source_bit b :: rev data)
      (map q16_restore
         (rev (4 :: rev
           (instruction_marked bits (action_init ++ [b]) ++ [3]) ++
          [4])) ++ source_bit bit :: tail) Hpost).
Qed.

Print Assumptions canonical_q21_decision_to_q5.

(** ** Generic q21/q22 -> q5 tail map

    The same post-q16 path with an arbitrary restored map, so the q12/q13
    restore phase can plug in its own map. *)

Theorem canonical_q21_decision_to_q5_map :
  forall (bits action_init : list bool) (tbuffer data tail : list nat)
         (b bit : bool) (s : nat) (remaining pre post : list nat)
         (hit : bool) (q16map : list nat),
    Forall q21_pass (s :: remaining) ->
    rev (s :: remaining) = pre ++ source_bit hit :: post ->
    Forall q15_pass pre ->
    Forall q17_pass post ->
    run (S (length (s :: remaining)) + S (length pre) + S (length post))
      (entry_config (if b then 22 else 21)
        (remaining ++ 3 :: rev data)
        (s :: 7 :: map q16_restore q16map ++ source_bit bit :: tail)) =
    cfg_ml 5
      (rev post ++ 6 :: rev pre ++ source_bit b :: rev data)
      ((if hit then 3 else 2) ::
       map q16_restore q16map ++ source_bit bit :: tail).
Proof.
  intros bits action_init tbuffer data tail b bit s remaining
    pre post hit q16map H21 Hdecomp Hpre Hpost.
  match goal with
  | |- run ?clock ?start = ?rhs =>
    replace clock with
      (S (length (s :: remaining)) +
       (S (length pre) + S (length post))) by lia;
    rewrite (dispatch_run_add
      (S (length (s :: remaining)))
      (S (length pre) + S (length post)) start)
  end.
  assert (Hq : (if b then 22 else 21) = 21 \/
               (if b then 22 else 21) = 22)
    by (destruct b; simpl; auto).
  rewrite (q21_scan_to_right_direction remaining s
    (if b then 22 else 21) (rev data)
    (7 :: map q16_restore q16map ++ source_bit bit :: tail) Hq H21).
  replace (q21_written (if b then 22 else 21)) with (source_bit b)
    by (destruct b; reflexivity).
  rewrite Hdecomp.
  replace ((pre ++ source_bit hit :: post) ++
      7 :: map q16_restore q16map ++ source_bit bit :: tail)
    with (pre ++ source_bit hit ::
      (post ++ 7 :: map q16_restore q16map ++
       source_bit bit :: tail))
    by (rewrite <- app_assoc; reflexivity).
  rewrite dispatch_run_add.
  rewrite (q19_scan_to_m pre hit (source_bit b :: rev data)
    (post ++ 7 :: map q16_restore q16map ++
     source_bit bit :: tail) Hpre).
  destruct hit.
  - apply (q18_scan_to_marker post
      (6 :: rev pre ++ source_bit b :: rev data)
      (map q16_restore q16map ++ source_bit bit :: tail) Hpost).
  - apply (q17_scan_to_marker post
      (6 :: rev pre ++ source_bit b :: rev data)
      (map q16_restore q16map ++ source_bit bit :: tail) Hpost).
Qed.

Print Assumptions canonical_q21_decision_to_q5_map.

Theorem canonical_q12_restore_to_q5 :
  forall marked tbuffer data b rest bit tail s21 rest21 pre hit post,
    Forall q12_pass (match_mark b :: rest ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev rest ++ [match_mark b]) ->
    Forall q15_pass (marked ++ [3]) ->
    Forall q16_pass marked ->
    map q14_restore (rest ++ 5 :: rev tbuffer) = s21 :: rest21 ->
    rev (s21 :: rest21) = pre ++ source_bit hit :: post ->
    Forall q15_pass pre ->
    Forall q17_pass post ->
    run (S (length (match_mark b :: rest ++ 5 :: rev tbuffer)) +
         S (length (tbuffer ++ [5] ++ rev rest ++ [match_mark b])) +
         S (length (s21 :: rest21)) + S (length pre) + S (length post))
      (cfg_ml 12
        (match_mark b :: rest ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ 3 :: source_bit bit :: tail)) =
    cfg_ml 5
      (rev post ++ 6 :: rev pre ++ source_bit b :: rev data)
      ((if hit then 3 else 2) ::
       map q16_restore (rev (3 :: rev marked ++ [4])) ++
       source_bit bit :: tail).
Proof.
  intros marked tbuffer data b rest bit tail s21 rest21
    pre hit post H12 H14 H15 H16 Hrestored Hdecomp Hpre Hpost.
  rewrite dispatch_run_add.
  rewrite (canonical_q12_restore_to_q16_decision marked tbuffer data
    b rest bit tail H12 H14 H15 H16).
  rewrite Hrestored.
  cbn [cfg_ml].
  apply (canonical_q21_decision_to_q5_map
    [] [] tbuffer data tail b bit s21 rest21 pre post hit
    (rev (3 :: rev marked ++ [4])) Hdecomp Hpre Hpost).
  - exact Hdecomp.
  - exact Hpre.
  - exact Hpost.
Qed.

Print Assumptions canonical_q12_restore_to_q5.
