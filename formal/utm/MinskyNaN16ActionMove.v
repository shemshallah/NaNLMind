From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action.

Definition action_move_stop (pc : nat) : bool := Nat.eqb pc 14.

Lemma action_move_zero :
  forall (vm : VM) (head : nat),
    vm_pc vm = 5 ->
    vm_reg vm 2 = head ->
    vm_reg vm 9 = 0 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_zf vm = true ->
    let vm' := run_until 6 action_block action_move_stop vm in
    vm_pc vm' = 14 /\
    vm_reg vm' 2 = head - 1 /\
    vm_halted vm' = false.
Proof.
  intros vm head Hpc Hr2 Hr9 Hr13 Hhalt Hzf.
  set (v1 := exec_instr action_block vm).
  set (v2 := exec_instr action_block v1).
  set (v3 := exec_instr action_block v2).
  rewrite (run_one_false 5 action_block action_move_stop vm).
  2:{ unfold action_move_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
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
  rewrite (run_one_false 4 action_block action_move_stop v1).
  2:{ unfold action_move_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
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
  rewrite (run_one_false 3 action_block action_move_stop v2).
  2:{ unfold action_move_stop. rewrite Hpc2, Hhalt2. cbn. reflexivity. }
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
  cbn [run_until action_move_stop orb].
  rewrite Hpc3. cbn.
  split; [exact Hpc3|split; [exact Hr2_3|exact Hhalt3]].
Qed.

Lemma action_move_right :
  forall (vm : VM) (head : nat),
    vm_pc vm = 5 ->
    vm_reg vm 2 = head ->
    vm_reg vm 9 = 2 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_zf vm = false ->
    let vm' := run_until 6 action_block action_move_stop vm in
    vm_pc vm' = 14 /\
    vm_reg vm' 2 = head + 1 /\
    vm_halted vm' = false.
Proof.
  intros vm head Hpc Hr2 Hr9 Hr13 Hhalt Hzf.
  set (v1 := exec_instr action_block vm).
  set (v2 := exec_instr action_block v1).
  set (v3 := exec_instr action_block v2).
  set (v4 := exec_instr action_block v3).
  set (v5 := exec_instr action_block v4).
  set (v6 := exec_instr action_block v5).
  rewrite (run_one_false 5 action_block action_move_stop vm).
  2:{ unfold action_move_stop. rewrite Hpc, Hhalt. cbn. reflexivity. }
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
  rewrite (run_one_false 4 action_block action_move_stop v1).
  2:{ unfold action_move_stop. rewrite Hpc1, Hhalt1. cbn. reflexivity. }
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
  rewrite (run_one_false 3 action_block action_move_stop v2).
  2:{ unfold action_move_stop. rewrite Hpc2, Hhalt2. cbn. reflexivity. }
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
  rewrite (run_one_false 2 action_block action_move_stop v3).
  2:{ unfold action_move_stop. rewrite Hpc3, Hhalt3. cbn. reflexivity. }
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
  rewrite (run_one_false 1 action_block action_move_stop v4).
  2:{ unfold action_move_stop. rewrite Hpc4, Hhalt4. cbn. reflexivity. }
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
  rewrite (run_one_false 0 action_block action_move_stop v5).
  2:{ unfold action_move_stop. rewrite Hpc5, Hhalt5. cbn. reflexivity. }
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
  split; [exact Hpc6|split; [exact Hr2_6|exact Hhalt6]].
Qed.
