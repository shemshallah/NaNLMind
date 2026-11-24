From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ActionMove MinskyNaN16StepHit MinskyNaN16StepNone.

Definition step_scan_fuel (table : list (list nat)) : nat :=
  12 * length table + 14.

Definition step_hit_fuel (row : list nat) : nat :=
  5 + action_move_fuel (nth 3 row 0) + 8.

Definition native_step (vm : VM) (table : list (list nat))
    (table_base tape_base : nat) : VM :=
  let state := vm_reg vm 1 in
  let head := vm_reg vm 2 in
  let sym := vm_mem vm (tape_base + head) in
  let vs := run_until (step_scan_fuel table) scan_block scan_stop vm in
  match scan_index_from 0 state sym table with
  | Some (j, row) =>
      run_until (step_hit_fuel row) action_block action_stop
        (action_init vs)
  | None =>
      run_until 2 no_trans_block no_trans_stop (no_trans_init vs)
  end.

Lemma scan_index_vm_eq :
  forall vm state head table_base tape_base table m,
    scan_ready vm 0 state (m (tape_base + head)) table_base m ->
    vm_reg vm 2 = head ->
    scan_index_from 0 (vm_reg vm 1)
      (vm_mem vm (tape_base + vm_reg vm 2)) table =
    scan_index_from 0 state (m (tape_base + head)) table.
Proof.
  intros vm state head table_base tape_base table m Hready Hr2.
  unfold scan_ready in Hready.
  destruct Hready as [Hpc [Hr1 [Hr4 [Hr5 [Hr6 [Hr8 [Hr13 [Hmem Hhalt]]]]]]]].
  rewrite Hr1, Hr2, Hmem. reflexivity.
Qed.

Lemma native_step_hit :
  forall vm table table_base tape_base j row,
    scan_index_from 0 (vm_reg vm 1)
      (vm_mem vm (tape_base + vm_reg vm 2)) table = Some (j, row) ->
    native_step vm table table_base tape_base =
      run_until (step_hit_fuel row) action_block action_stop
        (action_init (run_until (step_scan_fuel table)
          scan_block scan_stop vm)).
Proof.
  intros. unfold native_step, step_scan_fuel. rewrite H. reflexivity.
Qed.

Lemma native_step_none :
  forall vm table table_base tape_base,
    scan_index_from 0 (vm_reg vm 1)
      (vm_mem vm (tape_base + vm_reg vm 2)) table = None ->
    native_step vm table table_base tape_base =
      run_until 2 no_trans_block no_trans_stop
        (no_trans_init (run_until (step_scan_fuel table)
          scan_block scan_stop vm)).
Proof.
  intros. unfold native_step, step_scan_fuel. rewrite H. reflexivity.
Qed.

Lemma native_step_refines :
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
    match scan_index_from 0 state (m (tape_base + head)) table with
    | Some (j, row) =>
        vm_pc (native_step vm table table_base tape_base) = 22 /\
        vm_reg (native_step vm table table_base tape_base) 2 =
          action_new_head head (nth 3 row 0) /\
        vm_reg (native_step vm table table_base tape_base) 0 = 0 /\
        vm_reg (native_step vm table table_base tape_base) 7 =
          table_base + 8 * j /\
        vm_halted (native_step vm table table_base tape_base) = false /\
        (forall k,
          vm_mem (native_step vm table table_base tape_base) k =
          snd (action_run (table_base + 8 * j) (tape_base + head)
            head m row) k)
    | None =>
        vm_pc (native_step vm table table_base tape_base) = 2 /\
        vm_mem (native_step vm table table_base tape_base) =
          set_mem m action_halt_addr 1 /\
        vm_reg (native_step vm table table_base tape_base) 2 = head /\
        vm_reg (native_step vm table table_base tape_base) 0 = 0 /\
        vm_halted (native_step vm table table_base tape_base) = false
    end.
Proof.
  intros vm state head table_base tape_base table m
    Hlen Hshort Hlen8 Hmemtab Hready Hr2 Hr3 Hr0 Hhaltcell Hlayout.
  destruct (scan_index_from 0 state (m (tape_base + head)) table)
    as [[j row]|] eqn:Eidx.
  - assert (Eidx_vm : scan_index_from 0 (vm_reg vm 1)
      (vm_mem vm (tape_base + vm_reg vm 2)) table = Some (j, row)).
    { rewrite (scan_index_vm_eq vm state head table_base tape_base table m
        Hready Hr2). exact Eidx. }
    destruct (Hlayout j row eq_refl) as [Hdis [Hhead4 [Hstate5 Hhead5]]].
    rewrite (native_step_hit vm table table_base tape_base j row Eidx_vm).
    apply (step_hit_phase vm state head table_base tape_base table m j row
      Hlen Hshort Hlen8 Hmemtab Hready Hr2 Hr3 Hr0 Eidx Hdis Hhead4 Hstate5 Hhead5).
  - assert (Eidx_vm : scan_index_from 0 (vm_reg vm 1)
      (vm_mem vm (tape_base + vm_reg vm 2)) table = None).
    { rewrite (scan_index_vm_eq vm state head table_base tape_base table m
        Hready Hr2). exact Eidx. }
    rewrite (native_step_none vm table table_base tape_base Eidx_vm).
    apply (step_none_phase vm state head table_base tape_base table m
      Hlen Hshort Hmemtab Hready Hr2 Hr3 Hr0 Eidx).
Qed.
