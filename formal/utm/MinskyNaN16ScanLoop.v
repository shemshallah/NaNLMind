From Coq Require Import List Arith Lia.
Import ListNotations.
From NaNLM Require Import MinskyNaN16VM.

Lemma scan_stop_14 : scan_stop 14 = true.
Proof. reflexivity. Qed.
Lemma scan_stop_13 : scan_stop 13 = true.
Proof. reflexivity. Qed.

Lemma scan_loop_try :
  forall (i state sym start : nat) (table : list (list nat)) (m : Mem) (vm : VM),
    i + length table = 184 ->
    Forall (fun row => 0 < length row /\ 1 < length row) table ->
    table_mem_at (start + 8 * i) table m ->
    scan_ready vm i state sym start m ->
    exists vm',
      run_until (12 * length table + 14) scan_block scan_stop vm = vm' /\
      match scan_index_from i state sym table with
      | Some (j,row) =>
          vm_pc vm' = 14 /\ vm_reg vm' 7 = start + 8 * j /\ vm_reg vm' 8 = j
      | None => vm_pc vm' = 13 /\ vm_reg vm' 8 = 184
      end.
Proof.
  intros i state sym start table.
  revert i state sym start.
  induction table as [|row rest IH];
    intros i state sym start m vm Hlen Hforall Hmemtab Hready.
  - (* empty suffix: i = 184 *)
    simpl in Hlen.
    assert (Hi : i = 184) by lia.
    subst i.
    unfold scan_ready in Hready.
    destruct Hready as [Hpc [Hr1 [Hr4 [Hr5 [Hr6 [Hr8 [Hr13 [Hmem Hhalt]]]]]]]].
    assert (Hnone : scan_index_from 184 state sym [] = None) by reflexivity.
    rewrite Hnone.
    destruct (scan_none_at_end vm 184 state sym start m
      (conj Hpc (conj Hr1 (conj Hr4 (conj Hr5 (conj Hr6 (conj Hr8
        (conj Hr13 (conj Hmem Hhalt)))))))) Hr8)
      as [Hpc13 Hr8_184].
    exists (run_until 2 scan_block scan_stop vm).
    split.
    + change (run_until (2 + 12) scan_block scan_stop vm =
              run_until 2 scan_block scan_stop vm).
      rewrite (run_until_split 2 12 scan_block scan_stop vm).
      rewrite (run_until_stop 12 scan_block scan_stop
        (run_until 2 scan_block scan_stop vm)).
      * reflexivity.
      * rewrite Hpc13. rewrite scan_stop_13. reflexivity.
    + split; [exact Hpc13|exact Hr8_184].
  - (* nonempty suffix *)
    simpl in Hlen.
    assert (Hlt : i < 184) by lia.
    assert (Hlen' : S i + length rest = 184) by lia.
    inversion Hforall as [| a l Hrow HrestForall]; subst.
    destruct Hrow as [Hrow0 Hrow1].
    assert (Hmemtab' : table_mem_at (start + 8 * S i) rest m).
    { replace (start + 8 * S i) with (start + 8 * i + 8) by lia.
      apply (table_mem_at_tail (start + 8 * i) row rest m Hmemtab). }
    destruct (Nat.eqb (nth 0 row 0) state) eqn:Efrom.
    + destruct (Nat.eqb (nth 1 row 0) sym) eqn:Eread.
      * (* hit *)
        assert (Hfrom : nth 0 row 0 = state) by (apply Nat.eqb_eq; exact Efrom).
        assert (Hread : nth 1 row 0 = sym) by (apply Nat.eqb_eq; exact Eread).
        destruct (scan_iter_hit vm i state sym start row rest m Hlt Hready
          Hmemtab Hrow0 Hrow1 Hfrom Hread) as [Hpc14 [Hr7_14 Hr8_14]].
        exists (run_until 12 scan_block scan_stop vm).
        split.
        -- replace (12 * length (row :: rest) + 14)
             with (12 + (12 * length rest + 14)) by (simpl; lia).
           rewrite (run_until_split 12 (12 * length rest + 14) scan_block scan_stop vm).
           rewrite (run_until_stop (12 * length rest + 14) scan_block scan_stop
             (run_until 12 scan_block scan_stop vm)).
           ++ reflexivity.
           ++ rewrite Hpc14. rewrite scan_stop_14. reflexivity.
        -- cbn [scan_index_from].
           rewrite Efrom, Eread. simpl. split; [exact Hpc14|split; [exact Hr7_14|exact Hr8_14]].
      * (* from matches, read does not: miss_read *)
        assert (Hfrom : nth 0 row 0 = state) by (apply Nat.eqb_eq; exact Efrom).
        assert (Hread_neq : nth 1 row 0 <> sym).
        { intro H. apply Nat.eqb_neq in Eread. apply Eread. exact H. }
        assert (Hready9 : scan_ready (run_until 12 scan_block scan_stop vm)
          (S i) state sym start m).
        { apply (scan_iter_miss_read vm i state sym start row rest m
            Hlt Hready Hmemtab Hrow0 Hrow1 Hfrom Hread_neq). }
        destruct (IH (S i) state sym start m
          (run_until 12 scan_block scan_stop vm) Hlen' HrestForall Hmemtab' Hready9)
          as [vm' [Hrun Hres]].
        exists vm'.
        split.
        -- replace (12 * length (row :: rest) + 14)
             with (12 + (12 * length rest + 14)) by (simpl; lia).
           rewrite (run_until_split 12 (12 * length rest + 14) scan_block scan_stop vm).
           exact Hrun.
        -- cbn [scan_index_from]. rewrite Efrom, Eread. simpl. exact Hres.
    + (* from does not match: miss_from *)
      assert (Hneq : nth 0 row 0 <> state).
      { intro H. apply Nat.eqb_neq in Efrom. apply Efrom. exact H. }
      assert (Hready9 : scan_ready (run_until 9 scan_block scan_stop vm)
        (S i) state sym start m).
      { apply (scan_iter_miss_from vm i state sym start row rest m
          Hlt Hready Hmemtab Hrow0 Hneq). }
      destruct (IH (S i) state sym start m
        (run_until 9 scan_block scan_stop vm) Hlen' HrestForall Hmemtab' Hready9)
        as [vm' [Hrun Hres]].
      exists vm'.
      split.
      -- replace (12 * length (row :: rest) + 14)
           with (9 + ((12 * length rest + 14) + 3)) by (simpl; lia).
         rewrite (run_until_split 9 ((12 * length rest + 14) + 3)
           scan_block scan_stop vm).
         rewrite (run_until_extend_stopped (12 * length rest + 14) 3
           scan_block scan_stop (run_until 9 scan_block scan_stop vm)).
         ++ exact Hrun.
         ++ destruct (scan_index_from (S i) state sym rest) as [[j r]|] eqn:Eres.
            ** destruct Hres as [Hpc14 _]. rewrite Hpc14. rewrite scan_stop_14. reflexivity.
            ** destruct Hres as [Hpc13 _]. rewrite Hpc13. rewrite scan_stop_13. reflexivity.
      -- cbn [scan_index_from]. rewrite Efrom. simpl. exact Hres.
Qed.
