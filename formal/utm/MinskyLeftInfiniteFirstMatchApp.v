(** * Appending rows to a computed first match

    The final encoder augments the source program with an extra trailing
    row.  A first-match hit inside the original rows is unchanged by the
    appended suffix; the hit's [after] suffix simply grows.  A no-match
    halt concatenates the failure lists. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyBookLocateRows MinskyBookLocateLookup.

(** One-step unfolding that keeps the recursive call opaque. *)

Lemma book_first_match_cons :
  forall (src : list bool) (r : book_row) (rest : list book_row),
    book_first_match src (r :: rest) =
    if book_row_matches src r then book_lookup_hit [] r rest
    else book_lookup_cons src r rest (book_first_match src rest).
Proof. reflexivity. Qed.

(** ** Appending preserves a hit *)

Lemma book_first_match_hit_app :
  forall (src : list bool) (rows extra : list book_row)
         (steps : list book_failure) (hit : book_row)
         (after : list book_row),
    book_first_match src rows = book_lookup_hit steps hit after ->
    book_first_match src (rows ++ extra) =
    book_lookup_hit steps hit (after ++ extra).
Proof.
  intros src rows. induction rows as [|r rest IH];
    intros extra steps hit after H.
  - cbn [book_first_match] in H. discriminate H.
  - change (book_first_match src (r :: (rest ++ extra)) =
            book_lookup_hit steps hit (after ++ extra)).
    rewrite book_first_match_cons.
    rewrite book_first_match_cons in H.
    destruct (book_row_matches src r) eqn:Hm.
    + cbn in H. inversion H; subst; clear H. reflexivity.
    + destruct rest as [|r' rest'].
      * unfold book_lookup_cons, book_lookup_cons_of in H.
        destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:He.
        -- destruct e as [p Hp].
           destruct p as [[[good bad] srest] rrest].
           cbn [book_lookup_cons_of] in H. discriminate H.
        -- discriminate H.
      * unfold book_lookup_cons, book_lookup_cons_of in H.
        destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:He.
        -- destruct e as [p Hp].
           destruct p as [[[good bad] srest] rrest].
           cbn [book_lookup_cons_of] in H.
           destruct (book_first_match src (r' :: rest'))
             as [steps0 hit0 after0|steps0 last0|] eqn:Hrec.
           ++ cbn in H. inversion H; subst; clear H.
              unfold book_lookup_cons, book_lookup_cons_of.
              rewrite He.
              rewrite (IH extra steps0 hit after eq_refl).
              reflexivity.
           ++ discriminate H.
           ++ discriminate H.
        -- discriminate H.
Qed.

Print Assumptions book_first_match_hit_app.

(** ** Appending concatenates halts *)

Lemma book_first_match_halt_app :
  forall (src : list bool) (rows extra : list book_row)
         (steps : list book_failure) (last : book_failure)
         (steps' : list book_failure) (last' : book_failure),
    book_first_match src rows = book_lookup_halt steps last ->
    book_first_match src extra = book_lookup_halt steps' last' ->
    book_first_match src (rows ++ extra) =
    book_lookup_halt (steps ++ last :: steps') last'.
Proof.
  intros src rows. induction rows as [|r rest IH];
    intros extra steps last steps' last' H Hex.
  - cbn [book_first_match] in H. discriminate H.
  - change (book_first_match src (r :: (rest ++ extra)) =
            book_lookup_halt (steps ++ last :: steps') last').
    rewrite book_first_match_cons.
    rewrite book_first_match_cons in H.
    destruct (book_row_matches src r) eqn:Hm.
    + cbn in H. discriminate H.
    + destruct rest as [|r' rest'].
      * unfold book_lookup_cons, book_lookup_cons_of in H.
        destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:He.
        -- destruct e as [p Hp].
           destruct p as [[[good bad] srest] rrest].
           cbn [book_lookup_cons_of] in H.
           inversion H; subst; clear H.
           destruct extra as [|x xs].
           ++ cbn [book_first_match] in Hex. discriminate Hex.
           ++ unfold book_lookup_cons, book_lookup_cons_of.
              rewrite He.
              cbn [app].
              rewrite Hex. reflexivity.
        -- discriminate H.
      * unfold book_lookup_cons, book_lookup_cons_of in H.
        destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:He.
        -- destruct e as [p Hp].
           destruct p as [[[good bad] srest] rrest].
           cbn [book_lookup_cons_of] in H.
           destruct (book_first_match src (r' :: rest'))
             as [steps0 hit0 after0|steps0 last0|] eqn:Hrec.
           ++ discriminate H.
           ++ cbn in H. inversion H; subst; clear H.
              unfold book_lookup_cons, book_lookup_cons_of.
              rewrite He.
              rewrite (IH extra steps0 last steps' last' eq_refl Hex).
              reflexivity.
           ++ discriminate H.
        -- discriminate H.
Qed.

Print Assumptions book_first_match_halt_app.
