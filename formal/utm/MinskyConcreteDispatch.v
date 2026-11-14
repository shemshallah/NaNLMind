(** * Unbounded concrete dispatch and two source-record branches

    All reductions here execute the frozen 23-state, eight-symbol table.
    The state-2 return and state-3 forward scans work for arbitrarily
    many cells; neither uses a substituted source interpreter.

    This completes both continuations of the first encoded state-bit
    decision.  It does not yet certify the remaining bits, write/move,
    or source-run/halting equivalence, and is not a universality proof.
*)

From Coq Require Import List Arith Bool ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry.

(** Exact splitting of a concrete run, including runs that halt early. *)
Lemma dispatch_halted_run :
  forall fuel c, c_halted c = true -> run fuel c = c.
Proof.
  intros [|fuel] c Hhalt; simpl.
  - reflexivity.
  - now rewrite Hhalt.
Qed.

Lemma dispatch_run_add :
  forall n m c, run (n + m) c = run m (run n c).
Proof.
  induction n as [|n IH]; intros m c; simpl.
  - reflexivity.
  - destruct (c_halted c) eqn:Hhalt; simpl.
    + now rewrite (dispatch_halted_run m c Hhalt).
    + apply IH.
Qed.

(** State 2 moves left, preserving every in-alphabet symbol other than Y.
    Reading Y moves right and enters state 1. *)
Definition dispatch_left_symbol (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 4 \/ s = 6 \/ s = 7.

Lemma dispatch_left_one :
  forall s next left right,
    dispatch_left_symbol s ->
    step (entry_config 2 (next :: left) (s :: right)) =
    entry_config 2 left (next :: s :: right).
Proof.
  intros s next left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
    reflexivity.
Qed.

Lemma dispatch_left_delimiter :
  forall left right,
    step (entry_config 2 left (5 :: right)) =
    entry_config 1 (5 :: left) right.
Proof. reflexivity. Qed.

Theorem dispatch_left_to_delimiter :
  forall remaining s prefix suffix,
    Forall dispatch_left_symbol (s :: remaining) ->
    run (S (length (s :: remaining)))
      (entry_config 2 (remaining ++ 5 :: prefix) (s :: suffix)) =
    entry_config 1 (5 :: prefix) (rev (s :: remaining) ++ suffix).
Proof.
  intros remaining.
  induction remaining as [|next rest IH]; intros s prefix suffix Hscan.
  - inversion Hscan as [|? ? Hs _]; subst.
    destruct Hs as [-> | [-> | [-> | [-> | [-> | [-> | ->]]]]]];
      reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (S (length (next :: rest))))
      (entry_config 2 (next :: (rest ++ 5 :: prefix)) (s :: suffix)) =
      entry_config 1 (5 :: prefix) (rev (s :: next :: rest) ++ suffix)).
    rewrite entry_run_successor.
    rewrite (dispatch_left_one s next (rest ++ 5 :: prefix) suffix Hs).
    rewrite (IH next prefix (s :: suffix) Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest ++ [next]) s suffix).
    reflexivity.
Qed.

(** State 3 moves right, preserving ordinary binary and marked symbols.
    On X it moves left to state 5; on Y it halts without moving. *)
Definition dispatch_right_symbol (s : nat) : Prop :=
  s = 0 \/ s = 1 \/ s = 2 \/ s = 3 \/ s = 6 \/ s = 7.

Lemma dispatch_right_one :
  forall s left right,
    dispatch_right_symbol s ->
    step (entry_config 3 left (s :: right)) =
    entry_config 3 (s :: left) right.
Proof.
  intros s left right H.
  destruct H as [-> | [-> | [-> | [-> | [-> | ->]]]]];
    reflexivity.
Qed.

Theorem dispatch_right_preserves_scan :
  forall symbols prefix suffix,
    Forall dispatch_right_symbol symbols ->
    run (length symbols)
      (entry_config 3 prefix (symbols ++ suffix)) =
    entry_config 3 (rev symbols ++ prefix) suffix.
Proof.
  induction symbols as [|s rest IH]; intros prefix suffix Hscan.
  - reflexivity.
  - inversion Hscan as [|? ? Hs Hrest]; subst.
    change (run (S (length rest))
      (entry_config 3 prefix (s :: (rest ++ suffix))) =
      entry_config 3 (rev (s :: rest) ++ prefix) suffix).
    rewrite entry_run_successor.
    rewrite (dispatch_right_one s prefix (rest ++ suffix) Hs).
    rewrite (IH (s :: prefix) suffix Hrest).
    cbn [rev].
    rewrite (append_singleton_assoc (rev rest) s prefix).
    reflexivity.
Qed.

Theorem dispatch_right_reaches_marker :
  forall symbols prefix suffix,
    Forall dispatch_right_symbol symbols ->
    run (length symbols + 1)
      (entry_config 3 prefix (symbols ++ 4 :: suffix)) =
    step (entry_config 3 (rev symbols ++ prefix) (4 :: suffix)).
Proof.
  intros symbols prefix suffix Hscan.
  rewrite dispatch_run_add.
  rewrite (dispatch_right_preserves_scan symbols prefix (4 :: suffix) Hscan).
  reflexivity.
Qed.

Definition dispatch_halt_at_y (left right : list nat) : Config :=
  {| c_state := 0;
     c_tape := {| t_left := left; t_right := 5 :: right |};
     c_halted := true |}.

Theorem dispatch_right_halts_at_delimiter :
  forall symbols prefix suffix,
    Forall dispatch_right_symbol symbols ->
    run (length symbols + 1)
      (entry_config 3 prefix (symbols ++ 5 :: suffix)) =
    dispatch_halt_at_y (rev symbols ++ prefix) suffix.
Proof.
  intros symbols prefix suffix Hscan.
  rewrite dispatch_run_add.
  rewrite (dispatch_right_preserves_scan symbols prefix (5 :: suffix) Hscan).
  reflexivity.
Qed.

Lemma source_bit_is_right_symbol :
  forall b, dispatch_right_symbol (source_bit b).
Proof.
  intros [|]; unfold dispatch_right_symbol, source_bit;
    [right; left | left]; reflexivity.
Qed.

Lemma source_row_tail_is_right_scannable :
  forall row, Forall dispatch_right_symbol (source_row_tail row).
Proof.
  intros [a b c d e f g].
  unfold source_row_tail.
  constructor; [apply source_bit_is_right_symbol |].
  constructor; [apply source_bit_is_right_symbol |].
  constructor; [apply source_bit_is_right_symbol |].
  constructor; [apply source_bit_is_right_symbol |].
  constructor; [apply source_bit_is_right_symbol |].
  constructor; [apply source_bit_is_right_symbol |].
  constructor.
Qed.

(** This generalizes the first-bit dispatch beyond the old p=2 source
    record. The following tail can have any finite number of bits. *)
Theorem encoded_first_bit_any_width_ten_steps :
  forall high tail prefix suffix,
    run 10
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (4 :: source_bit high :: tail ++ suffix)) =
    if high then
      entry_config 3 ([3; 4; 2; 2; 0; 5] ++ prefix)
        (tail ++ suffix)
    else
      entry_config 2 ([2; 2; 0; 5] ++ prefix)
        (4 :: 2 :: tail ++ suffix).
Proof. intros [|] tail prefix suffix; reflexivity. Qed.

Lemma source_bit_list_is_right_scannable :
  forall bits, Forall dispatch_right_symbol (map source_bit bits).
Proof.
  induction bits as [|b bits IH]; simpl.
  - constructor.
  - constructor; [apply source_bit_is_right_symbol | exact IH].
Qed.

(** For arbitrarily wide source records, a high first state bit passes
    every remaining binary bit and returns left on the next X marker.
    The number of native steps is exactly 11 plus the tail-bit length. *)
Theorem encoded_any_width_high_branch_next_marker :
  forall bits prefix suffix,
    run (10 + (length bits + 1))
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (4 :: 1 :: map source_bit bits ++ 4 :: suffix)) =
    step (entry_config 3
      (rev (map source_bit bits) ++ [3; 4; 2; 2; 0; 5] ++ prefix)
      (4 :: suffix)).
Proof.
  intros bits prefix suffix.
  rewrite (dispatch_run_add 10 (length bits + 1)
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (4 :: 1 :: map source_bit bits ++ 4 :: suffix))).
  change (run 10
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (4 :: 1 :: map source_bit bits ++ 4 :: suffix))) with
    (entry_config 3 ([3; 4; 2; 2; 0; 5] ++ prefix)
      (map source_bit bits ++ 4 :: suffix)).
  rewrite <- (map_length source_bit bits).
  apply dispatch_right_reaches_marker.
  apply source_bit_list_is_right_scannable.
Qed.

Theorem encoded_any_width_high_branch_halts_on_y :
  forall bits prefix suffix,
    run (10 + (length bits + 1))
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (4 :: 1 :: map source_bit bits ++ 5 :: suffix)) =
    dispatch_halt_at_y
      (rev (map source_bit bits) ++ [3; 4; 2; 2; 0; 5] ++ prefix)
      suffix.
Proof.
  intros bits prefix suffix.
  rewrite (dispatch_run_add 10 (length bits + 1)
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (4 :: 1 :: map source_bit bits ++ 5 :: suffix))).
  change (run 10
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (4 :: 1 :: map source_bit bits ++ 5 :: suffix))) with
    (entry_config 3 ([3; 4; 2; 2; 0; 5] ++ prefix)
      (map source_bit bits ++ 5 :: suffix)).
  rewrite <- (map_length source_bit bits).
  apply dispatch_right_halts_at_delimiter.
  apply source_bit_list_is_right_scannable.
Qed.

(** The low branch likewise works for a tail of any width or contents:
    state 2 retreats to Y without consuming those remaining bits. *)
Theorem encoded_any_width_low_branch_returns_at_step_15 :
  forall tail prefix suffix,
    run 15
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (4 :: 0 :: tail ++ suffix)) =
    entry_config 1 (5 :: prefix)
      ([0; 2; 2; 4; 2] ++ tail ++ suffix).
Proof.
  intros tail prefix suffix.
  change 15 with (10 + 5).
  rewrite (dispatch_run_add 10 5
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (4 :: 0 :: tail ++ suffix))).
  change (run 10
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (4 :: 0 :: tail ++ suffix))) with
    (entry_config 2 ([2; 2; 0; 5] ++ prefix)
      (4 :: 2 :: tail ++ suffix)).
  apply (dispatch_left_to_delimiter [2; 2; 0] 4 prefix
    (2 :: tail ++ suffix)).
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor.
Qed.

(** In the low-state-bit branch the table returns across the original X
    and three buffer cells to the Y delimiter, preserving the row tail. *)
Theorem encoded_program_low_branch_returns_at_step_15 :
  forall row rows prefix suffix,
    sr_state_hi row = false ->
    run 15
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_source_program (row :: rows) ++ suffix)) =
    entry_config 1 (5 :: prefix)
      ([0; 2; 2; 4; 2] ++ source_row_tail row ++
       encode_source_program rows ++ suffix).
Proof.
  intros row rows prefix suffix Hhi.
  change 15 with (10 + 5).
  rewrite (dispatch_run_add 10 5
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (encode_source_program (row :: rows) ++ suffix))).
  rewrite encoded_program_first_decision_ten_steps.
  rewrite Hhi.
  apply (dispatch_left_to_delimiter [2; 2; 0] 4 prefix
    (2 :: source_row_tail row ++ encode_source_program rows ++ suffix)).
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor; [unfold dispatch_left_symbol; auto 8 |].
  constructor.
Qed.

(** A high first bit crosses the other six encoded bits. When a further
    record begins at X, state 3 turns back into state 5 after 17 steps. *)
Theorem encoded_program_high_branch_reaches_next_row_at_step_17 :
  forall row next rows prefix suffix,
    sr_state_hi row = true ->
    run 17
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_source_program (row :: next :: rows) ++ suffix)) =
    step (entry_config 3
      (rev (source_row_tail row) ++
       [3; 4; 2; 2; 0; 5] ++ prefix)
      (encode_source_program (next :: rows) ++ suffix)).
Proof.
  intros row next rows prefix suffix Hhi.
  change 17 with (10 + 7).
  rewrite (dispatch_run_add 10 7
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (encode_source_program (row :: next :: rows) ++ suffix))).
  rewrite encoded_program_first_decision_ten_steps.
  rewrite Hhi.
  change 7 with (length (source_row_tail row) + 1).
  rewrite (dispatch_run_add (length (source_row_tail row)) 1
    (entry_config 3 ([3; 4; 2; 2; 0; 5] ++ prefix)
      (source_row_tail row ++
        encode_source_program (next :: rows) ++ suffix))).
  rewrite (dispatch_right_preserves_scan
    (source_row_tail row) ([3; 4; 2; 2; 0; 5] ++ prefix)
    (encode_source_program (next :: rows) ++ suffix)
    (source_row_tail_is_right_scannable row)).
  reflexivity.
Qed.

(** With no additional row, the same branch finds Y and stops. This is
    a genuine table-level halt certificate, conditional on the tape layout. *)
Theorem encoded_program_high_branch_halts_at_step_17 :
  forall row prefix suffix,
    sr_state_hi row = true ->
    run 17
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_source_row row ++ 5 :: suffix)) =
    dispatch_halt_at_y
      (rev (source_row_tail row) ++ [3; 4; 2; 2; 0; 5] ++ prefix)
      suffix.
Proof.
  intros row prefix suffix Hhi.
  change 17 with (10 + 7).
  rewrite (dispatch_run_add 10 7
    (entry_config 5 ([0; 0; 0; 5] ++ prefix)
      (encode_source_program [row] ++ 5 :: suffix))).
  rewrite encoded_program_first_decision_ten_steps.
  rewrite Hhi.
  apply dispatch_right_halts_at_delimiter.
  apply source_row_tail_is_right_scannable.
Qed.

Print Assumptions dispatch_left_to_delimiter.
Print Assumptions dispatch_right_preserves_scan.
Print Assumptions encoded_first_bit_any_width_ten_steps.
Print Assumptions encoded_any_width_high_branch_next_marker.
Print Assumptions encoded_any_width_high_branch_halts_on_y.
Print Assumptions encoded_any_width_low_branch_returns_at_step_15.
Print Assumptions encoded_program_low_branch_returns_at_step_15.
Print Assumptions encoded_program_high_branch_reaches_next_row_at_step_17.
Print Assumptions encoded_program_high_branch_halts_at_step_17.
