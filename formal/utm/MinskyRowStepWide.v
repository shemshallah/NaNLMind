(** * From a wide source row to the generic native step

    [MinskyRowStepGeneric] constructs a concrete [canonical_return_step]
    from four distinguished condition bits and four action bits.  This
    module extracts those bits from an arbitrary [WideSourceRow] of state
    width at least two, using a simple [split_init] function, and
    discharges the generic length obligation from [wide_row_wellformed].

    The result is a native one-row step attached to a source row, with
    arbitrary data and program tail.  It is still a single macro; the
    whole-program invariant remains open.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyWideSource MinskyConcreteEntry MinskyCanonicalInstruction
  MinskyRowStepGeneric.

Fixpoint split_init (l : list bool) : list bool :=
  match l with
  | [] => []
  | [_] => []
  | x :: rest => x :: split_init rest
  end.

Lemma split_init_last :
  forall (l : list bool) (d : bool),
    l <> [] ->
    split_init l ++ [last l d] = l.
Proof.
  induction l as [|a [|b rest] IH]; intros d Hne.
  - contradiction.
  - simpl. reflexivity.
  - simpl.
    change (a :: (split_init (b :: rest) ++ [last (b :: rest) d]) =
            a :: b :: rest).
    rewrite IH.
    + reflexivity.
    + discriminate.
Qed.

Lemma split_current :
  forall (l : list bool) (d read : bool),
    2 <= length l ->
    hd d l :: tl (split_init l) ++ [last l d; read] = l ++ [read].
Proof.
  intros [|a [|b rest]] d read Hlen; try (cbn in Hlen; lia).
  simpl.
  replace (split_init (b :: rest) ++ [last (b :: rest) d; read])
    with ((split_init (b :: rest) ++ [last (b :: rest) d]) ++ [read]).
  2:{ rewrite <- app_assoc. reflexivity. }
  assert (Hne : b :: rest <> []) by discriminate.
  rewrite (split_init_last (b :: rest) d Hne).
  reflexivity.
Qed.

Lemma split_action :
  forall (l : list bool) (d last_bit : bool),
    2 <= length l ->
    hd d l :: tl (split_init l) ++ [last l d; last_bit] = l ++ [last_bit].
Proof.
  intros l d last_bit Hlen.
  apply split_current. exact Hlen.
Qed.

Definition wide_row_step
    (r : WideSourceRow) (data : list nat) (bprev : bool)
    (rest_tail : list nat) : canonical_return_step :=
  canonical_row_step
    (hd false (wr_current r))
    (tl (split_init (wr_current r)))
    (last (wr_current r) false)
    (wr_read r)
    (hd false (wr_next r))
    (tl (split_init (wr_next r)))
    (last (wr_next r) false)
    (wr_write r)
    data bprev rest_tail.

Theorem wide_row_step_ok :
  forall p r data bprev rest_tail,
    wide_row_wellformed p r ->
    2 <= p ->
    canonical_return_step_ok
      (wide_row_step r data bprev rest_tail).
Proof.
  intros p r data bprev rest_tail [Hcur Hnext] Hp.
  unfold wide_row_step.
  apply canonical_row_step_ok.
  rewrite (split_action (wr_next r) false (wr_write r)).
  2:{ rewrite Hnext. lia. }
  rewrite (split_current (wr_current r) false (wr_read r)).
  2:{ rewrite Hcur. lia. }
  rewrite app_length. cbn [length]. rewrite Hcur, Hnext. lia.
Qed.

Theorem wide_row_step_run :
  forall p r data bprev rest_tail,
    wide_row_wellformed p r ->
    2 <= p ->
    run (canonical_return_step_clock
           (wide_row_step r data bprev rest_tail))
        (canonical_return_step_start
           (wide_row_step r data bprev rest_tail)) =
    canonical_return_step_end
      (wide_row_step r data bprev rest_tail).
Proof.
  intros p r data bprev rest_tail Hwf Hp.
  apply canonical_return_step_run.
  apply wide_row_step_ok; assumption.
Qed.

Print Assumptions wide_row_step_ok.
Print Assumptions wide_row_step_run.
