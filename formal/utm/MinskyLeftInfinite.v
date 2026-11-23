(** * A left-infinite, right-bounded source tape for the book layout

    The project's [WideSourceConfig] (MinskyWideSource.v) uses a two-sided
    tape [Z -> bool] with no boundary.  The literal 23x8 book table does
    not simulate that object.  Minsky's published construction
    *Computation: Finite and Infinite Machines*, Ch. 7, Fig. 7.2-9,
    simulates a **left-infinite** tape: every cell at or to the left of a
    fixed rightmost cell [R] exists, and a move to the right of [R] is the
    blocking/undefined instruction.  This file isolates that source model
    and proves the same conditional halting equivalence as
    MinskyWideMacroSimulation.v.

    The concrete divergence is recorded in UNIVERSALITY_REVIEW_LEDGER.md
    ("November 23 buffer-exhaustion counterexample"): for a p=5 program
    whose head moves right forever, the literal table halts natively
    after 46,176 steps at q3/Y, while the two-sided source run never
    halts.  The new model halts in the same *situation* (the first right
    move at [R]), not after the same number of native steps.

    Nothing below assumes any of the three bridge premises.  In
    particular this is not an unconditional universality proof.

    ** Book-buffer accounting

    Write [h] for the simulated head position and [R] for the rightmost
    cell.  The book layout

      ptape ++ [M] ++ 0^b ++ [Y] ++ condition ++ description ++ [Y]

    puts all cells strictly left of [h] in [ptape], marks cell [h] with
    [M = 6], and uses the raw cells immediately to the right of [M] as
    the remaining right tape.  In the current zero-buffer book frame
    those cells are all zero, and the buffer count satisfies

      b = R - h.

    A right move [h -> h+1] gives [b' = R - (h+1) = b-1], exactly the
    [b -> b-1] of book_q6_to_q5_right / book_steady_q5_locate_to_q5_right.
    A left move [h -> h-1] gives [b' = R - (h-1) = b+1]: it must
    *increase* the buffer count, not decrease it.

    Moreover, a left move writes the source write bit [w] into the old
    head cell [h], which becomes the first cell to the right of the new
    head.  A buffer consisting only of zeros therefore cannot be
    preserved in general.  At the q6 level the new right tape is the raw
    list [w :: 0^b] (length [b+1]), not [0^b] and not [0^(b-1)].  When
    [w = false] one may identify it with [0^(b+1)]; when [w = true] no
    [book_buf] frame represents the result.  MinskyBookLeftCycle.v's
    book_q6_to_q5_left output is physically

      ptape_prefix ++ [6] ++ [source_bit w] ++ [0^b] ++ [5] ++ ...

    so its buffer segment is [source_bit w :: 0^b].  The theorem is
    correct as a literal execution statement, but it does not land in
    the zero-buffer normal form used by the next locate phase.  The
    generalized left-suffix locate (MinskyBookLocateWide.v) is what
    makes the left cycle reusable; a total encoder must either use a
    list-valued buffer or restrict normalization to [w = false] and
    record the count [b+1].  MinskyLeftCycleAudit.v mechanically checks
    a concrete [w = true] instance that cannot be a zero-buffer frame.

    ** Reusable native phases

    For a concrete encoder the following existing theorems are the
    intended reuse points (all are kernel-checked in this tree):

    - entry/locate: [book_q5_steady_to_locate_state_gen]
      (MinskyBookLocateCycle.v), [book_locate_by_computation_from_q5_to_q6]
      and [_to_halt] (MinskyBookLocateLookup.v);
    - right perform: [book_q6_to_q5_right] (MinskyBookCycle.v) and the
      combined [book_steady_q5_locate_to_q5_right]
      (MinskyBookLocateCycle.v);
    - left perform: [book_q6_to_q5_left] (MinskyBookLeftCycle.v) and the
      combined [book_steady_q5_locate_to_q5_left], with the buffer caveat
      above and [book_locate_state_wide] for the nonstandard suffix;
    - halt paths: [book_steady_q5_locate_perform_right_sentinel_halt] and
      [book_steady_q5_locate_perform_left_sentinel_halt]
      (MinskyBookLocateCycle.v).

    The boundary-right halt itself (q19 passes [Y] and the table walks to
    q3/Y) has only the concrete 46,176-step trace; there is no general
    native theorem for it yet.  That is precisely why the third premise
    below remains a hypothesis.

    ** The three premises

    [encode p rows c] must be the native book frame for [c] and
    [macro_cost p rows c] the number of native steps for one source
    instruction (locate + perform, including the boundary case).
    The theorem below assumes exactly:

      1. [c_halted (encode p rows c) = lic_halted c];
      2. [1 <= macro_cost p rows c];
      3. [run (macro_cost p rows c) (encode p rows c)
            = encode p rows (left_infinite_step rows c)].

    These are the direct analogues of the three hypotheses in
    MinskyWideMacroSimulation.v; no additional assumption on [R], the
    buffer, or the encoder is hidden. *)

From Coq Require Import List Arith Bool Lia ZArith FunctionalExtensionality.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch.

(** ** Configurations *)

Record LeftInfiniteConfig := {
  lic_state : list bool;
  lic_head : Z;
  lic_tape : Z -> bool;
  lic_R : Z;                 (* rightmost existing cell *)
  lic_halted : bool
}.

(** The structural invariant of a left-infinite tape: the head is at or
    to the left of [R], and every cell strictly to the right of [R] is
    blank (equivalently, not part of the tape). *)
Definition left_infinite_ok (c : LeftInfiniteConfig) : Prop :=
  (lic_head c <= lic_R c)%Z /\
  (forall z, (lic_R c < z)%Z -> lic_tape c z = false).

(** ** One step

    The step is total.  A lookup failure halts (as in
    [wide_source_step]).  A right move with [head = R] performs the
    write at the current head and then halts instead of moving to
    [R+1]. *)

Definition left_infinite_right_blocked
    (c : LeftInfiniteConfig) (row : WideSourceRow) : bool :=
  andb (wr_right row) (Z.eqb (lic_head c) (lic_R c)).

Definition left_infinite_step
    (rows : list WideSourceRow) (c : LeftInfiniteConfig)
    : LeftInfiniteConfig :=
  if lic_halted c then c else
    match wide_source_lookup rows (lic_state c)
                            (lic_tape c (lic_head c)) with
    | None =>
        {| lic_state := lic_state c;
           lic_head := lic_head c;
           lic_tape := lic_tape c;
           lic_R := lic_R c;
           lic_halted := true |}
    | Some row =>
        if left_infinite_right_blocked c row then
          {| lic_state := lic_state c;
             lic_head := lic_head c;
             lic_tape := source_write_at (lic_tape c) (lic_head c)
                                          (wr_write row);
             lic_R := lic_R c;
             lic_halted := true |}
        else
          {| lic_state := wr_next row;
             lic_head := (lic_head c +
                          (if wr_right row then 1 else -1))%Z;
             lic_tape := source_write_at (lic_tape c) (lic_head c)
                                          (wr_write row);
             lic_R := lic_R c;
             lic_halted := false |}
    end.

Fixpoint left_infinite_run
    (fuel : nat) (rows : list WideSourceRow)
    (c : LeftInfiniteConfig) : LeftInfiniteConfig :=
  match fuel with
  | O => c
  | S n => left_infinite_run n rows (left_infinite_step rows c)
  end.

(** ** Elementary step lemmas *)

Lemma left_infinite_step_halted :
  forall rows c,
    lic_halted c = true ->
    left_infinite_step rows c = c.
Proof.
  intros rows c H.
  unfold left_infinite_step. now rewrite H.
Qed.

Lemma left_infinite_run_halted :
  forall fuel rows c,
    lic_halted c = true ->
    left_infinite_run fuel rows c = c.
Proof.
  induction fuel as [|n IH]; intros rows c H; simpl.
  - reflexivity.
  - rewrite (left_infinite_step_halted rows c H).
    apply IH. exact H.
Qed.

Lemma left_infinite_step_lookup_none :
  forall rows c,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = None ->
    lic_halted (left_infinite_step rows c) = true.
Proof.
  intros rows c Hh Hlookup.
  unfold left_infinite_step. rewrite Hh, Hlookup. reflexivity.
Qed.

Lemma left_infinite_step_right_blocked_halts :
  forall rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    wr_right row = true ->
    lic_head c = lic_R c ->
    lic_halted (left_infinite_step rows c) = true.
Proof.
  intros rows c row Hh Hlookup Hright Hhead.
  unfold left_infinite_step.
  rewrite Hh, Hlookup.
  unfold left_infinite_right_blocked.
  rewrite Hright, Hhead, Z.eqb_refl.
  reflexivity.
Qed.

(** Full projection of the three non-halted/blocked branches.  These are
    the clauses an encoder-side macro proof must match. *)

Lemma left_infinite_step_lookup_none_fields :
  forall rows c,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = None ->
    lic_state (left_infinite_step rows c) = lic_state c /\
    lic_head (left_infinite_step rows c) = lic_head c /\
    lic_tape (left_infinite_step rows c) = lic_tape c /\
    lic_R (left_infinite_step rows c) = lic_R c /\
    lic_halted (left_infinite_step rows c) = true.
Proof.
  intros rows c Hh Hlookup.
  unfold left_infinite_step. rewrite Hh, Hlookup.
  repeat split; reflexivity.
Qed.

Lemma left_infinite_step_blocked_fields :
  forall rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_state (left_infinite_step rows c) = lic_state c /\
    lic_head (left_infinite_step rows c) = lic_head c /\
    lic_tape (left_infinite_step rows c) =
      source_write_at (lic_tape c) (lic_head c) (wr_write row) /\
    lic_R (left_infinite_step rows c) = lic_R c /\
    lic_halted (left_infinite_step rows c) = true.
Proof.
  intros rows c row Hh Hlookup Hb.
  unfold left_infinite_step. rewrite Hh, Hlookup, Hb.
  repeat split; reflexivity.
Qed.

Lemma left_infinite_step_running_fields :
  forall rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = false ->
    lic_state (left_infinite_step rows c) = wr_next row /\
    lic_head (left_infinite_step rows c) =
      (lic_head c + (if wr_right row then 1 else -1))%Z /\
    lic_tape (left_infinite_step rows c) =
      source_write_at (lic_tape c) (lic_head c) (wr_write row) /\
    lic_R (left_infinite_step rows c) = lic_R c /\
    lic_halted (left_infinite_step rows c) = false.
Proof.
  intros rows c row Hh Hlookup Hb.
  unfold left_infinite_step. rewrite Hh, Hlookup, Hb.
  repeat split; reflexivity.
Qed.

(** A write strictly above [R] cannot touch the tape; this is the only
    list/function fact needed for invariant preservation. *)
Lemma source_write_at_above :
  forall (t : Z -> bool) (h z : Z) (bit : bool),
    (h < z)%Z ->
    source_write_at t h bit z = t z.
Proof.
  intros t h z bit Hlt.
  unfold source_write_at.
  destruct (Z.eqb z h) eqn:He.
  - apply Z.eqb_eq in He. lia.
  - reflexivity.
Qed.

Lemma left_infinite_step_ok :
  forall rows c,
    left_infinite_ok c ->
    left_infinite_ok (left_infinite_step rows c).
Proof.
  intros rows c [Hle Hblank].
  unfold left_infinite_step.
  destruct (lic_halted c) eqn:Eh.
  - exact (conj Hle Hblank).
  - destruct (wide_source_lookup rows (lic_state c)
                (lic_tape c (lic_head c))) as [row|] eqn:El.
    + destruct (left_infinite_right_blocked c row) eqn:Eb.
      * split; [exact Hle|].
        intros z Hz.
        change ((lic_R c < z)%Z) in Hz.
        change (source_write_at (lic_tape c) (lic_head c)
                  (wr_write row) z = false).
        rewrite source_write_at_above by lia.
        apply Hblank. lia.
      * split.
        -- change ((lic_head c +
                     (if wr_right row then 1 else -1))%Z <= lic_R c)%Z.
           unfold left_infinite_right_blocked in Eb.
           apply Bool.andb_false_iff in Eb.
           destruct Eb as [Hr | He].
           ++ rewrite Hr. simpl. lia.
           ++ apply Z.eqb_neq in He.
              destruct (wr_right row).
              ** simpl. lia.
              ** simpl. lia.
        -- intros z Hz.
           change ((lic_R c < z)%Z) in Hz.
           change (source_write_at (lic_tape c) (lic_head c)
                     (wr_write row) z = false).
           rewrite source_write_at_above by lia.
           apply Hblank. lia.
    + exact (conj Hle Hblank).
Qed.

Lemma left_infinite_run_ok :
  forall fuel rows c,
    left_infinite_ok c ->
    left_infinite_ok (left_infinite_run fuel rows c).
Proof.
  induction fuel as [|n IH]; intros rows c H; simpl.
  - exact H.
  - apply IH, left_infinite_step_ok, H.
Qed.

(** ** Conditional halting equivalence

    This is the exact left-infinite analogue of
    [conditional_wide_source_native_halting_equivalence].  The three
    premises are explicit section variables, not theorems. *)

Section ConditionalLeftInfiniteNativeSimulation.

Variable encode :
  nat -> list WideSourceRow -> LeftInfiniteConfig -> Config.
Variable macro_cost :
  nat -> list WideSourceRow -> LeftInfiniteConfig -> nat.

Hypothesis lic_encode_reflects_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    c_halted (encode p rows c) = lic_halted c.

Hypothesis lic_macro_cost_positive :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    1 <= macro_cost p rows c.

Hypothesis lic_actual_table_macro_step :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    run (macro_cost p rows c) (encode p rows c) =
    encode p rows (left_infinite_step rows c).

Fixpoint left_macro_clock
    (n p : nat) (rows : list WideSourceRow)
    (c : LeftInfiniteConfig) : nat :=
  match n with
  | 0 => 0
  | S k => macro_cost p rows c +
           left_macro_clock k p rows (left_infinite_step rows c)
  end.

Lemma left_macro_clock_at_least_steps :
  forall n p rows c,
    Forall (wide_row_wellformed p) rows ->
    n <= left_macro_clock n p rows c.
Proof.
  induction n as [|n IH]; intros p rows c Hwf; simpl.
  - lia.
  - pose proof (lic_macro_cost_positive p rows c Hwf).
    specialize (IH p rows (left_infinite_step rows c) Hwf).
    lia.
Qed.

Theorem conditional_left_native_arbitrary_run :
  forall n p rows c,
    Forall (wide_row_wellformed p) rows ->
    run (left_macro_clock n p rows c) (encode p rows c) =
    encode p rows (left_infinite_run n rows c).
Proof.
  induction n as [|n IH]; intros p rows c Hwf; simpl.
  - reflexivity.
  - rewrite dispatch_run_add.
    rewrite (lic_actual_table_macro_step p rows c Hwf).
    apply IH. exact Hwf.
Qed.

Definition left_infinite_eventually_halts
    (rows : list WideSourceRow) (c : LeftInfiniteConfig) : Prop :=
  exists n, lic_halted (left_infinite_run n rows c) = true.

Definition left_native_eventually_halts
    (p : nat) (rows : list WideSourceRow)
    (c : LeftInfiniteConfig) : Prop :=
  exists n, c_halted (run n (encode p rows c)) = true.

Theorem conditional_left_source_halt_implies_native_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    left_infinite_eventually_halts rows c ->
    left_native_eventually_halts p rows c.
Proof.
  intros p rows c Hwf [n Hhalt].
  exists (left_macro_clock n p rows c).
  rewrite (conditional_left_native_arbitrary_run n p rows c Hwf).
  rewrite (lic_encode_reflects_halt p rows _ Hwf).
  exact Hhalt.
Qed.

Theorem conditional_left_native_halt_implies_source_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    left_native_eventually_halts p rows c ->
    left_infinite_eventually_halts rows c.
Proof.
  intros p rows c Hwf [t Hhalt].
  exists t.
  assert (Hclock : t <= left_macro_clock t p rows c).
  { apply left_macro_clock_at_least_steps. exact Hwf. }
  assert (Hnative :
    c_halted (run (left_macro_clock t p rows c)
      (encode p rows c)) = true).
  {
    replace (left_macro_clock t p rows c)
      with (t + (left_macro_clock t p rows c - t)) by lia.
    rewrite dispatch_run_add.
    rewrite (dispatch_halted_run
      (left_macro_clock t p rows c - t)
      (run t (encode p rows c)) Hhalt).
    exact Hhalt.
  }
  rewrite (conditional_left_native_arbitrary_run t p rows c Hwf)
    in Hnative.
  rewrite (lic_encode_reflects_halt p rows _ Hwf) in Hnative.
  exact Hnative.
Qed.

Theorem conditional_left_source_native_halting_equivalence :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    (left_infinite_eventually_halts rows c <->
     left_native_eventually_halts p rows c).
Proof.
  intros p rows c Hwf; split.
  - apply conditional_left_source_halt_implies_native_halt.
    exact Hwf.
  - apply conditional_left_native_halt_implies_source_halt.
    exact Hwf.
Qed.

End ConditionalLeftInfiniteNativeSimulation.

(** The three bridge premises are visible arguments of the elaborated
    theorem; this command does not certify them. *)
Print Assumptions conditional_left_source_native_halting_equivalence.

(** ** Buffer arithmetic and the zero-buffer obstruction *)

(** [b = R - h] is preserved with [b-1] on a right move and [b+1] on a
    left move.  These are the only two arithmetic facts the book
    accounting needs. *)
Lemma book_buffer_right_move_Z :
  forall (R h b : Z),
    b = (R - h)%Z ->
    (b - 1)%Z = (R - (h + 1))%Z.
Proof. lia. Qed.

Lemma book_buffer_left_move_Z :
  forall (R h b : Z),
    b = (R - h)%Z ->
    (b + 1)%Z = (R - (h - 1))%Z.
Proof. lia. Qed.

(** The cells strictly right of the head and at most [R]. *)
Definition cells_right_blank (t : Z -> bool) (h R : Z) : Prop :=
  forall z, (h < z <= R)%Z -> t z = false.

Lemma right_move_preserves_blank :
  forall t h R,
    cells_right_blank t h R ->
    cells_right_blank t (h + 1) R.
Proof.
  intros t h R H z Hz. apply H. lia.
Qed.

(** A left move whose write bit is [true] necessarily destroys the
    all-blank buffer invariant: the old head cell is now immediately to
    the right of the new head.  This is the abstract reason a [0^b]
    buffer cannot encode an arbitrary left perform. *)
Lemma left_move_write_true_breaks_blank :
  forall (t : Z -> bool) (h R : Z),
    (h <= R)%Z ->
    ~ cells_right_blank (source_write_at t h true) (h - 1) R.
Proof.
  intros t h R Hle Hblank.
  specialize (Hblank h).
  assert (Hz : (h - 1 < h <= R)%Z) by lia.
  apply Hblank in Hz.
  unfold source_write_at in Hz.
  rewrite Z.eqb_refl in Hz.
  discriminate.
Qed.

Lemma left_move_write_false_grows_blank :
  forall (t : Z -> bool) (h R : Z),
    cells_right_blank t h R ->
    cells_right_blank (source_write_at t h false) h R.
Proof.
  intros t h R H z Hz.
  destruct (Z.eqb z h) eqn:He.
  - apply Z.eqb_eq in He. lia.
  - rewrite source_write_at_above by (apply Z.eqb_neq in He; lia).
    apply H. lia.
Qed.

(** ** A concrete comparison with the two-sided model

    The always-right program below has no halting query.  On an all-zero
    tape the two-sided [wide_source_run] never halts, while the
    left-infinite run stops on the third right move when [R = 2] and the
    initial head is [0]: after moving to [1] and [2] the next right move
    is at the boundary.  This is the model-level form of the ledger's
    buffer-exhaustion counterexample (the native table spends 46,176
    steps reaching its q3/Y halt; the abstract left-infinite machine
    halts at the boundary move itself). *)

Definition always_right_row : WideSourceRow :=
  {| wr_current := [];
     wr_read := false;
     wr_next := [];
     wr_write := false;
     wr_right := true |}.

Definition always_right_rows : list WideSourceRow := [always_right_row].

Definition always_false_tape : Z -> bool := fun _ => false.

Definition lic_always_right_start : LeftInfiniteConfig :=
  {| lic_state := [];
     lic_head := 0%Z;
     lic_tape := always_false_tape;
     lic_R := 2%Z;
     lic_halted := false |}.

Definition wide_always_right_start : WideSourceConfig :=
  {| wc_state := [];
     wc_head := 0%Z;
     wc_tape := always_false_tape;
     wc_halted := false |}.

Lemma always_right_wellformed :
  Forall (wide_row_wellformed 0) always_right_rows.
Proof. repeat constructor. Qed.

Example left_infinite_always_right_not_halted_yet :
  lic_halted (left_infinite_run 2 always_right_rows lic_always_right_start)
  = false.
Proof. reflexivity. Qed.

Example left_infinite_always_right_halts_at_boundary :
  lic_halted (left_infinite_run 3 always_right_rows lic_always_right_start)
  = true.
Proof. reflexivity. Qed.

Lemma wide_lookup_always_right :
  forall h,
    wide_source_lookup always_right_rows []
      (always_false_tape h) = Some always_right_row.
Proof. reflexivity. Qed.

Lemma wide_always_right_step :
  forall h,
    wide_source_step always_right_rows
      {| wc_state := [];
         wc_head := h;
         wc_tape := always_false_tape;
         wc_halted := false |} =
    {| wc_state := [];
       wc_head := (h + 1)%Z;
       wc_tape := always_false_tape;
       wc_halted := false |}.
Proof.
  intros h.
  unfold wide_source_step.
  cbn [wc_state wc_tape wc_head wc_halted].
  rewrite (wide_lookup_always_right h).
  cbn [always_right_row wr_next wr_write wr_right].
  f_equal.
  apply functional_extensionality. intros z.
  unfold source_write_at, always_false_tape.
  destruct (Z.eqb z h); reflexivity.
Qed.

Lemma wide_always_right_run_from :
  forall n h,
    wide_source_run n always_right_rows
      {| wc_state := [];
         wc_head := h;
         wc_tape := always_false_tape;
         wc_halted := false |} =
    {| wc_state := [];
       wc_head := (h + Z.of_nat n)%Z;
       wc_tape := always_false_tape;
       wc_halted := false |}.
Proof.
  induction n as [|n IH]; intros h; simpl.
  - rewrite Z.add_0_r. reflexivity.
  - rewrite (wide_always_right_step h).
    rewrite (IH (h + 1)%Z).
    f_equal. lia.
Qed.

Lemma wide_always_right_run :
  forall n,
    wide_source_run n always_right_rows wide_always_right_start =
    {| wc_state := [];
       wc_head := Z.of_nat n;
       wc_tape := always_false_tape;
       wc_halted := false |}.
Proof.
  intros n.
  unfold wide_always_right_start.
  rewrite wide_always_right_run_from.
  reflexivity.
Qed.

Corollary wide_always_right_never_halts :
  forall n,
    wc_halted (wide_source_run n always_right_rows
                 wide_always_right_start) = false.
Proof.
  intros n. rewrite wide_always_right_run. reflexivity.
Qed.
