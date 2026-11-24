From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyMatchMacro MinskyBookLayout MinskyBookLocate
  MinskyBookLocateRows MinskyBookLocateWide MinskyBookLocateCycle
  MinskyBookLocateLookup MinskyBookEncode MinskyBookRawBuffer
  MinskyLeftInfinite MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteEncoding MinskyLeftInfiniteStepRight
  MinskyLeftInfiniteStepLeft MinskyLeftInfiniteBounded
  MinskyLeftInfiniteLeftDepth MinskyLeftInfiniteBoundary
  MinskyLeftInfiniteBoundaryLocate MinskyLeftInfiniteBoundaryBook
  MinskyLeftInfiniteBoundaryFinal MinskyLeftInfiniteBoundaryLookup
  MinskyLeftInfiniteBoundaryLifted MinskyLeftInfiniteClockInd
  MinskyLeftInfiniteLift MinskyLeftInfiniteLiftForward
  MinskyLeftInfiniteLiftBackward MinskyLeftInfiniteUniversality.

Local Open Scope nat_scope.

(** ** The forward clock reaches the native halt *)

Theorem lic_forward_clock_run :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    lic_left_ok lo n c ->
    lic_halted (left_infinite_run n rows c) = true ->
    c_halted (run (lic_forward_clock rows n lo c)
      (if lic_halted c then dispatch_halt_at_y [] []
       else lic_q5_encode lo (lic_lift_cfg c)
              (lic_book_rows (lic_lift_rows rows)) [])) = true.
Proof.
  intros n. induction n as [|n IH];
    intros p lo c rows Hwf Hne Hlen Hok Hleft Hhalt.
  - cbn [left_infinite_run] in Hhalt.
    cbn [lic_forward_clock].
    destruct (lic_halted c) eqn:Eh.
    + unfold dispatch_halt_at_y. reflexivity.
    + discriminate Hhalt.
  - cbn [left_infinite_run] in Hhalt.
    assert (Hwf' : Forall (wide_row_wellformed (p + 2))
      (lic_lift_rows rows))
      by (apply lic_lift_rows_wellformed; exact Hwf).
    assert (Hne' : lic_lift_rows rows <> []).
    { destruct rows as [|r rest]; [contradiction|].
      simpl. discriminate. }
    assert (Hlen' : length (lic_state (lic_lift_cfg c)) = p + 2)
      by (rewrite lic_lift_cfg_state_length; lia).
    assert (Hok' : left_infinite_ok (lic_lift_cfg c))
      by (apply (proj1 (lic_lift_cfg_ok c)); exact Hok).
    assert (Hleft' : lic_left_ok lo (S n) (lic_lift_cfg c))
      by (apply (proj2 (lic_left_ok_lift lo (S n) c)); exact Hleft).
    cbn [lic_forward_clock].
    destruct (lic_halted c) eqn:Eh.
    + unfold dispatch_halt_at_y. reflexivity.
    + destruct (wide_source_lookup rows (lic_state c)
        (lic_tape c (lic_head c))) as [r0|] eqn:El.
      * (* lookup hit *)
        assert (Hin0 : In r0 rows).
        { pose proof (find_some
            (fun row => wide_row_matches row (lic_state c)
               (lic_tape c (lic_head c))) rows El) as Hfs.
          exact (proj1 Hfs). }
        assert (Hwf0 : wide_row_wellformed p r0).
        { rewrite Forall_forall in Hwf. apply Hwf. exact Hin0. }
        assert (Hlookup_lift : wide_source_lookup (lic_lift_rows rows)
          (lic_state (lic_lift_cfg c))
          (lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))) =
          Some (lic_lift_row r0)).
        { cbn [lic_state lic_tape lic_head lic_lift_cfg].
          rewrite wide_source_lookup_lift. rewrite El. reflexivity. }
        destruct (wide_source_lookup_some_book_first_match_hit (p + 2)
          (lic_lift_rows rows) (lic_state (lic_lift_cfg c))
          (lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c)))
          (lic_lift_row r0) Hwf' Hlen' Hlookup_lift)
          as [steps [hit [after [Hbf_src [Hhit [Hrows_src Hforall]]]]]].
        destruct (wr_right r0) eqn:Hright.
        -- destruct (left_infinite_right_blocked c r0) eqn:Eb.
           ++ (* wall: the source and the native machine both halt now *)
              assert (HeqR : lic_head c = lic_R c).
              { unfold left_infinite_right_blocked in Eb.
                apply andb_true_iff in Eb. destruct Eb as [_ HE].
                apply Z.eqb_eq in HE. exact HE. }
              assert (HeqR' : lic_head (lic_lift_cfg c) = lic_R (lic_lift_cfg c)).
              { cbn [lic_head lic_R lic_lift_cfg]. exact HeqR. }
              assert (Hrawbuf : raw_buf (lic_lift_cfg c) = []).
              { change (raw_buf c = []).
                apply raw_buf_nil_of_boundary. exact HeqR. }
              assert (Hlo_c : (lo < lic_head c)%Z).
              { destruct Hleft as [Hlo _].
                rewrite Nat2Z.inj_succ in Hlo. lia. }
              assert (Hptape : raw_ptape_prefix (lic_lift_cfg c) lo ++
                [source_bit (raw_last (lic_lift_cfg c) lo)] =
                raw_ptape (lic_lift_cfg c) lo).
              { change (raw_ptape_prefix c lo ++
                  [source_bit (raw_last c lo)] = raw_ptape c lo).
                apply raw_ptape_prefix_last.
                apply raw_ptape_nonempty. exact Hlo_c. }
              destruct (lic_book_rows_first_match_hit_snoc
                (lic_state (lic_lift_cfg c) ++
                 [lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))])
                (lic_lift_rows rows) steps hit after Hbf_src)
                as [next [rest Hbf_aug]].
              destruct (book_first_match_hit_sound
                (lic_state (lic_lift_cfg c) ++
                 [lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))])
                (lic_book_rows (lic_lift_rows rows)) steps hit
                (next :: rest) Hbf_aug)
                as [Hrows_aug [Hforall_aug Hcond_aug]].
              assert (Hnext_cond : exists c0 creast,
                br_cond next = c0 :: creast).
              { assert (Hcond_ne : Forall (fun br => br_cond br <> [])
                  (lic_book_rows (lic_lift_rows rows)))
                  by (apply (lic_book_rows_cond_nonempty (p + 2)
                        (lic_lift_rows rows) Hwf' Hne')).
                assert (Hin_next : In next
                  (lic_book_rows (lic_lift_rows rows))).
                { rewrite Hrows_aug. apply in_or_app. right.
                  right. left. reflexivity. }
                pose proof (proj1 (@Forall_forall book_row
                  (fun br => br_cond br <> [])
                  (lic_book_rows (lic_lift_rows rows)))
                  Hcond_ne next Hin_next) as Hne_next.
                destruct (br_cond next) as [|c0 creast] eqn:E.
                - exfalso. apply Hne_next. exact E.
                - exists c0, creast. reflexivity. }
              destruct Hnext_cond as [c0 [creast Hnext_cond]].
              assert (Hrot : exists s,
                tl (lic_lift_state (wr_next r0)) ++
                [hd false (lic_lift_state (wr_next r0))] = true :: s).
              { exists (wr_next r0 ++ [false]).
                unfold lic_lift_state. cbn. reflexivity. }
              assert (Hrows_lift : forall br,
                In br (lic_book_rows (lic_lift_rows rows)) ->
                exists s, br_cond br = false :: s).
              { intros br Hin.
                apply (proj1 (@Forall_forall book_row
                  (fun br => exists s, br_cond br = false :: s)
                  (lic_book_rows (lic_lift_rows rows)))
                  (lic_book_rows_lift_first_bit rows) br Hin). }
              destruct (book_first_match_first_bit_halt
                (tl (lic_lift_state (wr_next r0)) ++
                 [hd false (lic_lift_state (wr_next r0))])
                (lic_book_rows (lic_lift_rows rows))
                (lic_book_rows_nonempty (lic_lift_rows rows))
                Hrot Hrows_lift) as [sf [lf HsfHalt]].
              assert (HsfHalt' : book_first_match
                (tl (lic_lift_state (wr_next r0)) ++
                 [hd false (lic_lift_state (wr_next r0))])
                (map bf_row steps ++ hit :: next :: rest) =
                book_lookup_halt sf lf).
              { rewrite <- Hrows_aug. exact HsfHalt. }
              rewrite (lic_boundary_clock_of_eq rows lo c r0 steps hit
                next rest sf lf Hbf_aug HsfHalt).
              assert (Hhit_init : lic_lift_state (wr_next r0) <> [])
                by (unfold lic_lift_state; discriminate).
              assert (Hact : br_action hit =
                lic_lift_state (wr_next r0) ++ [wr_write r0])
                by (rewrite Hhit; reflexivity).
              assert (Hlen_act : length (br_action hit) =
                length (lic_state (lic_lift_cfg c) ++
                  [lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))])).
              { rewrite Hhit.
                rewrite (source_row_action_length (p + 2)
                  (lic_lift_row r0) (lic_lift_row_wellformed p r0 Hwf0)).
                rewrite <- Hhit. rewrite Hcond_aug. reflexivity. }
              assert (Hdir : br_dir hit = true).
              { rewrite Hhit. rewrite source_row_dir. exact Hright. }
              rewrite Hrows_aug.
              rewrite (lic_q5_encode_lifted_boundary_step_premises lo
                (lic_lift_cfg c) steps hit next rest
                (lic_lift_state (wr_next r0)) (wr_write r0) c0 creast
                sf lf [] Hrawbuf Hptape Hhit_init Hforall_aug Hcond_aug
                Hlen_act Hact Hdir Hnext_cond HsfHalt').
              unfold boundary_halt_encode_from_failed, dispatch_halt_at_y.
              reflexivity.
           ++ (* right hit: one native macro, then the induction hypothesis *)
              assert (Hb : left_infinite_right_blocked c r0 = false)
                by exact Eb.
              destruct (left_infinite_step_running_fields rows c r0
                Eh El Hb) as [Hs [Hh [Ht [HR Hhalted_step]]]].
              assert (Hlt : (lic_head (lic_lift_cfg c) <
                lic_R (lic_lift_cfg c))%Z).
              { assert (Hle : (lic_head c <= lic_R c)%Z)
                  by (destruct Hok as [Hle _]; exact Hle).
                assert (HneR : lic_head c <> lic_R c).
                { intro He. unfold left_infinite_right_blocked in Hb.
                  rewrite Hright, He, Z.eqb_refl in Hb. discriminate Hb. }
                destruct (Z.lt_ge_cases (lic_head c) (lic_R c))
                  as [Hlt'|Hge]; [exact Hlt'|].
                exfalso. apply HneR. lia. }
              rewrite (lic_step_cost_right_eq rows lo c (lic_lift_row r0)
                steps hit after Hlookup_lift Hbf_src Hright).
              rewrite (dispatch_run_add
                (lic_q5_right_hit_cost lo (lic_lift_cfg c) steps hit
                  (wr_next (lic_lift_row r0)) (wr_write (lic_lift_row r0)))
                (lic_forward_clock rows n lo (left_infinite_step rows c))).
              assert (Hlo1 : (lo < lic_head (lic_lift_cfg c))%Z).
              { destruct Hleft as [Hlo _]. rewrite Nat2Z.inj_succ in Hlo.
                rewrite lic_lift_cfg_head. lia. }
              rewrite (lic_book_rows_right_hit_step (p + 2) lo
                (lic_lift_cfg c) (lic_lift_rows rows) (lic_lift_row r0) []
                steps hit after Hlo1 Eh Hwf' Hlen' Hne' Hlookup_lift
                Hright Hlt Hbf_src Hhit).
              rewrite <- (left_infinite_step_lift rows c).
              assert (Hleft_tail : lic_left_ok lo n
                (left_infinite_step rows c))
                by (apply (lic_left_ok_right lo n c rows r0
                      Hleft Eh El Hright)).
              assert (Hlen_tail : length (lic_state
                (left_infinite_step rows c)) = p)
                by (apply (lic_state_length_step_general p rows c Hlen Hwf)).
              assert (Hhalt_tail : lic_halted
                (left_infinite_run n rows (left_infinite_step rows c)) = true)
                by exact Hhalt.
              pose proof (IH p lo (left_infinite_step rows c) rows Hwf
                Hne Hlen_tail (left_infinite_step_ok rows c Hok)
                Hleft_tail Hhalt_tail) as HIH.
              rewrite Hhalted_step in HIH.
              rewrite HIH.
              reflexivity.
        -- (* left hit: one native macro, then the induction hypothesis *)
           assert (Hb : left_infinite_right_blocked c r0 = false).
           { unfold left_infinite_right_blocked. rewrite Hright. reflexivity. }
           destruct (left_infinite_step_running_fields rows c r0
             Eh El Hb) as [Hs [Hh [Ht [HR Hhalted_step]]]].
           destruct (lic_book_rows_first_match_hit_snoc
             (lic_state (lic_lift_cfg c) ++
              [lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))])
             (lic_lift_rows rows) steps hit after Hbf_src)
             as [next [rest Hbf_aug]].
           destruct (book_first_match_hit_sound
             (lic_state (lic_lift_cfg c) ++
              [lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))])
             (lic_book_rows (lic_lift_rows rows)) steps hit
             (next :: rest) Hbf_aug)
             as [Hrows_aug [Hforall_aug Hcond_aug]].
           assert (Hnext_cond : exists c0 creast,
             br_cond next = c0 :: creast).
           { assert (Hcond_ne : Forall (fun br => br_cond br <> [])
               (lic_book_rows (lic_lift_rows rows)))
               by (apply (lic_book_rows_cond_nonempty (p + 2)
                     (lic_lift_rows rows) Hwf' Hne')).
             assert (Hin_next : In next
               (lic_book_rows (lic_lift_rows rows))).
             { rewrite Hrows_aug. apply in_or_app. right.
               right. left. reflexivity. }
             pose proof (proj1 (@Forall_forall book_row
               (fun br => br_cond br <> [])
               (lic_book_rows (lic_lift_rows rows)))
               Hcond_ne next Hin_next) as Hne_next.
             destruct (br_cond next) as [|c0 creast] eqn:E.
             - exfalso. apply Hne_next. exact E.
             - exists c0, creast. reflexivity. }
           destruct Hnext_cond as [c0 [creast Hnext_cond]].
           assert (Hlo2 : (lo < lic_head (lic_lift_cfg c) - 1)%Z).
           { destruct Hleft as [Hlo _]. rewrite Nat2Z.inj_succ in Hlo.
             rewrite lic_lift_cfg_head. lia. }
           rewrite (lic_step_cost_left_eq rows lo c (lic_lift_row r0)
             steps hit after Hlookup_lift Hbf_src Hright).
           rewrite Hb.
           rewrite (dispatch_run_add
             (lic_q5_left_hit_cost lo (lic_lift_cfg c) steps hit
               (wr_next (lic_lift_row r0)) (wr_write (lic_lift_row r0)))
             (lic_forward_clock rows n lo (left_infinite_step rows c))).
           rewrite (lic_book_rows_left_hit_step (p + 2) lo
             (lic_lift_cfg c) (lic_lift_rows rows) (lic_lift_row r0) []
             steps hit next rest c0 creast Hlo2 Eh Hok' Hwf' Hlen' Hne'
             Hlookup_lift Hright Hbf_aug Hhit Hrows_aug Hnext_cond).
           rewrite <- (left_infinite_step_lift rows c).
           assert (Hleft_tail : lic_left_ok lo n
             (left_infinite_step rows c))
             by (apply (lic_left_ok_left lo n c rows r0
                   Hleft Eh El Hright)).
           assert (Hlen_tail : length (lic_state
             (left_infinite_step rows c)) = p)
             by (apply (lic_state_length_step_general p rows c Hlen Hwf)).
           assert (Hhalt_tail : lic_halted
             (left_infinite_run n rows (left_infinite_step rows c)) = true)
             by exact Hhalt.
           pose proof (IH p lo (left_infinite_step rows c) rows Hwf
             Hne Hlen_tail (left_infinite_step_ok rows c Hok)
             Hleft_tail Hhalt_tail) as HIH.
           rewrite Hhalted_step in HIH.
           rewrite HIH.
           reflexivity.
      * (* lookup none: the native machine halts in the locate/halt macro *)
        assert (Hlookup_none : wide_source_lookup (lic_lift_rows rows)
          (lic_state (lic_lift_cfg c))
          (lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))) = None).
        { cbn [lic_state lic_tape lic_head lic_lift_cfg].
          rewrite wide_source_lookup_lift. rewrite El. reflexivity. }
        destruct (lic_book_rows_first_match_halt (p + 2)
          (lic_lift_rows rows) (lic_state (lic_lift_cfg c))
          (lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c)))
          Hwf' Hlen' Hne' Hlookup_none) as [steps [last Hbf]].
        assert (Hlo1 : (lo < lic_head (lic_lift_cfg c))%Z).
        { destruct Hleft as [Hlo _]. rewrite Nat2Z.inj_succ in Hlo.
          rewrite lic_lift_cfg_head. lia. }
        rewrite (lic_step_cost_none_eq rows lo c steps last
          Hlookup_none Hbf).
        rewrite (lic_q5_encode_none_halt_book_macro lo (lic_lift_cfg c)
          (lic_book_rows (lic_lift_rows rows)) [] steps last Hlo1
          (lic_book_rows_nonempty (lic_lift_rows rows)) Hbf).
        apply lic_halt_encode_halted.
Qed.

Print Assumptions lic_forward_clock_run.

(** ** The unconditional halting equivalence *)

Theorem lic_lifted_halting_equivalence :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    left_infinite_eventually_halts rows c <->
    exists K t,
      K >= t /\
      c_halted (run t
        (if lic_halted c then dispatch_halt_at_y [] []
         else lic_q5_encode (lic_head c - Z.of_nat K - 2)
                (lic_lift_cfg c)
                (lic_book_rows (lic_lift_rows rows)) [])) = true.
Proof.
  intros p rows c Hwf Hne Hlen Hok. split.
  - (* forward: run the explicit clock at a deep enough left window *)
    intros [k Hk].
    set (lo0 := (lic_head c - Z.of_nat k - 2)%Z).
    set (t := lic_forward_clock rows k lo0 c).
    set (K := Nat.max k t).
    set (lo := (lic_head c - Z.of_nat K - 2)%Z).
    assert (Hlk : K >= k) by (subst K; apply Nat.le_max_l).
    assert (Hlt : K >= t) by (subst K; apply Nat.le_max_r).
    assert (HleftK : lic_left_ok lo k c).
    { subst lo. apply (lic_left_ok_window K k c Hlk Hok). }
    assert (Hleft0 : lic_left_ok lo0 k c).
    { subst lo0. apply (lic_left_ok_window k k c (Nat.le_refl k) Hok). }
    pose proof (lic_forward_clock_run k p lo c rows Hwf Hne
      Hlen Hok HleftK Hk) as Hrun.
    rewrite (lic_forward_clock_lo_ind rows k lo lo0 c) in Hrun.
    exists K, t. split; [exact Hlt|].
    subst t. exact Hrun.
  - (* backward: any native halt within the clock reflects to the source *)
    intros [K [t [HKt Hnative]]].
    destruct (lic_halted c) eqn:Eh.
    + exists 0. cbn [left_infinite_run]. rewrite Eh. reflexivity.
    + set (lo := (lic_head c - Z.of_nat K - 2)%Z).
      assert (Hleft : lic_left_ok lo t c).
      { subst lo. apply (lic_left_ok_window K t c HKt Hok). }
      assert (Hwf' : Forall (wide_row_wellformed (p + 2))
        (lic_lift_rows rows))
        by (apply lic_lift_rows_wellformed; exact Hwf).
      assert (Hne' : lic_lift_rows rows <> []).
      { destruct rows as [|r rest]; [contradiction|].
        simpl. discriminate. }
      assert (Hlen' : length (lic_state (lic_lift_cfg c)) = p + 2)
        by (rewrite lic_lift_cfg_state_length; lia).
      assert (Hbound : t <= lic_bounded_clock (lic_lift_rows rows) t lo
        (lic_lift_cfg c))
        by (apply (lic_bounded_clock_at_least_steps_general t (p + 2)
              (lic_lift_rows rows) lo (lic_lift_cfg c) Hwf' Hne' Hlen')).
      assert (Hnative' : c_halted (run t
        (lic_q5_encode lo (lic_lift_cfg c)
          (lic_book_rows (lic_lift_rows rows)) [])) = true).
      { subst lo. exact Hnative. }
      destruct (lic_lifted_native_halt_to_source t p lo c rows t
        Hwf Hne Hlen Hleft Eh Hbound Hnative')
        as [k [_ Hhalt]].
      apply (proj2 (left_infinite_halts_lift rows c)).
      exists k. exact Hhalt.
Qed.

Print Assumptions lic_lifted_halting_equivalence.
