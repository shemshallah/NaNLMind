From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ScanLoop MinskyNaN16ScanFrame.

(** Properties of the first-match scan index. *)

Lemma table_mem_at_row_at :
  forall start row rest m,
    table_mem_at start (row :: rest) m ->
    row_at start row m.
Proof.
  intros start row rest m H f Hf.
  unfold table_mem_at in H.
  specialize (H 0 f).
  assert (Hj : 0 < S (length rest)) by lia.
  assert (Hf' : f < length (nth 0 (row :: rest) [])) by (simpl; exact Hf).
  specialize (H Hj Hf').
  cbn in H. replace (start + 0 + f) with (start + f) in H by lia.
  exact H.
Qed.

Lemma scan_index_from_row_at :
  forall i state sym table j row start m,
    scan_index_from i state sym table = Some (j, row) ->
    table_mem_at (start + 8 * i) table m ->
    row_at (start + 8 * j) row m.
Proof.
  intros i state sym table.
  revert i state sym.
  induction table as [|row0 rest IH];
    intros i state sym j row start m Hidx Hmem.
  - discriminate.
  - cbn [scan_index_from] in Hidx.
    destruct (andb (Nat.eqb (nth 0 row0 0) state)
      (Nat.eqb (nth 1 row0 0) sym)) eqn:E.
    + injection Hidx as Hj Hrow. subst j row.
      apply (table_mem_at_row_at (start + 8 * i) row0 rest m Hmem).
    + apply (IH (S i) state sym j row start m Hidx).
      replace (start + 8 * S i) with (start + 8 * i + 8) by lia.
      apply (table_mem_at_tail (start + 8 * i) row0 rest m Hmem).
Qed.

Lemma scan_index_from_length :
  forall i state sym table j row,
    scan_index_from i state sym table = Some (j, row) ->
    Forall (fun r => length r = 8) table ->
    length row = 8.
Proof.
  intros i state sym table.
  revert i state sym.
  induction table as [|row0 rest IH];
    intros i state sym j row Hidx Hforall.
  - discriminate.
  - cbn [scan_index_from] in Hidx.
    inversion Hforall as [| r0 l Hlen Hrest]; subst.
    destruct (andb (Nat.eqb (nth 0 row0 0) state)
      (Nat.eqb (nth 1 row0 0) sym)) eqn:E.
    + injection Hidx as Hj Hrow. subst j row. exact Hlen.
    + apply (IH (S i) state sym j row Hidx Hrest).
Qed.

(** The scan phase, including the frame conditions needed by the action
    phase.  The result is either the hit exit at pc 14 with the selected row
    start in r7, or the no-transition exit at pc 13. *)

Lemma scan_phase :
  forall (vm : VM) (i state sym start : nat)
         (table : list (list nat)) (m : Mem),
    i + length table = 184 ->
    Forall (fun row => 0 < length row /\ 1 < length row) table ->
    table_mem_at (start + 8 * i) table m ->
    scan_ready vm i state sym start m ->
    vm_reg vm 0 = 0 ->
    exists vm',
      run_until (12 * length table + 14) scan_block scan_stop vm = vm' /\
      vm_reg vm' 2 = vm_reg vm 2 /\
      vm_reg vm' 3 = vm_reg vm 3 /\
      vm_reg vm' 0 = 0 /\
      vm_reg vm' 13 = 1 /\
      vm_mem vm' = m /\
      vm_halted vm' = false /\
      match scan_index_from i state sym table with
      | Some (j, row) =>
          vm_pc vm' = 14 /\
          vm_reg vm' 7 = start + 8 * j /\
          vm_reg vm' 8 = j
      | None =>
          vm_pc vm' = 13 /\
          vm_reg vm' 8 = 184
      end.
Proof.
  intros vm i state sym start table m Hlen Hforall Hmemtab Hready Hr0.
  pose proof Hready as Hready_loop.
  unfold scan_ready in Hready.
  destruct Hready as [Hpc [Hr1 [Hr4 [Hr5 [Hr6 [Hr8 [Hr13 [Hmem Hhalt]]]]]]]].
  destruct (scan_loop i state sym start table m vm
    Hlen Hforall Hmemtab Hready_loop) as [vm' [Hrun Hmatch]].
  exists vm'. split; [exact Hrun|].
  assert (Hr2 : vm_reg vm' 2 = vm_reg vm 2).
  { rewrite <- Hrun. apply scan_run_reg2. }
  assert (Hr3 : vm_reg vm' 3 = vm_reg vm 3).
  { rewrite <- Hrun. apply scan_run_reg3. }
  assert (Hr0' : vm_reg vm' 0 = 0).
  { rewrite <- Hrun. rewrite scan_run_reg0. exact Hr0. }
  assert (Hr13' : vm_reg vm' 13 = 1).
  { rewrite <- Hrun. rewrite scan_run_reg13. exact Hr13. }
  assert (Hmem' : vm_mem vm' = m).
  { rewrite <- Hrun. rewrite scan_run_mem. exact Hmem. }
  assert (Hpc0 : vm_pc vm < 15) by (rewrite Hpc; lia).
  assert (Hhalt' : vm_halted vm' = false).
  { rewrite <- Hrun. apply (scan_run_halted_false (12 * length table + 14)
      vm Hpc0 Hhalt). }
  split; [exact Hr2|split; [exact Hr3|split; [exact Hr0'|
    split; [exact Hr13'|split; [exact Hmem'|split; [exact Hhalt'|exact Hmatch]]]]]].
Qed.
