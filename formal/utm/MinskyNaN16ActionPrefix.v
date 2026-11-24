From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action.

Lemma action_prefix5_try :
  forall (vm : VM) row_addr tape_addr head m row,
    action_ready vm row_addr tape_addr head m ->
    row_at row_addr row m ->
    length row = 8 ->
    tape_addr <> row_addr + 3 ->
    let vm5 := run_until 5 action_block action_stop vm in
    vm_pc vm5 = 5 /\
    vm_reg vm5 9 = nth 3 row 0 /\
    vm_reg vm5 10 = 0 /\
    vm_reg vm5 2 = head /\
    vm_reg vm5 3 = tape_addr /\
    vm_reg vm5 7 = row_addr /\
    vm_mem vm5 = set_mem m tape_addr (nth 2 row 0) /\
    vm_halted vm5 = false.
Proof.
  intros vm row_addr tape_addr head m row Hready Hrow Hlen Hdis.
  unfold action_ready in Hready.
  destruct Hready as [Hpc [Hr0 [Hr2 [Hr3 [Hr7 [Hr13 [Hmem Hhalt]]]]]]].
  set (v1 := exec_instr action_block vm).
  set (v2 := exec_instr action_block v1).
  set (v3 := exec_instr action_block v2).
  set (v4 := exec_instr action_block v3).
  set (v5 := exec_instr action_block v4).
  rewrite (run_one_false 4 action_block action_stop vm).
  2:{ unfold action_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 1)
    by (unfold v1; rewrite (action_exec_pc vm 0 (iLD 9 7 2) Hpc eq_refl); cbn; reflexivity).
  assert (Hhalt1 : vm_halted v1 = false).
  { unfold v1. rewrite (action_not_halted vm 0 (iLD 9 7 2) Hpc eq_refl ltac:(discriminate)). exact Hhalt. }
  assert (Hr2_1 : vm_reg v1 2 = head).
  { unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error action_block]. cbn. exact Hr2. }
  assert (Hr3_1 : vm_reg v1 3 = tape_addr).
  { unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error action_block]. cbn. exact Hr3. }
  assert (Hr7_1 : vm_reg v1 7 = row_addr).
  { unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error action_block]. cbn. exact Hr7. }
  assert (Hmem1 : vm_mem v1 = m).
  { unfold v1. unfold exec_instr. rewrite Hpc. cbn [nth_error action_block]. cbn. exact Hmem. }
  assert (Hr9_1 : vm_reg v1 9 = m (row_addr + 2)).
  { unfold v1. rewrite (action_LD_reg vm 0 9 7 2 Hpc eq_refl). rewrite Hr7, Hmem. reflexivity. }
  rewrite (run_one_false 3 action_block action_stop v1).
  2:{ unfold action_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 2)
    by (unfold v2; rewrite (action_exec_pc v1 1 (iST 9 3 0) Hpc1 eq_refl); cbn; reflexivity).
  assert (Hhalt2 : vm_halted v2 = false).
  { unfold v2. rewrite (action_not_halted v1 1 (iST 9 3 0) Hpc1 eq_refl ltac:(discriminate)). exact Hhalt1. }
  assert (Hmem2 : vm_mem v2 = set_mem m tape_addr (nth 2 row 0)).
  { unfold v2. rewrite (action_ST_mem v1 1 9 3 0 Hpc1 eq_refl).
    rewrite Hr9_1, Hr3_1, Hmem1.
    replace (tape_addr + 0) with tape_addr by lia.
    f_equal. rewrite (Hrow 2 ltac:(simpl; lia)). reflexivity. }
  assert (Hr7_2 : vm_reg v2 7 = row_addr).
  { unfold v2. unfold exec_instr. rewrite Hpc1. cbn [nth_error action_block]. cbn. exact Hr7_1. }
  rewrite (run_one_false 2 action_block action_stop v2).
  2:{ unfold action_stop. rewrite Hpc2, Hhalt2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 3)
    by (unfold v3; rewrite (action_exec_pc v2 2 (iLD 9 7 3) Hpc2 eq_refl); cbn; reflexivity).
  assert (Hhalt3 : vm_halted v3 = false).
  { unfold v3. rewrite (action_not_halted v2 2 (iLD 9 7 3) Hpc2 eq_refl ltac:(discriminate)). exact Hhalt2. }
  assert (Hr9_3 : vm_reg v3 9 = nth 3 row 0).
  { unfold v3. rewrite (action_LD_reg v2 2 9 7 3 Hpc2 eq_refl).
    rewrite Hr7_2, Hmem2.
    rewrite (set_mem_neq m tape_addr (nth 2 row 0) (row_addr + 3)).
    - rewrite (Hrow 3 ltac:(simpl; lia)). reflexivity.
    - lia. }
  rewrite (run_one_false 1 action_block action_stop v3).
  2:{ unfold action_stop. rewrite Hpc3, Hhalt3. cbn. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 4)
    by (unfold v4; rewrite (action_exec_pc v3 3 (iMOVI 10 0) Hpc3 eq_refl); cbn; reflexivity).
  assert (Hhalt4 : vm_halted v4 = false).
  { unfold v4. rewrite (action_not_halted v3 3 (iMOVI 10 0) Hpc3 eq_refl ltac:(discriminate)). exact Hhalt3. }
  assert (Hr10_4 : vm_reg v4 10 = 0).
  { unfold v4. rewrite (action_MOVI_reg v3 3 10 0 Hpc3 eq_refl). reflexivity. }
  assert (Hr9_4 : vm_reg v4 9 = nth 3 row 0).
  { unfold v4. unfold exec_instr. rewrite Hpc3. cbn [nth_error action_block]. cbn. exact Hr9_3. }
  rewrite (run_one_false 0 action_block action_stop v4).
  2:{ unfold action_stop. rewrite Hpc4, Hhalt4. cbn. reflexivity. }
  cbn [run_until].
  fold v5.
  assert (Hpc5 : vm_pc v5 = 5)
    by (unfold v5; rewrite (action_exec_pc v4 4 (iCMP 9 10) Hpc4 eq_refl); cbn; reflexivity).
  assert (Hhalt5 : vm_halted v5 = false).
  { unfold v5. rewrite (action_not_halted v4 4 (iCMP 9 10) Hpc4 eq_refl ltac:(discriminate)). exact Hhalt4. }
  assert (Hr9_5 : vm_reg v5 9 = nth 3 row 0).
  { unfold v5. unfold exec_instr. rewrite Hpc4. cbn [nth_error action_block]. cbn.
    exact Hr9_4. }
  assert (Hr10_5 : vm_reg v5 10 = 0).
  { unfold v5. unfold exec_instr. rewrite Hpc4. cbn [nth_error action_block]. cbn.
    exact Hr10_4. }
  assert (Hr2_5 : vm_reg v5 2 = head).
  { rewrite (action_reg_preserved_CMP v4 4 9 10 2 Hpc4 eq_refl).
    rewrite (action_reg_preserved_MOVI v3 3 10 0 2 Hpc3 eq_refl ltac:(lia)).
    rewrite (action_reg_preserved_LD v2 2 9 7 3 2 Hpc2 eq_refl ltac:(lia)).
    rewrite (action_reg_preserved_ST v1 1 9 3 0 2 Hpc1 eq_refl).
    rewrite (action_reg_preserved_LD vm 0 9 7 2 2 Hpc eq_refl ltac:(lia)).
    exact Hr2. }
  assert (Hr3_5 : vm_reg v5 3 = tape_addr).
  { rewrite (action_reg_preserved_CMP v4 4 9 10 3 Hpc4 eq_refl).
    rewrite (action_reg_preserved_MOVI v3 3 10 0 3 Hpc3 eq_refl ltac:(lia)).
    rewrite (action_reg_preserved_LD v2 2 9 7 3 3 Hpc2 eq_refl ltac:(lia)).
    rewrite (action_reg_preserved_ST v1 1 9 3 0 3 Hpc1 eq_refl).
    rewrite (action_reg_preserved_LD vm 0 9 7 2 3 Hpc eq_refl ltac:(lia)).
    exact Hr3. }
  assert (Hr7_5 : vm_reg v5 7 = row_addr).
  { rewrite (action_reg_preserved_CMP v4 4 9 10 7 Hpc4 eq_refl).
    rewrite (action_reg_preserved_MOVI v3 3 10 0 7 Hpc3 eq_refl ltac:(lia)).
    rewrite (action_reg_preserved_LD v2 2 9 7 3 7 Hpc2 eq_refl ltac:(lia)).
    rewrite (action_reg_preserved_ST v1 1 9 3 0 7 Hpc1 eq_refl).
    rewrite (action_reg_preserved_LD vm 0 9 7 2 7 Hpc eq_refl ltac:(lia)).
    exact Hr7. }
  assert (Hmem5 : vm_mem v5 = set_mem m tape_addr (nth 2 row 0)).
  { rewrite (action_mem_preserved_CMP v4 4 9 10 Hpc4 eq_refl).
    rewrite (action_mem_preserved_MOVI v3 3 10 0 Hpc3 eq_refl).
    rewrite (action_mem_preserved_LD v2 2 9 7 3 Hpc2 eq_refl).
    exact Hmem2. }
  repeat split; assumption.
Qed.
