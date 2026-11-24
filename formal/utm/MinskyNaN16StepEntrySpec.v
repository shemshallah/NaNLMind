From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16Prelude MinskyNaN16PreludeReady MinskyNaN16Step
  MinskyNaN16StepSpec.

(** Keep the phase functions opaque: their internal matches are huge, and
    all composition below goes through the proved specifications. *)
Opaque native_step nstep.

Definition restart (vm : VM) : VM :=
  {| vm_pc := 0; vm_reg := vm_reg vm; vm_mem := vm_mem vm;
     vm_zf := vm_zf vm; vm_lf := vm_lf vm; vm_halted := vm_halted vm;
     vm_link := vm_link vm |}.

Definition step_entry (vm : VM) (table : list (list nat))
    (table_base : nat) : VM :=
  if Nat.eqb (vm_mem vm action_halt_addr) 0 then
    native_step
      (restart (run_until 11 (prelude_block table_base) (fun _ => false)
        (restart vm)))
      table table_base (vm_mem vm tape_base_addr)
  else
    run_until 3 (prelude_block table_base) (fun _ => false) (restart vm).

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
  destruct (Nat.eqb (vm_mem vm action_halt_addr) 0) eqn:Ehalt.
  - apply Nat.eqb_eq in Ehalt.
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
    pose proof (prelude_ready table_base (restart vm) Hpc_r Hr0r Hr13r
      Hhaltr Ehalt) as Hpre.
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
    assert (Hidx : scan_index_from 0 (vm_mem vscan action_state_addr)
        (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2)) table =
        scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table).
    { unfold vscan, restart.
      change (scan_index_from 0 (vm_mem vp action_state_addr)
        (vm_mem vp (vm_mem vm tape_base_addr + vm_reg vp 2)) table =
        scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (vm_mem vm tape_base_addr + vm_reg vm 2)) table).
      rewrite Hmemp, Hr2p, Hr2loc. reflexivity. }
    assert (Hlayout_v : forall j row,
      scan_index_from 0 (vm_mem vscan action_state_addr)
        (vm_mem vscan (vm_mem vm tape_base_addr + vm_reg vscan 2)) table =
        Some (j, row) ->
      (forall f, f < 8 -> table_base + 8 * j + f <>
        vm_mem vm tape_base_addr + vm_reg vscan 2) /\
      action_head_addr <> table_base + 8 * j + 4 /\
      action_state_addr <> table_base + 8 * j + 5 /\
      action_head_addr <> table_base + 8 * j + 5).
    { intros j row Hsome. rewrite Hr2s. apply (Hlayout j row).
      rewrite <- Hidx. exact Hsome. }
    pose proof (native_step_spec_active vscan table_base
      (vm_mem vm tape_base_addr) table
      ltac:(unfold vscan, restart; reflexivity)
      Hr0s Hr3s Hr13s Hhalts ltac:(rewrite Hmems; exact Ehalt) Hlen Hshort Hlen8
      ltac:(rewrite Hmems; exact Hmemtab) Hready Hlayout_v) as Hspec.
    eapply nstate_rel_trans.
    + exact Hspec.
    + apply nstep_congr.
      unfold nstate_rel. split.
      * change (vm_mem vp action_state_addr = vm_mem vm action_state_addr).
        rewrite Hmemp. reflexivity.
      * split.
        -- change (vm_reg vp 2 = vm_reg vm 2).
           rewrite Hr2p. symmetry. exact Hr2loc.
        -- split.
           ++ change (vm_mem vp action_halt_addr = vm_mem vm action_halt_addr).
              rewrite Hmemp. reflexivity.
           ++ intro k. change (vm_mem vp k = vm_mem vm k).
              rewrite Hmemp. reflexivity.
  - assert (Hne : vm_mem vm action_halt_addr <> 0).
    { intro E. apply Nat.eqb_neq in Ehalt. exact (Ehalt E). }
    set (vp := run_until 3 (prelude_block table_base) (fun _ => false)
                (restart vm)).
    assert (Hpc_r : vm_pc (restart vm) = 0)
      by (unfold restart; reflexivity).
    assert (Hr0r : vm_reg (restart vm) 0 = 0)
      by (unfold restart; exact Hr0).
    assert (Hr13r : vm_reg (restart vm) 13 = 1)
      by (unfold restart; exact Hr13).
    assert (Hhaltr : vm_halted (restart vm) = false)
      by (unfold restart; exact Hhalt).
    pose proof (prelude_halted table_base (restart vm) Hpc_r Hr0r Hr13r
      Hhaltr Hne) as Hpre.
    cbn zeta in Hpre. fold vp in Hpre.
    destruct Hpre as [Hpcp [Hr1p [Hr2p [Hr0p [Hr13p [Hmemp Hhaltp]]]]]].
    assert (Hmemr : vm_mem (restart vm) = vm_mem vm)
      by (unfold restart; reflexivity).
    rewrite Hmemr in Hmemp.
    fold vp in Hmemp, Hr2p.
    rewrite (nstep_halted table table_base (vm_mem vm tape_base_addr)
      (vm_to_nstate vm) Hne).
    unfold nstate_rel. split.
    + unfold vm_to_nstate. rewrite Hmemp. reflexivity.
    + split.
      * unfold vm_to_nstate. rewrite Hr2p. unfold restart. reflexivity.
      * split.
        -- unfold vm_to_nstate. rewrite Hmemp. reflexivity.
        -- intro k. unfold vm_to_nstate. rewrite Hmemp. reflexivity.
Qed.
