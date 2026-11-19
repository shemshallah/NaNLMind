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
