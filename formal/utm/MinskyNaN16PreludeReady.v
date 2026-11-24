From Coq Require Import List Arith Bool Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM MinskyNaN16Action MinskyNaN16Prelude.

(** The prelude when the halt cell is zero: it loads the source state, head,
    tape base and read symbol and ends at pc 11 with the scan registers set. *)

Lemma prelude_ready :
  forall (table_base : nat) (vm : VM),
    vm_pc vm = 0 ->
    vm_reg vm 0 = 0 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_mem vm action_halt_addr = 0 ->
    let vm' := run_until 11 (prelude_block table_base) (fun _ => false) vm in
    vm_pc vm' = 11 /\
    vm_reg vm' 1 = vm_mem vm action_state_addr /\
    vm_reg vm' 2 = vm_mem vm action_head_addr /\
    vm_reg vm' 3 = vm_mem vm tape_base_addr + vm_reg vm' 2 /\
    vm_reg vm' 4 = vm_mem vm (vm_reg vm' 3) /\
    vm_reg vm' 5 = table_base /\
    vm_reg vm' 6 = 184 /\
    vm_reg vm' 8 = 0 /\
    vm_reg vm' 0 = 0 /\
    vm_reg vm' 13 = 1 /\
    vm_mem vm' = vm_mem vm /\
    vm_halted vm' = false.
Proof.
  intros table_base vm Hpc Hr0 Hr13 Hhalt Hhaltcell.
  set (v1 := exec_instr (prelude_block table_base) vm).
  rewrite (run_one_false 10 (prelude_block table_base) (fun _ => false) vm).
  2:{ cbn. rewrite Hhalt. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 1).
  { unfold v1. rewrite (prelude_exec_pc table_base vm 0 (iLD 1 0 action_halt_addr) Hpc eq_refl). cbn. reflexivity. }
  assert (Hhalt1 : vm_halted v1 = false).
  { unfold v1. rewrite (prelude_not_halted table_base vm 0 (iLD 1 0 action_halt_addr) Hpc eq_refl ltac:(discriminate)). exact Hhalt. }
  assert (Hmem1 : vm_mem v1 = vm_mem vm).
  { unfold v1. apply prelude_exec_mem. }
  assert (Hr0_1 : vm_reg v1 0 = 0).
  { unfold v1. rewrite prelude_exec_reg0. exact Hr0. }
  assert (Hr13_1 : vm_reg v1 13 = 1).
  { unfold v1. rewrite prelude_exec_reg13. exact Hr13. }
  assert (Hr1_1 : vm_reg v1 1 = 0).
  { unfold v1. rewrite (prelude_LD_reg table_base vm 0 1 0 action_halt_addr Hpc eq_refl).
    rewrite Hr0. cbn. rewrite Hhaltcell. reflexivity. }

  set (v2 := exec_instr (prelude_block table_base) v1).
  rewrite (run_one_false 9 (prelude_block table_base) (fun _ => false) v1).
  2:{ cbn. rewrite Hhalt1. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 2).
  { unfold v2. rewrite (prelude_exec_pc table_base v1 1 (iCMP 1 0) Hpc1 eq_refl). cbn. reflexivity. }
  assert (Hhalt2 : vm_halted v2 = false).
  { unfold v2. rewrite (prelude_not_halted table_base v1 1 (iCMP 1 0) Hpc1 eq_refl ltac:(discriminate)). exact Hhalt1. }
  assert (Hmem2 : vm_mem v2 = vm_mem vm).
  { unfold v2. rewrite prelude_exec_mem. exact Hmem1. }
  assert (Hr0_2 : vm_reg v2 0 = 0).
  { unfold v2. rewrite prelude_exec_reg0. exact Hr0_1. }
  assert (Hr13_2 : vm_reg v2 13 = 1).
  { unfold v2. rewrite prelude_exec_reg13. exact Hr13_1. }
  assert (Hzf2 : vm_zf v2 = true).
  { unfold v2. rewrite (prelude_CMP_zf table_base v1 1 1 0 Hpc1 eq_refl).
    rewrite Hr1_1, Hr0_1. reflexivity. }

  set (v3 := exec_instr (prelude_block table_base) v2).
  rewrite (run_one_false 8 (prelude_block table_base) (fun _ => false) v2).
  2:{ cbn. rewrite Hhalt2. reflexivity. }
  fold v3.
  assert (Hpc3 : vm_pc v3 = 3).
  { unfold v3. rewrite (prelude_exec_pc table_base v2 2 (iJMP pNE 11) Hpc2 eq_refl).
    cbn [pred_holds]. rewrite Hzf2. cbn. reflexivity. }
  assert (Hhalt3 : vm_halted v3 = false).
  { unfold v3. rewrite (prelude_not_halted table_base v2 2 (iJMP pNE 11) Hpc2 eq_refl ltac:(discriminate)). exact Hhalt2. }
  assert (Hmem3 : vm_mem v3 = vm_mem vm).
  { unfold v3. rewrite prelude_exec_mem. exact Hmem2. }
  assert (Hr0_3 : vm_reg v3 0 = 0).
  { unfold v3. rewrite prelude_exec_reg0. exact Hr0_2. }
  assert (Hr13_3 : vm_reg v3 13 = 1).
  { unfold v3. rewrite prelude_exec_reg13. exact Hr13_2. }

  set (v4 := exec_instr (prelude_block table_base) v3).
  rewrite (run_one_false 7 (prelude_block table_base) (fun _ => false) v3).
  2:{ cbn. rewrite Hhalt3. reflexivity. }
  fold v4.
  assert (Hpc4 : vm_pc v4 = 4).
  { unfold v4. rewrite (prelude_exec_pc table_base v3 3 (iLD 1 0 action_state_addr) Hpc3 eq_refl). cbn. reflexivity. }
  assert (Hhalt4 : vm_halted v4 = false).
  { unfold v4. rewrite (prelude_not_halted table_base v3 3 (iLD 1 0 action_state_addr) Hpc3 eq_refl ltac:(discriminate)). exact Hhalt3. }
  assert (Hmem4 : vm_mem v4 = vm_mem vm).
  { unfold v4. rewrite prelude_exec_mem. exact Hmem3. }
  assert (Hr0_4 : vm_reg v4 0 = 0).
  { unfold v4. rewrite prelude_exec_reg0. exact Hr0_3. }
  assert (Hr13_4 : vm_reg v4 13 = 1).
  { unfold v4. rewrite prelude_exec_reg13. exact Hr13_3. }
  assert (Hr1_4 : vm_reg v4 1 = vm_mem vm action_state_addr).
  { unfold v4. rewrite (prelude_LD_reg table_base v3 3 1 0 action_state_addr Hpc3 eq_refl).
    rewrite Hr0_3, Hmem3. cbn. reflexivity. }

  set (v5 := exec_instr (prelude_block table_base) v4).
  rewrite (run_one_false 6 (prelude_block table_base) (fun _ => false) v4).
  2:{ cbn. rewrite Hhalt4. reflexivity. }
  fold v5.
  assert (Hpc5 : vm_pc v5 = 5).
  { unfold v5. rewrite (prelude_exec_pc table_base v4 4 (iLD 2 0 action_head_addr) Hpc4 eq_refl). cbn. reflexivity. }
  assert (Hhalt5 : vm_halted v5 = false).
  { unfold v5. rewrite (prelude_not_halted table_base v4 4 (iLD 2 0 action_head_addr) Hpc4 eq_refl ltac:(discriminate)). exact Hhalt4. }
  assert (Hmem5 : vm_mem v5 = vm_mem vm).
  { unfold v5. rewrite prelude_exec_mem. exact Hmem4. }
  assert (Hr0_5 : vm_reg v5 0 = 0).
  { unfold v5. rewrite prelude_exec_reg0. exact Hr0_4. }
  assert (Hr13_5 : vm_reg v5 13 = 1).
  { unfold v5. rewrite prelude_exec_reg13. exact Hr13_4. }
  assert (Hr2_5 : vm_reg v5 2 = vm_mem vm action_head_addr).
  { unfold v5. rewrite (prelude_LD_reg table_base v4 4 2 0 action_head_addr Hpc4 eq_refl).
    rewrite Hr0_4, Hmem4. cbn. reflexivity. }

  set (v6 := exec_instr (prelude_block table_base) v5).
  rewrite (run_one_false 5 (prelude_block table_base) (fun _ => false) v5).
  2:{ cbn. rewrite Hhalt5. reflexivity. }
  fold v6.
  assert (Hpc6 : vm_pc v6 = 6).
  { unfold v6. rewrite (prelude_exec_pc table_base v5 5 (iLD 3 0 tape_base_addr) Hpc5 eq_refl). cbn. reflexivity. }
  assert (Hhalt6 : vm_halted v6 = false).
  { unfold v6. rewrite (prelude_not_halted table_base v5 5 (iLD 3 0 tape_base_addr) Hpc5 eq_refl ltac:(discriminate)). exact Hhalt5. }
  assert (Hmem6 : vm_mem v6 = vm_mem vm).
  { unfold v6. rewrite prelude_exec_mem. exact Hmem5. }
  assert (Hr0_6 : vm_reg v6 0 = 0).
  { unfold v6. rewrite prelude_exec_reg0. exact Hr0_5. }
  assert (Hr13_6 : vm_reg v6 13 = 1).
  { unfold v6. rewrite prelude_exec_reg13. exact Hr13_5. }
  assert (Hr3_6 : vm_reg v6 3 = vm_mem vm tape_base_addr).
  { unfold v6. rewrite (prelude_LD_reg table_base v5 5 3 0 tape_base_addr Hpc5 eq_refl).
    rewrite Hr0_5, Hmem5. cbn. reflexivity. }
  assert (Hr2_6 : vm_reg v6 2 = vm_mem vm action_head_addr).
  { unfold v6, exec_instr. rewrite Hpc5. cbn [nth_error prelude_block]. cbn.
    exact Hr2_5. }

  set (v7 := exec_instr (prelude_block table_base) v6).
  rewrite (run_one_false 4 (prelude_block table_base) (fun _ => false) v6).
  2:{ cbn. rewrite Hhalt6. reflexivity. }
  fold v7.
  assert (Hpc7 : vm_pc v7 = 7).
  { unfold v7. rewrite (prelude_exec_pc table_base v6 6 (iADD 3 3 2) Hpc6 eq_refl). cbn. reflexivity. }
  assert (Hhalt7 : vm_halted v7 = false).
  { unfold v7. rewrite (prelude_not_halted table_base v6 6 (iADD 3 3 2) Hpc6 eq_refl ltac:(discriminate)). exact Hhalt6. }
  assert (Hmem7 : vm_mem v7 = vm_mem vm).
  { unfold v7. rewrite prelude_exec_mem. exact Hmem6. }
  assert (Hr0_7 : vm_reg v7 0 = 0).
  { unfold v7. rewrite prelude_exec_reg0. exact Hr0_6. }
  assert (Hr13_7 : vm_reg v7 13 = 1).
  { unfold v7. rewrite prelude_exec_reg13. exact Hr13_6. }
  assert (Hr3_7 : vm_reg v7 3 = vm_mem vm tape_base_addr + vm_mem vm action_head_addr).
  { unfold v7. rewrite (prelude_ADD_reg table_base v6 6 3 3 2 Hpc6 eq_refl).
    rewrite Hr3_6, Hr2_6. reflexivity. }

  set (v8 := exec_instr (prelude_block table_base) v7).
  rewrite (run_one_false 3 (prelude_block table_base) (fun _ => false) v7).
  2:{ cbn. rewrite Hhalt7. reflexivity. }
  fold v8.
  assert (Hpc8 : vm_pc v8 = 8).
  { unfold v8. rewrite (prelude_exec_pc table_base v7 7 (iLD 4 3 0) Hpc7 eq_refl). cbn. reflexivity. }
  assert (Hhalt8 : vm_halted v8 = false).
  { unfold v8. rewrite (prelude_not_halted table_base v7 7 (iLD 4 3 0) Hpc7 eq_refl ltac:(discriminate)). exact Hhalt7. }
  assert (Hmem8 : vm_mem v8 = vm_mem vm).
  { unfold v8. rewrite prelude_exec_mem. exact Hmem7. }
  assert (Hr0_8 : vm_reg v8 0 = 0).
  { unfold v8. rewrite prelude_exec_reg0. exact Hr0_7. }
  assert (Hr13_8 : vm_reg v8 13 = 1).
  { unfold v8. rewrite prelude_exec_reg13. exact Hr13_7. }
  assert (Hr4_8 : vm_reg v8 4 = vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr)).
  { unfold v8. rewrite (prelude_LD_reg table_base v7 7 4 3 0 Hpc7 eq_refl).
    rewrite Hr3_7, Hmem7.
    replace (vm_mem vm tape_base_addr + vm_mem vm action_head_addr + 0)
      with (vm_mem vm tape_base_addr + vm_mem vm action_head_addr) by lia.
    reflexivity. }

  set (v9 := exec_instr (prelude_block table_base) v8).
  rewrite (run_one_false 2 (prelude_block table_base) (fun _ => false) v8).
  2:{ cbn. rewrite Hhalt8. reflexivity. }
  fold v9.
  assert (Hpc9 : vm_pc v9 = 9).
  { unfold v9. rewrite (prelude_exec_pc table_base v8 8 (iMOVI 5 table_base) Hpc8 eq_refl). cbn. reflexivity. }
  assert (Hhalt9 : vm_halted v9 = false).
  { unfold v9. rewrite (prelude_not_halted table_base v8 8 (iMOVI 5 table_base) Hpc8 eq_refl ltac:(discriminate)). exact Hhalt8. }
  assert (Hmem9 : vm_mem v9 = vm_mem vm).
  { unfold v9. rewrite prelude_exec_mem. exact Hmem8. }
  assert (Hr0_9 : vm_reg v9 0 = 0).
  { unfold v9. rewrite prelude_exec_reg0. exact Hr0_8. }
  assert (Hr13_9 : vm_reg v9 13 = 1).
  { unfold v9. rewrite prelude_exec_reg13. exact Hr13_8. }
  assert (Hr5_9 : vm_reg v9 5 = table_base).
  { unfold v9. rewrite (prelude_MOVI_reg table_base v8 8 5 table_base Hpc8 eq_refl). reflexivity. }

  set (v10 := exec_instr (prelude_block table_base) v9).
  rewrite (run_one_false 1 (prelude_block table_base) (fun _ => false) v9).
  2:{ cbn. rewrite Hhalt9. reflexivity. }
  fold v10.
  assert (Hpc10 : vm_pc v10 = 10).
  { unfold v10. rewrite (prelude_exec_pc table_base v9 9 (iMOVI 6 184) Hpc9 eq_refl). cbn. reflexivity. }
  assert (Hhalt10 : vm_halted v10 = false).
  { unfold v10. rewrite (prelude_not_halted table_base v9 9 (iMOVI 6 184) Hpc9 eq_refl ltac:(discriminate)). exact Hhalt9. }
  assert (Hmem10 : vm_mem v10 = vm_mem vm).
  { unfold v10. rewrite prelude_exec_mem. exact Hmem9. }
  assert (Hr0_10 : vm_reg v10 0 = 0).
  { unfold v10. rewrite prelude_exec_reg0. exact Hr0_9. }
  assert (Hr13_10 : vm_reg v10 13 = 1).
  { unfold v10. rewrite prelude_exec_reg13. exact Hr13_9. }
  assert (Hr6_10 : vm_reg v10 6 = 184).
  { unfold v10. rewrite (prelude_MOVI_reg table_base v9 9 6 184 Hpc9 eq_refl). reflexivity. }

  set (v11 := exec_instr (prelude_block table_base) v10).
  rewrite (run_one_false 0 (prelude_block table_base) (fun _ => false) v10).
  2:{ cbn. rewrite Hhalt10. reflexivity. }
  cbn [run_until]. fold v11.
  assert (Hpc11 : vm_pc v11 = 11).
  { unfold v11. rewrite (prelude_exec_pc table_base v10 10 (iMOVI 8 0) Hpc10 eq_refl). cbn. reflexivity. }
  assert (Hhalt11 : vm_halted v11 = false).
  { unfold v11. rewrite (prelude_not_halted table_base v10 10 (iMOVI 8 0) Hpc10 eq_refl ltac:(discriminate)). exact Hhalt10. }
  assert (Hmem11 : vm_mem v11 = vm_mem vm).
  { unfold v11. rewrite prelude_exec_mem. exact Hmem10. }
  assert (Hr0_11 : vm_reg v11 0 = 0).
  { unfold v11. rewrite prelude_exec_reg0. exact Hr0_10. }
  assert (Hr13_11 : vm_reg v11 13 = 1).
  { unfold v11. rewrite prelude_exec_reg13. exact Hr13_10. }
  assert (Hr8_11 : vm_reg v11 8 = 0).
  { unfold v11. rewrite (prelude_MOVI_reg table_base v10 10 8 0 Hpc10 eq_refl). reflexivity. }
  assert (Hr1_5 : vm_reg v5 1 = vm_mem vm action_state_addr).
  { unfold v5, exec_instr. rewrite Hpc4. cbn [nth_error prelude_block]. cbn.
    exact Hr1_4. }
  assert (Hr1_6 : vm_reg v6 1 = vm_mem vm action_state_addr).
  { unfold v6, exec_instr. rewrite Hpc5. cbn [nth_error prelude_block]. cbn.
    exact Hr1_5. }
  assert (Hr1_7 : vm_reg v7 1 = vm_mem vm action_state_addr).
  { unfold v7, exec_instr. rewrite Hpc6. cbn [nth_error prelude_block]. cbn.
    exact Hr1_6. }
  assert (Hr1_8 : vm_reg v8 1 = vm_mem vm action_state_addr).
  { unfold v8, exec_instr. rewrite Hpc7. cbn [nth_error prelude_block]. cbn.
    exact Hr1_7. }
  assert (Hr1_9 : vm_reg v9 1 = vm_mem vm action_state_addr).
  { unfold v9, exec_instr. rewrite Hpc8. cbn [nth_error prelude_block]. cbn.
    exact Hr1_8. }
  assert (Hr1_10 : vm_reg v10 1 = vm_mem vm action_state_addr).
  { unfold v10, exec_instr. rewrite Hpc9. cbn [nth_error prelude_block]. cbn.
    exact Hr1_9. }
  assert (Hr1_11 : vm_reg v11 1 = vm_mem vm action_state_addr).
  { unfold v11, exec_instr. rewrite Hpc10. cbn [nth_error prelude_block]. cbn.
    exact Hr1_10. }
  assert (Hr2_7 : vm_reg v7 2 = vm_mem vm action_head_addr).
  { unfold v7, exec_instr. rewrite Hpc6. cbn [nth_error prelude_block]. cbn.
    exact Hr2_6. }
  assert (Hr2_8 : vm_reg v8 2 = vm_mem vm action_head_addr).
  { unfold v8, exec_instr. rewrite Hpc7. cbn [nth_error prelude_block]. cbn.
    exact Hr2_7. }
  assert (Hr2_9 : vm_reg v9 2 = vm_mem vm action_head_addr).
  { unfold v9, exec_instr. rewrite Hpc8. cbn [nth_error prelude_block]. cbn.
    exact Hr2_8. }
  assert (Hr2_10 : vm_reg v10 2 = vm_mem vm action_head_addr).
  { unfold v10, exec_instr. rewrite Hpc9. cbn [nth_error prelude_block]. cbn.
    exact Hr2_9. }
  assert (Hr2_11 : vm_reg v11 2 = vm_mem vm action_head_addr).
  { unfold v11, exec_instr. rewrite Hpc10. cbn [nth_error prelude_block]. cbn.
    exact Hr2_10. }
  assert (Hr3_8 : vm_reg v8 3 = vm_mem vm tape_base_addr + vm_mem vm action_head_addr).
  { unfold v8, exec_instr. rewrite Hpc7. cbn [nth_error prelude_block]. cbn.
    exact Hr3_7. }
  assert (Hr3_9 : vm_reg v9 3 = vm_mem vm tape_base_addr + vm_mem vm action_head_addr).
  { unfold v9, exec_instr. rewrite Hpc8. cbn [nth_error prelude_block]. cbn.
    exact Hr3_8. }
  assert (Hr3_10 : vm_reg v10 3 = vm_mem vm tape_base_addr + vm_mem vm action_head_addr).
  { unfold v10, exec_instr. rewrite Hpc9. cbn [nth_error prelude_block]. cbn.
    exact Hr3_9. }
  assert (Hr3_11 : vm_reg v11 3 = vm_mem vm tape_base_addr + vm_mem vm action_head_addr).
  { unfold v11, exec_instr. rewrite Hpc10. cbn [nth_error prelude_block]. cbn.
    exact Hr3_10. }
  assert (Hr4_9 : vm_reg v9 4 = vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr)).
  { unfold v9, exec_instr. rewrite Hpc8. cbn [nth_error prelude_block]. cbn.
    exact Hr4_8. }
  assert (Hr4_10 : vm_reg v10 4 = vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr)).
  { unfold v10, exec_instr. rewrite Hpc9. cbn [nth_error prelude_block]. cbn.
    exact Hr4_9. }
  assert (Hr4_11 : vm_reg v11 4 = vm_mem vm (vm_mem vm tape_base_addr + vm_mem vm action_head_addr)).
  { unfold v11, exec_instr. rewrite Hpc10. cbn [nth_error prelude_block]. cbn.
    exact Hr4_10. }
  assert (Hr5_10 : vm_reg v10 5 = table_base).
  { unfold v10, exec_instr. rewrite Hpc9. cbn [nth_error prelude_block]. cbn.
    exact Hr5_9. }
  assert (Hr5_11 : vm_reg v11 5 = table_base).
  { unfold v11, exec_instr. rewrite Hpc10. cbn [nth_error prelude_block]. cbn.
    exact Hr5_10. }
  assert (Hr6_11 : vm_reg v11 6 = 184).
  { unfold v11, exec_instr. rewrite Hpc10. cbn [nth_error prelude_block]. cbn.
    exact Hr6_10. }
  repeat split; try assumption.
  { rewrite Hr2_11. exact Hr3_11. }
  { rewrite Hr3_11. exact Hr4_11. }
Qed.

(** The prelude when the halt cell is nonzero: three instructions and a
    jump to the return point at pc 11. *)

Lemma prelude_halted :
  forall (table_base : nat) (vm : VM),
    vm_pc vm = 0 ->
    vm_reg vm 0 = 0 ->
    vm_reg vm 13 = 1 ->
    vm_halted vm = false ->
    vm_mem vm action_halt_addr <> 0 ->
    let vm' := run_until 3 (prelude_block table_base) (fun _ => false) vm in
    vm_pc vm' = 11 /\
    vm_reg vm' 1 = vm_mem vm action_halt_addr /\
    vm_reg vm' 0 = 0 /\
    vm_reg vm' 13 = 1 /\
    vm_mem vm' = vm_mem vm /\
    vm_halted vm' = false.
Proof.
  intros table_base vm Hpc Hr0 Hr13 Hhalt Hne.
  set (v1 := exec_instr (prelude_block table_base) vm).
  rewrite (run_one_false 2 (prelude_block table_base) (fun _ => false) vm).
  2:{ cbn. rewrite Hhalt. reflexivity. }
  fold v1.
  assert (Hpc1 : vm_pc v1 = 1).
  { unfold v1. rewrite (prelude_exec_pc table_base vm 0 (iLD 1 0 action_halt_addr) Hpc eq_refl). cbn. reflexivity. }
  assert (Hhalt1 : vm_halted v1 = false).
  { unfold v1. rewrite (prelude_not_halted table_base vm 0 (iLD 1 0 action_halt_addr) Hpc eq_refl ltac:(discriminate)). exact Hhalt. }
  assert (Hmem1 : vm_mem v1 = vm_mem vm).
  { unfold v1. apply prelude_exec_mem. }
  assert (Hr0_1 : vm_reg v1 0 = 0).
  { unfold v1. rewrite prelude_exec_reg0. exact Hr0. }
  assert (Hr13_1 : vm_reg v1 13 = 1).
  { unfold v1. rewrite prelude_exec_reg13. exact Hr13. }
  assert (Hr1_1 : vm_reg v1 1 = vm_mem vm action_halt_addr).
  { unfold v1. rewrite (prelude_LD_reg table_base vm 0 1 0 action_halt_addr Hpc eq_refl).
    rewrite Hr0. cbn. reflexivity. }

  set (v2 := exec_instr (prelude_block table_base) v1).
  rewrite (run_one_false 1 (prelude_block table_base) (fun _ => false) v1).
  2:{ cbn. rewrite Hhalt1. reflexivity. }
  fold v2.
  assert (Hpc2 : vm_pc v2 = 2).
  { unfold v2. rewrite (prelude_exec_pc table_base v1 1 (iCMP 1 0) Hpc1 eq_refl). cbn. reflexivity. }
  assert (Hhalt2 : vm_halted v2 = false).
  { unfold v2. rewrite (prelude_not_halted table_base v1 1 (iCMP 1 0) Hpc1 eq_refl ltac:(discriminate)). exact Hhalt1. }
  assert (Hmem2 : vm_mem v2 = vm_mem vm).
  { unfold v2. rewrite prelude_exec_mem. exact Hmem1. }
  assert (Hr0_2 : vm_reg v2 0 = 0).
  { unfold v2. rewrite prelude_exec_reg0. exact Hr0_1. }
  assert (Hr13_2 : vm_reg v2 13 = 1).
  { unfold v2. rewrite prelude_exec_reg13. exact Hr13_1. }
  assert (Hr1_2 : vm_reg v2 1 = vm_mem vm action_halt_addr).
  { unfold v2, exec_instr. rewrite Hpc1. cbn [nth_error prelude_block]. cbn.
    exact Hr1_1. }
  assert (Hzf2 : vm_zf v2 = false).
  { unfold v2. rewrite (prelude_CMP_zf table_base v1 1 1 0 Hpc1 eq_refl).
    rewrite Hr1_1, Hr0_1. apply Nat.eqb_neq. exact Hne. }

  set (v3 := exec_instr (prelude_block table_base) v2).
  rewrite (run_one_false 0 (prelude_block table_base) (fun _ => false) v2).
  2:{ cbn. rewrite Hhalt2. reflexivity. }
  cbn [run_until]. fold v3.
  assert (Hpc3 : vm_pc v3 = 11).
  { unfold v3. rewrite (prelude_exec_pc table_base v2 2 (iJMP pNE 11) Hpc2 eq_refl).
    cbn [pred_holds]. rewrite Hzf2. cbn. reflexivity. }
  assert (Hhalt3 : vm_halted v3 = false).
  { unfold v3. rewrite (prelude_not_halted table_base v2 2 (iJMP pNE 11) Hpc2 eq_refl ltac:(discriminate)). exact Hhalt2. }
  assert (Hmem3 : vm_mem v3 = vm_mem vm).
  { unfold v3. rewrite prelude_exec_mem. exact Hmem2. }
  assert (Hr0_3 : vm_reg v3 0 = 0).
  { unfold v3. rewrite prelude_exec_reg0. exact Hr0_2. }
  assert (Hr13_3 : vm_reg v3 13 = 1).
  { unfold v3. rewrite prelude_exec_reg13. exact Hr13_2. }
  assert (Hr1_3 : vm_reg v3 1 = vm_mem vm action_halt_addr).
  { unfold v3, exec_instr. rewrite Hpc2. cbn [nth_error prelude_block]. cbn.
    exact Hr1_2. }
  repeat split; assumption.
Qed.
