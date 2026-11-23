(** * Halt macro for an arbitrary book description

    [MinskyLeftInfiniteHalt] proves the no-match halt for the description
    [source_rows_to_book rows].  The final encoder augments that
    description with a trailing duplicate sentinel row, so the halt macro
    must be stated for an arbitrary [list book_row] whose first match is
    a halt.  The proof is the same q5 entry scan followed by the wide
    row-list halt. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyMatchMacro MinskyConcreteDispatch MinskyBookLayout
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateWide
  MinskyBookLocateCycle MinskyBookLocateLookup MinskyBookRawBuffer
  MinskyBookEncode MinskyLeftInfinite MinskyLeftInfiniteEncode
  MinskyLeftInfiniteWindow MinskyLeftInfiniteHalt.

(** ** q5 entry to the wide locate state, arbitrary book rows *)

Lemma lic_q5_encode_to_locate_state_wide_book :
  forall (lo : Z) (c : LeftInfiniteConfig)
         (rows_book : list book_row) (tail : list nat),
    rows_book <> [] ->
    (lo < lic_head c)%Z ->
    run (S (length (lic_state c))) (lic_q5_encode lo c rows_book tail) =
    book_locate_state_wide
      (lic_state c ++ [lic_tape c (lic_head c)]) []
      rows_book (rev (raw_buf c) ++ 6 :: rev (raw_ptape c lo)) tail.
Proof.
  intros lo c rows_book tail Hrows Hlt.
  unfold lic_q5_encode, book_q5_raw.
  rewrite (book_q5_steady_to_locate_state_raw_gen (lic_state c)
    (lic_tape c (lic_head c)) (raw_last c lo) (raw_buf c)
    (raw_ptape_prefix c lo) tail rows_book Hrows).
  rewrite (raw_ptape_prefix_last c lo).
  - reflexivity.
  - apply raw_ptape_nonempty. exact Hlt.
Qed.

(** ** No-match halt for arbitrary book rows *)

Theorem lic_q5_encode_none_halt_book_macro :
  forall (lo : Z) (c : LeftInfiniteConfig)
         (rows_book : list book_row) (tail : list nat)
         (steps : list book_failure) (last : book_failure),
    (lo < lic_head c)%Z ->
    rows_book <> [] ->
    book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
      rows_book = book_lookup_halt steps last ->
    run (S (length (lic_state c)) +
         (book_failures_clock [] steps +
          book_halt_clock (map bf_row steps) last))
      (lic_q5_encode lo c rows_book tail) =
    lic_halt_encode lo c steps last tail.
Proof.
  intros lo c rows_book tail steps last Hlt Hne Hbf.
  destruct (book_first_match_halt_sound _ _ _ _ Hbf)
    as [Hrows Hforall].
  rewrite (dispatch_run_add (S (length (lic_state c)))
    (book_failures_clock [] steps +
     book_halt_clock (map bf_row steps) last)).
  rewrite (lic_q5_encode_to_locate_state_wide_book lo c rows_book tail
    Hne Hlt).
  rewrite Hrows.
  change (run (book_failures_clock [] steps +
               book_halt_clock ([] ++ map bf_row steps) last)
            (book_locate_state_wide
               (lic_state c ++ [lic_tape c (lic_head c)]) []
               (map bf_row (steps ++ [last]))
               (rev (raw_buf c) ++ 6 :: rev (raw_ptape c lo)) tail) =
            lic_halt_encode lo c steps last tail).
  rewrite (book_locate_rows_to_halt_wide
    (lic_state c ++ [lic_tape c (lic_head c)]) [] steps last
    (rev (raw_buf c) ++ 6 :: rev (raw_ptape c lo)) tail Hforall).
  unfold lic_halt_encode, lic_halt_encode_from.
  reflexivity.
Qed.

Print Assumptions lic_q5_encode_none_halt_book_macro.
