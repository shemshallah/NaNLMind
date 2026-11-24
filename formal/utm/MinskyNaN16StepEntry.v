From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16Prelude MinskyNaN16PreludeReady MinskyNaN16Step.

Definition to_scan (vm : VM) : VM :=
  {| vm_pc := 0; vm_reg := vm_reg vm; vm_mem := vm_mem vm;
     vm_zf := vm_zf vm; vm_lf := vm_lf vm; vm_halted := vm_halted vm;
     vm_link := vm_link vm |}.

(** The not-halted step-entry path: run the prelude, reset pc to the scan
    entry, and run one native step on the loaded state. *)

Lemma step_entry_nohalt :
  forall (vm : VM) (table_base : nat) (table : list (list nat)),
    vm_pc vm = 0 ->
    vm_reg vm 0 = 0 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_mem vm action_halt_addr = 0 ->
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_mem_at table_base table (vm_mem vm) ->
    (forall j row,
      scan_index_from 0 (vm_mem vm action_state_addr)
        (vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr))
        table = Some (j, row) ->
      (forall f, f < 8 -> table_base + 8 * j + f <>
        vm_mem vm tape_base_addr + vm_mem vm action_head_addr) /\
      action_head_addr <> table_base + 8 * j + 4 /\
      action_state_addr <> table_base + 8 * j + 5 /\
      action_head_addr <> table_base + 8 * j + 5) ->
    let vp := run_until 11 (prelude_block table_base) (fun _ => false) vm in
    let vscan := to_scan vp in
    match scan_index_from 0 (vm_mem vm action_state_addr)
      (vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr))
      table with
    | Some (j, row) =>
        vm_pc (native_step vscan table table_base (vm_mem vm tape_base_addr)) = 22 /\
        vm_reg (native_step vscan table table_base (vm_mem vm tape_base_addr)) 2 =
          action_new_head (vm_mem vm action_head_addr) (nth 3 row 0) /\
        vm_reg (native_step vscan table table_base (vm_mem vm tape_base_addr)) 0 = 0 /\
        vm_reg (native_step vscan table table_base (vm_mem vm tape_base_addr)) 7 =
          table_base + 8 * j /\
        vm_halted (native_step vscan table table_base (vm_mem vm tape_base_addr)) = false /\
        (forall k,
          vm_mem (native_step vscan table table_base (vm_mem vm tape_base_addr)) k =
          snd (action_run (table_base + 8 * j)
            (vm_mem vm tape_base_addr + vm_mem vm action_head_addr)
            (vm_mem vm action_head_addr) (vm_mem vm) row) k)
    | None =>
        vm_pc (native_step vscan table table_base (vm_mem vm tape_base_addr)) = 2 /\
        vm_mem (native_step vscan table table_base (vm_mem vm tape_base_addr)) =
          set_mem (vm_mem vm) action_halt_addr 1 /\
        vm_reg (native_step vscan table table_base (vm_mem vm tape_base_addr)) 2 =
          vm_mem vm action_head_addr /\
        vm_reg (native_step vscan table table_base (vm_mem vm tape_base_addr)) 0 = 0 /\
        vm_halted (native_step vscan table table_base (vm_mem vm tape_base_addr)) = false
    end.
Proof.
  intros vm table_base table
    Hpc Hr0 Hr13 Hhalt Hhaltcell Hlen Hshort Hlen8 Hmemtab Hlayout.
  set (vp := run_until 11 (prelude_block table_base) (fun _ => false) vm).
  pose proof (prelude_ready table_base vm Hpc Hr0 Hr13 Hhalt Hhaltcell) as Hpre.
  cbn zeta in Hpre. fold vp in Hpre.
  destruct Hpre as [Hpcp [Hr1p [Hr2p [Hr3p [Hr4p [Hr5p [Hr6p
    [Hr8p [Hr0p [Hr13p [Hmemp Hhaltp]]]]]]]]]]].
  assert (Hr3p' : vm_reg vp 3 =
      vm_mem vm tape_base_addr + vm_mem vm action_head_addr)
    by (rewrite Hr3p, Hr2p; reflexivity).
  assert (Hr4p' : vm_reg vp 4 =
      vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr))
    by (rewrite Hr4p, Hr3p'; reflexivity).
  set (vscan := to_scan vp).
  assert (Hready : scan_ready vscan 0 (vm_mem vm action_state_addr)
      (vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr))
      table_base (vm_mem vm)).
  { unfold scan_ready.
    split; [unfold vscan, to_scan; reflexivity|].
    split; [unfold vscan, to_scan; exact Hr1p|].
    split; [unfold vscan, to_scan; exact Hr4p'|].
    split; [unfold vscan, to_scan; exact Hr5p|].
    split; [unfold vscan, to_scan; exact Hr6p|].
    split; [unfold vscan, to_scan; exact Hr8p|].
    split; [unfold vscan, to_scan; exact Hr13p|].
    split; [unfold vscan, to_scan; exact Hmemp|].
    unfold vscan, to_scan; exact Hhaltp. }
  assert (Hr2s : vm_reg vscan 2 = vm_mem vm action_head_addr)
    by (unfold vscan, to_scan; cbn; exact Hr2p).
  assert (Hr3s : vm_reg vscan 3 =
      vm_mem vm tape_base_addr + vm_mem vm action_head_addr)
    by (unfold vscan, to_scan; cbn; exact Hr3p').
  assert (Hr0s : vm_reg vscan 0 = 0)
    by (unfold vscan, to_scan; cbn; exact Hr0p).
  assert (Hmems : vm_mem vscan action_halt_addr = 0)
    by (unfold vscan, to_scan; cbn; rewrite Hmemp; exact Hhaltcell).
  apply (native_step_refines vscan (vm_mem vm action_state_addr)
    (vm_mem vm action_head_addr) table_base (vm_mem vm tape_base_addr)
    table (vm_mem vm) Hlen Hshort Hlen8 Hmemtab Hready Hr2s Hr3s Hr0s
    Hmems Hlayout).
Qed.
