From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16Prelude MinskyNaN16PreludeReady MinskyNaN16Step
  MinskyNaN16StepSpec.

Definition restart (vm : VM) : VM :=
  {| vm_pc := 0; vm_reg := vm_reg vm; vm_mem := vm_mem vm;
     vm_zf := vm_zf vm; vm_lf := vm_lf vm; vm_halted := vm_halted vm;
     vm_link := vm_link vm |}.

Definition step_entry (vm : VM) (table : list (list nat))
    (table_base : nat) : VM :=
  let vp := run_until 11 (prelude_block table_base) (fun _ => false)
              (restart vm) in
  if Nat.eqb (vm_mem vm action_halt_addr) 0 then
    native_step (restart vp) table table_base (vm_mem vm tape_base_addr)
  else vp.

Lemma nstate_rel_refl : forall a, nstate_rel a a.
Proof. intro a. unfold nstate_rel. repeat split; reflexivity. Qed.

Lemma nstate_rel_trans :
  forall a b c, nstate_rel a b -> nstate_rel b c -> nstate_rel a c.
Proof.
  intros a b c Hab Hbc. unfold nstate_rel in *.
  destruct Hab as [Hs [Hh [Hl Hm]]].
  destruct Hbc as [Hs' [Hh' [Hl' Hm']]].
  split; [rewrite Hs, Hs'; reflexivity|].
  split; [rewrite Hh, Hh'; reflexivity|].
  split; [rewrite Hl, Hl'; reflexivity|].
  intro k. rewrite Hm, Hm'. reflexivity.
Qed.

(** A not-halted step entry: prelude, then the native step, refines [nstep].
    The entry invariant is only that the head register and head cell agree. *)

Lemma step_entry_spec :
  forall (vm : VM) (table_base : nat) (table : list (list nat)),
    vm_reg vm 0 = 0 ->
    vm_reg vm 2 = vm_mem vm action_head_addr ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_mem_at table_base table (vm_mem vm) ->
    (forall j row,
      scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table = Some (j, row) ->
      (forall f, f < 8 -> table_base + 8 * j + f <>
        vm_mem vm tape_base_addr + vm_reg vm 2) /\
      action_head_addr <> table_base + 8 * j + 4 /\
      action_state_addr <> table_base + 8 * j + 5 /\
      action_head_addr <> table_base + 8 * j + 5) ->
    nstate_rel (vm_to_nstate (step_entry vm table table_base))
      (nstep table table_base (vm_mem vm tape_base_addr) (vm_to_nstate vm)).
Proof.
  intros vm table_base table Hr0 Hr2loc Hr13 Hhalt
    Hlen Hshort Hlen8 Hmemtab Hlayout.
  unfold step_entry.
  set (vp := run_until 11 (prelude_block table_base) (fun _ => false)
              (restart vm)).
  destruct (Nat.eqb (vm_mem vm action_halt_addr) 0) eqn:Ehalt.
  - apply Nat.eqb_eq in Ehalt.
    assert (Hr0r : vm_reg (restart vm) 0 = 0)
      by (unfold restart; cbn; exact Hr0).
    assert (Hr13r : vm_reg (restart vm) 13 = 1)
      by (unfold restart; cbn; exact Hr13).
    assert (Hhaltr : vm_halted (restart vm) = false)
      by (unfold restart; cbn; exact Hhalt).
    assert (Hpc_r : vm_pc (restart vm) = 0)
      by (unfold restart; cbn; reflexivity).
    pose proof (prelude_ready table_base (restart vm) Hpc_r Hr0r Hr13r
      Hhaltr Ehalt) as Hpre.
    cbn zeta in Hpre. fold vp in Hpre.
    destruct Hpre as [Hpcp [Hr1p [Hr2p [Hr3p [Hr4p [Hr5p [Hr6p
      [Hr8p [Hr0p [Hr13p [Hmemp Hhaltp]]]]]]]]]]].
    assert (Hmemr : vm_mem (restart vm) = vm_mem vm)
      by (unfold restart; reflexivity).
    rewrite Hmemr in Hr1p, Hr2p, Hr3p, Hr4p, Hmemp.
    (* The prelude did not change the observable state. *)
    assert (Hvs : nstate_rel (vm_to_nstate (restart vp))
        (vm_to_nstate vm)).
    { unfold nstate_rel. split.
      - change (vm_mem vp action_state_addr = vm_mem vm action_state_addr).
        rewrite Hmemp. reflexivity.
      - split.
        + change (vm_reg vp 2 = vm_reg vm 2).
          rewrite Hr2p. symmetry. exact Hr2loc.
        + split.
          * change (vm_mem vp action_halt_addr = vm_mem vm action_halt_addr).
            rewrite Hmemp. reflexivity.
          * intro k. change (vm_mem vp k = vm_mem vm k).
            rewrite Hmemp. reflexivity. }
    set (vscan := restart vp).
    assert (Hr3s : vm_reg vscan 3 =
        vm_mem vm tape_base_addr + vm_reg vscan 2).
    { change (vm_reg vp 3 = vm_mem vm tape_base_addr + vm_reg vp 2).
      rewrite Hr3p, Hr2p. reflexivity. }
    assert (Hr0s : vm_reg vscan 0 = 0).
    { change (vm_reg vp 0 = 0). exact Hr0p. }
    assert (Hr13s : vm_reg vscan 13 = 1).
    { change (vm_reg vp 13 = 1). exact Hr13p. }
    assert (Hhalts : vm_halted vscan = false).
    { change (vm_halted vp = false). exact Hhaltp. }
    assert (Hready : scan_ready vscan 0 (vm_mem vm action_state_addr)
        (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2))
        table_base (vm_mem vm)).
    { unfold scan_ready, vscan, restart. cbn.
      split; [reflexivity|].
      split; [exact Hr1p|].
      split; [rewrite Hr4p, Hr3p, Hr2p; reflexivity|].
      split; [exact Hr5p|].
      split; [exact Hr6p|].
      split; [exact Hr8p|].
      split; [exact Hr13p|].
      split; [exact Hmemp|exact Hhaltp]. }
    pose proof (native_step_spec_active vscan table_base
      (vm_mem vm tape_base_addr) table
      (eq_refl : vm_pc vscan = 0) Hr0s Hr3s Hr13s Hhalts Ehalt
      Hlen Hshort Hlen8
      ltac:(rewrite Hmemp; exact Hmemtab) Hready Hlayout) as Hspec.
    eapply nstate_rel_trans.
    + exact Hspec.
    + apply nstep_congr. exact Hvs.
  - (* already halted: the prelude returns without touching memory or head *)
    assert (Hne : vm_mem vm action_halt_addr <> 0).
    { intro E. apply Nat.eqb_neq in Ehalt. exact (Ehalt E). }
    assert (Hr0r : vm_reg (restart vm) 0 = 0)
      by (unfold restart; cbn; exact Hr0).
    assert (Hr13r : vm_reg (restart vm) 13 = 1)
      by (unfold restart; cbn; exact Hr13).
    assert (Hhaltr : vm_halted (restart vm) = false)
      by (unfold restart; cbn; exact Hhalt).
    assert (Hpc_r : vm_pc (restart vm) = 0)
      by (unfold restart; cbn; reflexivity).
    pose proof (prelude_halted table_base (restart vm) Hpc_r Hr0r Hr13r
      Hhaltr Hne) as Hpre.
    cbn zeta in Hpre. fold vp in Hpre.
    destruct Hpre as [Hpcp [Hr1p [Hr2p [Hr0p [Hr13p [Hmemp Hhaltp]]]]]].
    rewrite Hmemp. unfold nstep. rewrite Hne. cbn.
    unfold nstate_rel, vm_to_nstate. cbn.
    split; [reflexivity|].
    split; [rewrite Hr2p; reflexivity|].
    split; [reflexivity|].
    intro k. reflexivity.
Qed.
