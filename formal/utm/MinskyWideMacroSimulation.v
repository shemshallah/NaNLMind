(** * Conditional arbitrary-width source/23x8 halting equivalence

    The older MinskyMacroSimulation.v is phrased for a two-bit (four-state)
    binary source.  This module lifts the *target statement* to the existing
    variable-width source semantics, without replacing the frozen machine.

    The actual-table macro step, its positive running time, and the halting
    reflection of a concrete encoder remain explicit parameters.  None is
    assumed to be already constructed.  In particular, this module is NOT
    an unconditional universality proof.
*)

From Coq Require Import List Arith Lia.

From NaNLM Require Import MinskyTable MinskyWideSource
  MinskyConcreteDispatch.

Section ConditionalWideNativeSimulation.

Variable encode : nat -> list WideSourceRow -> WideSourceConfig -> Config.
Variable macro_cost : nat -> list WideSourceRow -> WideSourceConfig -> nat.

Hypothesis wide_encode_reflects_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    c_halted (encode p rows c) = wc_halted c.

Hypothesis wide_macro_cost_positive :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    1 <= macro_cost p rows c.

Hypothesis wide_actual_table_macro_step :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    run (macro_cost p rows c) (encode p rows c) =
    encode p rows (wide_source_step rows c).

Fixpoint wide_macro_clock
    (n p : nat) (rows : list WideSourceRow)
    (c : WideSourceConfig) : nat :=
  match n with
  | 0 => 0
  | S k => macro_cost p rows c +
           wide_macro_clock k p rows (wide_source_step rows c)
  end.

Lemma wide_macro_clock_at_least_steps :
  forall n p rows c,
    Forall (wide_row_wellformed p) rows ->
    n <= wide_macro_clock n p rows c.
Proof.
  induction n as [|n IH]; intros p rows c Hwf; simpl.
  - lia.
  - pose proof (wide_macro_cost_positive p rows c Hwf).
    specialize (IH p rows (wide_source_step rows c) Hwf).
    lia.
Qed.

Theorem conditional_wide_native_arbitrary_run :
  forall n p rows c,
    Forall (wide_row_wellformed p) rows ->
    run (wide_macro_clock n p rows c) (encode p rows c) =
    encode p rows (wide_source_run n rows c).
Proof.
  induction n as [|n IH]; intros p rows c Hwf; simpl.
  - reflexivity.
  - rewrite dispatch_run_add.
    rewrite (wide_actual_table_macro_step p rows c Hwf).
    apply IH. exact Hwf.
Qed.

Definition wide_source_eventually_halts
    (rows : list WideSourceRow) (c : WideSourceConfig) : Prop :=
  exists n, wc_halted (wide_source_run n rows c) = true.

Definition wide_native_eventually_halts
    (p : nat) (rows : list WideSourceRow)
    (c : WideSourceConfig) : Prop :=
  exists n, c_halted (run n (encode p rows c)) = true.

Theorem conditional_wide_source_halt_implies_native_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    wide_source_eventually_halts rows c ->
    wide_native_eventually_halts p rows c.
Proof.
  intros p rows c Hwf [n Hhalt].
  exists (wide_macro_clock n p rows c).
  rewrite (conditional_wide_native_arbitrary_run n p rows c Hwf).
  rewrite (wide_encode_reflects_halt p rows _ Hwf).
  exact Hhalt.
Qed.

Theorem conditional_wide_native_halt_implies_source_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    wide_native_eventually_halts p rows c ->
    wide_source_eventually_halts rows c.
Proof.
  intros p rows c Hwf [t Hhalt].
  exists t.
  assert (Hclock : t <= wide_macro_clock t p rows c).
  { apply wide_macro_clock_at_least_steps. exact Hwf. }
  assert (Hnative :
    c_halted (run (wide_macro_clock t p rows c)
      (encode p rows c)) = true).
  {
    replace (wide_macro_clock t p rows c)
      with (t + (wide_macro_clock t p rows c - t)) by lia.
    rewrite dispatch_run_add.
    rewrite (dispatch_halted_run
      (wide_macro_clock t p rows c - t)
      (run t (encode p rows c)) Hhalt).
    exact Hhalt.
  }
  rewrite (conditional_wide_native_arbitrary_run t p rows c Hwf)
    in Hnative.
  rewrite (wide_encode_reflects_halt p rows _ Hwf) in Hnative.
  exact Hnative.
Qed.

Theorem conditional_wide_source_native_halting_equivalence :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    (wide_source_eventually_halts rows c <->
     wide_native_eventually_halts p rows c).
Proof.
  intros p rows c Hwf; split.
  - apply conditional_wide_source_halt_implies_native_halt.
    exact Hwf.
  - apply conditional_wide_native_halt_implies_source_halt.
    exact Hwf.
Qed.

End ConditionalWideNativeSimulation.

(** The section's three bridge premises are visible arguments in the
    elaborated theorem: this command does not certify them. *)
Print Assumptions conditional_wide_source_native_halting_equivalence.

(** ** Concrete halt-side encoder fragment

    This is the first concrete piece of the wide-source encoder: the
    halted and lookup-failure cases.  The running case is left as an
    explicit placeholder; the theorem below proves the macro step only
    for the halt side. *)

Definition wide_halted_marker : Config :=
  {| c_state := 0;
     c_tape := {| t_left := []; t_right := [5] |};
     c_halted := true |}.

Definition wide_halt_entry : Config :=
  entry_config 3 [] [5].

Definition wide_encode_halt
    (rows : list WideSourceRow) (c : WideSourceConfig) : Config :=
  if wc_halted c then wide_halted_marker
  else
    match wide_source_lookup rows (wc_state c)
                              (wc_tape c (wc_head c)) with
    | None => wide_halt_entry
    | Some _ => wide_halt_entry  (* running-case placeholder *)
    end.

Lemma wide_halt_entry_step :
  step wide_halt_entry = wide_halted_marker.
Proof. reflexivity. Qed.

Lemma wide_encode_halt_reflects :
  forall rows c,
    c_halted (wide_encode_halt rows c) = wc_halted c.
Proof.
  intros rows c.
  unfold wide_encode_halt.
  destruct (wc_halted c) eqn:H.
  - reflexivity.
  - destruct (wide_source_lookup rows (wc_state c)
                (wc_tape c (wc_head c))); reflexivity.
Qed.

Lemma wide_encode_halt_step_none :
  forall rows c,
    wc_halted c = false ->
    wide_source_lookup rows (wc_state c) (wc_tape c (wc_head c)) = None ->
    run 1 (wide_encode_halt rows c) =
    wide_encode_halt rows (wide_source_step rows c).
Proof.
  intros rows c Hh Hlookup.
  unfold wide_encode_halt.
  rewrite Hh, Hlookup.
  unfold wide_source_step.
  rewrite Hh, Hlookup.
  cbn [wc_halted wc_state wc_tape wc_head].
  unfold wide_halt_entry, wide_halted_marker.
  reflexivity.
Qed.

Print Assumptions wide_encode_halt_reflects.
Print Assumptions wide_encode_halt_step_none.
