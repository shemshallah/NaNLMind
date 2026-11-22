(** * Generic one-row running step (right direction, width >= 2)

    This generalizes the fixed two-bit witness family to an arbitrary
    nonempty condition and action.  The condition is split as

      bits = first_init :: init_rest ++ [pre_last; last_bit]

    and the action as

      action = first_action :: action_tail ++ [last_state; bnext].

    The q5 rail is [pre_last] followed by the reversed marks of the
    earlier condition bits.  The construction is deliberately explicit:
    it is a concrete [canonical_return_step] whose [ok] fields are
    discharged by list algebra, not an axiom.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskySourceEncoding MinskyMatchMacro MinskyHeadMoveMacro
  MinskyActionMacro MinskyRelocationMacro MinskyCanonicalMatch
  MinskyCanonicalInstruction.

Lemma Forall_q17_source_bits :
  forall bits, Forall q17_pass (map source_bit bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold q17_pass; auto 12.
    + exact IH.
Qed.

Lemma Forall_q12_match_marks :
  forall bits, Forall q12_pass (map match_mark bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold q12_pass, match_mark; auto 12.
    + exact IH.
Qed.

Lemma Forall_q14_match_marks :
  forall bits, Forall q14_pass (map match_mark bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold q14_pass, match_mark; auto 12.
    + exact IH.
Qed.

Lemma Forall_q5_match_marks :
  forall bits, Forall canonical_q5_return_pass (map match_mark bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold canonical_q5_return_pass, match_mark; auto 12.
    + exact IH.
Qed.

Definition canonical_row_step
    (first_init : bool) (init_rest : list bool)
    (pre_last : bool) (last_bit : bool)
    (first_action : bool) (action_tail : list bool)
    (last_state : bool) (bnext : bool)
    (data : list nat) (bprev : bool) (rest_tail : list nat)
    : canonical_return_step :=
  let bits := first_init :: init_rest ++ [pre_last; last_bit] in
  let action_init := first_action :: action_tail ++ [last_state] in
  let tail := map source_bit (action_init ++ [bnext]) ++
              source_bit true :: source_bit false :: rest_tail in
  {| crs_post := 5 :: rev
        (match_mark pre_last ::
         rev (map match_mark (first_init :: init_rest)));
     crs_pre := [];
     crs_bprev := bprev;
     crs_data := data;
     crs_data' := data ++ [source_bit bprev];
     crs_symbol := match_mark pre_last;
     crs_remaining := rev (map match_mark (first_init :: init_rest));
     crs_prefix := [6] ++ source_bit bprev :: rev data;
     crs_hit := last_bit;
     crs_next_bit := first_init;
     crs_next_tail :=
       map match_raw init_rest ++
       [match_raw pre_last; match_raw last_bit] ++ tail;
     crs_q16map := [4];
     crs_bits := bits;
     crs_action_init := action_init;
     crs_tbuffer := [];
     crs_bnext := bnext;
     crs_rest := source_bit false :: rest_tail;
     crs_s21 := source_bit last_state;
     crs_rest21 :=
       rev (map source_bit (first_action :: action_tail)) ++ [5];
     crs_hpre := [5];
     crs_hhit := first_action;
     crs_hpost := map source_bit action_tail ++ [source_bit last_state];
     crs_next_bit' := false;
     crs_next_tail' := rest_tail;
     crs_tail := tail |}.

Lemma canonical_row_step_ok :
  forall first_init init_rest pre_last last_bit
         first_action action_tail last_state bnext
         data bprev rest_tail,
    length (first_action :: action_tail ++ [last_state; bnext]) =
    length (first_init :: init_rest ++ [pre_last; last_bit]) ->
    canonical_return_step_ok
      (canonical_row_step first_init init_rest pre_last last_bit
         first_action action_tail last_state bnext
         data bprev rest_tail).
Proof.
  intros first_init init_rest pre_last last_bit first_action action_tail
    last_state bnext data bprev rest_tail Hlen.
  unfold canonical_row_step.
  constructor.
  - (* left *) cbn. repeat rewrite rev_app_distr.
    repeat rewrite rev_involutive. cbn [rev app]. reflexivity.
  - (* scan *) cbn. constructor.
    + unfold canonical_q5_return_pass; auto 12.
    + apply Forall_q5_match_marks.
  - (* rail *) cbn.
    rewrite map_app, rev_app_distr, rev_involutive.
    cbn [map rev app].
    repeat rewrite <- app_assoc.
    reflexivity.
  - (* tail *) cbn. reflexivity.
  - (* prefix *) cbn. rewrite rev_app_distr. cbn. reflexivity.
  - (* shift *) cbn. rewrite rev_app_distr. cbn. reflexivity.
  - (* len *) exact Hlen.
  - (* rest *) cbn. reflexivity.
  - (* restored *) cbn. reflexivity.
  - (* decomp *) cbn. rewrite rev_app_distr. cbn.
    repeat rewrite <- app_assoc. reflexivity.
  - (* pre *) cbn. constructor.
    + unfold q15_pass; auto 12.
    + constructor.
  - (* post *) cbn. apply Forall_app. split.
    + apply Forall_q17_source_bits.
    + constructor.
      * destruct last_state; unfold q17_pass; auto 12.
      * constructor.
  - (* line12 *) cbn. apply Forall_app. split.
    + constructor.
      * destruct bnext; unfold q12_pass, match_mark; auto 12.
      * apply Forall_app. split.
        -- apply Forall_q12_match_marks.
        -- constructor.
           ++ unfold q12_pass; auto 12.
           ++ constructor.
    + constructor.
  - (* line14 *) cbn. apply Forall_app. split.
    + constructor.
      * unfold q14_pass; auto 12.
      * constructor.
    + apply Forall_app. split.
      * apply Forall_q14_match_marks.
      * constructor.
        -- destruct bnext; unfold q14_pass, match_mark; auto 12.
        -- constructor.
Qed.

Print Assumptions canonical_row_step_ok.
