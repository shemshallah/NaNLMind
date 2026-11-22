(** * Orientation obstruction for the raw q5-return layout

    The generic one-row step ends with the marker order

      data, bnext, 6, 5, action

    while the canonical q5-return start expects

      rail, 5, 6, bprev, data.

    The q5-return-to-q6 macro additionally requires its post-5 prefix to
    contain a 6.  This file proves that the two requirements cannot both
    hold when the prefix is a binary bit followed by binary data: the
    first 5 consumes the marker, and the prefix then has no 6.

    This is an exact negative result about the raw layout.  It is not a
    negative result about the frozen table: the tagged/normalized layout
    is a different encoding.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding.

Lemma prefix_after_first_five :
  forall (X rest rail prefix : list nat),
    ~ In 5 X ->
    ~ In 5 rail ->
    X ++ 5 :: rest = rail ++ 5 :: prefix ->
    prefix = rest.
Proof.
  induction X as [|x xs IH]; intros rest rail prefix HX Hrail Heq.
  - simpl in Heq. destruct rail as [|r rs].
    + simpl in Heq. inversion Heq. reflexivity.
    + simpl in Heq. injection Heq as Hhead Htail.
      exfalso. apply Hrail. left. symmetry. exact Hhead.
  - destruct rail as [|r rs].
    + simpl in Heq. injection Heq as Hhead Htail.
      exfalso. apply HX. left. exact Hhead.
    + simpl in Heq. injection Heq as Hhead Htail.
      apply (IH rest rs prefix).
      * intros H. apply HX. right. exact H.
      * intros H. apply Hrail. right. exact H.
      * exact Htail.
Qed.

Theorem five_six_swap_not_canonical_prefix :
  forall (X rest rail prefix tbuffer data'' : list nat),
    ~ In 5 X ->
    ~ In 5 rail ->
    ~ In 6 rest ->
    X ++ 5 :: rest = rail ++ 5 :: prefix ->
    prefix = rev tbuffer ++ 6 :: rev data'' ->
    False.
Proof.
  intros X rest rail prefix tbuffer data'' HX Hrail Hrest Heq Hpre.
  assert (Hpr : prefix = rest)
    by (apply (prefix_after_first_five X rest rail prefix); assumption).
  apply Hrest. rewrite <- Hpr. rewrite Hpre.
  apply in_or_app. right. left. reflexivity.
Qed.

Print Assumptions five_six_swap_not_canonical_prefix.
