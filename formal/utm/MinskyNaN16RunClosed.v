(** * Closed run-level refinement for the NaN16 universal machine

    [MinskyNaN16Run.v] proves the run-level induction

      [vm_run_refines : entry_ok vm -> (forall vm, entry_ok vm -> step_ok vm) ->
         entry_ok (vm_run n vm) /\ nstate_rel ...]

    leaving [step_ok] as a hypothesis, and [MinskyNaN16StepOk.v] discharges
    one [step_ok] from a *per-state* layout hypothesis on the current tape
    cell [tbase + vm_reg vm 2].

    This file closes the gap: the per-state hypothesis is replaced by one
    global tape window

      [tape_window_ok table table_base tbase window]

    saying that every address [z] in [[tbase, tbase + window)] is neither a
    table cell nor a control cell (head/state/halt/tape-base).  The only
    remaining run-dependent obligation is the explicit bound

      [vm_reg vm 2 + n < window]

    which guarantees that every head reachable in [n] steps stays inside the
    window.  It is preserved because one native step moves the head by at
    most one to the right ([nstep_head_le], [step_ok_head_le]); the lemma
    [vm_run_head_lt_window] records the resulting head bound explicitly.

    The resulting [vm_run_refines_closed] has no axioms and no [Admitted].
    A corollary [vm_run_refines_window] instantiates the window with
    [vm_reg vm 2 + n + 1], so no separate numeric side condition remains:
    it states directly that the whole reachable tape range is outside the
    table and control cells. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyNaN16Run MinskyNaN16StepOk
  MinskyNaN16VM MinskyNaN16Action MinskyNaN16Prelude
  MinskyNaN16StepSpec MinskyNaN16StepEntrySpec.

(** ** Global layout predicates *)

(** The table cells avoid the three processor cells.  These are static
    facts about the table placement, independent of the tape head. *)
Definition table_control_ok
    (table : list (list nat)) (table_base : nat) : Prop :=
  (forall i f, i < length table -> f < 8 ->
    table_base + 8 * i + f <> action_head_addr) /\
  (forall i f, i < length table -> f < 8 ->
    table_base + 8 * i + f <> action_state_addr) /\
  (forall i f, i < length table -> f < 8 ->
    table_base + 8 * i + f <> action_halt_addr).

(** One global tape window.  Every address in [[tbase, tbase + window)] is
    outside the table and outside the control cells.  Consequently the
    per-state layout clauses needed by [step_ok_of_layout] follow for any
    head whose tape cell lies in the window. *)
Definition tape_window_ok
    (table : list (list nat)) (table_base tbase window : nat) : Prop :=
  (forall z, tbase <= z -> z < tbase + window ->
    forall i f, i < length table -> f < 8 ->
      table_base + 8 * i + f <> z) /\
  (forall z, tbase <= z -> z < tbase + window ->
    z <> action_head_addr /\
    z <> action_state_addr /\
    z <> action_halt_addr /\
    z <> tape_base_addr).

(** In the intended layout the table sits above the processor cells, so
    [table_control_ok] follows from the single numeric fact
    [action_halt_addr < table_base]. *)
Lemma table_control_ok_of_base_above :
  forall table table_base,
    action_halt_addr < table_base ->
    table_control_ok table table_base.
Proof.
  intros table table_base Hbase.
  unfold table_control_ok.
  split; [|split]; intros i f Hi Hf E;
    unfold action_head_addr, action_state_addr, action_halt_addr in *;
    lia.
Qed.

(** ** The head moves by at most one cell per native step *)

(** [nstep] is kept opaque in [MinskyNaN16StepOk]; make it transparent only
    for this small arithmetic lemma and restore opacity afterwards. *)
Transparent nstep action_run action_new_head.

Lemma nstep_head_le :
  forall table table_base tape_base c,
    n_head (nstep table table_base tape_base c) <= n_head c + 1.
Proof.
  intros table table_base tape_base c.
  unfold nstep.
  destruct (Nat.eqb (n_halt c) 0) eqn:E.
  - destruct (scan_index_from 0 (n_state c)
      (n_mem c (tape_base + n_head c)) table) as [[j row]|].
    + unfold hit_nstate. cbn [n_head].
      unfold action_run. cbn [fst].
      unfold action_new_head. cbn.
      destruct (Nat.eqb (nth 3 row 1) 0) eqn:E0; cbn.
      * lia.
      * destruct (Nat.eqb (nth 3 row 1) 2) eqn:E2; cbn; lia.
    + cbn [n_head]. lia.
  - cbn [n_head]. lia.
Qed.

Opaque nstep action_run.

(** The refined head of one [step_entry] is at most one past the old head. *)
Lemma step_ok_head_le :
  forall vm table table_base tbase,
    step_ok vm table table_base tbase ->
    vm_reg (step_entry vm table table_base) 2 <= vm_reg vm 2 + 1.
Proof.
  intros vm table table_base tbase [_ Hrel].
  unfold nstate_rel in Hrel.
  destruct Hrel as [_ [Hh _]].
  change (n_head (vm_to_nstate (step_entry vm table table_base))
    <= n_head (vm_to_nstate vm) + 1).
  rewrite Hh.
  apply nstep_head_le.
Qed.

(** ** One step from the global window *)

Lemma step_ok_of_window :
  forall (vm : VM) (table : list (list nat))
         (table_base tbase window : nat),
    entry_ok vm table table_base tbase ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_control_ok table table_base ->
    tape_window_ok table table_base tbase window ->
    vm_reg vm 2 < window ->
    step_ok vm table table_base tbase.
Proof.
  intros vm table table_base tbase window
    Hentry Hlen Hshort Hlen8 Hstatic Hwin Hhead.
  unfold table_control_ok in Hstatic.
  unfold tape_window_ok in Hwin.
  destruct Hstatic as [Hdis_head [Hdis_state Hdis_halt]].
  destruct Hwin as [Hwin_table Hwin_control].
  apply (step_ok_of_layout vm table table_base tbase
    Hentry Hlen Hshort Hlen8).
  - (* the current tape cell is outside the table *)
    intros i f Hi Hf.
    assert (Hz1 : tbase <= tbase + vm_reg vm 2) by lia.
    assert (Hz2 : tbase + vm_reg vm 2 < tbase + window) by lia.
    exact (Hwin_table (tbase + vm_reg vm 2) Hz1 Hz2 i f Hi Hf).
  - (* the table avoids the processor cells *)
    exact Hdis_head.
  - exact Hdis_state.
  - exact Hdis_halt.
  - (* the tape cell is not the tape-base cell 303 *)
    intro E.
    assert (Hz1 : tbase <= tbase + vm_reg vm 2) by lia.
    assert (Hz2 : tbase + vm_reg vm 2 < tbase + window) by lia.
    destruct (Hwin_control (tbase + vm_reg vm 2) Hz1 Hz2)
      as [_ [_ [_ Htb]]].
    exact (Htb (eq_sym E)).
Qed.

(** ** The reachable head stays in the window *)

Lemma vm_run_head_lt_window :
  forall (n : nat) (vm : VM) (table : list (list nat))
         (table_base tbase window : nat),
    entry_ok vm table table_base tbase ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_control_ok table table_base ->
    tape_window_ok table table_base tbase window ->
    vm_reg vm 2 + n < window ->
    vm_reg (vm_run n vm table table_base) 2 < window.
Proof.
  induction n as [|n IH];
    intros vm table table_base tbase window
      Hentry Hlen Hshort Hlen8 Hstatic Hwin Hbound.
  - cbn [vm_run]. lia.
  - cbn [vm_run].
    assert (Hhead : vm_reg vm 2 < window) by lia.
    assert (Hstep : step_ok vm table table_base tbase)
      by (apply (step_ok_of_window vm table table_base tbase window
                 Hentry Hlen Hshort Hlen8 Hstatic Hwin Hhead)).
    pose proof (step_ok_head_le vm table table_base tbase Hstep) as Hle.
    destruct Hstep as [Hentry' _].
    apply (IH (step_entry vm table table_base) table table_base tbase window
      Hentry' Hlen Hshort Hlen8 Hstatic Hwin).
    lia.
Qed.

(** ** Closed run-level refinement *)

Theorem vm_run_refines_closed :
  forall (n : nat) (vm : VM) (table : list (list nat))
         (table_base tbase window : nat),
    entry_ok vm table table_base tbase ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_control_ok table table_base ->
    tape_window_ok table table_base tbase window ->
    vm_reg vm 2 + n < window ->
    entry_ok (vm_run n vm table table_base) table table_base tbase /\
    nstate_rel (vm_to_nstate (vm_run n vm table table_base))
      (nrun n table table_base tbase (vm_to_nstate vm)).
Proof.
  induction n as [|n IH];
    intros vm table table_base tbase window
      Hentry Hlen Hshort Hlen8 Hstatic Hwin Hbound.
  - cbn [vm_run nrun].
    split; [exact Hentry|apply nstate_rel_refl].
  - cbn [vm_run nrun].
    assert (Hhead : vm_reg vm 2 < window) by lia.
    assert (Hstep : step_ok vm table table_base tbase)
      by (apply (step_ok_of_window vm table table_base tbase window
                 Hentry Hlen Hshort Hlen8 Hstatic Hwin Hhead)).
    pose proof (step_ok_head_le vm table table_base tbase Hstep) as Hle.
    destruct Hstep as [Hentry' Hrel].
    assert (Hhead' : vm_reg (step_entry vm table table_base) 2 + n < window)
      by lia.
    destruct (IH (step_entry vm table table_base) table table_base tbase
      window Hentry' Hlen Hshort Hlen8 Hstatic Hwin Hhead')
      as [Hentry2 Hrel2].
    split; [exact Hentry2|].
    eapply nstate_rel_trans.
    + exact Hrel2.
    + apply nrun_congr. exact Hrel.
Qed.

(** The same run-level refinement with the window sized by the initial head
    and the number of steps: every address in
    [[tbase, tbase + vm_reg vm 2 + n + 1)] is outside the table and outside
    the control cells.  No numeric side condition is needed. *)

Corollary vm_run_refines_window :
  forall (n : nat) (vm : VM) (table : list (list nat))
         (table_base tbase : nat),
    entry_ok vm table table_base tbase ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_control_ok table table_base ->
    tape_window_ok table table_base tbase (vm_reg vm 2 + n + 1) ->
    entry_ok (vm_run n vm table table_base) table table_base tbase /\
    nstate_rel (vm_to_nstate (vm_run n vm table table_base))
      (nrun n table table_base tbase (vm_to_nstate vm)).
Proof.
  intros n vm table table_base tbase
    Hentry Hlen Hshort Hlen8 Hstatic Hwin.
  apply (vm_run_refines_closed n vm table table_base tbase
    (vm_reg vm 2 + n + 1) Hentry Hlen Hshort Hlen8 Hstatic Hwin).
  lia.
Qed.

(** No axioms are used. *)
Print Assumptions vm_run_refines_closed.
Print Assumptions vm_run_refines_window.
Print Assumptions vm_run_head_lt_window.
