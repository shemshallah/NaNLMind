From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ActionPrefix MinskyNaN16ActionMove MinskyNaN16ActionSuffix.

(** The full action phase: from the action entry point at pc 0 through the
    row-controlled move and the shared suffix to the RET at pc 22.  The
    native fuel is exact for the selected move branch. *)

Lemma action_refines :
  forall (vm : VM) row_addr tape_addr head m row,
    action_ready vm row_addr tape_addr head m ->
    row_at row_addr row m ->
    length row = 8 ->
    (forall f, f < 8 -> row_addr + f <> tape_addr) ->
    action_head_addr <> row_addr + 4 ->
    action_state_addr <> row_addr + 5 ->
    action_head_addr <> row_addr + 5 ->
    let vm' := run_until (5 + action_move_fuel (nth 3 row 0) + 8)
                  action_block action_stop vm in
    vm_pc vm' = 22 /\
    vm_reg vm' 2 = action_new_head head (nth 3 row 0) /\
    vm_reg vm' 0 = 0 /\
    vm_reg vm' 7 = row_addr /\
    vm_halted vm' = false /\
    (forall k, vm_mem vm' k =
      snd (action_run row_addr tape_addr head m row) k).
Proof.
  intros vm row_addr tape_addr head m row Hready Hrow Hlen Hdis
    Hhead4 Hstate5 Hhead5.
  set (vm5 := run_until 5 action_block action_stop vm).
  pose proof (action_prefix5 vm row_addr tape_addr head m row Hready
    Hrow Hlen
    ltac:(intro H; apply (Hdis 3 ltac:(lia)); symmetry; exact H)) as Hpre.
  cbn zeta in Hpre. fold vm5 in Hpre.
  unfold action_ready in Hready.
  destruct Hready as [Hpc [Hr0 [Hr2 [Hr3 [Hr7 [Hr13 [Hmem Hhalt]]]]]]].
  destruct Hpre as [Hpc5 [Hr9_5 [Hr10_5 [Hr2_5 [Hr3_5 [Hr7_5
    [Hr0_5 [Hr13_5 [Hmem5 [Hhalt5 [Hzf5 Hlf5]]]]]]]]]]].
  set (vm14 := run_until (action_move_fuel (nth 3 row 0))
                  action_block action_stop vm5).
  pose proof (action_move vm5 head (nth 3 row 0) Hpc5 Hr2_5 Hr9_5
    Hr13_5 Hhalt5 Hzf5 Hlf5) as Hmv.
  cbn zeta in Hmv. fold vm14 in Hmv.
  destruct Hmv as [Hpc14 [Hr2_14 [Hhalt14 [Hr0_14 [Hr7_14 Hmem14]]]]].
  set (m1 := set_mem m tape_addr (nth 2 row 0)).
  assert (Hrow1 : row_at row_addr row m1).
  { apply (row_at_set_mem_neq row_addr row m tape_addr (nth 2 row 0) Hrow).
    intros f Hf. apply Hdis. rewrite Hlen in Hf. exact Hf. }
  assert (Hr0_14' : vm_reg vm14 0 = 0).
  { rewrite Hr0_14, Hr0_5. reflexivity. }
  assert (Hr7_14' : vm_reg vm14 7 = row_addr).
  { rewrite Hr7_14, Hr7_5. reflexivity. }
  assert (Hmem14' : vm_mem vm14 = m1).
  { unfold m1. rewrite Hmem14, Hmem5. reflexivity. }
  set (vm22 := run_until 8 action_block action_stop vm14).
  pose proof (action_suffix vm14 row_addr (action_new_head head (nth 3 row 0))
    m1 row Hpc14 Hr0_14' Hr2_14 Hr7_14' Hmem14' Hhalt14 Hrow1 Hlen
    Hhead4 Hstate5 Hhead5) as Hsuf.
  cbn zeta in Hsuf. fold vm22 in Hsuf.
  destruct Hsuf as [Hpc22 [Hhead22 [Hstate22 [Hhaltcell22 [Hhalt22
    [Hr2_22 [Hr0_22 [Hr7_22 Hmem22]]]]]]]].
  assert (Hnth3 : nth 3 row 1 = nth 3 row 0)
    by (apply nth_indep; rewrite Hlen; lia).
  assert (Hnth4 : nth 4 row 1 = nth 4 row 0)
    by (apply nth_indep; rewrite Hlen; lia).
  assert (Hnth5 : nth 5 row 1 = nth 5 row 0)
    by (apply nth_indep; rewrite Hlen; lia).
  assert (Hmempt : forall k, vm_mem vm22 k =
      snd (action_run row_addr tape_addr head m row) k).
  { intro k.
    rewrite Hmem22.
    unfold action_run.
    cbn zeta.
    rewrite Hnth3, Hnth4, Hnth5.
    destruct (Nat.eqb (nth 5 row 0) 0); reflexivity. }
  replace (5 + action_move_fuel (nth 3 row 0) + 8)
    with (5 + (action_move_fuel (nth 3 row 0) + 8)) by lia.
  rewrite (run_until_split 5 (action_move_fuel (nth 3 row 0) + 8)
    action_block action_stop vm).
  fold vm5.
  rewrite (run_until_split (action_move_fuel (nth 3 row 0)) 8
    action_block action_stop vm5).
  fold vm14.
  fold vm22.
  repeat split; assumption || exact Hmempt.
Qed.
