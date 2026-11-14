(** * An arbitrary-length concrete-table scan of encoded source programs

    This file bridges the literal source-row encoder to MinskyTable.run,
    without replacing the table by the abstract source interpreter.

    The machine starts in state 5 with its head at the RIGHTMOST encoded
    symbol, and with the remaining encoded symbols in reversed zipper order
    to its left, followed by the Y delimiter (symbol 5).

    Every source symbol is a 0, 1, or X=4.  The actual table overwrites
    0->2 and 1->3 during the leftward pass.  A final transition across Y
    enters state 1.  The scan length depends on the source description,
    not on a fixed-size example.

    This theorem is a concrete macro-step, not the source-instruction
    simulation theorem and not an unrestricted universality claim.
*)

From Coq Require Import List Arith ZArith Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry.

Lemma source_bit_is_scan_symbol :
  forall b, entry_scan_symbol (source_bit b).
Proof.
  intros [|]; unfold entry_scan_symbol, source_bit;
    [right; left | left]; reflexivity.
Qed.

Lemma source_marker_is_scan_symbol : entry_scan_symbol 4.
Proof. unfold entry_scan_symbol; right; right; reflexivity. Qed.

Lemma encoded_row_is_scannable :
  forall row, Forall entry_scan_symbol (encode_source_row row).
Proof.
  intros [a b c d e f g].
  unfold encode_source_row.
  constructor. { apply source_marker_is_scan_symbol. }
  constructor. { apply source_bit_is_scan_symbol. }
  constructor. { apply source_bit_is_scan_symbol. }
  constructor. { apply source_bit_is_scan_symbol. }
  constructor. { apply source_bit_is_scan_symbol. }
  constructor. { apply source_bit_is_scan_symbol. }
  constructor. { apply source_bit_is_scan_symbol. }
  constructor. { apply source_bit_is_scan_symbol. }
  constructor.
Qed.

Lemma scan_symbols_append :
  forall xs ys,
    Forall entry_scan_symbol xs ->
    Forall entry_scan_symbol ys ->
    Forall entry_scan_symbol (xs ++ ys).
Proof.
  intros xs ys Hxs Hys.
  induction Hxs as [|x xs Hx Hxs IH].
  - exact Hys.
  - simpl. constructor; assumption.
Qed.

Theorem encoded_program_is_scannable :
  forall rows,
    Forall entry_scan_symbol (encode_source_program rows).
Proof.
  induction rows as [|row rows IH].
  - constructor.
  - change (Forall entry_scan_symbol
      (encode_source_row row ++ encode_source_program rows)).
    apply scan_symbols_append.
    + apply encoded_row_is_scannable.
    + exact IH.
Qed.

Lemma scannable_reverse :
  forall xs,
    Forall entry_scan_symbol xs ->
    Forall entry_scan_symbol (rev xs).
Proof.
  intros xs H.
  induction H as [|x xs Hx Hxs IH].
  - constructor.
  - simpl. apply scan_symbols_append.
    + exact IH.
    + constructor; [exact Hx | constructor].
Qed.

(** The zipper condition states the EXACT layout of the encoded program.
    For an empty program no such s/remaining pair exists.  For a nonempty
    program the pair is uniquely obtained by reversing the byte stream. *)
Theorem encoded_program_left_scan :
  forall rows s remaining prefix suffix,
    rev (encode_source_program rows) = s :: remaining ->
    run (S (length (s :: remaining)))
      (entry_config 5 (remaining ++ 5 :: prefix) (s :: suffix)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (encode_source_program rows) ++ suffix).
Proof.
  intros rows s remaining prefix suffix Hlayout.
  assert (Hscannable : Forall entry_scan_symbol (s :: remaining)).
  {
    rewrite <- Hlayout.
    apply scannable_reverse.
    apply encoded_program_is_scannable.
  }
  rewrite <- (rev_involutive (encode_source_program rows)).
  rewrite Hlayout.
  apply entry_scan_unbounded.
  exact Hscannable.
Qed.

(** Each program containing at least one row has such a nonempty
    reversed tape layout; there is no arbitrary finite length bound. *)
Lemma encoded_nonempty_program_layout :
  forall row rows,
    exists s remaining,
      rev (encode_source_program (row :: rows)) = s :: remaining.
Proof.
  intros row rows.
  destruct (rev (encode_source_program (row :: rows)))
    as [|s remaining] eqn:Hrev.
  - exfalso.
    assert (Hempty : encode_source_program (row :: rows) = []).
    {
      rewrite <- (rev_involutive (encode_source_program (row :: rows))).
      now rewrite Hrev.
    }
    unfold encode_source_program in Hempty.
    simpl in Hempty. discriminate.
  - now exists s, remaining.
Qed.

Theorem every_nonempty_program_left_scan :
  forall row rows prefix suffix,
    exists s remaining,
      rev (encode_source_program (row :: rows)) = s :: remaining /\
      run (S (length (s :: remaining)))
        (entry_config 5 (remaining ++ 5 :: prefix) (s :: suffix)) =
      entry_config 1 (5 :: prefix)
        (map entry_rewrite
          (encode_source_program (row :: rows)) ++ suffix).
Proof.
  intros row rows prefix suffix.
  destruct (encoded_nonempty_program_layout row rows)
    as [s [remaining Hlayout]].
  exists s, remaining.
  split.
  - exact Hlayout.
  - eapply encoded_program_left_scan. exact Hlayout.
Qed.

Print Assumptions encoded_program_left_scan.
Print Assumptions every_nonempty_program_left_scan.
