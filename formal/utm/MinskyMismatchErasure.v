(** * Logical-information preservation across the first failed comparison

    The concrete q1 matching-prefix/mismatch theorem produces marked
    cells.  This file proves that those physical changes do not alter the
    logically decoded comparison description.  It is a representation
    invariant, not an instruction-selection or universality proof.
*)

From Coq Require Import List Bool.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskyMatchMacro MinskyMarkedProgram.

Lemma erase_match_mark :
  forall b, erase_scan_mark (match_mark b) = match_raw b.
Proof. intros []; reflexivity. Qed.

Lemma erase_match_raw :
  forall b, erase_scan_mark (match_raw b) = match_raw b.
Proof. intros []; reflexivity. Qed.

Lemma erase_marked_comparisons :
  forall bits,
    map erase_scan_mark (map match_mark bits) = map match_raw bits.
Proof.
  induction bits as [|b rest IH]; simpl.
  - reflexivity.
  - rewrite erase_match_mark, IH. reflexivity.
Qed.

Lemma erase_raw_comparisons :
  forall bits,
    map erase_scan_mark (map match_raw bits) = map match_raw bits.
Proof.
  induction bits as [|b rest IH]; simpl.
  - reflexivity.
  - rewrite erase_match_raw, IH. reflexivity.
Qed.

(** The two copies of the compared condition bits remain in the same
    logical order even when the physical marks and raw cells exchange
    their roles.  The right-side frame is arbitrary. *)
Lemma first_mismatch_logical_frame :
  forall bits bad pass row_rest suffix,
    map erase_scan_mark
      (pass ++ map match_mark bits ++ [match_mark bad] ++
       map match_raw bits ++ match_raw (negb bad) :: row_rest ++ suffix) =
    map erase_scan_mark
      (pass ++ map match_raw bits ++ match_raw bad ::
       map match_mark bits ++ match_mark (negb bad) ::
       row_rest ++ suffix).
Proof.
  intros bits bad pass row_rest suffix.
  repeat rewrite map_app.
  simpl [map].
  repeat rewrite erase_marked_comparisons.
  repeat rewrite erase_raw_comparisons.
  repeat rewrite erase_match_mark.
  repeat rewrite erase_match_raw.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma reverse_two_marked_cells :
  forall (a b c : list nat) x y,
    rev (rev a ++ x :: rev b ++ y :: rev c) =
    c ++ y :: b ++ x :: a.
Proof.
  intros a b c x y.
  rewrite rev_app_distr.
  simpl [rev].
  rewrite rev_app_distr.
  simpl [rev].
  repeat rewrite rev_involutive.
  repeat rewrite app_assoc.
  simpl [app].
  reflexivity.
Qed.

(** A table-execution consequence: the right-of-Y representation after
    the full successful-prefix/first-mismatch macro erases to exactly
    the same logical symbols as the right-of-Y representation before. *)
Theorem q1_first_mismatch_preserves_erased_right :
  forall bits bad pass row_rest prefix afterX,
    Forall q1_pass pass ->
    Forall dispatch_right_symbol row_rest ->
    let initial_right :=
      pass ++ map match_mark bits ++ [match_mark bad] ++
      map match_raw bits ++
      match_raw (negb bad) :: row_rest ++ 4 :: afterX in
    let fuel :=
      3 * length bits * length bits +
      2 * length bits * length pass +
      7 * length bits + 2 * length pass +
      2 * length row_rest + 6 in
    map erase_scan_mark
      (t_right (c_tape
        (run fuel (entry_config 1 (5 :: prefix) initial_right)))) =
    map erase_scan_mark initial_right.
Proof.
  intros bits bad pass row_rest prefix afterX Hpass Hright.
  cbn zeta.
  rewrite (q1_first_mismatch_exact_clock
    bits bad pass row_rest prefix afterX Hpass Hright).
  cbn [c_tape t_right entry_config].
  rewrite (reverse_two_marked_cells row_rest
    (map match_mark bits) (pass ++ map match_raw bits)
    (match_mark (negb bad)) (match_raw bad)).
  rewrite map_app.
  rewrite erase_cleanup_preserves_logical_tape.
  rewrite <- map_app.
  symmetry.
  apply first_mismatch_logical_frame.
Qed.

Print Assumptions first_mismatch_logical_frame.
Print Assumptions q1_first_mismatch_preserves_erased_right.
