(** * From concrete macro-step obligations to halting equivalence

    This file proves a conditional, arbitrary-run reduction for the
    UNCHANGED MinskyTable.run.  The conditions are deliberately explicit:
    a computable encoding must preserve halting, each source transition
    must cost a strictly positive number of actual table transitions, and
    those transitions must reach the encoding of the source successor.

    No such encoding or full-instruction macro is constructed here.  In
    particular this theorem does not assert that the four-state binary
    source language is universal.  It isolates precise propositions that
    must be discharged before the 23x8 universality claim can be made.
*)

From Coq Require Import List Arith Lia.

From NaNLM Require Import MinskyTable MinskySourceEncoding
  MinskyConcreteDispatch.

Section ConditionalNativeSimulation.

Variable encode : list BinarySourceRow -> BinarySourceConfig -> Config.
Variable macro_cost : list BinarySourceRow -> BinarySourceConfig -> nat.

Hypothesis encode_reflects_halt :
  forall rows c,
    c_halted (encode rows c) = sc_halted c.

Hypothesis macro_cost_positive :
  forall rows c, 1 <= macro_cost rows c.

Hypothesis actual_table_macro_step :
  forall rows c,
    run (macro_cost rows c) (encode rows c) =
    encode rows (source_step rows c).

(** The clock follows the actual sequence of source configurations.
    It is not a constant fuel multiplier or a host-side interpreter. *)
Fixpoint macro_clock (n : nat) (rows : list BinarySourceRow)
    (c : BinarySourceConfig) : nat :=
  match n with
  | 0 => 0
  | S k => macro_cost rows c + macro_clock k rows (source_step rows c)
  end.

Lemma macro_clock_at_least_steps :
  forall n rows c, n <= macro_clock n rows c.
Proof.
  induction n as [|n IH]; intros rows c; simpl.
  - lia.
  - specialize (IH rows (source_step rows c)).
    pose proof (macro_cost_positive rows c).
    lia.
Qed.

(** A single executable table macro, if supplied, lifts to every finite
    source execution with the same inherited description and tape encoding. *)
Theorem conditional_native_arbitrary_run :
  forall n rows c,
    run (macro_clock n rows c) (encode rows c) =
    encode rows (source_run n rows c).
Proof.
  induction n as [|n IH]; intros rows c; simpl.
  - reflexivity.
  - rewrite dispatch_run_add.
    rewrite actual_table_macro_step.
    apply IH.
Qed.

Definition source_eventually_halts
    (rows : list BinarySourceRow) (c : BinarySourceConfig) : Prop :=
  exists n, sc_halted (source_run n rows c) = true.

Definition native_eventually_halts
    (rows : list BinarySourceRow) (c : BinarySourceConfig) : Prop :=
  exists n, c_halted (run n (encode rows c)) = true.

Theorem conditional_source_halt_implies_native_halt :
  forall rows c,
    source_eventually_halts rows c -> native_eventually_halts rows c.
Proof.
  intros rows c [n Hhalt].
  exists (macro_clock n rows c).
  rewrite conditional_native_arbitrary_run.
  rewrite encode_reflects_halt.
  exact Hhalt.
Qed.

(** The reverse direction rules out premature native halting.  Given a
    native halt at time t, the macro clock at source step t is >= t;
    a halted table configuration cannot restart before that boundary. *)
Theorem conditional_native_halt_implies_source_halt :
  forall rows c,
    native_eventually_halts rows c -> source_eventually_halts rows c.
Proof.
  intros rows c [t Hhalt].
  exists t.
  assert (Hclock : t <= macro_clock t rows c).
  { apply macro_clock_at_least_steps. }
  assert (Hnative :
    c_halted (run (macro_clock t rows c) (encode rows c)) = true).
  {
    replace (macro_clock t rows c)
      with (t + (macro_clock t rows c - t)) by lia.
    rewrite dispatch_run_add.
    rewrite (dispatch_halted_run
      (macro_clock t rows c - t) (run t (encode rows c)) Hhalt).
    exact Hhalt.
  }
  rewrite conditional_native_arbitrary_run in Hnative.
  rewrite encode_reflects_halt in Hnative.
  exact Hnative.
Qed.

Theorem conditional_source_native_halting_equivalence :
  forall rows c,
    source_eventually_halts rows c <-> native_eventually_halts rows c.
Proof.
  intros rows c; split.
  - apply conditional_source_halt_implies_native_halt.
  - apply conditional_native_halt_implies_source_halt.
Qed.

End ConditionalNativeSimulation.

(** Section hypotheses become explicit theorem parameters; no proof of
    actual_table_macro_step or of source universality has been assumed
    silently.  Kernel checking this conditional theorem does not close
    either obligation. *)
Print Assumptions conditional_source_native_halting_equivalence.
