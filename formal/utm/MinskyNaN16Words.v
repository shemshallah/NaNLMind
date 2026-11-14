(** * Eight-word native NaN16 Minsky-table refinement

    The native [mth_minsky_test.nas] and [mth_minsky_encoded_test.nas]
    use an eight-word stride (shift-left by three) for table rows:
       from, read, write, move+1, to, halt, 0, 0.
    This differs from the C++ interpreter's six-byte stride.  We model
    the two representations independently and prove that their sequential
    first-match lookup and arbitrary finite-run semantics agree.

    A separate repository gate checks the literal .nas table words against
    tests/minsky_table.inc.  The theorem covers transition semantics of
    the word-list model, not the NaN16 assembler, ISA, or compiled image.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.
Open Scope Z_scope.

From NaNLM Require Import MinskyTableData MinskyTable
  MinskyAddressRefinement MinskyChartEncoding MinskyChartScan.

Definition encode_nan16_words (e : Entry) : list nat :=
  encode_chart_row e ++ [0%nat; 0%nat].

Lemma encode_nan16_words_length :
  forall e, length (encode_nan16_words e) = 8%nat.
Proof. intro e. unfold encode_nan16_words, encode_chart_row.
  simpl. reflexivity. Qed.

(** The native loop performs the key comparison BEFORE decoding the
    remaining four fields.  The two padding words are skipped. *)
Fixpoint nan16_scan_words (q s : nat) (words : list nat) : option Entry :=
  match words with
  | from :: read_symbol :: write_symbol :: direction :: target :: stop ::
      _padding0 :: _padding1 :: rest =>
      if (Nat.eqb from q && Nat.eqb read_symbol s)%bool then
        decode_chart_row
          [from; read_symbol; write_symbol; direction; target; stop]
      else nan16_scan_words q s rest
  | _ => None
  end.

Lemma nan16_scan_words_cons :
  forall q s e tail,
    -1 <= e_move e ->
    nan16_scan_words q s (encode_nan16_words e ++ tail) =
      if (Nat.eqb (e_from e) q && Nat.eqb (e_read e) s)%bool
      then Some e else nan16_scan_words q s tail.
Proof.
  intros q s [f r w m dest stop] tail Hmove.
  simpl in Hmove.
  assert (Hnonnegative : (0 <= m + 1)%Z) by lia.
  unfold encode_nan16_words, encode_chart_row.
  simpl.
  rewrite (Z2Nat.id (m + 1)) by exact Hnonnegative.
  replace (m + 1 - 1) with m by lia.
  destruct stop; reflexivity.
Qed.

(** The first matching row wins even if multiple rows have the same key. *)
Theorem nan16_scan_matches_rows :
  forall rows q s,
    (forall e, In e rows -> -1 <= e_move e) ->
    nan16_scan_words q s (concat (map encode_nan16_words rows)) =
    scan_entry q s rows.
Proof.
  induction rows as [|e rest IH]; intros q s Hmoves.
  - reflexivity.
  - cbn [map concat scan_entry].
    rewrite nan16_scan_words_cons.
    + destruct (Nat.eqb (e_from e) q && Nat.eqb (e_read e) s)%bool.
      * reflexivity.
      * apply IH. intros e' Hin. apply Hmoves. now right.
    + apply Hmoves. now left.
Qed.

Definition nan16_word_image : list nat :=
  concat (map encode_nan16_words minsky_entries).

Theorem nan16_word_image_length :
  length nan16_word_image = 1472%nat.
Proof. vm_compute. reflexivity. Qed.

Definition nan16_lookup (q s : nat) : option Entry :=
  nan16_scan_words q s nan16_word_image.

Theorem nan16_lookup_agrees_all :
  forall q s, nan16_lookup q s = scan_table q s.
Proof.
  intros q s. unfold nan16_lookup, nan16_word_image, scan_table.
  apply nan16_scan_matches_rows.
  exact minsky_rows_move_safe.
Qed.

(** The six-byte C++ chart and eight-word NaN16 chart are extensionally
    equal as transition decoders, including out-of-range inputs. *)
Theorem nan16_sixbyte_lookup_agree :
  forall q s, nan16_lookup q s = chart_scan q s.
Proof.
  intros q s.
  rewrite nan16_lookup_agrees_all, chart_scan_agrees_all.
  reflexivity.
Qed.

Definition nan16_address_step : AddressConfig -> AddressConfig :=
  address_step_with nan16_lookup.

Theorem nan16_address_step_refines :
  forall c, nan16_address_step c = chart_scan_address_step c.
Proof.
  intro c.
  unfold nan16_address_step, chart_scan_address_step, address_step_with.
  destruct (a_halted c); [reflexivity |].
  rewrite nan16_sixbyte_lookup_agree.
  reflexivity.
Qed.

Theorem nan16_address_run_refines :
  forall fuel c,
    address_run fuel nan16_address_step c =
    address_run fuel chart_scan_address_step c.
Proof.
  induction fuel as [|n IH]; intro c; simpl.
  - reflexivity.
  - destruct (a_halted c); [reflexivity |].
    rewrite nan16_address_step_refines. apply IH.
Qed.

Theorem nan16_zipper_run_bisim :
  forall fuel zip addr,
    config_bisim zip addr ->
    config_bisim (run fuel zip)
      (address_run fuel nan16_address_step addr).
Proof.
  intros fuel zip addr H.
  rewrite nan16_address_run_refines.
  now apply zipper_chart_scan_run_bisim.
Qed.

Print Assumptions nan16_scan_matches_rows.
Print Assumptions nan16_lookup_agrees_all.
Print Assumptions nan16_sixbyte_lookup_agree.
Print Assumptions nan16_address_run_refines.
Print Assumptions nan16_zipper_run_bisim.
