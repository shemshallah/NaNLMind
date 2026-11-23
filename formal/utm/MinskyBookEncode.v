(** * Source-row to book-row encoding

    This module connects the wide source rows to the book-layout locate
    rows.  It deliberately stops at the initial q5/locate frame; the
    total tape-window encoder is a separate obligation. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskySourceEncoding MinskyWideSource MinskyBookLayout
  MinskyBookLocate MinskyBookLocateRows.

Definition source_row_to_book (r : WideSourceRow) : book_row :=
  {| br_cond := wr_current r ++ [wr_read r];
     br_action := wr_next r ++ [wr_write r];
     br_dir := wr_right r |}.

Definition source_rows_to_book (rows : list WideSourceRow) : list book_row :=
  map source_row_to_book rows.

Lemma source_row_cond :
  forall r,
    br_cond (source_row_to_book r) = wr_current r ++ [wr_read r].
Proof. reflexivity. Qed.

Lemma source_row_action :
  forall r,
    br_action (source_row_to_book r) = wr_next r ++ [wr_write r].
Proof. reflexivity. Qed.

Lemma source_row_dir :
  forall r, br_dir (source_row_to_book r) = wr_right r.
Proof. reflexivity. Qed.

Lemma source_row_action_length :
  forall p r,
    wide_row_wellformed p r ->
    length (br_action (source_row_to_book r)) =
    length (br_cond (source_row_to_book r)).
Proof.
  intros p r [Hc Hn].
  unfold source_row_to_book; simpl.
  rewrite app_length, app_length. cbn [length].
  rewrite Hc, Hn. lia.
Qed.

Lemma source_row_cond_length :
  forall p r,
    wide_row_wellformed p r ->
    length (br_cond (source_row_to_book r)) = S p.
Proof.
  intros p r [Hc Hn].
  unfold source_row_to_book; simpl.
  rewrite app_length. cbn [length]. rewrite Hc. lia.
Qed.

Lemma source_rows_cond_length :
  forall p rows,
    Forall (wide_row_wellformed p) rows ->
    Forall (fun r => length (br_cond r) = S p)
      (source_rows_to_book rows).
Proof.
  intros p rows H.
  induction H as [|r rows Hr Hrows IH]; simpl.
  - constructor.
  - constructor.
    + apply source_row_cond_length. exact Hr.
    + exact IH.
Qed.

(** The raw encoded description starts with the first X. *)
Definition book_initial_desc (rows : list WideSourceRow) : list nat :=
  4 :: book_raw_desc (source_rows_to_book rows).

Lemma book_initial_desc_nonempty :
  forall rows, book_initial_desc rows <> [].
Proof. intros rows. unfold book_initial_desc. discriminate. Qed.

(** Initial q5 entry for a nonempty encoded program. *)
Definition book_initial_frame
    (src : list bool) (rows : list WideSourceRow)
    (buf : nat) (ptape tail : list nat) : Config :=
  entry_config 5
    (rev (map source_bit src) ++ 5 :: rev (book_buf buf) ++
     6 :: rev ptape)
    (book_initial_desc rows ++ 5 :: tail).

Lemma book_initial_q5_to_locate_state :
  forall src rows buf ptape tail,
    rows <> [] ->
    run (length src + 2)
      (book_initial_frame src rows buf ptape tail) =
    book_locate_state src [] (source_rows_to_book rows) buf ptape tail.
Proof.
  intros src rows buf ptape tail Hne.
  unfold book_initial_frame, book_initial_desc.
  change (run (length src + 2)
    (entry_config 5
      (rev (map source_bit src) ++ 5 :: rev (book_buf buf) ++
       6 :: rev ptape)
      (4 :: (book_raw_desc (source_rows_to_book rows) ++ 5 :: tail))) =
    book_locate_state src [] (source_rows_to_book rows) buf ptape tail).
  rewrite (book_q5_scan_general src (book_buf buf) ptape
    (book_raw_desc (source_rows_to_book rows) ++ 5 :: tail)).
  assert (Htail :
    book_raw_tail (source_rows_to_book rows) =
    4 :: book_raw_desc (source_rows_to_book rows)).
  { destruct (source_rows_to_book rows) as [|r rest] eqn:E.
    - destruct rows; [contradiction|].
      unfold source_rows_to_book in E; simpl in E; discriminate E.
    - reflexivity. }
  unfold book_locate_state, book_marked_prefix.
  rewrite Htail. cbn [app]. reflexivity.
Qed.

Print Assumptions source_row_action_length.
Print Assumptions source_rows_cond_length.
Print Assumptions book_initial_q5_to_locate_state.
