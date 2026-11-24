From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTableData MinskyTable MinskyChartEncoding
  MinskyChartScan MinskyNaN16Words MinskyNaN16Lookup MinskyNaN16Action.

Lemma nan16_row_write :
  forall e, nth 2 (nan16_row e) 0%nat = e_write e.
Proof.
  intro e. unfold nan16_row, encode_nan16_words, encode_chart_row. cbn.
  reflexivity.
Qed.

Lemma nan16_row_move :
  forall e, nth 3 (nan16_row e) 0%nat = Z.to_nat (e_move e + 1).
Proof.
  intro e. unfold nan16_row, encode_nan16_words, encode_chart_row. cbn.
  reflexivity.
Qed.

Lemma nan16_row_to :
  forall e, nth 4 (nan16_row e) 0%nat = e_to e.
Proof.
  intro e. unfold nan16_row, encode_nan16_words, encode_chart_row. cbn.
  reflexivity.
Qed.

Lemma nan16_row_halt :
  forall e, nth 5 (nan16_row e) 0%nat = (if e_halt e then 1%nat else 0%nat).
Proof.
  intro e. unfold nan16_row, encode_nan16_words, encode_chart_row. cbn.
  destruct (e_halt e); reflexivity.
Qed.

Definition minsky_rows_move_upper : bool :=
  forallb (fun e => Z.leb (e_move e) 1) minsky_entries.

Theorem minsky_rows_move_upper_checked :
  minsky_rows_move_upper = true.
Proof. vm_compute. reflexivity. Qed.

Lemma minsky_rows_move_le_one :
  forall e, In e minsky_entries -> Z.le (e_move e) 1.
Proof.
  intros e Hin.
  pose proof (MinskyTable.forallb_forall _ _ _
    minsky_rows_move_upper_checked e Hin) as H.
  now apply Z.leb_le in H.
Qed.

Lemma nan16_scan_words_some_in :
  forall entries,
    (forall e, In e entries -> Z.le (-1) (e_move e)) ->
    forall q s e,
      nan16_scan_words q s (concat (map nan16_row entries)) = Some e ->
      In e entries.
Proof.
  induction entries as [|a rest IH]; intros Hsafe q s e H.
  - cbn in H. discriminate.
  - cbn [concat map] in H. rewrite nan16_scan_words_cons in H.
    2:{ apply Hsafe. now left. }
    destruct (andb (Nat.eqb (e_from a) q) (Nat.eqb (e_read a) s)) eqn:E.
    + injection H as He. subst e. now left.
    + right. apply (IH ltac:(intros e' Hin; apply Hsafe; now right) q s e H).
Qed.

Lemma nan16_lookup_some_in :
  forall q s e,
    nan16_lookup q s = Some e ->
    In e minsky_entries.
Proof.
  intros q s e H.
  unfold nan16_lookup, nan16_word_image in H.
  change (nan16_scan_words q s (concat (map nan16_row minsky_entries)) = Some e) in H.
  apply (nan16_scan_words_some_in minsky_entries minsky_rows_move_safe q s e H).
Qed.

Lemma nan16_lookup_some_move_range :
  forall q s e,
    nan16_lookup q s = Some e ->
    Z.le (-1) (e_move e) /\ Z.le (e_move e) 1.
Proof.
  intros q s e H.
  split.
  - apply minsky_rows_move_safe. exact (nan16_lookup_some_in q s e H).
  - apply minsky_rows_move_le_one. exact (nan16_lookup_some_in q s e H).
Qed.

Lemma action_new_head_win :
  forall (z : Z) (K h : nat) (mv : Z),
    (0 < z + Z.of_nat K)%Z ->
    Z.le (-1) mv -> Z.le mv 1 ->
    h = Z.to_nat (z + Z.of_nat K) ->
    Z.to_nat (z + mv + Z.of_nat K) =
      action_new_head h (Z.to_nat (mv + 1)).
Proof.
  intros z K h mv Hpos Hlo Hhi Hh.
  assert (Hn : 0 < Z.to_nat (z + Z.of_nat K)).
  { rewrite <- (Z2Nat.inj_lt (0%Z) (z + Z.of_nat K)) by lia. lia. }
  assert (Hmv : mv = (-1)%Z \/ mv = 0%Z \/ mv = 1%Z) by lia.
  destruct Hmv as [E1 | [E2 | E3]].
  - subst mv. replace (Z.add (Z.add z (-1)%Z) (Z.of_nat K)) with (Z.pred (Z.add z (Z.of_nat K))) by lia.
    rewrite Z2Nat.inj_pred.
    subst h. cbn.
    destruct (Z.to_nat (z + Z.of_nat K)) as [|n] eqn:E; [lia|].
    lia.
  - subst mv. replace (Z.add (Z.add z 0%Z) (Z.of_nat K)) with (Z.add z (Z.of_nat K)) by lia.
    subst h. cbn. reflexivity.
  - subst mv. replace (Z.add (Z.add z 1%Z) (Z.of_nat K)) with (Z.succ (Z.add z (Z.of_nat K))) by lia.
    rewrite Z2Nat.inj_succ by lia.
    assert (H2 : Z.to_nat (1%Z + 1%Z) = 2) by reflexivity.
    rewrite H2.
    cbn.
    lia.
Qed.
