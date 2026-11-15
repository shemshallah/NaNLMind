(** * A representation invariant for the concrete description scan

    The fixed 23x8 Minsky machine marks source bits while scanning left:
    0 becomes 2 and 1 becomes 3, while the row separator X=4 survives.
    Merely comparing the marked physical tape to the original byte stream
    therefore fails.  This file defines the exact logical erasure of those
    scan marks and proves that the COMPLETE arbitrary-width source program
    remains decodable after the literal table's leftward scan.

    The result relates actual native table steps to a logical program
    observable. It does NOT yet relate the native M marker, source head,
    write/move effects, or successive source instructions.  In particular
    it is not a universality theorem.
*)

From Coq Require Import List Arith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyWideSource MinskyConcreteEntry MinskyConcreteProgramScan
  MinskyWideConcreteDispatch.

(** A marked 2/3 is the same logical binary value as its unmarked 0/1.
    Every other symbol, including X=4 and Y=5, remains unchanged. *)
Definition erase_scan_mark (s : nat) : nat :=
  match s with
  | 2 => 0
  | 3 => 1
  | _ => s
  end.

Lemma erase_scan_mark_rewrite :
  forall s, entry_scan_symbol s ->
    erase_scan_mark (entry_rewrite s) = s.
Proof.
  intros s [-> | [-> | ->]]; reflexivity.
Qed.

Lemma erase_scan_marks_rewrite :
  forall symbols,
    Forall entry_scan_symbol symbols ->
    map erase_scan_mark (map entry_rewrite symbols) = symbols.
Proof.
  intros symbols Hscan.
  induction Hscan as [|s symbols Hs Hsymbols IH]; simpl.
  - reflexivity.
  - rewrite (erase_scan_mark_rewrite s Hs), IH. reflexivity.
Qed.

Theorem wide_program_marks_preserve_description :
  forall rows,
    map erase_scan_mark (map entry_rewrite (encode_wide_program rows)) =
    encode_wide_program rows.
Proof.
  intro rows.
  apply erase_scan_marks_rewrite.
  apply wide_program_scannable.
Qed.

Lemma marked_firstn_exact :
  forall (symbols suffix : list nat),
    firstn (length symbols) (symbols ++ suffix) = symbols.
Proof.
  induction symbols as [|s symbols IH]; intro suffix; simpl.
  - reflexivity.
  - now rewrite IH.
Qed.

Lemma marked_skipn_exact :
  forall (symbols suffix : list nat),
    skipn (length symbols) (symbols ++ suffix) = suffix.
Proof.
  induction symbols as [|s symbols IH]; intro suffix; simpl.
  - reflexivity.
  - exact IH.
Qed.

(** Exact-frame property: even when the tape suffix contains marked or
    otherwise arbitrary symbols, restoring the DESCRIPTION prefix alone
    recovers every original source row.  The suffix is not normalized. *)
Theorem marked_description_roundtrip :
  forall p rows suffix,
    Forall (wide_row_wellformed p) rows ->
    decode_wide_prefix p (length rows)
      (map erase_scan_mark
        (firstn (length (encode_wide_program rows))
          (map entry_rewrite (encode_wide_program rows) ++ suffix))) =
    Some (rows, []) /\
    skipn (length (encode_wide_program rows))
      (map entry_rewrite (encode_wide_program rows) ++ suffix) = suffix.
Proof.
  intros p rows suffix Hwf.
  split.
  - rewrite <- (map_length entry_rewrite (encode_wide_program rows)).
    rewrite marked_firstn_exact.
    rewrite wide_program_marks_preserve_description.
    pose proof (wide_program_roundtrip p rows [] Hwf) as Hdecode.
    now rewrite app_nil_r in Hdecode.
  - rewrite <- (map_length entry_rewrite (encode_wide_program rows)).
    apply marked_skipn_exact.
Qed.

(** The result of ACTUAL execution from a correctly oriented zipper
    decodes to the same arbitrary-width instruction list. The exact
    number of native steps is the scanned byte count plus one for Y. *)
Theorem concrete_left_scan_preserves_wide_program :
  forall p rows s remaining prefix suffix,
    Forall (wide_row_wellformed p) rows ->
    rev (encode_wide_program rows) = s :: remaining ->
    let result := run (S (length (s :: remaining)))
      (entry_config 5 (remaining ++ 5 :: prefix) (s :: suffix)) in
    c_state result = 1 /\
    t_left (c_tape result) = 5 :: prefix /\
    decode_wide_prefix p (length rows)
      (map erase_scan_mark
        (firstn (length (encode_wide_program rows))
          (t_right (c_tape result)))) = Some (rows, []) /\
    skipn (length (encode_wide_program rows))
      (t_right (c_tape result)) = suffix /\
    c_halted result = false.
Proof.
  intros p rows s remaining prefix suffix Hwf Hlayout.
  cbn zeta.
  rewrite (wide_program_left_scan rows s remaining prefix suffix Hlayout).
  cbn [c_state c_tape t_left t_right c_halted].
  pose proof (marked_description_roundtrip p rows suffix Hwf)
    as [Hdecoded Hsuffix].
  repeat split; try reflexivity; assumption.
Qed.

Print Assumptions wide_program_marks_preserve_description.
Print Assumptions marked_description_roundtrip.
Print Assumptions concrete_left_scan_preserves_wide_program.
