From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ActionMove MinskyNaN16ActionRefines MinskyNaN16ScanPhase
  MinskyNaN16Lookup.

(** One native step, hit path.  The scan is started at index 0; when it finds
    row [j], the action block is entered at pc 0 and runs to the RET at
    pc 22.  The final memory is exactly [action_run] on that row. *)

Lemma step_hit_phase :
  forall (vm : VM) (state head table_base tape_base : nat)
         (table : list (list nat)) (m : Mem) (j : nat) (row : list nat),
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    Forall (fun r => length r = 8) table ->
    table_mem_at table_base table m ->
    scan_ready vm 0 state (m (tape_base + head)) table_base m ->
    vm_reg vm 2 = head ->
    vm_reg vm 3 = tape_base + head ->
    vm_reg vm 0 = 0 ->
    scan_index_from 0 state (m (tape_base + head)) table = Some (j, row) ->
    (forall f, f < 8 -> table_base + 8 * j + f <> tape_base + head) ->
    action_head_addr <> table_base + 8 * j + 4 ->
    action_state_addr <> table_base + 8 * j + 5 ->
    action_head_addr <> table_base + 8 * j + 5 ->
    let vs := run_until (12 * length table + 14) scan_block scan_stop vm in
    let vm' := run_until (5 + action_move_fuel (nth 3 row 0) + 8)
                 action_block action_stop (action_init vs) in
    vm_pc vm' = 22 /\
    vm_reg vm' 2 = action_new_head head (nth 3 row 0) /\
    vm_reg vm' 0 = 0 /\
    vm_reg vm' 7 = table_base + 8 * j /\
    vm_halted vm' = false /\
    (forall k, vm_mem vm' k =
      snd (action_run (table_base + 8 * j) (tape_base + head) head m row) k).
Proof.
  intros vm state head table_base tape_base table m j row
    Hlen Hshort Hlen8 Hmemtab Hready Hr2 Hr3 Hr0 Hidx Hdis Hhead4 Hstate5 Hhead5.
  assert (Hmemtab0 : table_mem_at (table_base + 8 * 0) table m)
    by (replace (table_base + 8 * 0) with table_base by lia; exact Hmemtab).
  destruct (scan_phase vm 0 state (m (tape_base + head)) table_base table m
    ltac:(rewrite Hlen; lia) Hshort Hmemtab0 Hready Hr0)
    as [vs [Hrun [Hr2s [Hr3s [Hr0s [Hr13s [Hmems [Hhalts Hmatch]]]]]]]].
  cbn zeta. rewrite Hrun. cbn zeta.
  rewrite Hidx in Hmatch.
  destruct Hmatch as [Hpcs [Hr7s Hr8s]].
  assert (Hr2v : vm_reg vs 2 = head) by (rewrite Hr2s, Hr2; reflexivity).
  assert (Hr3v : vm_reg vs 3 = tape_base + head) by (rewrite Hr3s, Hr3; reflexivity).
  set (vm' := run_until (5 + action_move_fuel (nth 3 row 0) + 8)
               action_block action_stop (action_init vs)).
  assert (Hrow : row_at (table_base + 8 * j) row m).
  { apply (scan_index_from_row_at 0 state (m (tape_base + head)) table
      j row table_base m Hidx Hmemtab0). }
  assert (Hlenrow : length row = 8).
  { apply (scan_index_from_length 0 state (m (tape_base + head)) table
      j row Hidx Hlen8). }
  assert (Hready_action : action_ready (action_init vs)
      (table_base + 8 * j) (tape_base + head) head m).
  { unfold action_ready, action_init. cbn. repeat split; assumption. }
  pose proof (action_refines (action_init vs) (table_base + 8 * j)
    (tape_base + head) head m row Hready_action Hrow Hlenrow Hdis
    Hhead4 Hstate5 Hhead5) as Hact.
  cbn zeta in Hact. fold vm' in Hact.
  destruct Hact as [Hpc [Hr2' [Hr0' [Hr7' [Hhalt' Hmem']]]]].
  repeat split; assumption.
Qed.
