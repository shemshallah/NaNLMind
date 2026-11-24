From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action.

Lemma action_suffix_prefix :
  forall (vm : VM) row_addr head m row,
    vm_pc vm = 14 ->
    vm_reg vm 0 = 0 ->
    vm_reg vm 2 = head ->
    vm_reg vm 7 = row_addr ->
    vm_mem vm = m ->
    vm_halted vm = false ->
    row_at row_addr row m ->
    length row = 8 ->
    action_head_addr <> row_addr + 4 ->
    action_state_addr <> row_addr + 5 ->
    action_head_addr <> row_addr + 5 ->
    let vm' := run_until 5 action_block action_stop vm in
    vm_pc vm' = 19 /\
    vm_reg vm' 9 = nth 5 row 0 /\
    vm_reg vm' 0 = 0 /\
    vm_reg vm' 2 = head /\
    vm_reg vm' 7 = row_addr /\
    vm_mem vm' = set_mem (set_mem m action_head_addr head)
      action_state_addr (nth 4 row 0) /\
    vm_halted vm' = false /\
    vm_zf vm' = Nat.eqb (nth 5 row 0) 0 /\
    vm_lf vm' = Nat.ltb (nth 5 row 0) 0.
Proof.
  intros vm row_addr head m row Hpc Hr0 Hr2 Hr7 Hmem Hhalt Hrow Hlen
    Hhead4 Hstate5 Hhead5.
  set (v1 := exec_instr action_block vm).
  set (v2 := exec_instr action_block v1).
  set (v3 := exec_instr action_block v2).
  set (v4 := exec_instr action_block v3).
  set (v5 := exec_instr action_block v4).
  rewrite (run_one_false 4 action_block action_stop vm).
  2:{ unfold action_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 15)
    by (unfold v1; rewrite (action_exec_pc vm 14 (iST 2 0 action_head_addr) Hpc eq_refl);
        cbn; reflexivity).
  assert (Hhalt1 : vm_halted v1 = false).
  { unfold v1. rewrite (action_not_halted vm 14 (iST 2 0 action_head_addr) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  assert (Hmem1 : vm_mem v1 = set_mem m action_head_addr head).
  { unfold v1. rewrite (action_ST_mem vm 14 2 0 action_head_addr Hpc eq_refl).
    rewrite Hr0, Hr2, Hmem. cbn. reflexivity. }
  assert (Hr0_1 : vm_reg v1 0 = 0).
  { unfold v1. rewrite (action_reg_preserved_ST vm 14 2 0 action_head_addr 0 Hpc eq_refl).
    exact Hr0. }
  assert (Hr2_1 : vm_reg v1 2 = head).
  { unfold v1. rewrite (action_reg_preserved_ST vm 14 2 0 action_head_addr 2 Hpc eq_refl).
    exact Hr2. }
  assert (Hr7_1 : vm_reg v1 7 = row_addr).
  { unfold v1. rewrite (action_reg_preserved_ST vm 14 2 0 action_head_addr 7 Hpc eq_refl).
    exact Hr7. }
  rewrite (run_one_false 3 action_block action_stop v1).
  2:{ unfold action_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 16)
    by (unfold v2; rewrite (action_exec_pc v1 15 (iLD 9 7 4) Hpc1 eq_refl);
        cbn; reflexivity).
  assert (Hhalt2 : vm_halted v2 = false).
  { unfold v2. rewrite (action_not_halted v1 15 (iLD 9 7 4) Hpc1 eq_refl
      ltac:(discriminate)). exact Hhalt1. }
  assert (Hr9_2 : vm_reg v2 9 = nth 4 row 0).
  { unfold v2. rewrite (action_LD_reg v1 15 9 7 4 Hpc1 eq_refl).
    rewrite Hr7_1, Hmem1.
    rewrite (set_mem_neq m action_head_addr head (row_addr + 4)).
    - rewrite (Hrow 4 ltac:(simpl; lia)). reflexivity.
    - lia. }
  assert (Hmem2 : vm_mem v2 = set_mem m action_head_addr head).
  { unfold v2. rewrite (action_mem_preserved_LD v1 15 9 7 4 Hpc1 eq_refl). exact Hmem1. }
  assert (Hr0_2 : vm_reg v2 0 = 0).
  { unfold v2. rewrite (action_reg_preserved_LD v1 15 9 7 4 0 Hpc1 eq_refl ltac:(lia)).
    exact Hr0_1. }
  assert (Hr2_2 : vm_reg v2 2 = head).
  { unfold v2. rewrite (action_reg_preserved_LD v1 15 9 7 4 2 Hpc1 eq_refl ltac:(lia)).
    exact Hr2_1. }
  assert (Hr7_2 : vm_reg v2 7 = row_addr).
  { unfold v2. rewrite (action_reg_preserved_LD v1 15 9 7 4 7 Hpc1 eq_refl ltac:(lia)).
    exact Hr7_1. }
  rewrite (run_one_false 2 action_block action_stop v2).
  2:{ unfold action_stop. rewrite Hpc2, Hhalt2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 17)
    by (unfold v3; rewrite (action_exec_pc v2 16 (iST 9 0 action_state_addr) Hpc2 eq_refl);
        cbn; reflexivity).
  assert (Hhalt3 : vm_halted v3 = false).
  { unfold v3. rewrite (action_not_halted v2 16 (iST 9 0 action_state_addr) Hpc2 eq_refl
      ltac:(discriminate)). exact Hhalt2. }
  assert (Hmem3 : vm_mem v3 = set_mem (set_mem m action_head_addr head)
    action_state_addr (nth 4 row 0)).
  { unfold v3. rewrite (action_ST_mem v2 16 9 0 action_state_addr Hpc2 eq_refl).
    rewrite Hr0_2, Hr9_2, Hmem2. cbn. reflexivity. }
  assert (Hr0_3 : vm_reg v3 0 = 0).
  { unfold v3. rewrite (action_reg_preserved_ST v2 16 9 0 action_state_addr 0 Hpc2 eq_refl).
    exact Hr0_2. }
  assert (Hr2_3 : vm_reg v3 2 = head).
  { unfold v3. rewrite (action_reg_preserved_ST v2 16 9 0 action_state_addr 2 Hpc2 eq_refl).
    exact Hr2_2. }
  assert (Hr7_3 : vm_reg v3 7 = row_addr).
  { unfold v3. rewrite (action_reg_preserved_ST v2 16 9 0 action_state_addr 7 Hpc2 eq_refl).
    exact Hr7_2. }
  rewrite (run_one_false 1 action_block action_stop v3).
  2:{ unfold action_stop. rewrite Hpc3, Hhalt3. cbn. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 18)
    by (unfold v4; rewrite (action_exec_pc v3 17 (iLD 9 7 5) Hpc3 eq_refl);
        cbn; reflexivity).
  assert (Hhalt4 : vm_halted v4 = false).
  { unfold v4. rewrite (action_not_halted v3 17 (iLD 9 7 5) Hpc3 eq_refl
      ltac:(discriminate)). exact Hhalt3. }
  assert (Hr9_4 : vm_reg v4 9 = nth 5 row 0).
  { unfold v4. rewrite (action_LD_reg v3 17 9 7 5 Hpc3 eq_refl).
    rewrite Hr7_3, Hmem3.
    rewrite (set_mem_neq (set_mem m action_head_addr head)
      action_state_addr (nth 4 row 0) (row_addr + 5)).
    - rewrite (set_mem_neq m action_head_addr head (row_addr + 5)).
      + rewrite (Hrow 5 ltac:(simpl; lia)). reflexivity.
      + lia.
    - lia. }
  assert (Hmem4 : vm_mem v4 = set_mem (set_mem m action_head_addr head)
    action_state_addr (nth 4 row 0)).
  { unfold v4. rewrite (action_mem_preserved_LD v3 17 9 7 5 Hpc3 eq_refl). exact Hmem3. }
  assert (Hr0_4 : vm_reg v4 0 = 0).
  { unfold v4. rewrite (action_reg_preserved_LD v3 17 9 7 5 0 Hpc3 eq_refl ltac:(lia)).
    exact Hr0_3. }
  assert (Hr2_4 : vm_reg v4 2 = head).
  { unfold v4. rewrite (action_reg_preserved_LD v3 17 9 7 5 2 Hpc3 eq_refl ltac:(lia)).
    exact Hr2_3. }
  assert (Hr7_4 : vm_reg v4 7 = row_addr).
  { unfold v4. rewrite (action_reg_preserved_LD v3 17 9 7 5 7 Hpc3 eq_refl ltac:(lia)).
    exact Hr7_3. }
  rewrite (run_one_false 0 action_block action_stop v4).
  2:{ unfold action_stop. rewrite Hpc4, Hhalt4. cbn. reflexivity. }
  cbn [run_until].
  fold v5.
  assert (Hpc5 : vm_pc v5 = 19)
    by (unfold v5; rewrite (action_exec_pc v4 18 (iCMP 9 0) Hpc4 eq_refl);
        cbn; reflexivity).
  assert (Hhalt5 : vm_halted v5 = false).
  { unfold v5. rewrite (action_not_halted v4 18 (iCMP 9 0) Hpc4 eq_refl
      ltac:(discriminate)). exact Hhalt4. }
  assert (Hzf5 : vm_zf v5 = Nat.eqb (nth 5 row 0) 0).
  { unfold v5. rewrite (action_CMP_zf v4 18 9 0 Hpc4 eq_refl). rewrite Hr9_4, Hr0_4.
    reflexivity. }
  assert (Hlf5 : vm_lf v5 = Nat.ltb (nth 5 row 0) 0).
  { unfold v5. rewrite (action_CMP_lf v4 18 9 0 Hpc4 eq_refl). rewrite Hr9_4, Hr0_4.
    reflexivity. }
  assert (Hr9_5 : vm_reg v5 9 = nth 5 row 0).
  { unfold v5. rewrite (action_reg_preserved_CMP v4 18 9 0 9 Hpc4 eq_refl). exact Hr9_4. }
  assert (Hr0_5 : vm_reg v5 0 = 0).
  { unfold v5. rewrite (action_reg_preserved_CMP v4 18 9 0 0 Hpc4 eq_refl). exact Hr0_4. }
  assert (Hr2_5 : vm_reg v5 2 = head).
  { unfold v5. rewrite (action_reg_preserved_CMP v4 18 9 0 2 Hpc4 eq_refl). exact Hr2_4. }
  assert (Hr7_5 : vm_reg v5 7 = row_addr).
  { unfold v5. rewrite (action_reg_preserved_CMP v4 18 9 0 7 Hpc4 eq_refl). exact Hr7_4. }
  assert (Hmem5 : vm_mem v5 = set_mem (set_mem m action_head_addr head)
    action_state_addr (nth 4 row 0)).
  { unfold v5. rewrite (action_mem_preserved_CMP v4 18 9 0 Hpc4 eq_refl). exact Hmem4. }
  repeat split; assumption.
Qed.
