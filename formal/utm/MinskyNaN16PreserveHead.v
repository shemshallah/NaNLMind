(** * Hit-case projections for the NaN16 entry step

    This module records the read-back facts that the higher-level refinement
    needs after a successful (hit) native step:

    - the head/state/halt cells produced by the abstract action block
      ([action_run]) are the corresponding fields of the scanned row;
    - the hit branch of [native_step] writes the moved head into register 2
      and into the head cell, keeps the machine running, and exposes the
      state/halt cells as the [action_run] projections;
    - the same projections hold for [step_entry], whose result is related to
      the abstract [nstep] by [step_entry_spec].

    The tape address is required to be disjoint from the three control
    addresses because the action block writes the tape cell first; [nth]
    alignment uses the fact that scanned rows have length 8. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ActionRun MinskyNaN16Prelude MinskyNaN16PreludeReady
  MinskyNaN16StepSpec MinskyNaN16ScanPhase MinskyNaN16Step
  MinskyNaN16StepEntrySpec.

(** ** Concrete action-run hit projections *)

(** The three control cells after [action_run] on a row, assuming the tape
    cell is not one of the control addresses. *)
Lemma action_run_hit_cells :
  forall row_addr tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) action_head_addr =
      action_new_head head (nth 3 row 1) /\
    snd (action_run row_addr tape_addr head m row) action_state_addr =
      nth 4 row 1 /\
    snd (action_run row_addr tape_addr head m row) action_halt_addr =
      (if Nat.eqb (nth 5 row 1) 0 then m action_halt_addr else 1).
Proof.
  intros row_addr tape_addr head m row Hh Hs Hl.
  split.
  - apply (action_run_head_cell row_addr tape_addr head m row Hh Hs Hl).
  - split.
    + apply (action_run_state row_addr tape_addr head m row Hh Hs Hl).
    + apply (action_run_halt_cell row_addr tape_addr head m row Hh Hs Hl).
Qed.

(** Every cell other than the tape cell and the three control cells is
    untouched by [action_run]. *)
Lemma action_run_hit_frame :
  forall row_addr tape_addr head m row k,
    k <> tape_addr ->
    k <> action_head_addr ->
    k <> action_state_addr ->
    k <> action_halt_addr ->
    snd (action_run row_addr tape_addr head m row) k = m k.
Proof.
  intros row_addr tape_addr head m row k Ht Hh Hs Hl.
  apply (action_run_frame row_addr tape_addr head m row k Ht Hh Hs Hl).
Qed.

(** ** Projections of the abstract hit state [hit_nstate] *)

Lemma hit_nstate_head :
  forall table_base tape_addr head m row,
    n_head (hit_nstate table_base tape_addr head m row) =
      action_new_head head (nth 3 row 1).
Proof. intros. reflexivity. Qed.

Lemma hit_nstate_head_cell :
  forall table_base tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    n_mem (hit_nstate table_base tape_addr head m row) action_head_addr =
      action_new_head head (nth 3 row 1).
Proof.
  intros table_base tape_addr head m row Hh Hs Hl.
  unfold hit_nstate. cbn.
  apply (action_run_head_cell table_base tape_addr head m row Hh Hs Hl).
Qed.

Lemma hit_nstate_state_cell :
  forall table_base tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    n_state (hit_nstate table_base tape_addr head m row) = nth 4 row 1.
Proof.
  intros table_base tape_addr head m row Hh Hs Hl.
  unfold hit_nstate. cbn.
  apply (action_run_state table_base tape_addr head m row Hh Hs Hl).
Qed.

Lemma hit_nstate_halt_cell :
  forall table_base tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    n_halt (hit_nstate table_base tape_addr head m row) =
      (if Nat.eqb (nth 5 row 1) 0 then m action_halt_addr else 1).
Proof.
  intros table_base tape_addr head m row Hh Hs Hl.
  unfold hit_nstate. cbn.
  apply (action_run_halt_cell table_base tape_addr head m row Hh Hs Hl).
Qed.

Lemma hit_nstate_frame :
  forall table_base tape_addr head m row k,
    k <> tape_addr ->
    k <> action_head_addr ->
    k <> action_state_addr ->
    k <> action_halt_addr ->
    n_mem (hit_nstate table_base tape_addr head m row) k = m k.
Proof.
  intros table_base tape_addr head m row k Ht Hh Hs Hl.
  unfold hit_nstate. cbn.
  apply (action_run_frame table_base tape_addr head m row k Ht Hh Hs Hl).
Qed.

(** In the hit state the head register and the head cell agree. *)
Lemma hit_nstate_head_mem :
  forall table_base tape_addr head m row,
    tape_addr <> action_head_addr ->
    tape_addr <> action_state_addr ->
    tape_addr <> action_halt_addr ->
    n_head (hit_nstate table_base tape_addr head m row) =
      n_mem (hit_nstate table_base tape_addr head m row) action_head_addr.
Proof.
  intros table_base tape_addr head m row Hh Hs Hl.
  etransitivity.
  - apply hit_nstate_head.
  - symmetry. apply (hit_nstate_head_cell table_base tape_addr head m row Hh Hs Hl).
Qed.

(** ** The native-step hit postcondition *)

Section NativeStepHit.

Variables (vm : VM) (state head table_base tape_base : nat)
          (table : list (list nat)) (m : Mem) (j : nat) (row : list nat).

Hypothesis Hlen : length table = 184.
Hypothesis Hshort : Forall (fun r => 0 < length r /\ 1 < length r) table.
Hypothesis Hlen8 : Forall (fun r => length r = 8) table.
Hypothesis Hmemtab : table_mem_at table_base table m.
Hypothesis Hready : scan_ready vm 0 state (m (tape_base + head)) table_base m.
Hypothesis Hr2 : vm_reg vm 2 = head.
Hypothesis Hr3 : vm_reg vm 3 = tape_base + head.
Hypothesis Hr0 : vm_reg vm 0 = 0.
Hypothesis Hhaltcell : vm_mem vm action_halt_addr = 0.
Hypothesis Hlayout : forall j0 row0,
  scan_index_from 0 state (m (tape_base + head)) table = Some (j0, row0) ->
  (forall f, f < 8 -> table_base + 8 * j0 + f <> tape_base + head) /\
  action_head_addr <> table_base + 8 * j0 + 4 /\
  action_state_addr <> table_base + 8 * j0 + 5 /\
  action_head_addr <> table_base + 8 * j0 + 5.
Hypothesis Hdist_head : tape_base + head <> action_head_addr.
Hypothesis Hdist_state : tape_base + head <> action_state_addr.
Hypothesis Hdist_halt : tape_base + head <> action_halt_addr.
Hypothesis Hidx : scan_index_from 0 state (m (tape_base + head)) table =
  Some (j, row).

(** The raw [native_step_refines] hit branch, with [nth 3 row 0] kept. *)
Lemma native_step_hit_core :
  vm_pc (native_step vm table table_base tape_base) = 22 /\
  vm_reg (native_step vm table table_base tape_base) 2 =
    action_new_head head (nth 3 row 0) /\
  vm_reg (native_step vm table table_base tape_base) 0 = 0 /\
  vm_reg (native_step vm table table_base tape_base) 7 = table_base + 8 * j /\
  vm_halted (native_step vm table table_base tape_base) = false /\
  (forall k, vm_mem (native_step vm table table_base tape_base) k =
    snd (action_run (table_base + 8 * j) (tape_base + head) head m row) k).
Proof.
  pose proof (native_step_refines vm state head table_base tape_base table m
    Hlen Hshort Hlen8 Hmemtab Hready Hr2 Hr3 Hr0 Hhaltcell Hlayout) as H.
  rewrite Hidx in H. cbn in H.
  exact H.
Qed.

(** Register 2 holds the new head, and the head cell holds the same value. *)
Lemma native_step_hit_head_cell :
  vm_reg (native_step vm table table_base tape_base) 2 =
    vm_mem (native_step vm table table_base tape_base) action_head_addr.
Proof.
  destruct native_step_hit_core as [Hpc [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
  assert (Hlenrow : length row = 8).
  { apply (scan_index_from_length 0 state (m (tape_base + head)) table
      j row Hidx Hlen8). }
  assert (Hnth3 : nth 3 row 0 = nth 3 row 1).
  { symmetry. apply nth_indep. rewrite Hlenrow. lia. }
  rewrite Hr2', (Hmem' action_head_addr).
  rewrite (action_run_head_cell (table_base + 8 * j) (tape_base + head)
    head m row Hdist_head Hdist_state Hdist_halt).
  rewrite Hnth3. reflexivity.
Qed.

Lemma native_step_hit_halted :
  vm_halted (native_step vm table table_base tape_base) = false.
Proof.
  destruct native_step_hit_core as [Hpc [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
  exact Hhalt'.
Qed.

Lemma native_step_hit_state_cell :
  vm_mem (native_step vm table table_base tape_base) action_state_addr =
    nth 4 row 1.
Proof.
  destruct native_step_hit_core as [Hpc [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
  rewrite (Hmem' action_state_addr).
  apply (action_run_state (table_base + 8 * j) (tape_base + head) head m row
    Hdist_head Hdist_state Hdist_halt).
Qed.

Lemma native_step_hit_halt_cell :
  vm_mem (native_step vm table table_base tape_base) action_halt_addr =
    (if Nat.eqb (nth 5 row 1) 0 then m action_halt_addr else 1).
Proof.
  destruct native_step_hit_core as [Hpc [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
  rewrite (Hmem' action_halt_addr).
  apply (action_run_halt_cell (table_base + 8 * j) (tape_base + head) head m row
    Hdist_head Hdist_state Hdist_halt).
Qed.

Lemma native_step_hit_frame :
  forall k,
    k <> tape_base + head ->
    k <> action_head_addr ->
    k <> action_state_addr ->
    k <> action_halt_addr ->
    vm_mem (native_step vm table table_base tape_base) k = m k.
Proof.
  intros k Ht Hh Hs Hl.
  destruct native_step_hit_core as [Hpc [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
  rewrite (Hmem' k).
  apply (action_run_frame (table_base + 8 * j) (tape_base + head) head m row k
    Ht Hh Hs Hl).
Qed.

(** The complete hit postcondition: the head register equals the head cell,
    the machine is not halted, the state/halt cells are the [action_run]
    projections, and every other non-control cell is framed. *)
Lemma native_step_hit_projections :
  vm_reg (native_step vm table table_base tape_base) 2 =
    vm_mem (native_step vm table table_base tape_base) action_head_addr /\
  vm_halted (native_step vm table table_base tape_base) = false /\
  vm_mem (native_step vm table table_base tape_base) action_state_addr =
    nth 4 row 1 /\
  vm_mem (native_step vm table table_base tape_base) action_halt_addr =
    (if Nat.eqb (nth 5 row 1) 0 then m action_halt_addr else 1) /\
  (forall k,
    k <> tape_base + head ->
    k <> action_head_addr ->
    k <> action_state_addr ->
    k <> action_halt_addr ->
    vm_mem (native_step vm table table_base tape_base) k = m k).
Proof.
  repeat split.
  - apply native_step_hit_head_cell.
  - apply native_step_hit_halted.
  - apply native_step_hit_state_cell.
  - apply native_step_hit_halt_cell.
  - exact native_step_hit_frame.
Qed.

End NativeStepHit.

(** vm_halted is false after a native step in either scan branch.  (The action
    block has no HALT; this is the halted component of
    [native_step_refines].) *)
Lemma native_step_halted :
  forall (vm : VM) (state head table_base tape_base : nat)
         (table : list (list nat)) (m : Mem),
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_mem_at table_base table m ->
    scan_ready vm 0 state (m (tape_base + head)) table_base m ->
    vm_reg vm 2 = head ->
    vm_reg vm 3 = tape_base + head ->
    vm_reg vm 0 = 0 ->
    vm_mem vm action_halt_addr = 0 ->
    (forall j row,
      scan_index_from 0 state (m (tape_base + head)) table = Some (j, row) ->
      (forall f, f < 8 -> table_base + 8 * j + f <> tape_base + head) /\
      action_head_addr <> table_base + 8 * j + 4 /\
      action_state_addr <> table_base + 8 * j + 5 /\
      action_head_addr <> table_base + 8 * j + 5) ->
    vm_halted (native_step vm table table_base tape_base) = false.
Proof.
  intros vm state head table_base tape_base table m
    Hlen Hshort Hlen8 Hmemtab Hready Hr2 Hr3 Hr0 Hhaltcell Hlayout.
  destruct (scan_index_from 0 state (m (tape_base + head)) table)
    as [[j row]|] eqn:Eidx.
  - assert (Hlayout' : forall j0 row0,
      scan_index_from 0 state (m (tape_base + head)) table = Some (j0, row0) ->
      (forall f, f < 8 -> table_base + 8 * j0 + f <> tape_base + head) /\
      action_head_addr <> table_base + 8 * j0 + 4 /\
      action_state_addr <> table_base + 8 * j0 + 5 /\
      action_head_addr <> table_base + 8 * j0 + 5).
    { intros j0 row0 Hsome. apply (Hlayout j0 row0).
      rewrite <- Eidx. exact Hsome. }
    pose proof (native_step_refines vm state head table_base tape_base table m
      Hlen Hshort Hlen8 Hmemtab Hready Hr2 Hr3 Hr0 Hhaltcell Hlayout') as H.
    rewrite Eidx in H. cbn in H.
    destruct H as [Hpc [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
    exact Hhalt'.
  - assert (Hlayout' : forall j0 row0,
      scan_index_from 0 state (m (tape_base + head)) table = Some (j0, row0) ->
      (forall f, f < 8 -> table_base + 8 * j0 + f <> tape_base + head) /\
      action_head_addr <> table_base + 8 * j0 + 4 /\
      action_state_addr <> table_base + 8 * j0 + 5 /\
      action_head_addr <> table_base + 8 * j0 + 5).
    { intros j0 row0 Hsome. rewrite Eidx in Hsome. discriminate. }
    pose proof (native_step_refines vm state head table_base tape_base table m
      Hlen Hshort Hlen8 Hmemtab Hready Hr2 Hr3 Hr0 Hhaltcell Hlayout') as H.
    rewrite Eidx in H. cbn in H.
    destruct H as [Hpc [Hmem' [Hr2' [Hr0' Hhalt']]]].
    exact Hhalt'.
Qed.

(** ** The step_entry hit postcondition *)

Section StepEntryHit.

Variables (vm : VM) (table_base : nat) (table : list (list nat))
          (j : nat) (row : list nat).

Hypothesis Hr0 : vm_reg vm 0 = 0.
Hypothesis Hr2loc : vm_reg vm 2 = vm_mem vm action_head_addr.
Hypothesis Hr13 : vm_reg vm 13 = 1.
Hypothesis Hhalt : vm_halted vm = false.
Hypothesis Hlen : length table = 184.
Hypothesis Hshort : Forall (fun r => 0 < length r /\ 1 < length r) table.
Hypothesis Hlen8 : Forall (fun r => length r = 8) table.
Hypothesis Hmemtab : table_mem_at table_base table (vm_mem vm).
Hypothesis Hlayout : forall j0 row0,
  scan_index_from 0 (vm_mem vm action_state_addr)
    (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table = Some (j0, row0) ->
  (forall f, f < 8 -> table_base + 8 * j0 + f <>
    vm_mem vm tape_base_addr + vm_reg vm 2) /\
  action_head_addr <> table_base + 8 * j0 + 4 /\
  action_state_addr <> table_base + 8 * j0 + 5 /\
  action_head_addr <> table_base + 8 * j0 + 5.
Hypothesis Hhaltcell : vm_mem vm action_halt_addr = 0.
Hypothesis Hidx : scan_index_from 0 (vm_mem vm action_state_addr)
  (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table = Some (j, row).
Hypothesis Hdist_head : vm_mem vm tape_base_addr + vm_reg vm 2 <> action_head_addr.
Hypothesis Hdist_state : vm_mem vm tape_base_addr + vm_reg vm 2 <> action_state_addr.
Hypothesis Hdist_halt : vm_mem vm tape_base_addr + vm_reg vm 2 <> action_halt_addr.

(** [step_entry_spec] followed by the abstract hit reduction: the VM state
    after [step_entry] projects onto [hit_nstate] of the scanned row. *)
Lemma step_entry_hit_rel :
  nstate_rel (vm_to_nstate (step_entry vm table table_base))
    (hit_nstate table_base (vm_mem vm tape_base_addr + vm_reg vm 2)
      (vm_reg vm 2) (vm_mem vm) row).
Proof.
  pose proof (step_entry_spec vm table_base table Hr0 Hr2loc Hr13 Hhalt
    Hlen Hshort Hlen8 Hmemtab Hlayout) as Hspec.
  unfold nstate_rel in Hspec.
  destruct Hspec as [Hs [Hh [Hl Hmem]]].
  assert (Hnh : n_halt (vm_to_nstate vm) = 0).
  { unfold vm_to_nstate. cbn. exact Hhaltcell. }
  pose proof (nstep_active_hit table table_base (vm_mem vm tape_base_addr)
    (vm_to_nstate vm) j row Hnh Hidx) as Hstep.
  rewrite Hstep in Hs, Hh, Hl, Hmem.
  unfold nstate_rel. split; [exact Hs|].
  split; [exact Hh|].
  split; [exact Hl|exact Hmem].
Qed.

(** The step_entry hit postcondition: the head register equals the head cell,
    the state/halt cells are the [action_run] projections, and every other
    non-control cell is framed. *)
Lemma step_entry_hit_projections :
  vm_reg (step_entry vm table table_base) 2 =
    vm_mem (step_entry vm table table_base) action_head_addr /\
  vm_mem (step_entry vm table table_base) action_state_addr = nth 4 row 1 /\
  vm_mem (step_entry vm table table_base) action_halt_addr =
    (if Nat.eqb (nth 5 row 1) 0 then vm_mem vm action_halt_addr else 1) /\
  (forall k, k <> vm_mem vm tape_base_addr + vm_reg vm 2 ->
    k <> action_head_addr -> k <> action_state_addr -> k <> action_halt_addr ->
    vm_mem (step_entry vm table table_base) k = vm_mem vm k).
Proof.
  pose proof step_entry_hit_rel as Hrel.
  unfold nstate_rel in Hrel.
  destruct Hrel as [Hs [Hh [Hl Hmem]]].
  repeat split.
  - change (n_head (vm_to_nstate (step_entry vm table table_base)) =
      n_mem (vm_to_nstate (step_entry vm table table_base)) action_head_addr).
    rewrite Hh, (Hmem action_head_addr).
    apply (hit_nstate_head_mem table_base
      (vm_mem vm tape_base_addr + vm_reg vm 2) (vm_reg vm 2) (vm_mem vm) row
      Hdist_head Hdist_state Hdist_halt).
  - change (n_mem (vm_to_nstate (step_entry vm table table_base))
      action_state_addr = nth 4 row 1).
    rewrite (Hmem action_state_addr).
    apply (hit_nstate_state_cell table_base
      (vm_mem vm tape_base_addr + vm_reg vm 2) (vm_reg vm 2) (vm_mem vm) row
      Hdist_head Hdist_state Hdist_halt).
  - change (n_mem (vm_to_nstate (step_entry vm table table_base))
      action_halt_addr =
      (if Nat.eqb (nth 5 row 1) 0 then vm_mem vm action_halt_addr else 1)).
    rewrite (Hmem action_halt_addr).
    apply (hit_nstate_halt_cell table_base
      (vm_mem vm tape_base_addr + vm_reg vm 2) (vm_reg vm 2) (vm_mem vm) row
      Hdist_head Hdist_state Hdist_halt).
  - intros k Ht Hh' Hs' Hl'.
    change (n_mem (vm_to_nstate (step_entry vm table table_base)) k = vm_mem vm k).
    rewrite (Hmem k).
    apply (hit_nstate_frame table_base
      (vm_mem vm tape_base_addr + vm_reg vm 2) (vm_reg vm 2) (vm_mem vm) row k
      Ht Hh' Hs' Hl').
Qed.

End StepEntryHit.

(** ** [step_entry] keeps the machine running in the hit case *)

Section StepEntryHalted.

Variables (vm : VM) (table_base : nat) (table : list (list nat)).

Hypothesis Hr0 : vm_reg vm 0 = 0.
Hypothesis Hr2loc : vm_reg vm 2 = vm_mem vm action_head_addr.
Hypothesis Hr13 : vm_reg vm 13 = 1.
Hypothesis Hhalt : vm_halted vm = false.
Hypothesis Hlen : length table = 184.
Hypothesis Hshort : Forall (fun r => 0 < length r /\ 1 < length r) table.
Hypothesis Hlen8 : Forall (fun r => length r = 8) table.
Hypothesis Hmemtab : table_mem_at table_base table (vm_mem vm).
Hypothesis Hlayout : forall j0 row0,
  scan_index_from 0 (vm_mem vm action_state_addr)
    (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table = Some (j0, row0) ->
  (forall f, f < 8 -> table_base + 8 * j0 + f <>
    vm_mem vm tape_base_addr + vm_reg vm 2) /\
  action_head_addr <> table_base + 8 * j0 + 4 /\
  action_state_addr <> table_base + 8 * j0 + 5 /\
  action_head_addr <> table_base + 8 * j0 + 5.
Hypothesis Hhaltcell : vm_mem vm action_halt_addr = 0.

(** The halted flag is not part of [nstate_rel], so this needs the concrete
    prelude facts and [native_step_halted] rather than just
    [step_entry_spec]. *)
Lemma step_entry_hit_halted :
  vm_halted (step_entry vm table table_base) = false.
Proof.
  unfold step_entry.
  assert (Ehalt : Nat.eqb (vm_mem vm action_halt_addr) 0 = true)
    by (apply Nat.eqb_eq; exact Hhaltcell).
  rewrite Ehalt.
  set (vp := run_until 11 (prelude_block table_base) (fun _ => false)
              (restart vm)).
  assert (Hpc_r : vm_pc (restart vm) = 0)
    by (unfold restart; reflexivity).
  assert (Hr0r : vm_reg (restart vm) 0 = 0)
    by (unfold restart; exact Hr0).
  assert (Hr13r : vm_reg (restart vm) 13 = 1)
    by (unfold restart; exact Hr13).
  assert (Hhaltr : vm_halted (restart vm) = false)
    by (unfold restart; exact Hhalt).
  assert (Ehaltr : vm_mem (restart vm) action_halt_addr = 0).
  { unfold restart. exact Hhaltcell. }
  pose proof (prelude_ready table_base (restart vm) Hpc_r Hr0r Hr13r
    Hhaltr Ehaltr) as Hpre.
  cbn zeta in Hpre. fold vp in Hpre.
  destruct Hpre as [Hpcp [Hr1p [Hr2p [Hr3p [Hr4p [Hr5p [Hr6p
    [Hr8p [Hr0p [Hr13p [Hmemp Hhaltp]]]]]]]]]]].
  assert (Hmemr : vm_mem (restart vm) = vm_mem vm)
    by (unfold restart; reflexivity).
  rewrite Hmemr in Hr1p, Hr2p, Hr3p, Hr4p, Hmemp.
  set (vscan := restart vp).
  assert (Hr2s : vm_reg vscan 2 = vm_reg vm 2).
  { unfold vscan, restart. change (vm_reg vp 2 = vm_reg vm 2).
    rewrite Hr2p. symmetry. exact Hr2loc. }
  assert (Hr3s : vm_reg vscan 3 =
      vm_mem vm tape_base_addr + vm_reg vscan 2).
  { unfold vscan, restart.
    change (vm_reg vp 3 = vm_mem vm tape_base_addr + vm_reg vp 2).
    rewrite Hr3p, Hr2p. reflexivity. }
  assert (Hr0s : vm_reg vscan 0 = 0).
  { unfold vscan, restart. change (vm_reg vp 0 = 0). exact Hr0p. }
  assert (Hr13s : vm_reg vscan 13 = 1).
  { unfold vscan, restart. change (vm_reg vp 13 = 1). exact Hr13p. }
  assert (Hhalts : vm_halted vscan = false).
  { unfold vscan, restart. change (vm_halted vp = false). exact Hhaltp. }
  assert (Hmems : vm_mem vscan = vm_mem vm).
  { unfold vscan, restart. change (vm_mem vp = vm_mem vm). exact Hmemp. }
  assert (Hready : scan_ready vscan 0 (vm_mem vscan action_state_addr)
      (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2))
      table_base (vm_mem vscan)).
  { unfold scan_ready. split; [reflexivity|].
    split.
    { unfold vscan, restart.
      change (vm_reg vp 1 = vm_mem vp action_state_addr).
      rewrite Hr1p, Hmemp. reflexivity. }
    split.
    { unfold vscan, restart.
      change (vm_reg vp 4 =
        vm_mem vp (vm_mem vm tape_base_addr + vm_reg vp 2)).
      rewrite Hr4p, Hmemp, Hr3p, Hr2p. reflexivity. }
    split.
    { unfold vscan, restart. change (vm_reg vp 5 = table_base). exact Hr5p. }
    split.
    { unfold vscan, restart. change (vm_reg vp 6 = 184). exact Hr6p. }
    split.
    { unfold vscan, restart. change (vm_reg vp 8 = 0). exact Hr8p. }
    split.
    { unfold vscan, restart. change (vm_reg vp 13 = 1). exact Hr13p. }
    split; [reflexivity|].
    { unfold vscan, restart. change (vm_halted vp = false). exact Hhaltp. } }
  assert (Hlayout_v : forall j0 row0,
    scan_index_from 0 (vm_mem vscan action_state_addr)
      (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2)) table =
      Some (j0, row0) ->
    (forall f, f < 8 -> table_base + 8 * j0 + f <>
      vm_mem vm tape_base_addr + vm_reg vscan 2) /\
    action_head_addr <> table_base + 8 * j0 + 4 /\
    action_state_addr <> table_base + 8 * j0 + 5 /\
    action_head_addr <> table_base + 8 * j0 + 5).
  { intros j0 row0 Hsome.
    rewrite Hmems, Hr2s in Hsome.
    destruct (Hlayout j0 row0 Hsome) as [Hdis [Hhead4 [Hstate5 Hhead5]]].
    split; [|split; [|split]].
    - intros f Hf. rewrite Hr2s. apply Hdis. exact Hf.
    - exact Hhead4.
    - exact Hstate5.
    - exact Hhead5. }
  assert (Hmemtab_v : table_mem_at table_base table (vm_mem vscan)).
  { rewrite Hmems. exact Hmemtab. }
  assert (Hhaltcell_v : vm_mem vscan action_halt_addr = 0).
  { rewrite Hmems. exact Hhaltcell. }
  change (vm_halted (native_step vscan table table_base
    (vm_mem vm tape_base_addr)) = false).
  apply (native_step_halted vscan (vm_mem vscan action_state_addr)
    (vm_reg vscan 2) table_base (vm_mem vm tape_base_addr) table
    (vm_mem vscan) Hlen Hshort Hlen8 Hmemtab_v Hready eq_refl Hr3s
    Hr0s Hhaltcell_v Hlayout_v).
Qed.

End StepEntryHalted.
