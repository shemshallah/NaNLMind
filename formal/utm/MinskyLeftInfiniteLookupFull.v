(** * Full source lookup / book first-match correspondence *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskySourceEncoding MinskyWideSource
  MinskyBookEncode MinskyBookLocateRows MinskyBookLocateLookup MinskyLeftInfinite
  MinskyLeftInfiniteLookup.

Lemma find_cons_true :
  forall (A : Type) (f : A -> bool) (x : A) (xs : list A),
    f x = true -> find f (x :: xs) = Some x.
Proof. intros; cbn [find]; rewrite H; reflexivity. Qed.

Lemma find_cons_false :
  forall (A : Type) (f : A -> bool) (x : A) (xs : list A),
    f x = false -> find f (x :: xs) = find f xs.
Proof. intros; cbn [find]; rewrite H; reflexivity. Qed.

Lemma source_row_book_matches :
  forall state bit r,
    wide_row_matches r state bit =
    book_row_matches (state ++ [bit]) (source_row_to_book r).
Proof. intros; apply source_row_to_book_matches. Qed.

Lemma book_mismatch_some_of_nonmatch :
  forall p state bit r,
    length state = p ->
    wide_row_wellformed p r ->
    wide_row_matches r state bit = false ->
    exists e, book_mismatch_ev (state ++ [bit])
                (br_cond (source_row_to_book r)) = Some e.
Proof.
  intros p state bit r Hlen Hwf Hm.
  assert (Hcond : length (br_cond (source_row_to_book r)) =
                  length (state ++ [bit])).
  { rewrite source_row_cond.
    destruct Hwf as [Hc _].
    repeat rewrite app_length. cbn [length].
    rewrite Hc, Hlen. lia. }
  assert (Hbm : book_row_matches (state ++ [bit])
                  (source_row_to_book r) = false).
  { rewrite <- source_row_book_matches. exact Hm. }
  apply (book_row_matches_false_ev _ _ Hcond Hbm).
Qed.

Theorem wide_source_lookup_some_book_hit :
  forall p rows state bit r,
    Forall (wide_row_wellformed p) rows ->
    length state = p ->
    wide_source_lookup rows state bit = Some r ->
    exists steps hit after,
      book_first_match (state ++ [bit]) (source_rows_to_book rows) =
      book_lookup_hit steps hit after /\
      hit = source_row_to_book r.
Proof.
  intros p rows.
  induction rows as [|r0 rest IH]; intros state bit r Hwf Hlen Hlookup.
  - cbn [wide_source_lookup] in Hlookup. discriminate Hlookup.
  - inversion Hwf as [|? ? Hr0 Hrest].
    unfold wide_source_lookup in Hlookup.
    destruct (wide_row_matches r0 state bit) eqn:Hm.
    + assert (Hfind := find_cons_true WideSourceRow
        (fun row => wide_row_matches row state bit) r0 rest Hm).
      rewrite Hfind in Hlookup. inversion Hlookup; subst r0; subst x; clear Hlookup.
      cbn [source_rows_to_book map].
      exists [], (source_row_to_book r), (source_rows_to_book rest).
      split.
      * assert (Hbm : book_row_matches (state ++ [bit])
                      (source_row_to_book r) = true).
        { rewrite <- source_row_book_matches. exact Hm. }
        unfold book_first_match. rewrite Hbm. reflexivity.
      * reflexivity.
    + assert (Hfind := find_cons_false WideSourceRow
        (fun row => wide_row_matches row state bit) r0 rest Hm).
      rewrite Hfind in Hlookup.
      destruct (IH state bit r Hrest Hlen Hlookup)
        as [steps [hit [after [Hbook Hhit]]]].
      assert (Hbm : book_row_matches (state ++ [bit])
                      (source_row_to_book r0) = false).
      { rewrite <- source_row_book_matches. exact Hm. }
      destruct (book_mismatch_some_of_nonmatch p state bit r0 Hlen Hr0 Hm)
        as [e He].
      cbn [source_rows_to_book map book_first_match].
      rewrite Hbm.
      unfold book_lookup_cons, book_lookup_cons_of.
      rewrite He.
      destruct e as [p0 Hp0].
      destruct p0 as [[[good bad] srest] rrest].
      destruct rest as [|r1 rest'].
      * cbn [book_first_match] in Hbook. discriminate Hbook.
      * unfold source_rows_to_book in Hbook.
        cbn [map] in Hbook.
        replace (book_first_match (state ++ [bit])
          (map source_row_to_book (r1 :: rest')))
          with (book_first_match (state ++ [bit])
            (source_row_to_book r1 :: map source_row_to_book rest'))
          by reflexivity.
        rewrite Hbook.
        exists (book_failure_of_split (state ++ [bit])
                  (source_row_to_book r0) good bad srest rrest Hp0 :: steps),
               hit, after.
        split; [reflexivity|exact Hhit].
Qed.

Lemma book_row_matches_false_of_wide_false :
  forall p state bit r,
    length state = p ->
    wide_row_wellformed p r ->
    wide_row_matches r state bit = false ->
    book_row_matches (state ++ [bit]) (source_row_to_book r) = false.
Proof.
  intros p state bit r Hlen Hwf Hm.
  rewrite <- source_row_book_matches. exact Hm.
Qed.

Theorem wide_source_lookup_none_book_halt :
  forall p rows state bit,
    Forall (wide_row_wellformed p) rows ->
    length state = p ->
    rows <> [] ->
    wide_source_lookup rows state bit = None ->
    exists steps last,
      book_first_match (state ++ [bit]) (source_rows_to_book rows) =
      book_lookup_halt steps last.
Proof.
  intros p rows.
  induction rows as [|r0 rest IH]; intros state bit Hwf Hlen Hne Hlookup.
  - contradiction.
  - inversion Hwf as [|? ? Hr0 Hrest].
    unfold wide_source_lookup in Hlookup.
    destruct (wide_row_matches r0 state bit) eqn:Hm.
    + assert (Hfind := find_cons_true WideSourceRow
        (fun row => wide_row_matches row state bit) r0 rest Hm).
      rewrite Hfind in Hlookup. discriminate Hlookup.
    + assert (Hfind := find_cons_false WideSourceRow
        (fun row => wide_row_matches row state bit) r0 rest Hm).
      rewrite Hfind in Hlookup.
      assert (Hbm : book_row_matches (state ++ [bit])
                      (source_row_to_book r0) = false).
      { rewrite <- source_row_book_matches. exact Hm. }
      destruct (book_mismatch_some_of_nonmatch p state bit r0 Hlen Hr0 Hm)
        as [e He].
      destruct e as [p0 Hp0].
      destruct p0 as [[[good bad] srest] rrest].
      cbn [source_rows_to_book map book_first_match].
      rewrite Hbm.
      unfold book_lookup_cons, book_lookup_cons_of.
      rewrite He.
      destruct rest as [|r1 rest'].
      * exists [], (book_failure_of_split (state ++ [bit])
          (source_row_to_book r0) good bad srest rrest Hp0).
        reflexivity.
      * assert (Hne' : r1 :: rest' <> []) by discriminate.
        destruct (IH state bit Hrest Hlen Hne' Hlookup)
          as [steps [last Hbook]].
        exists (book_failure_of_split (state ++ [bit])
          (source_row_to_book r0) good bad srest rrest Hp0 :: steps), last.
        unfold source_rows_to_book in Hbook.
        cbn [map] in Hbook.
        replace (book_first_match (state ++ [bit])
          (map source_row_to_book (r1 :: rest')))
          with (book_first_match (state ++ [bit])
            (source_row_to_book r1 :: map source_row_to_book rest'))
          by reflexivity.
        rewrite Hbook. reflexivity.
Qed.

Print Assumptions wide_source_lookup_some_book_hit.
Print Assumptions wide_source_lookup_none_book_halt.
