(** * First-bit mismatch halt for the boundary lookup

    The lifted boundary source starts with [true], while every lifted
    row condition starts with [false].  The first bit is therefore a
    valid mismatch witness, so the first-match compiler halts (it does
    not return [book_lookup_bad]).  The p-bit source length is not a
    problem: the mismatch is found at bit 0, before any length issue. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyBookLocateRows MinskyBookLocateLookup
  MinskyLeftInfiniteFirstMatchApp.

Lemma book_mismatch_ev_first_bit :
  forall (s rest : list bool),
    book_mismatch_ev (true :: s) (false :: rest) <> None.
Proof.
  intros s rest H. cbn [book_mismatch_ev] in H. discriminate H.
Qed.

Lemma book_row_matches_first_bit_false :
  forall (src_tail row_tail : list bool) (r : book_row),
    br_cond r = false :: row_tail ->
    book_row_matches (true :: src_tail) r = false.
Proof.
  intros src_tail row_tail r Hrow.
  unfold book_row_matches. rewrite Hrow.
  destruct (Nat.eqb (length (false :: row_tail))
    (length (true :: src_tail))) eqn:E.
  - cbn [andb]. cbn [book_mismatch_ev]. reflexivity.
  - reflexivity.
Qed.

Lemma book_first_match_first_bit_halt :
  forall (src : list bool) (rows : list book_row),
    rows <> [] ->
    (exists s, src = true :: s) ->
    (forall r, In r rows -> exists s, br_cond r = false :: s) ->
    exists steps last, book_first_match src rows = book_lookup_halt steps last.
Proof.
  intros src rows. induction rows as [|r rest IH];
    intros Hne Hsrc Hrow.
  - contradiction.
  - destruct Hsrc as [s Hsrc].
    destruct (Hrow r (or_introl eq_refl)) as [srest Hcond].
    assert (Hbm : book_row_matches src r = false).
    { rewrite Hsrc.
      apply (book_row_matches_first_bit_false s srest r Hcond). }
    rewrite book_first_match_cons.
    rewrite Hbm.
    destruct rest as [|r' rest'].
    + (* last row: rest = [] *)
      destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:E.
      * destruct e as [p Hp].
        destruct p as [[[good bad] src_rest] row_rest].
        exists [], (book_failure_of_split src r good bad src_rest row_rest Hp).
        unfold book_lookup_cons, book_lookup_cons_of.
        rewrite E. reflexivity.
      * exfalso. apply (book_mismatch_ev_first_bit s srest).
        rewrite Hsrc, Hcond in E. exact E.
    + (* another row follows *)
      assert (Hrows' : r' :: rest' <> []) by discriminate.
      destruct (IH Hrows' ltac:(exists s; exact Hsrc)
        ltac:(intros x Hx; apply Hrow; right; exact Hx))
        as [steps [last Hbf]].
      destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:E.
      * destruct e as [p Hp].
        destruct p as [[[good bad] src_rest] row_rest].
        exists (book_failure_of_split src r good bad src_rest row_rest Hp :: steps), last.
        unfold book_lookup_cons, book_lookup_cons_of.
        rewrite E. rewrite Hbf. reflexivity.
      * exfalso. apply (book_mismatch_ev_first_bit s srest).
        rewrite Hsrc, Hcond in E. exact E.
Qed.

Print Assumptions book_first_match_first_bit_halt.
