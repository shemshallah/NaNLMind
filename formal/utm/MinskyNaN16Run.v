From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16Prelude MinskyNaN16Step MinskyNaN16StepSpec MinskyNaN16StepEntrySpec.

(** ** run100 phase: iteration and invariant *)

Definition entry_ok (vm : VM) (table : list (list nat))
    (table_base tbase : nat) : Prop :=
  vm_reg vm 0 = 0 /\
  vm_reg vm 2 = vm_mem vm action_head_addr /\
  vm_reg vm 13 = 1 /\
  vm_halted vm = false /\
  vm_mem vm tape_base_addr = tbase /\
  table_mem_at table_base table (vm_mem vm).

Definition step_ok (vm : VM) (table : list (list nat))
    (table_base tbase : nat) : Prop :=
  entry_ok (step_entry vm table table_base) table table_base tbase /\
  nstate_rel (vm_to_nstate (step_entry vm table table_base))
    (nstep table table_base tbase (vm_to_nstate vm)).

Fixpoint vm_run (n : nat) (vm : VM) (table : list (list nat))
    (table_base : nat) : VM :=
  match n with
  | 0 => vm
  | S k => vm_run k (step_entry vm table table_base) table table_base
  end.

Fixpoint nrun (n : nat) (table : list (list nat))
    (table_base tbase : nat) (c : NState) : NState :=
  match n with
  | 0 => c
  | S k => nrun k table table_base tbase (nstep table table_base tbase c)
  end.

Lemma nstate_rel_refl : forall c, nstate_rel c c.
Proof. intro c. unfold nstate_rel. repeat split; reflexivity. Qed.

Lemma nrun_congr :
  forall n table table_base tbase a b,
    nstate_rel a b ->
    nstate_rel (nrun n table table_base tbase a)
      (nrun n table table_base tbase b).
Proof.
  induction n as [|n IH]; intros table table_base tbase a b H.
  - cbn. exact H.
  - cbn. apply IH. apply nstep_congr. exact H.
Qed.

(** The remaining proof obligation is exactly [step_ok]: one entry-ready
    native step preserves [entry_ok] and refines one [nstep].  The run
    induction below is complete and axiom-free. *)

Theorem vm_run_refines :
  forall n vm table table_base tbase,
    entry_ok vm table table_base tbase ->
    (forall vm, entry_ok vm table table_base tbase ->
      step_ok vm table table_base tbase) ->
    entry_ok (vm_run n vm table table_base) table table_base tbase /\
    nstate_rel (vm_to_nstate (vm_run n vm table table_base))
      (nrun n table table_base tbase (vm_to_nstate vm)).
Proof.
  induction n as [|n IH]; intros vm table table_base tbase Hentry Hstep.
  - cbn. split; [exact Hentry|apply nstate_rel_refl].
  - cbn [vm_run nrun].
    destruct (Hstep vm Hentry) as [Hentry' Hrel].
    destruct (IH (step_entry vm table table_base) table table_base tbase Hentry' Hstep) as [Hentry2 Hrel2].
    split; [exact Hentry2|].
    eapply nstate_rel_trans.
    + exact Hrel2.
    + apply nrun_congr. exact Hrel.
Qed.
