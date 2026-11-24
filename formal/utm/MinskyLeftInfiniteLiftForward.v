(** * Forward lifted source-to-native halting theorem *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyMatchMacro MinskyBookLayout MinskyBookLocate
  MinskyBookLocateRows MinskyBookLocateWide MinskyBookLocateCycle
  MinskyBookLocateLookup MinskyBookEncode MinskyBookRawBuffer
  MinskyLeftInfinite MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteEncoding MinskyLeftInfiniteBounded
  MinskyLeftInfiniteLeftDepth MinskyLeftInfiniteBoundary
  MinskyLeftInfiniteBoundaryLocate MinskyLeftInfiniteBoundaryBook
  MinskyLeftInfiniteBoundaryFinal MinskyLeftInfiniteBoundaryLookup
  MinskyLeftInfiniteBoundaryLifted MinskyLeftInfiniteLift.

Local Open Scope nat_scope.

Theorem lic_lifted_source_halt_to_native :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_left_ok lo n c ->
    lic_halted (left_infinite_run n rows c) = true ->
    exists t,
      c_halted (run t
        (if lic_halted c then dispatch_halt_at_y [] []
         else lic_q5_encode lo (lic_lift_cfg c)
                (lic_book_rows (lic_lift_rows rows)) [])) = true.
Proof.
  intros n p lo c rows Hwf Hne Hlen Hleft Hhalt.
  set (cl := lic_lift_cfg c).
  set (rl := lic_lift_rows rows).
  assert (Hhalt_cl : lic_halted (left_infinite_run n rl cl) = true).
  { subst cl rl. rewrite <- (left_infinite_run_lift n rows c).
    cbn [lic_halted lic_lift_cfg]. exact Hhalt. }
  destruct (lic_first_halt_exists n rl cl Hhalt_cl)
    as [k [Hk Hfirst]].
  destruct k as [|k'].
  - (* source already halted *)
    exists 0.
    assert (Hc : lic_halted c = true).
    { pose proof (proj1 Hfirst) as Hk0.
      cbn [left_infinite_run] in Hk0.
      subst cl. cbn [lic_halted lic_lift_cfg] in Hk0. exact Hk0. }
    rewrite Hc. unfold dispatch_halt_at_y. reflexivity.
  - (* first halt at S k' *)
    assert (Hk' : k' < n) by lia.
    assert (Hhalted_k : lic_halted (left_infinite_run k' rl cl) = false).
    { apply (proj2 Hfirst k'). lia. }
    assert (Hhalted_S :
      lic_halted (left_infinite_run (S k') rl cl) = true).
    { exact (proj1 Hfirst). }
    assert (Hc_running : lic_halted c = false).
    { pose proof (proj2 Hfirst 0 ltac:(lia)) as Hk0.
      cbn [left_infinite_run] in Hk0.
      subst cl. cbn [lic_halted lic_lift_cfg] in Hk0. exact Hk0. }
    (* lifted wellformedness / length / nonempty *)
    assert (Hwf_cl : Forall (wide_row_wellformed (p + 2)) rl).
    { subst rl. apply (lic_lift_rows_wellformed p rows Hwf). }
    assert (Hne_cl : rl <> []).
    { subst rl. intro H. apply Hne.
      apply (@map_eq_nil WideSourceRow WideSourceRow lic_lift_row rows H). }
    assert (Hlen_cl : length (lic_state cl) = p + 2).
    { subst cl. rewrite lic_lift_cfg_state_length. rewrite Hlen. lia. }
    assert (Hleft_k : lic_left_ok lo k' cl).
    { subst cl. destruct Hleft as [Hlo Hok].
      unfold lic_left_ok. rewrite lic_lift_cfg_head.
      split; [|apply (proj1 (lic_lift_cfg_ok c) Hok)].
      lia. }
    assert (Hhit_cl : forall i, i < k' -> lic_hit_state rl
      (left_infinite_run i rl cl)).
    { intros i Hi. apply (lic_first_halt_hit_prefix (S k') rl cl
        Hfirst i). lia. }
    assert (Hwall : forall i, i < k' -> forall r,
      wide_source_lookup rl
        (lic_state (left_infinite_run i rl cl))
        (lic_tape (left_infinite_run i rl cl)
           (lic_head (left_infinite_run i rl cl))) = Some r ->
      wr_right r = true ->
      (lic_head (left_infinite_run i rl cl) < lic_R cl)%Z).
    { intros i Hi r Hlook Hright.
      destruct (Z.lt_ge_cases
        (lic_head (left_infinite_run i rl cl)) (lic_R cl)) as [Hlt|Hge].
      - exact Hlt.
      - exfalso.
        assert (Hok_i : left_infinite_ok (left_infinite_run i rl cl)).
        { apply (left_infinite_run_ok i rl cl (proj2 Hleft_k)). }
        destruct Hok_i as [Hle _].
        assert (Heq : lic_head (left_infinite_run i rl cl) = lic_R cl).
        { assert (Hle' : (lic_head (left_infinite_run i rl cl) <=
            lic_R cl)%Z).
          { rewrite <- (lic_R_run i rl cl). exact Hle. }
          apply Z.le_antisymm; [exact Hle'|exact Hge]. }
        assert (Hh_i : lic_halted (left_infinite_run i rl cl) = false).
        { apply (proj2 Hfirst i). lia. }
        assert (Heq' : lic_head (left_infinite_run i rl cl) =
          lic_R (left_infinite_run i rl cl)).
        { rewrite (lic_R_run i rl cl). exact Heq. }
        assert (Hstep : lic_halted
          (left_infinite_step rl (left_infinite_run i rl cl)) = true).
        { apply (left_infinite_step_right_blocked_halts rl
            (left_infinite_run i rl cl) r Hh_i Hlook Hright Heq'). }
        rewrite <- left_infinite_run_succ in Hstep.
        assert (Hfalse := proj2 Hfirst (S i) ltac:(lia)).
        rewrite Hstep in Hfalse. discriminate. }
    (* hit-only prefix *)
    assert (Hrun_prefix := lic_left_hit_run k' (p + 2) lo cl rl
      Hwf_cl Hne_cl Hlen_cl Hleft_k Hhit_cl Hwall).
    set (c_k := left_infinite_run k' rl cl) in *.
    assert (Hlen_ck : length (lic_state c_k) = p + 2).
    { subst c_k. apply (lic_state_length_run k' (p + 2) cl rl
        Hlen_cl Hwf_cl Hhit_cl). }
    assert (Hok_ck : left_infinite_ok c_k).
    { subst c_k. apply (left_infinite_run_ok k' rl cl
        (proj2 Hleft_k)). }
    (* case on the lookup at the pre-halt state *)
    destruct (wide_source_lookup rl (lic_state c_k)
      (lic_tape c_k (lic_head c_k))) as [r|] eqn:Hlookup.
    + (* a matched row: it must be the right wall *)
      destruct (wr_right r) eqn:Hright.
      * (* boundary right move *)
        assert (Hle : (lic_head c_k <= lic_R cl)%Z).
        { destruct Hok_ck as [Hle _].
          rewrite <- (lic_R_run k' rl cl). exact Hle. }
        assert (Heq : lic_head c_k = lic_R cl).
        { destruct (Z.lt_ge_cases (lic_head c_k) (lic_R cl)) as [Hlt|Hge].
          - exfalso.
            assert (Hb : left_infinite_right_blocked c_k r = false).
            { unfold left_infinite_right_blocked. rewrite Hright.
              assert (HR : lic_R c_k = lic_R cl).
              { change (lic_R (left_infinite_run k' rl cl) = lic_R cl).
                rewrite (lic_R_run k' rl cl). reflexivity. }
              rewrite HR.
              destruct (Z.eqb (lic_head c_k) (lic_R cl)) eqn:E.
              - apply Z.eqb_eq in E. lia.
              - reflexivity. }
            assert (Hh_k : lic_halted c_k = false) by exact Hhalted_k.
            destruct (left_infinite_step_running_fields rl c_k r
              Hh_k Hlookup Hb) as [_ [_ [_ [_ Hhalted_step]]]].
            unfold c_k in Hhalted_step.
            rewrite <- left_infinite_run_succ in Hhalted_step.
            rewrite Hhalted_S in Hhalted_step. discriminate.
          - lia. }
        assert (HR_ck : lic_R c_k = lic_R cl).
        { change (lic_R (left_infinite_run k' rl cl) = lic_R cl).
          rewrite (lic_R_run k' rl cl). reflexivity. }
        assert (Heq_ck : lic_head c_k = lic_R c_k).
        { transitivity (lic_R cl); [exact Heq|symmetry; exact HR_ck]. }
        assert (Hrawbuf : raw_buf c_k = []).
        { apply raw_buf_nil_of_boundary. exact Heq_ck. }
        assert (Hleft0 : lic_left_ok lo 0 c_k).
        { subst c_k. apply (lic_left_ok_run k' lo cl rl
            Hleft_k Hhit_cl). }
        assert (Hlo_k : (lo < lic_head c_k)%Z).
        { destruct Hleft0 as [Hlo _]. cbn [Z.of_nat] in Hlo. lia. }
        assert (Hptape : raw_ptape_prefix c_k lo ++
          [source_bit (raw_last c_k lo)] = raw_ptape c_k lo).
        { apply raw_ptape_prefix_last.
          apply raw_ptape_nonempty. exact Hlo_k. }
        (* identify the lifted row *)
        assert (Hlift_run : c_k = lic_lift_cfg
          (left_infinite_run k' rows c)).
        { subst c_k cl rl. symmetry.
          apply (left_infinite_run_lift k' rows c). }
        rewrite Hlift_run in Hlookup.
        unfold rl in Hlookup.
        pose proof (wide_source_lookup_lift_cfg rows
          (left_infinite_run k' rows c)) as Hlift_lookup.
        rewrite Hlift_lookup in Hlookup.
        destruct (wide_source_lookup rows
          (lic_state (left_infinite_run k' rows c))
          (lic_tape (left_infinite_run k' rows c)
            (lic_head (left_infinite_run k' rows c)))) as [r0|] eqn:Hlookup0.
        -- cbn [option_map] in Hlookup.
           injection Hlookup as Hr.
           assert (Hlookup_lift : wide_source_lookup rl
             (lic_state c_k) (lic_tape c_k (lic_head c_k)) = Some r).
           { rewrite Hlift_run. unfold rl.
             rewrite (wide_source_lookup_lift_cfg rows
               (left_infinite_run k' rows c)).
             rewrite Hlookup0. cbn [option_map]. rewrite Hr. reflexivity. }
           (* hit packaging on the lifted rows *)
           destruct (lic_book_rows_first_match_hit (p + 2) rl r
             (lic_state c_k) (lic_tape c_k (lic_head c_k))
             Hwf_cl Hlen_ck Hlookup_lift)
             as [steps [hit [after [Hbf [Hhit [Hafter_ne _]]]]]].
           destruct after as [|next rest]; [contradiction|].
           destruct (book_first_match_hit_sound
             (lic_state c_k ++ [lic_tape c_k (lic_head c_k)])
             (lic_book_rows rl) steps hit (next :: rest) Hbf)
             as [Hrows0 [Hforall Hcond]].
           assert (Hhit' : hit = source_row_to_book (lic_lift_row r0)).
           { rewrite Hhit. rewrite <- Hr. reflexivity. }
           assert (Hin_r0 : In r0 rows).
           { apply (proj1 (find_some
               (fun row => wide_row_matches row
                 (lic_state (left_infinite_run k' rows c))
                 (lic_tape (left_infinite_run k' rows c)
                   (lic_head (left_infinite_run k' rows c))))
               rows Hlookup0)). }
           assert (Hwf_r0 : wide_row_wellformed p r0).
           { rewrite Forall_forall in Hwf. apply Hwf. exact Hin_r0. }
           assert (Hdir : br_dir hit = true).
           { rewrite Hhit'. rewrite source_row_dir. rewrite Hr. exact Hright. }
           assert (Hlen_act : length (br_action hit) =
             length (lic_state c_k ++ [lic_tape c_k (lic_head c_k)])).
           { rewrite Hhit'.
             rewrite (source_row_action_length (p + 2)
               (lic_lift_row r0) (lic_lift_row_wellformed p r0 Hwf_r0)).
             rewrite Hhit' in Hcond. rewrite Hcond. reflexivity. }
           assert (Hnext_cond : exists c0 creast,
             br_cond next = c0 :: creast).
           { assert (Hcond_ne : Forall (fun br => br_cond br <> [])
               (lic_book_rows rl)).
             { apply (lic_book_rows_cond_nonempty (p + 2) rl
                 Hwf_cl Hne_cl). }
             assert (Hin_next : In next (lic_book_rows rl)).
             { rewrite Hrows0. apply in_or_app. right.
               right. left. reflexivity. }
             pose proof (proj1 (@Forall_forall book_row
               (fun br => br_cond br <> []) (lic_book_rows rl))
               Hcond_ne next Hin_next) as Hne_next.
             destruct (br_cond next) as [|c0 creast] eqn:E.
             - exfalso. apply Hne_next. exact E.
             - exists c0, creast. reflexivity. }
           destruct Hnext_cond as [c0 [creast Hnext_cond]].
           destruct (lic_q5_encode_lifted_boundary_halt_state lo c_k
             rows r0 (lic_book_rows rl) steps hit next rest
             (wr_write r0) c0 creast [] Hrawbuf Hptape
             eq_refl Hhit' Hrows0 Hforall Hcond Hlen_act Hdir
             Hnext_cond) as [steps_fail [last_fail [Hrun_b Hhalt_b]]].
           exists (lic_bounded_clock rl k' lo cl +
             lic_q5_empty_boundary_clock lo c_k steps hit
               (lic_lift_state (wr_next r0)) (wr_write r0)
               steps_fail last_fail).
           rewrite Hc_running.
           rewrite (dispatch_run_add (lic_bounded_clock rl k' lo cl)
             (lic_q5_empty_boundary_clock lo c_k steps hit
               (lic_lift_state (wr_next r0)) (wr_write r0)
               steps_fail last_fail)).
           rewrite Hrun_prefix.
           rewrite Hrun_b. exact Hhalt_b.
        -- cbn [option_map] in Hlookup. discriminate Hlookup.
      * (* left move would keep the machine running: contradiction *)
        exfalso.
        assert (Hb : left_infinite_right_blocked c_k r = false).
        { unfold left_infinite_right_blocked. rewrite Hright. reflexivity. }
        destruct (left_infinite_step_running_fields rl c_k r
          Hhalted_k Hlookup Hb) as [_ [_ [_ [_ Hhalted_step]]]].
        unfold c_k in Hhalted_step.
        rewrite <- left_infinite_run_succ in Hhalted_step.
        rewrite Hhalted_S in Hhalted_step. discriminate.
    + (* lookup none: the halt branch *)
      destruct (lic_left_none_halt_run k' (p + 2) lo cl rl
        Hwf_cl Hne_cl Hlen_cl Hleft_k Hhit_cl Hwall Hhalted_k
        Hlookup) as [steps [last [Hrun_n Hhalt_n]]].
      exists (lic_bounded_clock rl k' lo cl +
        (S (length (lic_state c_k)) +
         (book_failures_clock [] steps +
          book_halt_clock (map bf_row steps) last))).
      rewrite Hc_running.
      unfold c_k.
      rewrite Hrun_n. exact Hhalt_n.
Qed.

Print Assumptions lic_lifted_source_halt_to_native.
