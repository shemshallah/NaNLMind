(** * Source/book row-match equivalence

    The general lookup correspondence starts with the pointwise fact

      wide_row_matches r state bit =
      book_row_matches (state ++ [bit]) (source_row_to_book r).

    This file proves that, plus the source-row extraction for a book hit.
    The remaining lookup packaging is the prefix/failure-witness order
    (see the final gap). *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyMatchMacro MinskyBookLayout MinskyBookLocate
  MinskyBookLocateRows MinskyBookLocateWide MinskyBookLocateCycle
  MinskyBookLocateLookup MinskyBookEncode.

(** ** Append-one injectivity *)

Lemma app_singleton_inj :
  forall (A : Type) (l1 l2 : list A) (x y : A),
    l1 ++ [x] = l2 ++ [y] -> l1 = l2 /\ x = y.
Proof.
  intros A l1. induction l1 as [|a l1 IH]; intros l2 x y H.
  - destruct l2 as [|b l2].
    + cbn in H. injection H as Hx. split; [reflexivity | exact Hx].
    + cbn in H. injection H as _ Htail.
      destruct l2 as [|b' l2']; cbn in Htail; discriminate Htail.
  - destruct l2 as [|b l2].
    + cbn in H. injection H as _ Htail.
      destruct l1 as [|a' l1']; cbn in Htail; discriminate Htail.
    + cbn in H. injection H as Ha Hrest. subst b.
      destruct (IH l2 x y Hrest) as [Hl Hx].
      split; [f_equal; exact Hl | exact Hx].
Qed.

Lemma app_singleton_neq :
  forall (A : Type) (l1 l2 : list A) (x y : A),
    l1 <> l2 -> l1 ++ [x] <> l2 ++ [y].
Proof.
  intros A l1 l2 x y Hneq Heq.
  apply Hneq. apply (proj1 (app_singleton_inj A l1 l2 x y Heq)).
Qed.

(** ** Option helper *)

Lemma book_mismatch_ev_some_of_neq :
  forall (src cond : list bool),
    length src = length cond ->
    src <> cond ->
    exists e, book_mismatch_ev src cond = Some e.
Proof.
  intros src cond Hlen Hneq.
  destruct (book_mismatch_ev src cond) as [e|] eqn:E.
  - exists e. reflexivity.
  - exfalso. apply Hneq.
    apply (book_mismatch_ev_none_eq src cond Hlen E).
Qed.

(** ** Pointwise row-match equivalence *)

Lemma source_row_to_book_matches :
  forall (r : WideSourceRow) (state : list bool) (bit : bool),
    wide_row_matches r state bit =
    book_row_matches (state ++ [bit]) (source_row_to_book r).
Proof.
  intros r state bit.
  unfold wide_row_matches, book_row_matches.
  rewrite source_row_cond.
  destruct (list_eq_dec Bool.bool_dec (wr_current r) state)
    as [Heq | Hneq].
  - subst state.
    destruct (Bool.eqb (wr_read r) bit) eqn:E.
    + apply eqb_prop in E. subst bit.
      rewrite Nat.eqb_refl.
      rewrite book_mismatch_ev_eq_none by reflexivity. reflexivity.
    + apply eqb_false_iff in E.
      assert (Hlenb : Nat.eqb (length (wr_current r ++ [wr_read r]))
                       (length (wr_current r ++ [bit])) = true).
      { apply Nat.eqb_eq. repeat rewrite app_length. cbn [length]. lia. }
      rewrite Hlenb.
      assert (Hlen : length (wr_current r ++ [bit]) =
                    length (wr_current r ++ [wr_read r]))
        by (repeat rewrite app_length; cbn [length]; lia).
      destruct (book_mismatch_ev (wr_current r ++ [bit])
                  (wr_current r ++ [wr_read r])) as [e|] eqn:Hm.
      * reflexivity.
      * exfalso. apply E. symmetry.
        assert (HeqList : wr_current r ++ [bit] =
                          wr_current r ++ [wr_read r])
          by (apply (book_mismatch_ev_none_eq (wr_current r ++ [bit])
            (wr_current r ++ [wr_read r]) Hlen Hm)).
        apply (proj2 (app_singleton_inj bool (wr_current r)
          (wr_current r) bit (wr_read r) HeqList)).
  - destruct (Nat.eqb (length (wr_current r ++ [wr_read r]))
                (length (state ++ [bit]))) eqn:L.
    + apply Nat.eqb_eq in L.
      destruct (book_mismatch_ev (state ++ [bit])
                  (wr_current r ++ [wr_read r])) as [e|] eqn:Hm.
      * reflexivity.
      * exfalso.
        assert (HeqList : state ++ [bit] = wr_current r ++ [wr_read r])
          by (apply (book_mismatch_ev_none_eq (state ++ [bit])
            (wr_current r ++ [wr_read r]) (eq_sym L) Hm)).
        apply Hneq. symmetry.
        apply (proj1 (app_singleton_inj bool state (wr_current r)
          bit (wr_read r) HeqList)).
    + reflexivity.
Qed.

Print Assumptions source_row_to_book_matches.

(** ** A book hit is a source row hit *)

Lemma book_first_match_hit_is_source_row :
  forall (rows : list WideSourceRow) (state : list bool) (bit : bool)
         (steps : list book_failure) (hit : book_row)
         (after : list book_row),
    book_first_match (state ++ [bit]) (source_rows_to_book rows) =
    book_lookup_hit steps hit after ->
    exists r,
      In r rows /\
      hit = source_row_to_book r /\
      wide_row_matches r state bit = true.
Proof.
  intros rows state bit steps hit after Hhit.
  destruct (book_first_match_hit_sound (state ++ [bit])
    (source_rows_to_book rows) steps hit after Hhit)
    as [Hrows [Hforall Hcond]].
  assert (Hin : In hit (source_rows_to_book rows)).
  { rewrite Hrows. apply in_or_app. right. left. reflexivity. }
  apply in_map_iff in Hin.
  destruct Hin as [r [Hr Inr]].
  exists r. split; [exact Inr|].
  split; [symmetry; exact Hr|].
  rewrite (source_row_to_book_matches r state bit).
  rewrite Hr.
  apply book_row_matches_true_of_eq. exact Hcond.
Qed.

Print Assumptions book_first_match_hit_is_source_row.

(** ** Definitional book_lookup_cons steps *)

Lemma book_lookup_cons_hit_some :
  forall (src : list bool) (r : book_row) (rest : list book_row)
         (steps : list book_failure) (hit : book_row) (after : list book_row)
         (e : book_mismatch_type src (br_cond r)),
    rest <> [] ->
    book_mismatch_ev src (br_cond r) = Some e ->
    exists f,
      book_lookup_cons src r rest (book_lookup_hit steps hit after) =
      book_lookup_hit (f :: steps) hit after /\
      bf_src f = src /\
      bf_row f = r.
Proof.
  intros src r rest steps hit after e Hne Hev.
  unfold book_lookup_cons, book_lookup_cons_of.
  rewrite Hev.
  destruct e as [[[[good bad] srest] rrest] Hp].
  destruct rest as [|r' rest']; [contradiction|].
  cbn [book_lookup_cons_of].
  exists (book_failure_of_split src r good bad srest rrest Hp).
  split; [reflexivity|split; reflexivity].
Qed.

Lemma book_lookup_cons_halt_some :
  forall (src : list bool) (r : book_row) (rest : list book_row)
         (steps : list book_failure) (last : book_failure)
         (e : book_mismatch_type src (br_cond r)),
    book_mismatch_ev src (br_cond r) = Some e ->
    exists f,
      book_lookup_cons src r rest (book_lookup_halt steps last) =
      (match rest with
       | [] => book_lookup_halt [] f
       | _ => book_lookup_halt (f :: steps) last
       end) /\
      bf_src f = src /\
      bf_row f = r.
Proof.
  intros src r rest steps last e Hev.
  unfold book_lookup_cons, book_lookup_cons_of.
  rewrite Hev.
  destruct e as [[[[good bad] srest] rrest] Hp].
  destruct rest as [|r' rest']; cbn [book_lookup_cons_of].
  - exists (book_failure_of_split src r good bad srest rrest Hp).
    split; [reflexivity|split; reflexivity].
  - exists (book_failure_of_split src r good bad srest rrest Hp).
    split; [reflexivity|split; reflexivity].
Qed.

(** ** Full hit correspondence *)

Theorem wide_source_lookup_some_book_first_match_hit :
  forall (p : nat) (rows : list WideSourceRow) (state : list bool)
         (bit : bool) (r : WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    length state = p ->
    wide_source_lookup rows state bit = Some r ->
    exists steps hit after,
      book_first_match (state ++ [bit]) (source_rows_to_book rows) =
      book_lookup_hit steps hit after /\
      hit = source_row_to_book r /\
      source_rows_to_book rows = map bf_row steps ++ hit :: after /\
      Forall (fun st => bf_src st = state ++ [bit]) steps.
Proof.
  intros p rows. induction rows as [|r0 rest IH];
    intros state bit r Hwf Hlen Hlookup.
  - unfold wide_source_lookup in Hlookup. simpl in Hlookup. discriminate Hlookup.
  - inversion Hwf as [|? ? Hr0 Hrest]; subst.
    unfold wide_source_lookup in Hlookup. simpl in Hlookup.
    destruct (wide_row_matches r0 state bit) eqn:Hmatch.
    + simpl in Hlookup.
      inversion Hlookup; subst r.
      exists [], (source_row_to_book r0), (source_rows_to_book rest).
      split; [|split; [reflexivity|split; [reflexivity|constructor]]].
      change (book_first_match (state ++ [bit])
                (source_row_to_book r0 :: source_rows_to_book rest) =
              book_lookup_hit [] (source_row_to_book r0)
                (source_rows_to_book rest)).
      cbn [book_first_match].
      rewrite <- (source_row_to_book_matches r0 state bit).
      rewrite Hmatch. reflexivity.
    + simpl in Hlookup.
      assert (Hlookup_rest : wide_source_lookup rest state bit = Some r)
        by exact Hlookup.
      destruct (IH state bit r Hrest eq_refl Hlookup_rest)
        as [steps [hit [after [Hbf [Hhit [Hrows Hforall]]]]]].
      assert (Hne : rest <> []).
      { intro Hnil. subst rest. cbn [wide_source_lookup] in Hlookup_rest.
        discriminate Hlookup_rest. }
      assert (Hbm_false : book_row_matches (state ++ [bit])
                            (source_row_to_book r0) = false).
      { rewrite <- (source_row_to_book_matches r0 state bit).
        exact Hmatch. }
      assert (Hlencond : length (br_cond (source_row_to_book r0)) = S (length state))
        by (apply source_row_cond_length; exact Hr0).
      assert (Hlensrc : length (state ++ [bit]) = S (length state))
        by (rewrite app_length; cbn [length]; lia).
      assert (Hlen_eq : length (br_cond (source_row_to_book r0)) =
                        length (state ++ [bit])) by lia.
      destruct (book_row_matches_false_ev (state ++ [bit])
        (source_row_to_book r0) Hlen_eq Hbm_false) as [e Hev].
      assert (Hne_book : source_rows_to_book rest <> []).
      { intro Hnil. apply Hne. unfold source_rows_to_book in Hnil.
        exact (@map_eq_nil WideSourceRow book_row source_row_to_book rest Hnil). }
      destruct (book_lookup_cons_hit_some (state ++ [bit])
        (source_row_to_book r0) (source_rows_to_book rest)
        steps hit after e Hne_book Hev) as [f [Hcons [Hfsrc Hfrow]]].
      exists (f :: steps), hit, after.
      split; [|split; [exact Hhit|split; [|constructor; [exact Hfsrc|exact Hforall]]]].
      * change (book_first_match (state ++ [bit])
                  (source_row_to_book r0 :: source_rows_to_book rest) =
                book_lookup_hit (f :: steps) hit after).
        cbn [book_first_match].
        rewrite Hbm_false.
        rewrite Hbf.
        exact Hcons.
      * change (source_row_to_book r0 :: source_rows_to_book rest =
                map bf_row (f :: steps) ++ hit :: after).
        rewrite Hrows. cbn [map]. rewrite Hfrow.
        reflexivity.
Qed.

Print Assumptions wide_source_lookup_some_book_first_match_hit.

(** ** Full halt correspondence *)

Theorem wide_source_lookup_none_book_first_match_halt :
  forall (p : nat) (rows : list WideSourceRow) (state : list bool)
         (bit : bool),
    Forall (wide_row_wellformed p) rows ->
    length state = p ->
    rows <> [] ->
    wide_source_lookup rows state bit = None ->
    exists steps last,
      book_first_match (state ++ [bit]) (source_rows_to_book rows) =
      book_lookup_halt steps last /\
      Forall (fun st => bf_src st = state ++ [bit]) (steps ++ [last]) /\
      source_rows_to_book rows = map bf_row (steps ++ [last]).
Proof.
  intros p rows. induction rows as [|r0 rest IH];
    intros state bit Hwf Hlen Hne Hlookup.
  - contradiction.
  - inversion Hwf as [|? ? Hr0 Hrest]; subst.
    unfold wide_source_lookup in Hlookup. simpl in Hlookup.
    destruct (wide_row_matches r0 state bit) eqn:Hmatch.
    + simpl in Hlookup. discriminate Hlookup.
    + simpl in Hlookup.
      assert (Hlookup_rest : wide_source_lookup rest state bit = None)
        by exact Hlookup.
      assert (Hbm_false : book_row_matches (state ++ [bit])
                            (source_row_to_book r0) = false).
      { rewrite <- (source_row_to_book_matches r0 state bit).
        exact Hmatch. }
      assert (Hlencond : length (br_cond (source_row_to_book r0)) =
                          S (length state))
        by (apply source_row_cond_length; exact Hr0).
      assert (Hlensrc : length (state ++ [bit]) = S (length state))
        by (rewrite app_length; cbn [length]; lia).
      assert (Hlen_eq : length (br_cond (source_row_to_book r0)) =
                        length (state ++ [bit])) by lia.
      destruct (book_row_matches_false_ev (state ++ [bit])
        (source_row_to_book r0) Hlen_eq Hbm_false) as [e Hev].
      destruct rest as [|r1 rest'].
      * (* last row; the book cons returns a one-failure halt *)
        destruct e as [[[[good bad] srest] rrest] Hp].
        set (f := book_failure_of_split (state ++ [bit])
          (source_row_to_book r0) good bad srest rrest Hp).
        assert (Hbf : book_first_match (state ++ [bit])
                        (source_row_to_book r0 :: source_rows_to_book [])
                      = book_lookup_halt [] f).
        { change (book_first_match (state ++ [bit])
                    (source_row_to_book r0 :: source_rows_to_book []) =
                  book_lookup_halt [] f).
          cbn [book_first_match].
          rewrite Hbm_false.
          unfold book_lookup_cons, book_lookup_cons_of.
          rewrite Hev.
          cbn [book_lookup_cons_of].
          reflexivity. }
        exists [], f.
        destruct (book_first_match_halt_sound (state ++ [bit])
          (source_rows_to_book (r0 :: [])) [] f Hbf) as [Hrows Hforall].
        split; [exact Hbf|].
        split; [simpl; exact Hforall|exact Hrows].
      * (* a later row; append the current failure to the tail halt *)
        assert (Hne_cons : r1 :: rest' <> []) by discriminate.
        destruct (IH state bit Hrest eq_refl Hne_cons Hlookup_rest)
          as [steps [last [Hbf_rest [Hforall Hrows]]]].
        assert (Hne_book : source_rows_to_book (r1 :: rest') <> []).
        { discriminate. }
        destruct (book_lookup_cons_halt_some (state ++ [bit])
          (source_row_to_book r0) (source_rows_to_book (r1 :: rest'))
          steps last e Hev) as [f [Hcons [Hfsrc Hfrow]]].
        assert (Hbf : book_first_match (state ++ [bit])
                        (source_row_to_book r0 ::
                         source_rows_to_book (r1 :: rest')) =
                      book_lookup_halt (f :: steps) last).
        { change (book_first_match (state ++ [bit])
                    (source_row_to_book r0 ::
                     source_rows_to_book (r1 :: rest')) =
                  book_lookup_halt (f :: steps) last).
          cbn [book_first_match].
          rewrite Hbm_false.
          rewrite Hbf_rest.
          cbn [source_rows_to_book map] in Hcons.
          exact Hcons. }
        exists (f :: steps), last.
        destruct (book_first_match_halt_sound (state ++ [bit])
          (source_rows_to_book (r0 :: r1 :: rest')) (f :: steps) last
          Hbf) as [Hrows' Hforall'].
        split; [exact Hbf|].
        split; [exact Hforall'|exact Hrows'].
Qed.

Print Assumptions wide_source_lookup_none_book_first_match_halt.
