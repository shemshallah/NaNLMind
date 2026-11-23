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
