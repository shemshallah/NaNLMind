(** * A concrete entry macro for the literal 23-state/8-symbol table

    The native encoded-source fixture starts state 5 with its head on the
    first X (symbol 4) of an eight-symbol source record.  Immediately to
    its left are three 0 cells and a Y (symbol 5).  The actual fixed table
    walks left across X and those cells, replaces 0 by blank symbol 2,
    and returns right from Y in state 1.

    These theorems are about MinskyTable.step, *not* source_step.  They
    certify a genuine table-executed macro for arbitrary source records
    and arbitrary surrounding tape, plus an unbounded left-scan lemma.
    They do not yet prove the subsequent source-instruction dispatch,
    write, movement, or halt simulation, hence not universality.
*)

From Coq Require Import List Arith ZArith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding.

Definition entry_config (q : nat) (left right : list nat) : Config :=
  {| c_state := q;
     c_tape := {| t_left := left; t_right := right |};
     c_halted := false |}.

Definition entry_scan_symbol (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 4.

Definition entry_rewrite (s : nat) : nat :=
  match s with
  | 0 => 2
  | 1 => 3
  | _ => s
  end.

(** These are literal table entries, with no symbolic source interpreter
    substituted for the real transition relation. *)
Lemma entry_scan_one :
  forall s next left right,
    entry_scan_symbol s ->
    step (entry_config 5 (next :: left) (s :: right)) =
    entry_config 5 left (next :: entry_rewrite s :: right).
Proof.
  intros s next left right H.
  destruct H as [-> | [-> | ->]]; reflexivity.
Qed.

Lemma entry_cross_delimiter :
  forall left right,
    step (entry_config 5 left (5 :: right)) =
    entry_config 1 (5 :: left) right.
Proof. reflexivity. Qed.

Lemma entry_run_successor :
  forall fuel q left right,
    run (S fuel) (entry_config q left right) =
    run fuel (step (entry_config q left right)).
Proof. reflexivity. Qed.

(** [symbols] is the sequence scanned right-to-left: its head is under
    the machine head, and its tail lies in the reversed left zipper.
    Every scanned cell is rewritten before the delimiter transition;
    the untouched outer prefix and suffix are universally quantified. *)
Theorem entry_scan_unbounded :
  forall remaining s prefix suffix,
    Forall entry_scan_symbol (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 5 (remaining ++ 5 :: prefix) (s :: suffix)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (rev (s :: remaining)) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix Hscan.
  - inversion Hscan as [|? ? Hs _]; subst.
    rewrite entry_run_successor.
    rewrite (entry_scan_one s 5 prefix suffix Hs).
    rewrite entry_run_successor.
    rewrite entry_cross_delimiter.
    reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    rewrite entry_run_successor.
    rewrite (entry_scan_one s next (rest ++ 5 :: prefix) suffix Hs).
    rewrite (IH next prefix (entry_rewrite s :: suffix) Hrest).
    simpl [rev].
    rewrite map_app.
    simpl [map].
    now rewrite app_assoc.
Qed.

(** The actual first five table transitions on the native source format.
    No restriction is placed on the seven instruction bits, later rows,
    or any cells beyond the immediate delimiter and three-cell buffer. *)
Theorem encoded_source_entry_five_steps :
  forall (row : BinarySourceRow) prefix suffix,
    run 5
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_source_row row ++ suffix)) =
    entry_config 1 (5 :: prefix)
      ([2; 2; 2] ++ encode_source_row row ++ suffix).
Proof.
  intros [a b c d e f g] prefix suffix.
  reflexivity.
Qed.

Theorem encoded_program_entry_five_steps :
  forall (row : BinarySourceRow) rows prefix suffix,
    run 5
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_source_program (row :: rows) ++ suffix)) =
    entry_config 1 (5 :: prefix)
      ([2; 2; 2] ++ encode_source_program (row :: rows) ++ suffix).
Proof.
  intros [a b c d e f g] rows prefix suffix.
  reflexivity.
Qed.

(** Three more real table steps convert the leading blank to 0 and scan
    the remaining two blanks.  State 0 then faces the X record marker,
    with the original source record and the outer tape still intact. *)
Theorem encoded_program_dispatch_eight_steps :
  forall (row : BinarySourceRow) rows prefix suffix,
    run 8
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_source_program (row :: rows) ++ suffix)) =
    entry_config 0 ([2; 2; 0; 5] ++ prefix)
      (encode_source_program (row :: rows) ++ suffix).
Proof.
  intros [a b c d e f g] rows prefix suffix.
  reflexivity.
Qed.

(** The first state bit branches into two *different* fixed-table
    continuations. The left branch overwrites 0 with 2 and returns to X
    in state 2; the right branch overwrites 1 with 3 and advances in
    state 3. This is control-flow evidence, not a whole-instruction proof. *)
Lemma encoded_state_high_bit_branch :
  forall high prefix tail,
    step (entry_config 0 (4 :: prefix) (source_bit high :: tail)) =
    if high then entry_config 3 (3 :: 4 :: prefix) tail
    else entry_config 2 prefix (4 :: 2 :: tail).
Proof. intros []; reflexivity. Qed.

Definition source_row_tail (row : BinarySourceRow) : list nat :=
  [source_bit (sr_state_lo row); source_bit (sr_read row);
   source_bit (sr_next_hi row); source_bit (sr_next_lo row);
   source_bit (sr_write row); source_bit (sr_right row)].

(** Ten consecutive native-table transitions from the executable entry
    configuration reach the exact high-bit dispatch branch of every
    representable source row, with no assumptions on later records. *)
Theorem encoded_program_first_decision_ten_steps :
  forall (row : BinarySourceRow) rows prefix suffix,
    run 10
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_source_program (row :: rows) ++ suffix)) =
    if sr_state_hi row then
      entry_config 3 (3 :: 4 :: 2 :: 2 :: 0 :: 5 :: prefix)
        (source_row_tail row ++ encode_source_program rows ++ suffix)
    else
      entry_config 2 (2 :: 2 :: 0 :: 5 :: prefix)
        (4 :: 2 :: source_row_tail row ++
         encode_source_program rows ++ suffix).
Proof.
  intros [a b c d e f g] rows prefix suffix.
  destruct a; reflexivity.
Qed.

Print Assumptions entry_scan_unbounded.
Print Assumptions encoded_program_entry_five_steps.
Print Assumptions encoded_program_first_decision_ten_steps.
