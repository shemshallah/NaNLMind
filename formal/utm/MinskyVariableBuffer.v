(** * Positive-width buffer macros for the frozen Minsky 23x8 table

    The executable source fixture fixes the buffer immediately before the
    X instruction marker to three zero cells.  This file removes that
    arbitrary width bound: for every POSITIVE number n of such cells,
    the literal native transition table dispatches the first source-state
    bit after exactly 2*n+4 steps.  Both branches and their surrounding
    tape are specified, and the low branch's return to Y is also proved.

    A zero-cell buffer follows a different native path and is deliberately
    excluded.  These are concrete table macros, not a full simulation of
    encoded instructions or a proof of universality.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteEntry MinskyConcreteDispatch.

Lemma variable_buffer_repeat_snoc :
  forall (symbol n : nat),
    repeat symbol n ++ [symbol] = repeat symbol (S n).
Proof.
  intros symbol n; induction n as [|n IH]; simpl.
  - reflexivity.
  - now rewrite IH.
Qed.

Lemma variable_buffer_rev_repeat :
  forall (symbol n : nat),
    rev (repeat symbol n) = repeat symbol n.
Proof.
  intros symbol n; induction n as [|n IH]; simpl.
  - reflexivity.
  - now rewrite IH, variable_buffer_repeat_snoc.
Qed.

Lemma variable_buffer_rewrite_zeros :
  forall n, map entry_rewrite (repeat 0 n) = repeat 2 n.
Proof.
  induction n as [|n IH]; simpl.
  - reflexivity.
  - now rewrite IH.
Qed.

Lemma variable_buffer_entry_shape :
  forall n,
    map entry_rewrite (rev (4 :: repeat 0 n)) = repeat 2 n ++ [4].
Proof.
  intro n.
  simpl [rev].
  rewrite variable_buffer_rev_repeat.
  rewrite map_app.
  rewrite variable_buffer_rewrite_zeros.
  reflexivity.
Qed.

Lemma variable_buffer_entry_scannable :
  forall n, Forall entry_scan_symbol (4 :: repeat 0 n).
Proof.
  intro n; constructor.
  - unfold entry_scan_symbol; auto.
  - induction n as [|n IH]; simpl.
    + constructor.
    + constructor; [unfold entry_scan_symbol; auto | exact IH].
Qed.

(** State 0 traverses an arbitrary number of blank-2 cells to the right,
    without modifying them.  Its zipper left field is stored reversed. *)
Lemma variable_buffer_state_zero_scan :
  forall n left suffix,
    run n (entry_config 0 left (repeat 2 n ++ suffix)) =
    entry_config 0 (repeat 2 n ++ left) suffix.
Proof.
  induction n as [|n IH]; intros left suffix.
  - reflexivity.
  - rewrite entry_run_successor.
    change (step (entry_config 0 left
      (repeat 2 (S n) ++ suffix))) with
      (entry_config 0 (2 :: left) (repeat 2 n ++ suffix)).
    rewrite (IH (2 :: left) suffix).
    replace (repeat 2 n ++ (2 :: left))
      with (repeat 2 (S n) ++ left).
    + reflexivity.
    + change (repeat 2 (S n) ++ left =
        repeat 2 n ++ ([2] ++ left)).
      rewrite <- app_assoc.
      now rewrite variable_buffer_repeat_snoc.
Qed.

(** State 1 turns the first blank into 0, then state 0 crosses the
    remaining blanks.  At the end the following source marker is intact. *)
Lemma variable_buffer_state_one_scan :
  forall n prefix suffix,
    run (S n)
      (entry_config 1 (5 :: prefix) (repeat 2 (S n) ++ suffix)) =
    entry_config 0 (repeat 2 n ++ 0 :: 5 :: prefix) suffix.
Proof.
  intros n prefix suffix.
  rewrite entry_run_successor.
  change (step (entry_config 1 (5 :: prefix)
    (repeat 2 (S n) ++ suffix))) with
    (entry_config 0 (0 :: 5 :: prefix) (repeat 2 n ++ suffix)).
  apply variable_buffer_state_zero_scan.
Qed.

Lemma variable_buffer_marker_bit :
  forall high left tail,
    run 2 (entry_config 0 left (4 :: source_bit high :: tail)) =
    if high then entry_config 3 (3 :: 4 :: left) tail
    else entry_config 2 left (4 :: 2 :: tail).
Proof.
  intros [|] left tail; reflexivity.
Qed.

Lemma variable_buffer_state_one_dispatch :
  forall n high prefix tail,
    run (S n + 2)
      (entry_config 1 (5 :: prefix)
        (repeat 2 (S n) ++ 4 :: source_bit high :: tail)) =
    if high then
      entry_config 3 (3 :: 4 :: repeat 2 n ++ 0 :: 5 :: prefix) tail
    else
      entry_config 2 (repeat 2 n ++ 0 :: 5 :: prefix)
        (4 :: 2 :: tail).
Proof.
  intros n high prefix tail.
  rewrite (dispatch_run_add (S n) 2
    (entry_config 1 (5 :: prefix)
      (repeat 2 (S n) ++ 4 :: source_bit high :: tail))).
  rewrite variable_buffer_state_one_scan.
  apply variable_buffer_marker_bit.
Qed.

(** n = S k > 0 is necessary: n = 0 takes a different native path.
    The formula is exact, rather than merely an existential fuel bound. *)
Theorem positive_buffer_first_bit_at_2n_plus_4 :
  forall k high prefix tail,
    run (2 * S k + 4)
      (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
        (4 :: source_bit high :: tail)) =
    if high then
      entry_config 3 (3 :: 4 :: repeat 2 k ++ 0 :: 5 :: prefix) tail
    else
      entry_config 2 (repeat 2 k ++ 0 :: 5 :: prefix)
        (4 :: 2 :: tail).
Proof.
  intros k high prefix tail.
  replace (2 * S k + 4) with
    (S (length (4 :: repeat 0 (S k))) + (S k + 2))
    by (rewrite repeat_length; simpl; lia).
  rewrite (dispatch_run_add
    (S (length (4 :: repeat 0 (S k)))) (S k + 2)
    (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
      (4 :: source_bit high :: tail))).
  rewrite (entry_scan_unbounded (repeat 0 (S k)) 4 prefix
    (source_bit high :: tail) (variable_buffer_entry_scannable (S k))).
  rewrite variable_buffer_entry_shape.
  rewrite app_assoc.
  apply variable_buffer_state_one_dispatch.
Qed.

Lemma variable_buffer_left_suffix_scannable :
  forall n, Forall dispatch_left_symbol (4 :: repeat 2 n ++ [0]).
Proof.
  intro n; constructor.
  - unfold dispatch_left_symbol; auto 8.
  - induction n as [|n IH]; simpl.
    + constructor; [unfold dispatch_left_symbol; auto 8 | constructor].
    + constructor; [unfold dispatch_left_symbol; auto 8 | exact IH].
Qed.

Lemma variable_buffer_left_reverse :
  forall n, rev (4 :: repeat 2 n ++ [0]) = 0 :: repeat 2 n ++ [4].
Proof.
  intro n.
  simpl [rev].
  rewrite rev_app_distr.
  simpl [rev app].
  rewrite variable_buffer_rev_repeat.
  reflexivity.
Qed.

(** With the low state-bit, the native state-2 backward scan returns to
    delimiter Y after another n+2 steps; the entire row tail is untouched. *)
Theorem positive_buffer_low_returns_at_3n_plus_6 :
  forall k prefix tail,
    run (3 * S k + 6)
      (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
        (4 :: 0 :: tail)) =
    entry_config 1 (5 :: prefix)
      (0 :: repeat 2 k ++ 4 :: 2 :: tail).
Proof.
  intros k prefix tail.
  replace (3 * S k + 6) with
    ((2 * S k + 4) + (S k + 2)) by lia.
  rewrite (dispatch_run_add (2 * S k + 4) (S k + 2)
    (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
      (4 :: 0 :: tail))).
  rewrite (positive_buffer_first_bit_at_2n_plus_4 k false prefix tail).
  replace (S k + 2) with
    (S (length (4 :: repeat 2 k ++ [0])))
    by (rewrite app_length, repeat_length; simpl; lia).
  replace (repeat 2 k ++ 0 :: 5 :: prefix)
    with ((repeat 2 k ++ [0]) ++ 5 :: prefix).
  2:{ rewrite app_assoc. reflexivity. }
  rewrite (dispatch_left_to_delimiter (repeat 2 k ++ [0]) 4 prefix
    (2 :: tail) (variable_buffer_left_suffix_scannable k)).
  rewrite variable_buffer_left_reverse.
  rewrite app_assoc.
  reflexivity.
Qed.

(** Positive-buffer high branch remains a rightward table scan across
    arbitrarily many instruction-tail bits, stopping on the next X or Y. *)
Theorem positive_buffer_high_reaches_next_marker :
  forall k bits prefix suffix,
    run (2 * S k + 4 + (length bits + 1))
      (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
        (4 :: 1 :: map source_bit bits ++ 4 :: suffix)) =
    step (entry_config 3
      (rev (map source_bit bits) ++
        3 :: 4 :: repeat 2 k ++ 0 :: 5 :: prefix)
      (4 :: suffix)).
Proof.
  intros k bits prefix suffix.
  rewrite (dispatch_run_add (2 * S k + 4) (length bits + 1)
    (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
      (4 :: 1 :: map source_bit bits ++ 4 :: suffix))).
  rewrite (positive_buffer_first_bit_at_2n_plus_4 k true prefix
    (map source_bit bits ++ 4 :: suffix)).
  rewrite <- (map_length source_bit bits).
  apply dispatch_right_reaches_marker.
  apply source_bit_list_is_right_scannable.
Qed.

Theorem positive_buffer_high_halts_on_y :
  forall k bits prefix suffix,
    run (2 * S k + 4 + (length bits + 1))
      (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
        (4 :: 1 :: map source_bit bits ++ 5 :: suffix)) =
    dispatch_halt_at_y
      (rev (map source_bit bits) ++
        3 :: 4 :: repeat 2 k ++ 0 :: 5 :: prefix) suffix.
Proof.
  intros k bits prefix suffix.
  rewrite (dispatch_run_add (2 * S k + 4) (length bits + 1)
    (entry_config 5 (repeat 0 (S k) ++ 5 :: prefix)
      (4 :: 1 :: map source_bit bits ++ 5 :: suffix))).
  rewrite (positive_buffer_first_bit_at_2n_plus_4 k true prefix
    (map source_bit bits ++ 5 :: suffix)).
  rewrite <- (map_length source_bit bits).
  apply dispatch_right_halts_at_delimiter.
  apply source_bit_list_is_right_scannable.
Qed.

Print Assumptions positive_buffer_first_bit_at_2n_plus_4.
Print Assumptions positive_buffer_low_returns_at_3n_plus_6.
Print Assumptions positive_buffer_high_reaches_next_marker.
Print Assumptions positive_buffer_high_halts_on_y.
