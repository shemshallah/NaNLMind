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
    (forall k, k < n -> forall r,
       wide_source_lookup rows
         (lic_state (left_infinite_run k rows c))
         (lic_tape (left_infinite_run k rows c)
            (lic_head (left_infinite_run k rows c))) = Some r ->
       wr_right r = true ->
       (lic_head (left_infinite_run k rows c) < lic_R c)%Z) ->
    run (lic_bounded_clock rows n lo c)
      (lic_q5_encode lo c (lic_book_rows rows) []) =
    lic_q5_encode lo (left_infinite_run n rows c)
      (lic_book_rows rows) [].
Proof.
  intros n. induction n as [|n IH];
    intros p lo c rows Hwf Hne Hlen Hleft Hhit Hwall.
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
        ltac:(exact (Hwall 0 (Nat.lt_0_succ n) r Hlookup Hright))
        Hbf Hhitrow).
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
               assert (Hlt := Hwall 0 (Nat.lt_0_succ n) r Hlookup Hright);
               cbn [left_infinite_run] in Hlt; lia|reflexivity]))
            as [Hs _]. exact Hs. }
        rewrite Hstate. exact (proj2 Hwf_r).
      * apply (lic_left_ok_right lo n c rows r
          (conj Hlo Hok) Hh Hlookup Hright).
      * intros k Hk. exact (Hhit (S k) ltac:(lia)).
      * intros k Hk r0 Hlk Hright0.
        pose proof (Hwall (S k) ltac:(lia) r0 Hlk Hright0) as H.
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
      * intros k Hk r0 Hlk Hright0.
        pose proof (Hwall (S k) ltac:(lia) r0 Hlk Hright0) as H.
        cbn [left_infinite_run] in H.
        change (lic_head (left_infinite_run k rows
          (left_infinite_step rows c)) <
          lic_R (left_infinite_step rows c))%Z.
        rewrite lic_R_step. exact H.
Qed.

Print Assumptions lic_left_hit_run.

Lemma lic_left_ok_run :
  forall (n : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    lic_left_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    lic_left_ok lo 0 (left_infinite_run n rows c).
Proof.
  induction n as [|n IH]; intros lo c rows Hleft Hhit.
  - cbn [left_infinite_run]. exact Hleft.
  - assert (H0 : lic_hit_state rows c).
    { specialize (Hhit 0 (Nat.lt_0_succ n)).
      cbn [left_infinite_run] in Hhit. exact Hhit. }
    destruct H0 as [Hh [r Hlookup]].
    cbn [left_infinite_run].
    destruct (wr_right r) eqn:Hright.
    + apply IH.
      * apply (lic_left_ok_right lo n c rows r Hleft Hh Hlookup Hright).
      * intros k Hk. exact (Hhit (S k) ltac:(lia)).
    + apply IH.
      * apply (lic_left_ok_left lo n c rows r Hleft Hh Hlookup Hright).
      * intros k Hk. exact (Hhit (S k) ltac:(lia)).
Qed.

Theorem lic_left_none_halt_run :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_left_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    (forall k, k < n -> forall r,
       wide_source_lookup rows
         (lic_state (left_infinite_run k rows c))
         (lic_tape (left_infinite_run k rows c)
            (lic_head (left_infinite_run k rows c))) = Some r ->
       wr_right r = true ->
       (lic_head (left_infinite_run k rows c) < lic_R c)%Z) ->
    lic_halted (left_infinite_run n rows c) = false ->
    wide_source_lookup rows
      (lic_state (left_infinite_run n rows c))
      (lic_tape (left_infinite_run n rows c)
        (lic_head (left_infinite_run n rows c))) = None ->
    exists steps last,
      run (lic_bounded_clock rows n lo c +
           (S (length (lic_state (left_infinite_run n rows c))) +
            (book_failures_clock [] steps +
             book_halt_clock (map bf_row steps) last)))
        (lic_q5_encode lo c (lic_book_rows rows) []) =
      lic_halt_encode lo
        (left_infinite_step rows (left_infinite_run n rows c))
        steps last [] /\
      c_halted (lic_halt_encode lo
        (left_infinite_step rows (left_infinite_run n rows c))
        steps last []) = true.
Proof.
  intros n p lo c rows Hwf Hne Hlen Hleft Hhit Hwall Hhalted Hnone.
  assert (Hleft0 : lic_left_ok lo 0 (left_infinite_run n rows c))
    by (apply (lic_left_ok_run n lo c rows Hleft Hhit)).
  assert (Hlo : (lo < lic_head (left_infinite_run n rows c))%Z).
  { destruct Hleft0 as [Hlo _]. cbn [Z.of_nat] in Hlo. lia. }
  assert (Hlen0 : length (lic_state (left_infinite_run n rows c)) = p)
    by (apply (lic_state_length_run n p c rows Hlen Hwf Hhit)).
  destruct (lic_book_rows_none_halt_step p lo
    (left_infinite_run n rows c) rows [] Hlo Hhalted Hwf Hlen0 Hne Hnone)
    as [steps [last [Hbf [Hrun Hhaltedc]]]].
  exists steps, last. split.
  - rewrite (dispatch_run_add (lic_bounded_clock rows n lo c)
      (S (length (lic_state (left_infinite_run n rows c))) +
       (book_failures_clock [] steps +
        book_halt_clock (map bf_row steps) last))).
    rewrite (lic_left_hit_run n p lo c rows Hwf Hne Hlen Hleft Hhit Hwall).
    exact Hrun.
  - exact Hhaltedc.
Qed.

(** ** No premature halt for a left-depth hit run *)

Theorem lic_left_no_premature_halt :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_left_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    (forall k, k < n -> forall r,
       wide_source_lookup rows
         (lic_state (left_infinite_run k rows c))
         (lic_tape (left_infinite_run k rows c)
            (lic_head (left_infinite_run k rows c))) = Some r ->
       wr_right r = true ->
       (lic_head (left_infinite_run k rows c) < lic_R c)%Z) ->
    forall t,
      t <= lic_bounded_clock rows n lo c ->
      c_halted (run t
        (lic_q5_encode lo c (lic_book_rows rows) [])) = true ->
      False.
Proof.
  intros n p lo c rows Hwf Hne Hlen Hleft Hhit Hwall t Ht Hhalt.
  assert (Hhalt_clock : c_halted
    (run (lic_bounded_clock rows n lo c)
      (lic_q5_encode lo c (lic_book_rows rows) [])) = true).
  { replace (lic_bounded_clock rows n lo c)
      with (t + (lic_bounded_clock rows n lo c - t)) by lia.
    rewrite dispatch_run_add.
    rewrite (dispatch_halted_run
      (lic_bounded_clock rows n lo c - t)
      (run t (lic_q5_encode lo c (lic_book_rows rows) [])) Hhalt).
    exact Hhalt. }
  rewrite (lic_left_hit_run n p lo c rows Hwf Hne Hlen Hleft Hhit Hwall)
    in Hhalt_clock.
  unfold lic_q5_encode, book_q5_raw in Hhalt_clock.
  rewrite cfg_ml_halted in Hhalt_clock.
  discriminate Hhalt_clock.
Qed.

Print Assumptions lic_left_no_premature_halt.

(** ** The left-depth invariant for a window of depth [K] *)

Lemma lic_left_ok_window :
  forall (K k : nat) (c : LeftInfiniteConfig),
    K >= k ->
    left_infinite_ok c ->
    lic_left_ok (lic_head c - Z.of_nat K - 2) k c.
Proof.
  intros K k c Hle Hok. unfold lic_left_ok.
  split; [|exact Hok].
  assert (HZK : (Z.of_nat k <= Z.of_nat K)%Z)
    by (apply (proj1 (Nat2Z.inj_le k K)); exact Hle).
  lia.
Qed.

Print Assumptions lic_left_ok_window.
