(** * Generic one-row running step (left direction, width >= 2)

    The leftward analogue of [MinskyRowStepGeneric].  The condition is
    split as

      bits = first_init :: init_rest ++ [pre_last; last_bit]

    and the action as

      action = first_action :: action_tail ++ [last_state; bnext].

    The data shift writes [bprev] at the old head and then pops it on the
    q20 left move, so the next data list is the old one.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskySourceEncoding MinskyMatchMacro MinskyHeadMoveMacro
  MinskyActionMacro MinskyRelocationMacro MinskyCanonicalMatch
  MinskyCanonicalInstruction MinskyCanonicalLeftStep
  MinskyRowStepGeneric.

Definition canonical_left_row_step
    (first_init : bool) (init_rest : list bool)
    (pre_last : bool) (last_bit : bool)
    (first_action : bool) (action_tail : list bool)
    (last_state : bool) (bnext : bool)
    (data : list nat) (bprev : bool) (rest_tail : list nat)
    : canonical_left_step :=
  let bits := first_init :: init_rest ++ [pre_last; last_bit] in
  let action_init := first_action :: action_tail ++ [last_state] in
  let tail' := map source_bit (action_init ++ [bnext]) ++
               source_bit false :: source_bit true :: rest_tail in
  {| cls_post := 5 :: rev
        (match_mark pre_last ::
         rev (map match_mark (first_init :: init_rest)));
     cls_pre := [];
     cls_bprev := bprev;
     cls_data := data;
     cls_data_q6 := data ++ [source_bit bprev];
     cls_data' := data;
     cls_symbol := match_mark pre_last;
     cls_remaining := rev (map match_mark (first_init :: init_rest));
     cls_prefix := [6] ++ source_bit bprev :: rev data;
     cls_hit := last_bit;
     cls_next_bit := first_init;
     cls_next_tail :=
       map match_raw init_rest ++
       [match_raw pre_last; match_raw last_bit] ++ tail';
     cls_q16map := [4];
     cls_bits := bits;
     cls_action_init := action_init;
     cls_tbuffer := [];
     cls_bnext := bnext;
     cls_rest := source_bit true :: rest_tail;
     cls_d := bprev;
     cls_bit := true;
     cls_tail := rest_tail;
     cls_s21 := source_bit last_state;
     cls_rest21 :=
       rev (map source_bit (first_action :: action_tail)) ++ [5];
     cls_tail' := tail' |}.

Lemma canonical_left_row_step_ok :
  forall first_init init_rest pre_last last_bit
         first_action action_tail last_state bnext
         data bprev rest_tail,
    length (first_action :: action_tail ++ [last_state; bnext]) =
    length (first_init :: init_rest ++ [pre_last; last_bit]) ->
    canonical_left_step_ok
      (canonical_left_row_step first_init init_rest pre_last last_bit
         first_action action_tail last_state bnext
         data bprev rest_tail).
Proof.
  intros first_init init_rest pre_last last_bit first_action action_tail
    last_state bnext data bprev rest_tail Hlen.
  unfold canonical_left_row_step.
  constructor.
  - (* left *) cbn. repeat rewrite rev_app_distr.
    repeat rewrite rev_involutive. cbn [rev app].
    repeat rewrite <- app_assoc. reflexivity.
  - (* scan *) cbn. constructor.
    + destruct pre_last; unfold canonical_q5_return_pass, match_mark;
        auto 12.
    + change (Forall canonical_q5_return_pass
        (rev (map match_mark (first_init :: init_rest)))).
      apply Forall_rev. apply Forall_q5_match_marks.
  - (* rail *) cbn.
    rewrite rev_app_distr. cbn [rev]. rewrite rev_involutive.
    rewrite (map_entry_rewrite_marks_id
      (match_mark first_init :: map match_mark init_rest ++
       [match_mark pre_last])).
    2:{ constructor.
        - destruct first_init; cbn; auto.
        - rewrite Forall_app. split.
          + apply Forall_marks_two_or_three.
          + constructor.
            * destruct pre_last; cbn; auto.
            * constructor. }
    cbn [map app].
    repeat rewrite map_app.
    repeat rewrite <- app_assoc.
    reflexivity.
  - (* tail *) cbn. reflexivity.
  - (* prefix *) cbn. rewrite rev_app_distr. cbn. reflexivity.
  - (* shift *) cbn. rewrite rev_app_distr. cbn. reflexivity.
  - (* len *) cbn. cbn in Hlen.
    replace (S (length ((action_tail ++ [last_state]) ++ [bnext])))
      with (S (length (action_tail ++ [last_state; bnext]))).
    2:{ rewrite <- app_assoc. reflexivity. }
    exact Hlen.
  - (* data *) cbn. rewrite rev_app_distr. cbn. reflexivity.
  - (* rest *) cbn. reflexivity.
  - (* restored *) cbn.
    repeat rewrite map_app.
    repeat rewrite map_rev.
    repeat rewrite map_app.
    repeat rewrite map_q14_restore_match_marks.
    rewrite rev_app_distr. cbn [rev].
    repeat rewrite q14_restore_match_mark.
    cbn [q14_restore map rev app].
    repeat rewrite q14_restore_match_mark.
    repeat rewrite <- app_assoc.
    reflexivity.
  - (* return *) cbn. constructor.
    + destruct bnext; unfold q17_pass; auto 12.
    + constructor.
      * unfold q17_pass; auto 12.
      * apply Forall_rev. apply Forall_q17_source_bits.
  - (* line12 *) cbn. constructor.
    + destruct bnext; unfold q12_pass, match_mark; auto 12.
    + rewrite Forall_app. split.
      * rewrite Forall_app. split.
        -- apply Forall_q12_rev_marks.
        -- constructor.
           ++ destruct first_action; unfold q12_pass, match_mark; auto 12.
           ++ constructor.
      * constructor.
        -- unfold q12_pass; auto 12.
        -- constructor.
  - (* line14 *) cbn. constructor.
    + unfold q14_pass; auto 12.
    + rewrite Forall_app. split.
      * rewrite rev_app_distr. cbn [rev]. rewrite rev_involutive.
        change (Forall q14_pass
          (map match_mark (first_action :: action_tail ++ [last_state]))).
        apply Forall_q14_match_marks.
      * constructor.
        -- destruct bnext; unfold q14_pass, match_mark; auto 12.
        -- constructor.
Qed.

Print Assumptions canonical_left_row_step_ok.
