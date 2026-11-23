(** * Padding invariance via the address refinement

    Two zipper configurations with the same state and halt flag whose
    embedded address tapes at a common head coordinate are equal have
    the same halt flag after any fixed fuel.  This is the abstract bridge
    needed for padding invariance; the remaining encoder-side obligation
    is to show that two q5 encodings with different padding embed to the
    same address tape (or agree on the reachable window). *)

From Coq Require Import List Arith Bool ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyAddressRefinement.

Lemma zipper_run_halt_eq_of_embed_eq :
  forall (fuel : nat) (zip1 zip2 : Config) (h : Z),
    c_state zip1 = c_state zip2 ->
    c_halted zip1 = c_halted zip2 ->
    embed_tape (c_tape zip1) h = embed_tape (c_tape zip2) h ->
    c_halted (run fuel zip1) = c_halted (run fuel zip2).
Proof.
  intros fuel zip1 zip2 h Hstate Hhalt Hemb.
  assert (Hsim : config_bisim zip1 (embed_config zip2 h)).
  { unfold config_bisim, embed_config. cbn.
    split; [exact Hstate|]. split; [exact Hhalt|].
    unfold tape_bisim. rewrite <- Hemb. apply embed_tape_bisim. }
  pose proof (zipper_address_run_bisim fuel zip1
    (embed_config zip2 h) Hsim) as H1.
  pose proof (every_zipper_run_has_address_refinement fuel zip2 h) as H2.
  destruct H1 as [_ [Hh1 _]].
  destruct H2 as [_ [Hh2 _]].
  rewrite Hh1, Hh2. reflexivity.
Qed.

Print Assumptions zipper_run_halt_eq_of_embed_eq.
