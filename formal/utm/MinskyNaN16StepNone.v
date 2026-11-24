From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action
  MinskyNaN16ScanPhase MinskyNaN16Lookup.

Definition no_trans_block : list Instr :=
  [ iMOVI 9 1;
    iST 9 0 action_halt_addr;
    iRET ].

Definition no_trans_stop (pc : nat) : bool := Nat.eqb pc 2.

Definition no_trans_init (vm : VM) : VM :=
  {| vm_pc := 0; vm_reg := vm_reg vm; vm_mem := vm_mem vm;
     vm_zf := vm_zf vm; vm_lf := vm_lf vm; vm_halted := vm_halted vm;
     vm_link := vm_link vm |}.

Lemma no_trans_run :
  forall vm,
    vm_pc vm = 0 ->
    vm_reg vm 0 = 0 ->
    vm_halted vm = false ->
    vm_pc (run_until 2 no_trans_block no_trans_stop vm) = 2 /\
    vm_mem (run_until 2 no_trans_block no_trans_stop vm) =
      set_mem (vm_mem vm) action_halt_addr 1 /\
    vm_reg (run_until 2 no_trans_block no_trans_stop vm) 2 = vm_reg vm 2 /\
    vm_reg (run_until 2 no_trans_block no_trans_stop vm) 0 = 0 /\
    vm_reg (run_until 2 no_trans_block no_trans_stop vm) 9 = 1 /\
    vm_halted (run_until 2 no_trans_block no_trans_stop vm) = false.
Proof.
  intros vm Hpc Hr0 Hhalt.
  set (v1 := exec_instr no_trans_block vm).
  rewrite (run_one_false 1 no_trans_block no_trans_stop vm).
  2:{ unfold no_trans_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 1)
    by (unfold v1, exec_instr; rewrite Hpc; cbn; reflexivity).
  assert (Hhalt1 : vm_halted v1 = false)
    by (unfold v1, exec_instr; rewrite Hpc; cbn; exact Hhalt).
  assert (Hr2_1 : vm_reg v1 2 = vm_reg vm 2)
    by (unfold v1, exec_instr; rewrite Hpc; cbn; reflexivity).
  assert (Hr0_1 : vm_reg v1 0 = 0)
    by (unfold v1, exec_instr; rewrite Hpc; cbn; exact Hr0).
  assert (Hr9_1 : vm_reg v1 9 = 1)
    by (unfold v1, exec_instr; rewrite Hpc; cbn; reflexivity).
  assert (Hmem1 : vm_mem v1 = vm_mem vm)
    by (unfold v1, exec_instr; rewrite Hpc; cbn; reflexivity).
  set (v2 := exec_instr no_trans_block v1).
  rewrite (run_one_false 0 no_trans_block no_trans_stop v1).
  2:{ unfold no_trans_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
  cbn [run_until]. fold v2.
  assert (Hpc2 : vm_pc v2 = 2)
    by (unfold v2, exec_instr; rewrite Hpc1; cbn; reflexivity).
  assert (Hhalt2 : vm_halted v2 = false)
    by (unfold v2, exec_instr; rewrite Hpc1; cbn; exact Hhalt1).
  assert (Hr2_2 : vm_reg v2 2 = vm_reg vm 2)
    by (unfold v2, exec_instr; rewrite Hpc1; cbn; exact Hr2_1).
  assert (Hr0_2 : vm_reg v2 0 = 0)
    by (unfold v2, exec_instr; rewrite Hpc1; cbn; exact Hr0_1).
  assert (Hr9_2 : vm_reg v2 9 = 1)
    by (unfold v2, exec_instr; rewrite Hpc1; cbn; exact Hr9_1).
  assert (Hmem2 : vm_mem v2 = set_mem (vm_mem vm) action_halt_addr 1).
  { unfold v2, exec_instr, get_reg. rewrite Hpc1. cbn.
    rewrite Hr0_1, Hr9_1, Hmem1. unfold set_mem. cbn. reflexivity. }
  repeat split; assumption.
Qed.

Lemma step_none_phase :
  forall (vm : VM) (state head table_base tape_base : nat)
         (table : list (list nat)) (m : Mem),
    length table = 184 ->
    Forall (fun r => 0 < length r /\ 1 < length r) table ->
    table_mem_at table_base table m ->
    scan_ready vm 0 state (m (tape_base + head)) table_base m ->
    vm_reg vm 2 = head ->
    vm_reg vm 3 = tape_base + head ->
    vm_reg vm 0 = 0 ->
    scan_index_from 0 state (m (tape_base + head)) table = None ->
    let vs := run_until (12 * length table + 14) scan_block scan_stop vm in
    let vm' := run_until 2 no_trans_block no_trans_stop (no_trans_init vs) in
    vm_pc vm' = 2 /\
    vm_mem vm' = set_mem m action_halt_addr 1 /\
    vm_reg vm' 2 = head /\
    vm_reg vm' 0 = 0 /\
    vm_halted vm' = false.
Proof.
  intros vm state head table_base tape_base table m
    Hlen Hshort Hmemtab Hready Hr2 Hr3 Hr0 Hidx.
  assert (Hmemtab0 : table_mem_at (table_base + 8 * 0) table m)
    by (replace (table_base + 8 * 0) with table_base by lia; exact Hmemtab).
  destruct (scan_phase vm 0 state (m (tape_base + head)) table_base table m
    ltac:(rewrite Hlen; lia) Hshort Hmemtab0 Hready Hr0)
    as [vs [Hrun [Hr2s [Hr3s [Hr0s [Hr13s [Hmems [Hhalts Hmatch]]]]]]]].
  cbn zeta. rewrite Hrun. cbn zeta.
  rewrite Hidx in Hmatch.
  destruct Hmatch as [Hpcs Hr8s].
  assert (Hr0v : vm_reg vs 0 = 0) by exact Hr0s.
  assert (Hhaltv : vm_halted vs = false) by exact Hhalts.
  set (vn := run_until 2 no_trans_block no_trans_stop (no_trans_init vs)).
  pose proof (no_trans_run (no_trans_init vs)
    ltac:(unfold no_trans_init; cbn; reflexivity)
    ltac:(unfold no_trans_init; cbn; exact Hr0v)
    ltac:(unfold no_trans_init; cbn; exact Hhaltv)) as Hnone.
  fold vn in Hnone.
  destruct Hnone as [Hpc2 [Hmem2 [Hr2' [Hr0' [Hr9' Hhalt']]]]].
  assert (Hr2v : vm_reg vs 2 = head) by (rewrite Hr2s, Hr2; reflexivity).
  assert (Hmemv : vm_mem vs = m) by exact Hmems.
  fold vn.
  repeat split; try assumption.
  - unfold no_trans_init in Hmem2. rewrite Hmemv in Hmem2. exact Hmem2.
  - unfold no_trans_init in Hr2'. rewrite Hr2'. exact Hr2v.
Qed.
