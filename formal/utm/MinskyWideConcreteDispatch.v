(** * Concrete table macros for variable-width source records

    These results connect the arbitrary-width source encoding in
    MinskyWideSource to literal executions of the unchanged 23x8 table.
    In particular they do not use the abstract wide_source_step as a
    substitute for MinskyTable.run.

    The scans and first-state-bit branches hold for EVERY finite width.
    A complete native simulation of an instruction (all state bits,
    read, write, direction, and return to a canonical entry layout)
    remains an open proof obligation.  Consequently no unconditional
    universality claim is made here.
*)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyWideSource MinskyConcreteEntry MinskyConcreteProgramScan
  MinskyConcreteDispatch.

(** The portion of a row following its first current-state bit. *)
Definition wide_row_tail_bits (row : WideSourceRow)
    (remaining_state : list bool) : list bool :=
  remaining_state ++ [wr_read row] ++ wr_next row ++
  [wr_write row; wr_right row].

Lemma wide_row_first_bit_layout :
  forall row high remaining,
    wr_current row = high :: remaining ->
    encode_wide_row row =
      4 :: source_bit high ::
      map source_bit (wide_row_tail_bits row remaining).
Proof.
  intros [current scanned next written direction] high remaining Hcurrent.
  simpl in Hcurrent; subst current.
  unfold encode_wide_row, wide_row_tail_bits; simpl.
  match goal with |- ?G => idtac "WIDE_LAYOUT:" G end.
  repeat rewrite map_app.
  simpl.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma wide_row_tail_width :
  forall p row high remaining,
    wide_row_wellformed p row ->
    wr_current row = high :: remaining ->
    length (wide_row_tail_bits row remaining) = 2 * p + 2.
Proof.
  intros p [current scanned next written direction] high remaining
    [Hcurrent Hnext] Hfirst.
  simpl in Hcurrent, Hnext, Hfirst.
  subst current.
  simpl in Hcurrent.
  unfold wide_row_tail_bits; simpl.
  repeat rewrite app_length; simpl.
  lia.
Qed.

(** Ten transitions consume the X marker and first current-state bit.
    The remaining state bits, read bit, next-state bits, write bit, and
    movement bit remain intact.  The width is not fixed at two. *)
Theorem wide_first_bit_ten_steps :
  forall row high remaining prefix suffix,
    wr_current row = high :: remaining ->
    run 10
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_wide_row row ++ suffix)) =
    if high then
      entry_config 3 ([3; 4; 2; 2; 0; 5] ++ prefix)
        (map source_bit (wide_row_tail_bits row remaining) ++ suffix)
    else
      entry_config 2 ([2; 2; 0; 5] ++ prefix)
        (4 :: 2 :: map source_bit
          (wide_row_tail_bits row remaining) ++ suffix).
Proof.
  intros row high remaining prefix suffix Hfirst.
  rewrite (wide_row_first_bit_layout row high remaining Hfirst).
  apply encoded_first_bit_any_width_ten_steps.
Qed.

(** A low first state bit returns to Y after exactly 15 concrete
    transitions, independent of the number of following source bits. *)
Theorem wide_low_first_bit_returns_at_15 :
  forall row remaining prefix suffix,
    wr_current row = false :: remaining ->
    run 15
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_wide_row row ++ suffix)) =
    entry_config 1 (5 :: prefix)
      ([0; 2; 2; 4; 2] ++
       map source_bit (wide_row_tail_bits row remaining) ++ suffix).
Proof.
  intros row remaining prefix suffix Hfirst.
  rewrite (wide_row_first_bit_layout row false remaining Hfirst).
  apply encoded_any_width_low_branch_returns_at_step_15.
Qed.

(** A high bit follows the rest of the source record rightwards, then
    encounters the NEXT X record marker.  Every step is an actual call
    to the frozen table.  The next X is not consumed by the scan itself. *)
Theorem wide_high_first_bit_reaches_next_marker :
  forall row remaining prefix suffix,
    wr_current row = true :: remaining ->
    run (10 + (length (wide_row_tail_bits row remaining) + 1))
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_wide_row row ++ 4 :: suffix)) =
    step (entry_config 3
      (rev (map source_bit (wide_row_tail_bits row remaining)) ++
       [3; 4; 2; 2; 0; 5] ++ prefix)
      (4 :: suffix)).
Proof.
  intros row remaining prefix suffix Hfirst.
  rewrite (wide_row_first_bit_layout row true remaining Hfirst).
  apply encoded_any_width_high_branch_next_marker.
Qed.

(** When the next separator is Y instead of X, that same rightward
    concrete scan reaches the table's halting transition. *)
Theorem wide_high_first_bit_halts_on_y :
  forall row remaining prefix suffix,
    wr_current row = true :: remaining ->
    run (10 + (length (wide_row_tail_bits row remaining) + 1))
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_wide_row row ++ 5 :: suffix)) =
    dispatch_halt_at_y
      (rev (map source_bit (wide_row_tail_bits row remaining)) ++
       [3; 4; 2; 2; 0; 5] ++ prefix) suffix.
Proof.
  intros row remaining prefix suffix Hfirst.
  rewrite (wide_row_first_bit_layout row true remaining Hfirst).
  apply encoded_any_width_high_branch_halts_on_y.
Qed.

(** Exact macro clock for a well-formed p-bit record: 2*p+13 native
    steps from entry to the next X/Y when its first state bit is high.
    In particular p=9 gives 31 concrete transitions. *)
Corollary wide_high_next_marker_cost :
  forall p row remaining prefix suffix,
    wide_row_wellformed p row ->
    wr_current row = true :: remaining ->
    run (2 * p + 13)
      (entry_config 5 ([0; 0; 0; 5] ++ prefix)
        (encode_wide_row row ++ 4 :: suffix)) =
    step (entry_config 3
      (rev (map source_bit (wide_row_tail_bits row remaining)) ++
       [3; 4; 2; 2; 0; 5] ++ prefix)
      (4 :: suffix)).
Proof.
  intros p row remaining prefix suffix Hwf Hfirst.
  replace (2 * p + 13)
    with (10 + (length (wide_row_tail_bits row remaining) + 1)).
  2:{ rewrite (wide_row_tail_width p row true remaining Hwf Hfirst).
      lia. }
  apply wide_high_first_bit_reaches_next_marker.
  exact Hfirst.
Qed.

(** Concrete p=9 witness: 22-symbol instruction, 31 native steps to
    the following X marker.  The other state bits remain unconstrained
    in the general theorem above. *)
Definition wide_nine_bit_high_example : WideSourceRow :=
  {| wr_current := true :: repeat false 8;
     wr_read := true;
     wr_next := repeat false 8 ++ [true];
     wr_write := true;
     wr_right := true |}.

Example wide_nine_bit_high_macro :
  run 31
    (entry_config 5 [0; 0; 0; 5]
      (encode_wide_row wide_nine_bit_high_example ++ [4; 5])) =
  step (entry_config 3
    (rev (map source_bit
      (wide_row_tail_bits wide_nine_bit_high_example (repeat false 8))) ++
     [3; 4; 2; 2; 0; 5])
    [4; 5]).
Proof.
  change 31 with (2 * 9 + 13).
  change [0; 0; 0; 5] with ([0; 0; 0; 5] ++ []).
  change [4; 5] with (4 :: [5]).
  change ([3; 4; 2; 2; 0; 5]) with
    ([3; 4; 2; 2; 0; 5] ++ []).
  apply (wide_high_next_marker_cost 9 wide_nine_bit_high_example
    (repeat false 8) [] [5]); reflexivity.
Qed.

(** An entire program is scannable, rather than just a bounded fixture.
    This is a leftward table execution, not a source-instruction step. *)
Lemma wide_bits_scannable :
  forall bits, Forall entry_scan_symbol (map source_bit bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor; [apply source_bit_is_scan_symbol | exact IH].
Qed.

Lemma wide_row_scannable :
  forall row, Forall entry_scan_symbol (encode_wide_row row).
Proof.
  intros [current scanned next written direction].
  unfold encode_wide_row; simpl.
  constructor; [apply source_marker_is_scan_symbol |].
  repeat rewrite app_assoc.
  apply scan_symbols_append.
  - apply wide_bits_scannable.
  - constructor; [apply source_bit_is_scan_symbol |].
    apply scan_symbols_append.
    + apply wide_bits_scannable.
    + constructor; [apply source_bit_is_scan_symbol |].
      constructor; [apply source_bit_is_scan_symbol | constructor].
Qed.

Lemma wide_program_scannable :
  forall rows, Forall entry_scan_symbol (encode_wide_program rows).
Proof.
  induction rows as [|row rows IH]; simpl.
  - constructor.
  - apply scan_symbols_append.
    + apply wide_row_scannable.
    + exact IH.
Qed.

Theorem wide_program_left_scan :
  forall rows s remaining prefix suffix,
    rev (encode_wide_program rows) = s :: remaining ->
    run (S (length (s :: remaining)))
      (entry_config 5 (remaining ++ 5 :: prefix) (s :: suffix)) =
    entry_config 1 (5 :: prefix)
      (map entry_rewrite (encode_wide_program rows) ++ suffix).
Proof.
  intros rows s remaining prefix suffix Hlayout.
  assert (Hscan : Forall entry_scan_symbol (s :: remaining)).
  { rewrite <- Hlayout.
    apply scannable_reverse, wide_program_scannable. }
  rewrite <- (rev_involutive (encode_wide_program rows)).
  rewrite Hlayout.
  apply entry_scan_unbounded.
  exact Hscan.
Qed.

Print Assumptions wide_first_bit_ten_steps.
Print Assumptions wide_high_next_marker_cost.
Print Assumptions wide_nine_bit_high_macro.
Print Assumptions wide_program_left_scan.
