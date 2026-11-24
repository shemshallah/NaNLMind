From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action.

Definition action_move_stop (pc : nat) : bool := Nat.eqb pc 14.

Lemma run_until_move_stop_at_14 :
  forall (fuel : nat) (vm : VM),
    vm_pc vm = 14 ->
    vm_halted vm = false ->
    run_until fuel action_block action_move_stop vm = vm.
Proof.
  intros. apply run_until_stop.
  unfold action_move_stop. rewrite H, H0. cbn. reflexivity.
Qed.

Lemma action_move_zero :
  forall (vm : VM) (head : nat),
    vm_pc vm = 5 ->
    vm_reg vm 2 = head ->
    vm_reg vm 9 = 0 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_zf vm = true ->
    let vm' := run_until 3 action_block action_stop vm in
    vm_pc vm' = 14 /\
    vm_reg vm' 2 = head - 1 /\
    vm_halted vm' = false /\
    vm_reg vm' 0 = vm_reg vm 0 /\
    vm_reg vm' 7 = vm_reg vm 7 /\
    vm_mem vm' = vm_mem vm.
Proof.
  intros vm head Hpc Hr2 Hr9 Hr13 Hhalt Hzf.
  set (v1 := exec_instr action_block vm).
  set (v2 := exec_instr action_block v1).
  set (v3 := exec_instr action_block v2).
  rewrite (run_one_false 2 action_block action_stop vm).
  2:{ unfold action_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 10)
    by (unfold v1; rewrite (action_exec_pc vm 5 (iJMP pEQ 10) Hpc eq_refl);
        rewrite Hzf; cbn; reflexivity).
  assert (Hhalt1 : vm_halted v1 = false).
  { unfold v1. rewrite (action_not_halted vm 5 (iJMP pEQ 10) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  assert (Hr2_1 : vm_reg v1 2 = head).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 2 Hpc eq_refl). exact Hr2. }
  assert (Hr9_1 : vm_reg v1 9 = 0).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 9 Hpc eq_refl). exact Hr9. }
  assert (Hr13_1 : vm_reg v1 13 = 1).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 13 Hpc eq_refl). exact Hr13. }
  assert (Hr0_1 : vm_reg v1 0 = vm_reg vm 0).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 0 Hpc eq_refl). reflexivity. }
  assert (Hr7_1 : vm_reg v1 7 = vm_reg vm 7).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 7 Hpc eq_refl). reflexivity. }
  assert (Hmem1 : vm_mem v1 = vm_mem vm).
  { unfold v1. rewrite (action_mem_preserved_JMP vm 5 pEQ 10 Hpc eq_refl). reflexivity. }
  rewrite (run_one_false 1 action_block action_stop v1).
  2:{ unfold action_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 11)
    by (unfold v2; rewrite (action_exec_pc v1 10 (iSUB 2 2 13) Hpc1 eq_refl);
        cbn; reflexivity).
  assert (Hhalt2 : vm_halted v2 = false).
  { unfold v2. rewrite (action_not_halted v1 10 (iSUB 2 2 13) Hpc1 eq_refl
      ltac:(discriminate)). exact Hhalt1. }
  assert (Hr2_2 : vm_reg v2 2 = head - 1).
  { unfold v2. rewrite (action_SUB_reg v1 10 2 2 13 Hpc1 eq_refl).
    rewrite Hr2_1, Hr13_1. reflexivity. }
  assert (Hr0_2 : vm_reg v2 0 = vm_reg v1 0).
  { unfold v2. rewrite (action_reg_preserved_SUB v1 10 2 2 13 0 Hpc1 eq_refl ltac:(lia)). reflexivity. }
  assert (Hr7_2 : vm_reg v2 7 = vm_reg v1 7).
  { unfold v2. rewrite (action_reg_preserved_SUB v1 10 2 2 13 7 Hpc1 eq_refl ltac:(lia)). reflexivity. }
  assert (Hmem2 : vm_mem v2 = vm_mem v1).
  { unfold v2. rewrite (action_mem_preserved_SUB v1 10 2 2 13 Hpc1 eq_refl). reflexivity. }
  rewrite (run_one_false 0 action_block action_stop v2).
  2:{ unfold action_stop. rewrite Hpc2, Hhalt2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 14)
    by (unfold v3; rewrite (action_exec_pc v2 11 (iJMP pALWAYS 14) Hpc2 eq_refl);
        cbn; reflexivity).
  assert (Hhalt3 : vm_halted v3 = false).
  { unfold v3. rewrite (action_not_halted v2 11 (iJMP pALWAYS 14) Hpc2 eq_refl
      ltac:(discriminate)). exact Hhalt2. }
  assert (Hr2_3 : vm_reg v3 2 = head - 1).
  { unfold v3. rewrite (action_reg_preserved_JMP v2 11 pALWAYS 14 2 Hpc2 eq_refl).
    exact Hr2_2. }
  assert (Hr0_3 : vm_reg v3 0 = vm_reg vm 0).
  { unfold v3. rewrite (action_reg_preserved_JMP v2 11 pALWAYS 14 0 Hpc2 eq_refl).
    rewrite Hr0_2, Hr0_1. reflexivity. }
  assert (Hr7_3 : vm_reg v3 7 = vm_reg vm 7).
  { unfold v3. rewrite (action_reg_preserved_JMP v2 11 pALWAYS 14 7 Hpc2 eq_refl).
    rewrite Hr7_2, Hr7_1. reflexivity. }
  assert (Hmem3 : vm_mem v3 = vm_mem vm).
  { unfold v3. rewrite (action_mem_preserved_JMP v2 11 pALWAYS 14 Hpc2 eq_refl).
    rewrite Hmem2, Hmem1. reflexivity. }
  cbn [run_until].
  fold v3.
  repeat split; assumption.
Qed.

Lemma action_move_right :
  forall (vm : VM) (head : nat),
    vm_pc vm = 5 ->
    vm_reg vm 2 = head ->
    vm_reg vm 9 = 2 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_zf vm = false ->
    let vm' := run_until 6 action_block action_stop vm in
    vm_pc vm' = 14 /\
    vm_reg vm' 2 = head + 1 /\
    vm_halted vm' = false /\
    vm_reg vm' 0 = vm_reg vm 0 /\
    vm_reg vm' 7 = vm_reg vm 7 /\
    vm_mem vm' = vm_mem vm.
Proof.
  intros vm head Hpc Hr2 Hr9 Hr13 Hhalt Hzf.
  set (v1 := exec_instr action_block vm).
  set (v2 := exec_instr action_block v1).
  set (v3 := exec_instr action_block v2).
  set (v4 := exec_instr action_block v3).
  set (v5 := exec_instr action_block v4).
  set (v6 := exec_instr action_block v5).
  rewrite (run_one_false 5 action_block action_stop vm).
  2:{ unfold action_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 6)
    by (unfold v1; rewrite (action_exec_pc vm 5 (iJMP pEQ 10) Hpc eq_refl);
        rewrite Hzf; cbn; reflexivity).
  assert (Hhalt1 : vm_halted v1 = false).
  { unfold v1. rewrite (action_not_halted vm 5 (iJMP pEQ 10) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  assert (Hr2_1 : vm_reg v1 2 = head).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 2 Hpc eq_refl). exact Hr2. }
  assert (Hr9_1 : vm_reg v1 9 = 2).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 9 Hpc eq_refl). exact Hr9. }
  assert (Hr13_1 : vm_reg v1 13 = 1).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 13 Hpc eq_refl). exact Hr13. }
  assert (Hr0_1 : vm_reg v1 0 = vm_reg vm 0).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 0 Hpc eq_refl). reflexivity. }
  assert (Hr7_1 : vm_reg v1 7 = vm_reg vm 7).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 7 Hpc eq_refl). reflexivity. }
  assert (Hmem1 : vm_mem v1 = vm_mem vm).
  { unfold v1. rewrite (action_mem_preserved_JMP vm 5 pEQ 10 Hpc eq_refl). reflexivity. }
  rewrite (run_one_false 4 action_block action_stop v1).
  2:{ unfold action_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 7)
    by (unfold v2; rewrite (action_exec_pc v1 6 (iMOVI 10 2) Hpc1 eq_refl);
        cbn; reflexivity).
  assert (Hhalt2 : vm_halted v2 = false).
  { unfold v2. rewrite (action_not_halted v1 6 (iMOVI 10 2) Hpc1 eq_refl
      ltac:(discriminate)). exact Hhalt1. }
  assert (Hr2_2 : vm_reg v2 2 = head).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 2 Hpc1 eq_refl ltac:(lia)).
    exact Hr2_1. }
  assert (Hr9_2 : vm_reg v2 9 = 2).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 9 Hpc1 eq_refl ltac:(lia)).
    exact Hr9_1. }
  assert (Hr10_2 : vm_reg v2 10 = 2).
  { unfold v2. rewrite (action_MOVI_reg v1 6 10 2 Hpc1 eq_refl). reflexivity. }
  assert (Hr13_2 : vm_reg v2 13 = 1).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 13 Hpc1 eq_refl ltac:(lia)).
    exact Hr13_1. }
  assert (Hr0_2 : vm_reg v2 0 = vm_reg v1 0).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 0 Hpc1 eq_refl ltac:(lia)).
    reflexivity. }
  assert (Hr7_2 : vm_reg v2 7 = vm_reg v1 7).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 7 Hpc1 eq_refl ltac:(lia)).
    reflexivity. }
  assert (Hmem2 : vm_mem v2 = vm_mem v1).
  { unfold v2. rewrite (action_mem_preserved_MOVI v1 6 10 2 Hpc1 eq_refl). reflexivity. }
  rewrite (run_one_false 3 action_block action_stop v2).
  2:{ unfold action_stop. rewrite Hpc2, Hhalt2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 8)
    by (unfold v3; rewrite (action_exec_pc v2 7 (iCMP 9 10) Hpc2 eq_refl);
        cbn; reflexivity).
  assert (Hhalt3 : vm_halted v3 = false).
  { unfold v3. rewrite (action_not_halted v2 7 (iCMP 9 10) Hpc2 eq_refl
      ltac:(discriminate)). exact Hhalt2. }
  assert (Hzf3 : vm_zf v3 = true).
  { unfold v3. rewrite (action_CMP_zf v2 7 9 10 Hpc2 eq_refl).
    rewrite Hr9_2, Hr10_2, Nat.eqb_refl. reflexivity. }
  assert (Hr2_3 : vm_reg v3 2 = head).
  { unfold v3. rewrite (action_reg_preserved_CMP v2 7 9 10 2 Hpc2 eq_refl). exact Hr2_2. }
  assert (Hr13_3 : vm_reg v3 13 = 1).
  { unfold v3. rewrite (action_reg_preserved_CMP v2 7 9 10 13 Hpc2 eq_refl). exact Hr13_2. }
  assert (Hr0_3 : vm_reg v3 0 = vm_reg v2 0).
  { unfold v3. rewrite (action_reg_preserved_CMP v2 7 9 10 0 Hpc2 eq_refl). reflexivity. }
  assert (Hr7_3 : vm_reg v3 7 = vm_reg v2 7).
  { unfold v3. rewrite (action_reg_preserved_CMP v2 7 9 10 7 Hpc2 eq_refl). reflexivity. }
  assert (Hmem3 : vm_mem v3 = vm_mem v2).
  { unfold v3. rewrite (action_mem_preserved_CMP v2 7 9 10 Hpc2 eq_refl). reflexivity. }
  rewrite (run_one_false 2 action_block action_stop v3).
  2:{ unfold action_stop. rewrite Hpc3, Hhalt3. cbn. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 12)
    by (unfold v4; rewrite (action_exec_pc v3 8 (iJMP pEQ 12) Hpc3 eq_refl);
        rewrite Hzf3; cbn; reflexivity).
  assert (Hhalt4 : vm_halted v4 = false).
  { unfold v4. rewrite (action_not_halted v3 8 (iJMP pEQ 12) Hpc3 eq_refl
      ltac:(discriminate)). exact Hhalt3. }
  assert (Hr2_4 : vm_reg v4 2 = head).
  { unfold v4. rewrite (action_reg_preserved_JMP v3 8 pEQ 12 2 Hpc3 eq_refl). exact Hr2_3. }
  assert (Hr13_4 : vm_reg v4 13 = 1).
  { unfold v4. rewrite (action_reg_preserved_JMP v3 8 pEQ 12 13 Hpc3 eq_refl). exact Hr13_3. }
  assert (Hr0_4 : vm_reg v4 0 = vm_reg v3 0).
  { unfold v4. rewrite (action_reg_preserved_JMP v3 8 pEQ 12 0 Hpc3 eq_refl). reflexivity. }
  assert (Hr7_4 : vm_reg v4 7 = vm_reg v3 7).
  { unfold v4. rewrite (action_reg_preserved_JMP v3 8 pEQ 12 7 Hpc3 eq_refl). reflexivity. }
  assert (Hmem4 : vm_mem v4 = vm_mem v3).
  { unfold v4. rewrite (action_mem_preserved_JMP v3 8 pEQ 12 Hpc3 eq_refl). reflexivity. }
  rewrite (run_one_false 1 action_block action_stop v4).
  2:{ unfold action_stop. rewrite Hpc4, Hhalt4. cbn. reflexivity. }
  fold v5.
  assert (Hpc5 : vm_pc v5 = 13)
    by (unfold v5; rewrite (action_exec_pc v4 12 (iADD 2 2 13) Hpc4 eq_refl);
        cbn; reflexivity).
  assert (Hhalt5 : vm_halted v5 = false).
  { unfold v5. rewrite (action_not_halted v4 12 (iADD 2 2 13) Hpc4 eq_refl
      ltac:(discriminate)). exact Hhalt4. }
  assert (Hr2_5 : vm_reg v5 2 = head + 1).
  { unfold v5. rewrite (action_ADD_reg v4 12 2 2 13 Hpc4 eq_refl).
    rewrite Hr2_4, Hr13_4. reflexivity. }
  assert (Hr0_5 : vm_reg v5 0 = vm_reg v4 0).
  { unfold v5. rewrite (action_reg_preserved_ADD v4 12 2 2 13 0 Hpc4 eq_refl ltac:(lia)).
    reflexivity. }
  assert (Hr7_5 : vm_reg v5 7 = vm_reg v4 7).
  { unfold v5. rewrite (action_reg_preserved_ADD v4 12 2 2 13 7 Hpc4 eq_refl ltac:(lia)).
    reflexivity. }
  assert (Hmem5 : vm_mem v5 = vm_mem v4).
  { unfold v5. rewrite (action_mem_preserved_ADD v4 12 2 2 13 Hpc4 eq_refl). reflexivity. }
  rewrite (run_one_false 0 action_block action_stop v5).
  2:{ unfold action_stop. rewrite Hpc5, Hhalt5. cbn. reflexivity. }
  cbn [run_until].
  fold v6.
  assert (Hpc6 : vm_pc v6 = 14)
    by (unfold v6; rewrite (action_exec_pc v5 13 (iJMP pALWAYS 14) Hpc5 eq_refl);
        cbn; reflexivity).
  assert (Hhalt6 : vm_halted v6 = false).
  { unfold v6. rewrite (action_not_halted v5 13 (iJMP pALWAYS 14) Hpc5 eq_refl
      ltac:(discriminate)). exact Hhalt5. }
  assert (Hr2_6 : vm_reg v6 2 = head + 1).
  { unfold v6. rewrite (action_reg_preserved_JMP v5 13 pALWAYS 14 2 Hpc5 eq_refl).
    exact Hr2_5. }
  assert (Hr0_6 : vm_reg v6 0 = vm_reg vm 0).
  { unfold v6. rewrite (action_reg_preserved_JMP v5 13 pALWAYS 14 0 Hpc5 eq_refl).
    rewrite Hr0_5, Hr0_4, Hr0_3, Hr0_2, Hr0_1. reflexivity. }
  assert (Hr7_6 : vm_reg v6 7 = vm_reg vm 7).
  { unfold v6. rewrite (action_reg_preserved_JMP v5 13 pALWAYS 14 7 Hpc5 eq_refl).
    rewrite Hr7_5, Hr7_4, Hr7_3, Hr7_2, Hr7_1. reflexivity. }
  assert (Hmem6 : vm_mem v6 = vm_mem vm).
  { unfold v6. rewrite (action_mem_preserved_JMP v5 13 pALWAYS 14 Hpc5 eq_refl).
    rewrite Hmem5, Hmem4, Hmem3, Hmem2, Hmem1. reflexivity. }
  repeat split; assumption.
Qed.

Lemma action_move_other :
  forall (vm : VM) (head move : nat),
    vm_pc vm = 5 ->
    vm_reg vm 2 = head ->
    vm_reg vm 9 = move ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_zf vm = false ->
    Nat.eqb move 2 = false ->
    let vm' := run_until 5 action_block action_stop vm in
    vm_pc vm' = 14 /\
    vm_reg vm' 2 = head /\
    vm_halted vm' = false /\
    vm_reg vm' 0 = vm_reg vm 0 /\
    vm_reg vm' 7 = vm_reg vm 7 /\
    vm_mem vm' = vm_mem vm.
Proof.
  intros vm head move Hpc Hr2 Hr9 Hr13 Hhalt Hzf E2.
  set (v1 := exec_instr action_block vm).
  set (v2 := exec_instr action_block v1).
  set (v3 := exec_instr action_block v2).
  set (v4 := exec_instr action_block v3).
  set (v5 := exec_instr action_block v4).
  rewrite (run_one_false 4 action_block action_stop vm).
  2:{ unfold action_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 6)
    by (unfold v1; rewrite (action_exec_pc vm 5 (iJMP pEQ 10) Hpc eq_refl);
        rewrite Hzf; cbn; reflexivity).
  assert (Hhalt1 : vm_halted v1 = false).
  { unfold v1. rewrite (action_not_halted vm 5 (iJMP pEQ 10) Hpc eq_refl
      ltac:(discriminate)). exact Hhalt. }
  assert (Hr2_1 : vm_reg v1 2 = head).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 2 Hpc eq_refl). exact Hr2. }
  assert (Hr9_1 : vm_reg v1 9 = move).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 9 Hpc eq_refl). exact Hr9. }
  assert (Hr0_1 : vm_reg v1 0 = vm_reg vm 0).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 0 Hpc eq_refl). reflexivity. }
  assert (Hr7_1 : vm_reg v1 7 = vm_reg vm 7).
  { unfold v1. rewrite (action_reg_preserved_JMP vm 5 pEQ 10 7 Hpc eq_refl). reflexivity. }
  assert (Hmem1 : vm_mem v1 = vm_mem vm).
  { unfold v1. rewrite (action_mem_preserved_JMP vm 5 pEQ 10 Hpc eq_refl). reflexivity. }
  rewrite (run_one_false 3 action_block action_stop v1).
  2:{ unfold action_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 7)
    by (unfold v2; rewrite (action_exec_pc v1 6 (iMOVI 10 2) Hpc1 eq_refl);
        cbn; reflexivity).
  assert (Hhalt2 : vm_halted v2 = false).
  { unfold v2. rewrite (action_not_halted v1 6 (iMOVI 10 2) Hpc1 eq_refl
      ltac:(discriminate)). exact Hhalt1. }
  assert (Hr2_2 : vm_reg v2 2 = head).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 2 Hpc1 eq_refl ltac:(lia)).
    exact Hr2_1. }
  assert (Hr9_2 : vm_reg v2 9 = move).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 9 Hpc1 eq_refl ltac:(lia)).
    exact Hr9_1. }
  assert (Hr10_2 : vm_reg v2 10 = 2).
  { unfold v2. rewrite (action_MOVI_reg v1 6 10 2 Hpc1 eq_refl). reflexivity. }
  assert (Hr0_2 : vm_reg v2 0 = vm_reg v1 0).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 0 Hpc1 eq_refl ltac:(lia)).
    reflexivity. }
  assert (Hr7_2 : vm_reg v2 7 = vm_reg v1 7).
  { unfold v2. rewrite (action_reg_preserved_MOVI v1 6 10 2 7 Hpc1 eq_refl ltac:(lia)).
    reflexivity. }
  assert (Hmem2 : vm_mem v2 = vm_mem v1).
  { unfold v2. rewrite (action_mem_preserved_MOVI v1 6 10 2 Hpc1 eq_refl). reflexivity. }
  rewrite (run_one_false 2 action_block action_stop v2).
  2:{ unfold action_stop. rewrite Hpc2, Hhalt2. cbn. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 8)
    by (unfold v3; rewrite (action_exec_pc v2 7 (iCMP 9 10) Hpc2 eq_refl);
        cbn; reflexivity).
  assert (Hhalt3 : vm_halted v3 = false).
  { unfold v3. rewrite (action_not_halted v2 7 (iCMP 9 10) Hpc2 eq_refl
      ltac:(discriminate)). exact Hhalt2. }
  assert (Hzf3 : vm_zf v3 = false).
  { unfold v3. rewrite (action_CMP_zf v2 7 9 10 Hpc2 eq_refl).
    rewrite Hr9_2, Hr10_2. exact E2. }
  assert (Hr2_3 : vm_reg v3 2 = head).
  { unfold v3. rewrite (action_reg_preserved_CMP v2 7 9 10 2 Hpc2 eq_refl). exact Hr2_2. }
  assert (Hr0_3 : vm_reg v3 0 = vm_reg v2 0).
  { unfold v3. rewrite (action_reg_preserved_CMP v2 7 9 10 0 Hpc2 eq_refl). reflexivity. }
  assert (Hr7_3 : vm_reg v3 7 = vm_reg v2 7).
  { unfold v3. rewrite (action_reg_preserved_CMP v2 7 9 10 7 Hpc2 eq_refl). reflexivity. }
  assert (Hmem3 : vm_mem v3 = vm_mem v2).
  { unfold v3. rewrite (action_mem_preserved_CMP v2 7 9 10 Hpc2 eq_refl). reflexivity. }
  rewrite (run_one_false 1 action_block action_stop v3).
  2:{ unfold action_stop. rewrite Hpc3, Hhalt3. cbn. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 9)
    by (unfold v4; rewrite (action_exec_pc v3 8 (iJMP pEQ 12) Hpc3 eq_refl);
        rewrite Hzf3; cbn; reflexivity).
  assert (Hhalt4 : vm_halted v4 = false).
  { unfold v4. rewrite (action_not_halted v3 8 (iJMP pEQ 12) Hpc3 eq_refl
      ltac:(discriminate)). exact Hhalt3. }
  assert (Hr2_4 : vm_reg v4 2 = head).
  { unfold v4. rewrite (action_reg_preserved_JMP v3 8 pEQ 12 2 Hpc3 eq_refl). exact Hr2_3. }
  assert (Hr0_4 : vm_reg v4 0 = vm_reg v3 0).
  { unfold v4. rewrite (action_reg_preserved_JMP v3 8 pEQ 12 0 Hpc3 eq_refl). reflexivity. }
  assert (Hr7_4 : vm_reg v4 7 = vm_reg v3 7).
  { unfold v4. rewrite (action_reg_preserved_JMP v3 8 pEQ 12 7 Hpc3 eq_refl). reflexivity. }
  assert (Hmem4 : vm_mem v4 = vm_mem v3).
  { unfold v4. rewrite (action_mem_preserved_JMP v3 8 pEQ 12 Hpc3 eq_refl). reflexivity. }
  rewrite (run_one_false 0 action_block action_stop v4).
  2:{ unfold action_stop. rewrite Hpc4, Hhalt4. cbn. reflexivity. }
  fold v5.
  assert (Hpc5 : vm_pc v5 = 14)
    by (unfold v5; rewrite (action_exec_pc v4 9 (iJMP pALWAYS 14) Hpc4 eq_refl);
        cbn; reflexivity).
  assert (Hhalt5 : vm_halted v5 = false).
  { unfold v5. rewrite (action_not_halted v4 9 (iJMP pALWAYS 14) Hpc4 eq_refl
      ltac:(discriminate)). exact Hhalt4. }
  assert (Hr2_5 : vm_reg v5 2 = head).
  { unfold v5. rewrite (action_reg_preserved_JMP v4 9 pALWAYS 14 2 Hpc4 eq_refl).
    exact Hr2_4. }
  assert (Hr0_5 : vm_reg v5 0 = vm_reg vm 0).
  { unfold v5. rewrite (action_reg_preserved_JMP v4 9 pALWAYS 14 0 Hpc4 eq_refl).
    rewrite Hr0_4, Hr0_3, Hr0_2, Hr0_1. reflexivity. }
  assert (Hr7_5 : vm_reg v5 7 = vm_reg vm 7).
  { unfold v5. rewrite (action_reg_preserved_JMP v4 9 pALWAYS 14 7 Hpc4 eq_refl).
    rewrite Hr7_4, Hr7_3, Hr7_2, Hr7_1. reflexivity. }
  assert (Hmem5 : vm_mem v5 = vm_mem vm).
  { unfold v5. rewrite (action_mem_preserved_JMP v4 9 pALWAYS 14 Hpc4 eq_refl).
    rewrite Hmem4, Hmem3, Hmem2, Hmem1. reflexivity. }
  cbn [run_until].
  fold v5.
  repeat split; assumption.
Qed.

Definition action_move_fuel (move : nat) : nat :=
  if Nat.eqb move 0 then 3 else if Nat.eqb move 2 then 6 else 5.

Lemma action_move :
  forall (vm : VM) (head move : nat),
    vm_pc vm = 5 ->
    vm_reg vm 2 = head ->
    vm_reg vm 9 = move ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_zf vm = Nat.eqb move 0 ->
    vm_lf vm = Nat.ltb move 0 ->
    let vm' := run_until (action_move_fuel move) action_block action_stop vm in
    vm_pc vm' = 14 /\
    vm_reg vm' 2 = action_new_head head move /\
    vm_halted vm' = false /\
    vm_reg vm' 0 = vm_reg vm 0 /\
    vm_reg vm' 7 = vm_reg vm 7 /\
    vm_mem vm' = vm_mem vm.
Proof.
  intros vm head move Hpc Hr2 Hr9 Hr13 Hhalt Hzf Hlf.
  destruct (Nat.eqb move 0) eqn:E0.
  - apply Nat.eqb_eq in E0.
    rewrite E0 in Hr9.
    unfold action_new_head, action_move_fuel. rewrite E0. cbn.
    apply action_move_zero; [exact Hpc|exact Hr2|exact Hr9|exact Hr13|exact Hhalt|exact Hzf].
  - destruct (Nat.eqb move 2) eqn:E2.
    + apply Nat.eqb_eq in E2.
      rewrite E2 in Hr9.
      unfold action_new_head, action_move_fuel. rewrite E0, E2. cbn.
      apply action_move_right; [exact Hpc|exact Hr2|exact Hr9|exact Hr13|exact Hhalt|exact Hzf].
    + unfold action_new_head, action_move_fuel. rewrite E0, E2. cbn.
      apply (action_move_other vm head move); [exact Hpc|exact Hr2|exact Hr9|exact Hr13|exact Hhalt|exact Hzf|exact E2].
Qed.


