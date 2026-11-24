From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ActionRun MinskyNaN16Step MinskyNaN16ScanPhase.

Record NState := {
  n_state : nat;
  n_head : nat;
  n_halt : nat;
  n_mem : Mem
}.

Definition vm_to_nstate (vm : VM) : NState :=
  {| n_state := vm_mem vm action_state_addr;
     n_head := vm_reg vm 2;
     n_halt := vm_mem vm action_halt_addr;
     n_mem := vm_mem vm |}.

Definition hit_nstate (table_base tape_addr head : nat) (m : Mem)
    (row : list nat) : NState :=
  let res := action_run table_base tape_addr head m row in
  {| n_state := snd res action_state_addr;
     n_head := fst res;
     n_halt := snd res action_halt_addr;
     n_mem := snd res |}.

Definition nstep (table : list (list nat)) (table_base tape_base : nat)
    (c : NState) : NState :=
  if Nat.eqb (n_halt c) 0 then
    match scan_index_from 0 (n_state c) (n_mem c (tape_base + n_head c)) table with
    | Some (j, row) =>
        hit_nstate table_base (tape_base + n_head c) (n_head c) (n_mem c) row
    | None =>
        {| n_state := n_state c; n_head := n_head c; n_halt := 1;
           n_mem := set_mem (n_mem c) action_halt_addr 1 |}
    end
  else c.

Definition nstate_rel (a b : NState) : Prop :=
  n_state a = n_state b /\
  n_head a = n_head b /\
  n_halt a = n_halt b /\
  (forall k, n_mem a k = n_mem b k).

Lemma nstep_active_hit :
  forall table table_base tape_base c j row,
    n_halt c = 0 ->
    scan_index_from 0 (n_state c) (n_mem c (tape_base + n_head c)) table =
      Some (j, row) ->
    nstep table table_base tape_base c =
      hit_nstate table_base (tape_base + n_head c) (n_head c) (n_mem c) row.
Proof.
  intros. unfold nstep. rewrite H. cbn. rewrite H0. reflexivity.
Qed.

Lemma nstep_active_none :
  forall table table_base tape_base c,
    n_halt c = 0 ->
    scan_index_from 0 (n_state c) (n_mem c (tape_base + n_head c)) table = None ->
    nstep table table_base tape_base c =
      {| n_state := n_state c; n_head := n_head c; n_halt := 1;
         n_mem := set_mem (n_mem c) action_halt_addr 1 |}.
Proof.
  intros. unfold nstep. rewrite H, H0. reflexivity.
Qed.

Lemma native_step_spec_active :
  forall (vm : VM) (table_base tape_base : nat) (table : list (list nat)),
    vm_pc vm = 0 ->
    vm_reg vm 0 = 0 ->
    vm_reg vm 3 = tape_base + vm_reg vm 2 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_mem vm action_halt_addr = 0 ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_mem_at table_base table (vm_mem vm) ->
    scan_ready vm 0 (vm_mem vm action_state_addr)
      (vm_mem vm (tape_base + vm_reg vm 2)) table_base (vm_mem vm) ->
    (forall j row,
      scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (tape_base + vm_reg vm 2)) table = Some (j, row) ->
      (forall f, f < 8 -> table_base + 8 * j + f <>
        tape_base + vm_reg vm 2) /\
      action_head_addr <> table_base + 8 * j + 4 /\
      action_state_addr <> table_base + 8 * j + 5 /\
      action_head_addr <> table_base + 8 * j + 5) ->
    nstate_rel (vm_to_nstate (native_step vm table table_base tape_base))
      (nstep table table_base tape_base (vm_to_nstate vm)).
Proof.
  intros vm table_base tape_base table
    Hpc Hr0 Hr3 Hr13 Hhalt Hhaltcell Hlen Hshort Hlen8 Hmemtab Hready Hlayout.
  destruct (scan_index_from 0 (vm_mem vm action_state_addr)
    (vm_mem vm (tape_base + vm_reg vm 2)) table) as [[j row]|] eqn:Eidx.
  - assert (Hlayout_new : forall j0 row0,
      scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (tape_base + vm_reg vm 2)) table = Some (j0, row0) ->
      (forall f, f < 8 -> table_base + 8 * j0 + f <>
        tape_base + vm_reg vm 2) /\
      action_head_addr <> table_base + 8 * j0 + 4 /\
      action_state_addr <> table_base + 8 * j0 + 5 /\
      action_head_addr <> table_base + 8 * j0 + 5).
    { intros j0 row0 Hsome. apply (Hlayout j0 row0). rewrite <- Eidx. exact Hsome. }
    pose proof (native_step_refines vm (vm_mem vm action_state_addr)
      (vm_reg vm 2) table_base tape_base table (vm_mem vm)
      Hlen Hshort Hlen8 Hmemtab Hready eq_refl Hr3 Hr0 Hhaltcell Hlayout_new) as H.
    rewrite Eidx in H. cbn in H.
    destruct H as [Hpc' [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
    assert (Hn_halt : n_halt (vm_to_nstate vm) = 0)
      by (unfold vm_to_nstate; cbn; exact Hhaltcell).
    rewrite (nstep_active_hit table table_base tape_base (vm_to_nstate vm)
      j row Hn_halt Eidx).
    assert (Hlenrow : length row = 8).
    { apply (scan_index_from_length 0 (vm_mem vm action_state_addr)
        (vm_mem vm (tape_base + vm_reg vm 2)) table j row Eidx Hlen8). }
    assert (Hnth3 : nth 3 row 1 = nth 3 row 0).
    { apply nth_indep. rewrite Hlenrow. lia. }
    unfold nstate_rel. split; [|split; [|split]].
    + unfold vm_to_nstate, hit_nstate. cbn. rewrite (Hmem' action_state_addr). reflexivity.
    + unfold vm_to_nstate, hit_nstate. cbn. rewrite Hr2', Hnth3. reflexivity.
    + unfold vm_to_nstate, hit_nstate. cbn. rewrite (Hmem' action_halt_addr). reflexivity.
    + intro k. unfold vm_to_nstate, hit_nstate. cbn. rewrite (Hmem' k). reflexivity.
  - assert (Hlayout_new : forall j0 row0,
      scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (tape_base + vm_reg vm 2)) table = Some (j0, row0) ->
      (forall f, f < 8 -> table_base + 8 * j0 + f <>
        tape_base + vm_reg vm 2) /\
      action_head_addr <> table_base + 8 * j0 + 4 /\
      action_state_addr <> table_base + 8 * j0 + 5 /\
      action_head_addr <> table_base + 8 * j0 + 5).
    { intros j0 row0 Hsome. rewrite Eidx in Hsome. discriminate. }
    pose proof (native_step_refines vm (vm_mem vm action_state_addr)
      (vm_reg vm 2) table_base tape_base table (vm_mem vm)
      Hlen Hshort Hlen8 Hmemtab Hready eq_refl Hr3 Hr0 Hhaltcell Hlayout_new) as H.
    rewrite Eidx in H. cbn in H.
    destruct H as [Hpc' [Hmem' [Hr2' [Hr0' Hhalt']]]].
    assert (Hn_halt : n_halt (vm_to_nstate vm) = 0)
      by (unfold vm_to_nstate; cbn; exact Hhaltcell).
    rewrite (nstep_active_none table table_base tape_base (vm_to_nstate vm)
      Hn_halt Eidx).
    unfold nstate_rel. split; [|split; [|split]].
    + unfold vm_to_nstate. cbn. rewrite Hmem'.
      rewrite (set_mem_neq (vm_mem vm) action_halt_addr 1 action_state_addr)
        by (unfold action_state_addr, action_halt_addr; lia).
      reflexivity.
    + unfold vm_to_nstate. cbn. rewrite Hr2'. reflexivity.
    + unfold vm_to_nstate. cbn. rewrite Hmem'. apply set_mem_same.
    + intro k. unfold vm_to_nstate. cbn. rewrite Hmem'. reflexivity.
Qed.

Lemma nstep_halted :
  forall table table_base tape_base c,
    n_halt c <> 0 ->
    nstep table table_base tape_base c = c.
Proof.
  intros. unfold nstep.
  assert (E : Nat.eqb (n_halt c) 0 = false)
    by (apply Nat.eqb_neq; exact H).
  rewrite E. reflexivity.
Qed.

Lemma set_mem_rel :
  forall (m1 m2 : Mem) (a v : nat),
    (forall k, m1 k = m2 k) ->
    forall k, set_mem m1 a v k = set_mem m2 a v k.
Proof.
  intros. unfold set_mem. destruct (Nat.eqb k a); [reflexivity|apply H].
Qed.

Lemma action_run_mem_rel :
  forall row_addr tape_addr head (m1 m2 : Mem) row,
    (forall k, m1 k = m2 k) ->
    forall k,
      snd (action_run row_addr tape_addr head m1 row) k =
      snd (action_run row_addr tape_addr head m2 row) k.
Proof.
  intros row_addr tape_addr head m1 m2 row H k.
  unfold action_run. cbn.
  destruct (Nat.eqb (nth 5 row 1) 0); cbn;
    repeat (apply set_mem_rel); assumption.
Qed.

Lemma nstep_congr :
  forall table table_base tape_base a b,
    nstate_rel a b ->
    nstate_rel (nstep table table_base tape_base a)
      (nstep table table_base tape_base b).
Proof.
  intros table table_base tape_base a b Hab.
  pose proof Hab as Hrel.
  unfold nstate_rel in Hab.
  destruct Hab as [Hs [Hh [Hl Hm]]].
  unfold nstep. rewrite Hs, Hh, Hl.
  destruct (Nat.eqb (n_halt b) 0) eqn:Eh.
  - rewrite (Hm (tape_base + n_head b)).
    destruct (scan_index_from 0 (n_state b) (n_mem b (tape_base + n_head b)) table)
      as [[j row]|].
    + unfold nstate_rel, hit_nstate. cbn.
      pose proof (action_run_mem_rel table_base (tape_base + n_head b)
        (n_head b) (n_mem a) (n_mem b) row Hm) as Hr.
      split; [exact (Hr action_state_addr)|].
      split; [reflexivity|].
      split; [exact (Hr action_halt_addr)|exact Hr].
    + unfold nstate_rel. cbn. split; [reflexivity|split; [reflexivity|split; [reflexivity|]]].
      intro k. apply set_mem_rel. exact Hm.
  - exact Hrel.
Qed.
