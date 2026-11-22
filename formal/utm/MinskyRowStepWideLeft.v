(** * Wide row to the generic left native step

    The leftward analogue of [MinskyRowStepWide].  It uses the same
    concrete condition/action split and the same width obligation.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyWideSource MinskyConcreteEntry MinskyCanonicalInstruction
  MinskyCanonicalLeftStep MinskyRowStepGeneric
  MinskyRowStepGenericLeft MinskyRowStepWide.

Definition wide_row_step_left
    (r : WideSourceRow) (data : list nat) (bprev : bool)
    (rest_tail : list nat) : canonical_left_step :=
  canonical_left_row_step
    (hd false (wr_current r))
    (tl (split_init (wr_current r)))
    (split_last (wr_current r) false)
    (wr_read r)
    (hd false (wr_next r))
    (tl (split_init (wr_next r)))
    (split_last (wr_next r) false)
    (wr_write r)
    data bprev rest_tail.

Theorem wide_row_step_left_ok :
  forall p r data bprev rest_tail,
    wide_row_wellformed p r ->
    2 <= p ->
    canonical_left_step_ok
      (wide_row_step_left r data bprev rest_tail).
Proof.
  intros p r data bprev rest_tail [Hcur Hnext] Hp.
  unfold wide_row_step_left.
  apply canonical_left_row_step_ok.
  rewrite (split_action (wr_next r) false (wr_write r)).
  2:{ rewrite Hnext. lia. }
  rewrite (split_current (wr_current r) false (wr_read r)).
  2:{ rewrite Hcur. lia. }
  assert (Hlen : length (wr_next r) = length (wr_current r))
    by (rewrite Hnext, Hcur; reflexivity).
  repeat rewrite app_length. cbn [length]. rewrite Hlen. reflexivity.
Qed.

Theorem wide_row_step_left_run :
  forall p r data bprev rest_tail,
    wide_row_wellformed p r ->
    2 <= p ->
    run (canonical_left_step_clock
           (wide_row_step_left r data bprev rest_tail))
        (canonical_left_step_start
           (wide_row_step_left r data bprev rest_tail)) =
    canonical_left_step_end
      (wide_row_step_left r data bprev rest_tail).
Proof.
  intros p r data bprev rest_tail Hwf Hp.
  apply canonical_left_step_run.
  apply (wide_row_step_left_ok p r data bprev rest_tail Hwf Hp).
Qed.

Print Assumptions wide_row_step_left_ok.
Print Assumptions wide_row_step_left_run.
