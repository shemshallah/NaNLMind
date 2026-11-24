From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTableData MinskyTable
  MinskyChartEncoding MinskyChartScan MinskyNaN16Words MinskyNaN16VM.

Definition nan16_row (e : Entry) : list nat := encode_nan16_words e.
Definition nan16_rows : list (list nat) := map nan16_row minsky_entries.

Lemma nan16_row_length : forall e, length (nan16_row e) = 8.
Proof. intro e. apply encode_nan16_words_length. Qed.

Lemma nan16_row_head0 :
  forall e, nth 0 (nan16_row e) 0 = e_from e.
Proof.
  intro e. unfold nan16_row, encode_nan16_words, encode_chart_row. cbn.
  reflexivity.
Qed.

Lemma nan16_row_head1 :
  forall e, nth 1 (nan16_row e) 0 = e_read e.
Proof.
  intro e. unfold nan16_row, encode_nan16_words, encode_chart_row. cbn.
  reflexivity.
Qed.

Lemma nan16_rows_length : length nan16_rows = 184.
Proof.
  unfold nan16_rows. rewrite length_map. apply minsky_entries_length.
Qed.

Lemma nan16_rows_forall_short :
  Forall (fun row => 0 < length row /\ 1 < length row) nan16_rows.
Proof.
  apply Forall_forall. intros row Hin.
  apply in_map_iff in Hin. destruct Hin as [e [He Hmem]]. subst row.
  rewrite nan16_row_length. lia.
Qed.

Lemma nan16_rows_forall_len :
  Forall (fun row => length row = 8) nan16_rows.
Proof.
  apply Forall_forall. intros row Hin.
  apply in_map_iff in Hin. destruct Hin as [e [He Hmem]]. subst row.
  apply nan16_row_length.
Qed.

Lemma scan_index_from_image_some :
  forall entries,
    (forall e, In e entries -> Z.le (-1) (e_move e)) ->
    forall i state sym j row,
      scan_index_from i state sym (map nan16_row entries) = Some (j, row) ->
      exists e,
        row = nan16_row e /\
        nan16_scan_words state sym (concat (map nan16_row entries)) = Some e.
Proof.
  induction entries as [|e rest IH]; intros Hsafe i state sym j row Hidx.
  - cbn in Hidx. discriminate.
  - cbn [map scan_index_from] in Hidx.
    rewrite nan16_row_head0, nan16_row_head1 in Hidx.
    cbn [concat map].
    rewrite nan16_scan_words_cons.
    2:{ apply Hsafe. now left. }
    destruct ((e_from e =? state) && (e_read e =? sym)) eqn:E.
    + cbn in Hidx. injection Hidx as Hj Hrow. subst j row.
      exists e. split; [reflexivity|]. reflexivity.
    + cbn in Hidx.
      destruct (IH ltac:(intros e' Hin; apply Hsafe; now right) (S i)
        state sym j row Hidx) as [e' [Hrow Hlook]].
      exists e'. split; [exact Hrow|]. exact Hlook.
Qed.

Lemma scan_index_from_image_none :
  forall entries,
    (forall e, In e entries -> Z.le (-1) (e_move e)) ->
    forall i state sym,
      scan_index_from i state sym (map nan16_row entries) = None ->
      nan16_scan_words state sym (concat (map nan16_row entries)) = None.
Proof.
  induction entries as [|e rest IH]; intros Hsafe i state sym Hidx.
  - reflexivity.
  - cbn [map scan_index_from] in Hidx.
    rewrite nan16_row_head0, nan16_row_head1 in Hidx.
    cbn [concat map].
    rewrite nan16_scan_words_cons.
    2:{ apply Hsafe. now left. }
    destruct ((e_from e =? state) && (e_read e =? sym)) eqn:E.
    + cbn in Hidx. discriminate.
    + cbn in Hidx.
      apply (IH ltac:(intros e' Hin; apply Hsafe; now right)
        (S i) state sym Hidx).
Qed.

Lemma scan_index_nan16_rows_some :
  forall state sym j row,
    scan_index_from 0 state sym nan16_rows = Some (j, row) ->
    exists e, nan16_lookup state sym = Some e /\ row = nan16_row e.
Proof.
  intros state sym j row Hidx.
  unfold nan16_rows in Hidx.
  destruct (scan_index_from_image_some minsky_entries minsky_rows_move_safe
    0 state sym j row Hidx) as [e [Hrow Hlook]].
  exists e. split; [|exact Hrow].
  unfold nan16_lookup, nan16_word_image.
  change (nan16_scan_words state sym
    (concat (map nan16_row minsky_entries)) = Some e).
  exact Hlook.
Qed.

Lemma scan_index_nan16_rows_none :
  forall state sym,
    scan_index_from 0 state sym nan16_rows = None ->
    nan16_lookup state sym = None.
Proof.
  intros state sym Hidx.
  unfold nan16_rows in Hidx.
  unfold nan16_lookup, nan16_word_image.
  change (nan16_scan_words state sym
    (concat (map nan16_row minsky_entries)) = None).
  apply (scan_index_from_image_none minsky_entries minsky_rows_move_safe
    0 state sym Hidx).
Qed.
