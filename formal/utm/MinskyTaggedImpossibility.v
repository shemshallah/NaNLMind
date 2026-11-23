(** * Two formal obstructions for the current prefetch -> q6 route

    The q1 prefetch endpoints carry a q1-skip prefix containing both 0
    and 6.  The q6 copy phase requires its processed rail to be q9-pass,
    i.e. only 2/3, and the q12 scan excludes 6.  These are direct
    interface obstructions for composing the current prefetch macro with
    the canonical q6/q12 phases; they do not rule out a different native
    layout. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyMatchMacro MinskyActionMacro MinskyDirectionRelocationCycle
  MinskyTaggedPrefetch.

Definition right_prefetch_pass (tags : list bool) : list nat :=
  rev (map q0_stable_control_tag tags) ++ [6; 0].

Definition left_prefetch_pass (tags : list bool) : list nat :=
  [6; 0] ++ rev (map q0_stable_control_tag (rev tags)).

Lemma right_prefetch_pass_has_zero :
  forall tags, In 0 (right_prefetch_pass tags).
Proof.
  intros tags. unfold right_prefetch_pass.
  apply in_or_app. right. simpl; auto.
Qed.

Lemma right_prefetch_pass_has_six :
  forall tags, In 6 (right_prefetch_pass tags).
Proof.
  intros tags. unfold right_prefetch_pass.
  apply in_or_app. right. simpl; auto.
Qed.

Lemma left_prefetch_pass_has_zero :
  forall tags, In 0 (left_prefetch_pass tags).
Proof.
  intros tags. unfold left_prefetch_pass.
  apply in_or_app. left. simpl; auto.
Qed.

Lemma left_prefetch_pass_has_six :
  forall tags, In 6 (left_prefetch_pass tags).
Proof.
  intros tags. unfold left_prefetch_pass.
  apply in_or_app. left. simpl; auto.
Qed.

Lemma q9_pass_zero_false : ~ q9_pass 0.
Proof. unfold q9_pass; intros [H|H]; discriminate H. Qed.

Lemma q12_pass_six_false : ~ q12_pass 6.
Proof. unfold q12_pass; intros [H|[H|[H|[H|[H|[H|H]]]]]]; discriminate H. Qed.

Lemma right_prefetch_pass_not_q9 :
  forall tags, ~ Forall q9_pass (right_prefetch_pass tags).
Proof.
  intros tags H.
  pose proof (right_prefetch_pass_has_zero tags) as Hin.
  apply Forall_forall with (x := 0) in H; [| exact Hin].
  exact (q9_pass_zero_false H).
Qed.

Lemma left_prefetch_pass_not_q9 :
  forall tags, ~ Forall q9_pass (left_prefetch_pass tags).
Proof.
  intros tags H.
  pose proof (left_prefetch_pass_has_zero tags) as Hin.
  apply Forall_forall with (x := 0) in H; [| exact Hin].
  exact (q9_pass_zero_false H).
Qed.

Lemma right_prefetch_pass_not_q12 :
  forall tags, ~ Forall q12_pass (right_prefetch_pass tags).
Proof.
  intros tags H.
  pose proof (right_prefetch_pass_has_six tags) as Hin.
  apply Forall_forall with (x := 6) in H; [| exact Hin].
  exact (q12_pass_six_false H).
Qed.

Lemma left_prefetch_pass_not_q12 :
  forall tags, ~ Forall q12_pass (left_prefetch_pass tags).
Proof.
  intros tags H.
  pose proof (left_prefetch_pass_has_six tags) as Hin.
  apply Forall_forall with (x := 6) in H; [| exact Hin].
  exact (q12_pass_six_false H).
Qed.

Print Assumptions right_prefetch_pass_not_q9.
Print Assumptions right_prefetch_pass_not_q12.
Print Assumptions left_prefetch_pass_not_q9.
Print Assumptions left_prefetch_pass_not_q12.
