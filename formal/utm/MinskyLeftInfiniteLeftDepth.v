(** * Left-depth window with the actual right wall

    The bounded-window theorem pads both sides.  For a run that may last
    longer than the initial right padding, the left window depth and the
    right endpoint should be separate: the right endpoint is the source's
    actual wall [lic_R], while the left window is [head - K].  This file
    isolates the left-depth invariant and the hit-only run theorem.

    Right moves require [head < R] explicitly; a right move at [R] is the
    boundary macro, not this file. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyMatchMacro MinskyCanonicalInstruction
  MinskyBookLayout MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyBookLocateCycle MinskyBookLocateLookup
  MinskyBookEncode MinskyBookRawBuffer MinskyLeftInfinite
  MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteFirstMatchApp MinskyLeftInfiniteStepRight
  MinskyLeftInfiniteStepLeft MinskyLeftInfiniteEncoding
  MinskyLeftInfiniteBounded.

Local Open Scope nat_scope.

Definition lic_left_ok (lo : Z) (n : nat)
    (c : LeftInfiniteConfig) : Prop :=
  (lo + Z.of_nat n + 2 <= lic_head c)%Z /\
  left_infinite_ok c.

Lemma lic_left_ok_right :
  forall (lo : Z) (n : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow),
    lic_left_ok lo (S n) c ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    lic_left_ok lo n (left_infinite_step rows c).
Proof.
  intros lo n c rows r [Hlo Hok] Hh Hlookup Hright.
  destruct (left_infinite_right_blocked c r) eqn:Hb.
  - destruct (left_infinite_step_blocked_fields rows c r Hh Hlookup Hb)
      as [_ [Hhead [_ [_ _]]]].
    unfold lic_left_ok. rewrite Hhead.
    rewrite Nat2Z.inj_succ in Hlo.
    split; [lia|]. apply (left_infinite_step_ok rows c Hok).
  - destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
      as [_ [Hhead [_ [_ _]]]].
    rewrite Hright in Hhead.
    unfold lic_left_ok. rewrite Hhead.
    rewrite Nat2Z.inj_succ in Hlo.
    split; [lia|]. apply (left_infinite_step_ok rows c Hok).
Qed.

Lemma lic_left_ok_left :
  forall (lo : Z) (n : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow),
    lic_left_ok lo (S n) c ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    lic_left_ok lo n (left_infinite_step rows c).
Proof.
  intros lo n c rows r [Hlo Hok] Hh Hlookup Hleft.
  assert (Hb : left_infinite_right_blocked c r = false)
    by (unfold left_infinite_right_blocked; rewrite Hleft; reflexivity).
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [_ [_ _]]]].
  rewrite Hleft in Hhead.
  unfold lic_left_ok. rewrite Hhead.
  rewrite Nat2Z.inj_succ in Hlo.
  split; [lia|]. apply (left_infinite_step_ok rows c Hok).
Qed.

Lemma lic_left_ok_halt :
  forall (lo : Z) (n : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    lic_left_ok lo (S n) c ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = None ->
    lic_left_ok lo n (left_infinite_step rows c).
Proof.
  intros lo n c rows [Hlo Hok] Hh Hnone.
  destruct (left_infinite_step_lookup_none_fields rows c Hh Hnone)
    as [_ [Hhead [_ [_ _]]]].
  unfold lic_left_ok. rewrite Hhead.
  rewrite Nat2Z.inj_succ in Hlo.
  split; [lia|]. apply (left_infinite_step_ok rows c Hok).
Qed.

Print Assumptions lic_left_ok_right.
Print Assumptions lic_left_ok_left.
Print Assumptions lic_left_ok_halt.

(** ** Hit-only run with a separate left-depth window *)

Theorem lic_left_hit_run :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_left_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    (forall k, k < n ->
       (lic_head (left_infinite_run k rows c) < lic_R c)%Z) ->
    run (lic_bounded_clock rows n lo c)
      (lic_q5_encode lo c (lic_book_rows rows) []) =
    lic_q5_encode lo (left_infinite_run n rows c)
      (lic_book_rows rows) [].
Proof.
  intros n. induction n as [|n IH];
    intros p lo c rows Hwf Hne Hlen Hleft Hhit HheadR.
  - reflexivity.
  - assert (H0 : lic_hit_state rows c).
    { specialize (Hhit 0 (Nat.lt_0_succ n)).
      cbn [left_infinite_run] in Hhit. exact Hhit. }
    destruct H0 as [Hh [r Hlookup]].
    destruct Hleft as [Hlo Hok].
    cbn [lic_bounded_clock left_infinite_run].
    unfold lic_step_cost.
    rewrite Hlookup.
    destruct (wide_source_lookup_some_book_first_match_hit p rows
      (lic_state c) (lic_tape c (lic_head c)) r Hwf Hlen Hlookup)
      as [steps [hit [after [Hbf [Hhitrow [Hrows0 Hforall]]]]]].
    rewrite Hbf.
    destruct (wr_right r) eqn:Hright.
    + (* right *)
      rewrite (dispatch_run_add
        (lic_q5_right_hit_cost lo c steps hit (wr_next r) (wr_write r))
        (lic_bounded_clock rows n lo (left_infinite_step rows c))).
      rewrite (lic_book_rows_right_hit_step p lo c rows r [] steps hit after
        ltac:(lia) Hh Hwf Hlen Hne Hlookup Hright
        ltac:(exact (HheadR 0 (Nat.lt_0_succ n))) Hbf Hhitrow).
      eapply IH.
      * exact Hwf.
      * exact Hne.
      * assert (Hin_r : In r rows).
        { pose proof (find_some
            (fun row => wide_row_matches row (lic_state c)
               (lic_tape c (lic_head c))) rows Hlookup) as Hfs.
          exact (proj1 Hfs). }
        assert (Hwf_r : wide_row_wellformed p r).
        { rewrite Forall_forall in Hwf. apply Hwf. exact Hin_r. }
        assert (Hstate : lic_state (left_infinite_step rows c) = wr_next r).
        { destruct (left_infinite_step_running_fields rows c r Hh Hlookup
            ltac:(unfold left_infinite_right_blocked; rewrite Hright;
              destruct (Z.eqb (lic_head c) (lic_R c)) eqn:E;
              [apply Z.eqb_eq in E;
               assert (Hlt := HheadR 0 (Nat.lt_0_succ n));
               cbn [left_infinite_run] in Hlt; lia|reflexivity]))
            as [Hs _]. exact Hs. }
        rewrite Hstate. exact (proj2 Hwf_r).
      * apply (lic_left_ok_right lo n c rows r
          (conj Hlo Hok) Hh Hlookup Hright).
      * intros k Hk. exact (Hhit (S k) ltac:(lia)).
      * intros k Hk.
        pose proof (HheadR (S k) ltac:(lia)) as H.
        cbn [left_infinite_run] in H.
        change (lic_head (left_infinite_run k rows
          (left_infinite_step rows c)) <
          lic_R (left_infinite_step rows c))%Z.
        rewrite lic_R_step. exact H.
    + (* left *)
      assert (Hlt : (lo < lic_head c - 1)%Z).
      { rewrite Nat2Z.inj_succ in Hlo. lia. }
      assert (Hbf' : book_first_match
        (lic_state c ++ [lic_tape c (lic_head c)])
        (lic_book_rows rows) =
        book_lookup_hit steps hit (after ++ [lic_sentinel_row rows])).
      { unfold lic_book_rows.
        rewrite (@book_first_match_hit_app
          (lic_state c ++ [lic_tape c (lic_head c)])
          (source_rows_to_book rows) [lic_sentinel_row rows]
          steps hit after Hbf).
        reflexivity. }
      destruct (after ++ [lic_sentinel_row rows]) as [|next rest] eqn:E.
      { apply snoc_neq_nil in E. contradiction. }
      assert (Hrows_aug : lic_book_rows rows =
        map bf_row steps ++ hit :: next :: rest).
      { unfold lic_book_rows. rewrite Hrows0.
        rewrite <- app_assoc. cbn [app]. rewrite E. reflexivity. }
      assert (Hconds : Forall (fun br => br_cond br <> [])
        (lic_book_rows rows)).
      { apply (lic_book_rows_cond_nonempty p rows Hwf Hne). }
      assert (Hin : In next (lic_book_rows rows)).
      { assert (Hin' : In next
            (map bf_row steps ++ hit :: next :: rest)).
        { apply in_or_app. right. right. left. reflexivity. }
        exact (eq_ind (map bf_row steps ++ hit :: next :: rest)
          (fun l => In next l) Hin' (lic_book_rows rows)
          (eq_sym Hrows_aug)). }
      assert (Hne_next : br_cond next <> []).
      { exact (proj1 (Forall_forall (fun br => br_cond br <> [])
          (lic_book_rows rows)) Hconds next Hin). }
      destruct (br_cond next) as [|c0 creast] eqn:Enext.
      { contradiction. }
      rewrite (dispatch_run_add
        (lic_q5_left_hit_cost lo c steps hit (wr_next r) (wr_write r))
        (lic_bounded_clock rows n lo (left_infinite_step rows c))).
      rewrite (lic_book_rows_left_hit_step p lo c rows r [] steps hit
        next rest c0 creast Hlt Hh Hok Hwf Hlen Hne Hlookup Hright
        Hbf' Hhitrow Hrows_aug Enext).
      eapply IH.
      * exact Hwf.
      * exact Hne.
      * assert (Hin_r : In r rows).
        { pose proof (find_some
            (fun row => wide_row_matches row (lic_state c)
               (lic_tape c (lic_head c))) rows Hlookup) as Hfs.
          exact (proj1 Hfs). }
        assert (Hwf_r : wide_row_wellformed p r).
        { rewrite Forall_forall in Hwf. apply Hwf. exact Hin_r. }
        assert (Hstate : lic_state (left_infinite_step rows c) = wr_next r).
        { destruct (left_infinite_step_running_fields rows c r Hh Hlookup
            ltac:(unfold left_infinite_right_blocked; rewrite Hright;
              reflexivity)) as [Hs _]. exact Hs. }
        rewrite Hstate. exact (proj2 Hwf_r).
      * apply (lic_left_ok_left lo n c rows r
          (conj Hlo Hok) Hh Hlookup Hright).
      * intros k Hk. exact (Hhit (S k) ltac:(lia)).
      * intros k Hk.
        pose proof (HheadR (S k) ltac:(lia)) as H.
        cbn [left_infinite_run] in H.
        change (lic_head (left_infinite_run k rows
          (left_infinite_step rows c)) <
          lic_R (left_infinite_step rows c))%Z.
        rewrite lic_R_step. exact H.
Qed.

Print Assumptions lic_left_hit_run.
