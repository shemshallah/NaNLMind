(** * Bounded-window simulation of hit-only source runs

    This file isolates the clean, unconditional part of the final
    universality argument: a source run of [n] steps that never reaches
    the right wall and never fails lookup is simulated exactly by the
    frozen table, with a window chosen [n+2] cells deep on each side.

    The window is only used for the induction; it is not part of the
    frozen table.  The one-step macros are the sentinel-augmented
    description macros from [MinskyLeftInfiniteEncoding]. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyMatchMacro MinskyCanonicalInstruction MinskyBookLayout MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyBookLocateCycle MinskyBookLocateLookup
  MinskyBookEncode MinskyBookRawBuffer MinskyLeftInfinite
  MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteFirstMatchApp MinskyLeftInfiniteStepRight
  MinskyLeftInfiniteStepLeft MinskyLeftInfiniteEncoding.

(** ** Padding and the bounded-window invariant *)

Definition lic_pad_lo (c : LeftInfiniteConfig) (n : nat) : Z :=
  lic_head c - Z.of_nat n - 2.

Definition lic_pad_R (c : LeftInfiniteConfig) (n : nat) : Z :=
  Z.max (lic_R c) (lic_head c + Z.of_nat n + 2).

Definition lic_pad_cfg (c : LeftInfiniteConfig) (n : nat)
    : LeftInfiniteConfig :=
  {| lic_state := lic_state c;
     lic_head := lic_head c;
     lic_tape := lic_tape c;
     lic_R := lic_pad_R c n;
     lic_halted := lic_halted c |}.

Definition lic_bounded_ok (lo : Z) (n : nat)
    (c : LeftInfiniteConfig) : Prop :=
  (lo + Z.of_nat n + 2 <= lic_head c)%Z /\
  (lic_head c + Z.of_nat n + 2 <= lic_R c)%Z /\
  left_infinite_ok c.

Lemma lic_R_pad_cfg :
  forall c n,
    lic_R (lic_pad_cfg c n) =
    Z.max (lic_R c) (lic_head c + Z.of_nat n + 2).
Proof. reflexivity. Qed.

Lemma lic_head_pad_cfg :
  forall c n, lic_head (lic_pad_cfg c n) = lic_head c.
Proof. reflexivity. Qed.

Lemma lic_state_pad_cfg :
  forall c n, lic_state (lic_pad_cfg c n) = lic_state c.
Proof. reflexivity. Qed.

Lemma lic_tape_pad_cfg :
  forall c n, lic_tape (lic_pad_cfg c n) = lic_tape c.
Proof. reflexivity. Qed.

Lemma lic_halted_pad_cfg :
  forall c n, lic_halted (lic_pad_cfg c n) = lic_halted c.
Proof. reflexivity. Qed.

Lemma lic_pad_cfg_ok :
  forall c n,
    left_infinite_ok c ->
    left_infinite_ok (lic_pad_cfg c n).
Proof.
  intros c n [Hle Hblank]. unfold left_infinite_ok.
  rewrite lic_head_pad_cfg, lic_R_pad_cfg.
  split.
  - etransitivity; [exact Hle|]. apply Z.le_max_l.
  - intros z Hz.
    rewrite lic_tape_pad_cfg.
    apply Hblank.
    exact (Z.le_lt_trans _ _ _ (Z.le_max_l _ _) Hz).
Qed.

Lemma lic_pad_cfg_bounded :
  forall c n,
    left_infinite_ok c ->
    lic_bounded_ok (lic_pad_lo c n) n (lic_pad_cfg c n).
Proof.
  intros c n Hok. unfold lic_bounded_ok, lic_pad_lo.
  rewrite lic_head_pad_cfg, lic_R_pad_cfg.
  split; [lia|].
  split.
  - apply Z.le_max_r.
  - apply lic_pad_cfg_ok. exact Hok.
Qed.

(** ** Preservation of the bounded-window invariant *)

Lemma lic_bounded_ok_right :
  forall (lo : Z) (n : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow),
    lic_bounded_ok lo (S n) c ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    lic_bounded_ok lo n (left_infinite_step rows c).
Proof.
  intros lo n c rows r [Hlo [Hhi Hok]] Hh Hlookup Hright.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright.
    destruct (Z.eqb (lic_head c) (lic_R c)) eqn:E.
    - apply Z.eqb_eq in E. lia.
    - reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [_ [HR _]]]].
  rewrite Hright in Hhead.
  unfold lic_bounded_ok.
  rewrite Hhead, HR.
  rewrite Nat2Z.inj_succ in Hlo, Hhi.
  split; [|split].
  - lia.
  - lia.
  - apply (left_infinite_step_ok rows c Hok).
Qed.

Lemma lic_bounded_ok_left :
  forall (lo : Z) (n : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow),
    lic_bounded_ok lo (S n) c ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    lic_bounded_ok lo n (left_infinite_step rows c).
Proof.
  intros lo n c rows r [Hlo [Hhi Hok]] Hh Hlookup Hleft.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hleft. reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead [_ [HR _]]]].
  rewrite Hleft in Hhead.
  unfold lic_bounded_ok.
  rewrite Hhead, HR.
  rewrite Nat2Z.inj_succ in Hlo, Hhi.
  split; [|split].
  - lia.
  - lia.
  - apply (left_infinite_step_ok rows c Hok).
Qed.

Lemma lic_bounded_ok_halt :
  forall (lo : Z) (n : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    lic_bounded_ok lo (S n) c ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = None ->
    lic_bounded_ok lo n (left_infinite_step rows c).
Proof.
  intros lo n c rows [Hlo [Hhi Hok]] Hh Hnone.
  destruct (left_infinite_step_lookup_none_fields rows c Hh Hnone)
    as [_ [Hhead [_ [HR _]]]].
  unfold lic_bounded_ok. rewrite Hhead, HR.
  rewrite Nat2Z.inj_succ in Hlo, Hhi.
  split; [|split].
  - lia.
  - lia.
  - apply (left_infinite_step_ok rows c Hok).
Qed.

Print Assumptions lic_bounded_ok_right.
Print Assumptions lic_bounded_ok_left.
Print Assumptions lic_bounded_ok_halt.

(** ** Per-step computation and the bounded clock *)

Definition lic_hit_state
    (rows : list WideSourceRow) (c : LeftInfiniteConfig) : Prop :=
  lic_halted c = false /\
  exists r, wide_source_lookup rows (lic_state c)
              (lic_tape c (lic_head c)) = Some r.

Definition lic_step_cost
    (rows : list WideSourceRow) (lo : Z) (c : LeftInfiniteConfig) : nat :=
  let src := lic_state c ++ [lic_tape c (lic_head c)] in
  match wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) with
  | Some r =>
      match book_first_match src (source_rows_to_book rows) with
      | book_lookup_hit steps hit after =>
          if wr_right r
          then lic_q5_right_hit_cost lo c steps hit
                 (wr_next r) (wr_write r)
          else lic_q5_left_hit_cost lo c steps hit
                 (wr_next r) (wr_write r)
      | _ => 0
      end
  | None =>
      match book_first_match src (lic_book_rows rows) with
      | book_lookup_halt steps last =>
          S (length (lic_state c)) +
          (book_failures_clock [] steps +
           book_halt_clock (map bf_row steps) last)
      | _ => 0
      end
  end.

Fixpoint lic_bounded_clock
    (rows : list WideSourceRow) (n : nat) (lo : Z)
    (c : LeftInfiniteConfig) : nat :=
  match n with
  | 0 => 0
  | S k =>
      lic_step_cost rows lo c +
      lic_bounded_clock rows k lo (left_infinite_step rows c)
  end.

(** ** The bounded hit-only run theorem *)

Theorem lic_bounded_hit_run :
  forall (n : nat) (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_bounded_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    run (lic_bounded_clock rows n lo c)
      (lic_q5_encode lo c (lic_book_rows rows) []) =
    lic_q5_encode lo (left_infinite_run n rows c)
      (lic_book_rows rows) [].
Proof.
  intros n. induction n as [|n IH];
    intros p lo c rows Hwf Hne Hlen Hbounded Hhit.
  - reflexivity.
  - assert (H0 : lic_hit_state rows c).
    { specialize (Hhit 0 (Nat.lt_0_succ n)).
      cbn [left_infinite_run] in Hhit. exact Hhit. }
    destruct H0 as [Hh [r Hlookup]].
    destruct Hbounded as [Hlo [Hhi Hok]].
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
        ltac:(lia) Hh Hwf Hlen Hne Hlookup Hright ltac:(lia)
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
              [apply Z.eqb_eq in E; lia|reflexivity])) as [Hs _].
          exact Hs. }
        rewrite Hstate. exact (proj2 Hwf_r).
      * apply (lic_bounded_ok_right lo n c rows r
          (conj Hlo (conj Hhi Hok)) Hh Hlookup Hright).
      * intros k Hk.
        exact (Hhit (S k) (ltac:(lia))).
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
        next rest c0 creast Hlt Hh
        Hok
        Hwf Hlen Hne Hlookup Hright Hbf' Hhitrow Hrows_aug Enext).
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
              reflexivity)) as [Hs _].
          exact Hs. }
        rewrite Hstate. exact (proj2 Hwf_r).
      * apply (lic_bounded_ok_left lo n c rows r
          (conj Hlo (conj Hhi Hok)) Hh Hlookup Hright).
      * intros k Hk.
        exact (Hhit (S k) (ltac:(lia))).
Qed.

Print Assumptions lic_bounded_hit_run.

(** ** Preservation of the window along a hit-only run *)

Lemma lic_bounded_ok_run :
  forall (n : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    lic_bounded_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    lic_bounded_ok lo 0 (left_infinite_run n rows c).
Proof.
  induction n as [|n IH]; intros lo c rows Hbounded Hhit.
  - cbn [left_infinite_run]. exact Hbounded.
  - assert (H0 : lic_hit_state rows c).
    { specialize (Hhit 0 (Nat.lt_0_succ n)).
      cbn [left_infinite_run] in Hhit. exact Hhit. }
    destruct H0 as [Hh [r Hlookup]].
    cbn [left_infinite_run].
    destruct (wr_right r) eqn:Hright.
    + apply IH.
      * apply (lic_bounded_ok_right lo n c rows r Hbounded Hh Hlookup Hright).
      * intros k Hk. exact (Hhit (S k) ltac:(lia)).
    + apply IH.
      * apply (lic_bounded_ok_left lo n c rows r Hbounded Hh Hlookup Hright).
      * intros k Hk. exact (Hhit (S k) ltac:(lia)).
Qed.

(** ** State length along a hit-only run *)

Lemma lic_state_length_run :
  forall (n p : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    length (lic_state c) = p ->
    Forall (wide_row_wellformed p) rows ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    length (lic_state (left_infinite_run n rows c)) = p.
Proof.
  induction n as [|n IH]; intros p c rows Hlen Hwf Hhit.
  - cbn [left_infinite_run]. exact Hlen.
  - assert (H0 : lic_hit_state rows c).
    { specialize (Hhit 0 (Nat.lt_0_succ n)).
      cbn [left_infinite_run] in Hhit. exact Hhit. }
    destruct H0 as [Hh [r Hlookup]].
    cbn [left_infinite_run].
    assert (Hin_r : In r rows).
    { pose proof (find_some
        (fun row => wide_row_matches row (lic_state c)
           (lic_tape c (lic_head c))) rows Hlookup) as Hfs.
      exact (proj1 Hfs). }
    assert (Hwf_r : wide_row_wellformed p r).
    { rewrite Forall_forall in Hwf. apply Hwf. exact Hin_r. }
    assert (Hstate : length (lic_state (left_infinite_step rows c)) = p).
    { destruct (left_infinite_right_blocked c r) eqn:Hb.
      - destruct (left_infinite_step_blocked_fields rows c r Hh Hlookup Hb)
          as [Hs _]. rewrite Hs. exact Hlen.
      - destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
          as [Hs _]. rewrite Hs. exact (proj2 Hwf_r). }
    apply (IH p (left_infinite_step rows c) rows).
    + exact Hstate.
    + exact Hwf.
    + intros k Hk. exact (Hhit (S k) ltac:(lia)).
Qed.

(** ** Bounded run reaching a no-match halt *)

Theorem lic_bounded_none_halt_run :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_bounded_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
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
  intros n p lo c rows Hwf Hne Hlen Hbounded Hhit Hhalted Hnone.
  assert (Hbounded0 : lic_bounded_ok lo 0 (left_infinite_run n rows c))
    by (apply (lic_bounded_ok_run n lo c rows Hbounded Hhit)).
  assert (Hlo : (lo < lic_head (left_infinite_run n rows c))%Z).
  { destruct Hbounded0 as [Hlo _]. cbn [Z.of_nat] in Hlo. lia. }
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
    rewrite (lic_bounded_hit_run n p lo c rows Hwf Hne Hlen Hbounded Hhit).
    exact Hrun.
  - exact Hhaltedc.
Qed.

Print Assumptions lic_bounded_ok_run.
Print Assumptions lic_state_length_run.
Print Assumptions lic_bounded_none_halt_run.

(** ** Positivity of the per-step clock *)

Lemma lic_step_cost_pos :
  forall (p : nat) (rows : list WideSourceRow) (lo : Z)
         (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    lic_hit_state rows c ->
    1 <= lic_step_cost rows lo c.
Proof.
  intros p rows lo c Hwf Hlen [Hh [r Hlookup]].
  destruct (wide_source_lookup_some_book_first_match_hit p rows
    (lic_state c) (lic_tape c (lic_head c)) r Hwf Hlen Hlookup)
    as [steps [hit [after [Hbf _]]]].
  unfold lic_step_cost. rewrite Hlookup, Hbf.
  destruct (wr_right r).
  - unfold lic_q5_right_hit_cost, book_steady_locate_q12_clock_gen,
      book_q12_perform_right_clock_raw, restore_clock. lia.
  - unfold lic_q5_left_hit_cost, book_steady_locate_q12_clock_gen,
      book_q13_perform_left_clock_raw, restore_clock. lia.
Qed.

Lemma lic_state_length_step :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    length (lic_state c) = p ->
    Forall (wide_row_wellformed p) rows ->
    lic_hit_state rows c ->
    length (lic_state (left_infinite_step rows c)) = p.
Proof.
  intros p rows c Hlen Hwf [Hh [r Hlookup]].
  assert (Hin_r : In r rows).
  { pose proof (find_some
      (fun row => wide_row_matches row (lic_state c)
         (lic_tape c (lic_head c))) rows Hlookup) as Hfs.
    exact (proj1 Hfs). }
  assert (Hwf_r : wide_row_wellformed p r).
  { rewrite Forall_forall in Hwf. apply Hwf. exact Hin_r. }
  destruct (left_infinite_right_blocked c r) eqn:Hb.
  - destruct (left_infinite_step_blocked_fields rows c r Hh Hlookup Hb)
      as [Hs _]. rewrite Hs. exact Hlen.
  - destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
      as [Hs _]. rewrite Hs. exact (proj2 Hwf_r).
Qed.

Lemma lic_bounded_clock_at_least_steps :
  forall (n p : nat) (rows : list WideSourceRow) (lo : Z)
         (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    n <= lic_bounded_clock rows n lo c.
Proof.
  induction n as [|n IH]; intros p rows lo c Hwf Hlen Hhit.
  - cbn [lic_bounded_clock]. lia.
  - cbn [lic_bounded_clock].
    assert (Hh : lic_hit_state rows c).
    { specialize (Hhit 0 (Nat.lt_0_succ n)).
      cbn [left_infinite_run] in Hhit. exact Hhit. }
    assert (Hpos : 1 <= lic_step_cost rows lo c)
      by (apply (lic_step_cost_pos p rows lo c Hwf Hlen Hh)).
    assert (Hlen' : length (lic_state (left_infinite_step rows c)) = p)
      by (apply (lic_state_length_step p rows c Hlen Hwf Hh)).
    assert (Hrec : n <= lic_bounded_clock rows n lo
        (left_infinite_step rows c)).
    { apply (IH p rows lo (left_infinite_step rows c) Hwf Hlen').
      intros k Hk. exact (Hhit (S k) ltac:(lia)). }
    lia.
Qed.

Print Assumptions lic_step_cost_pos.
Print Assumptions lic_bounded_clock_at_least_steps.

Lemma cfg_ml_halted :
  forall (q : nat) (l r : list nat), c_halted (cfg_ml q l r) = false.
Proof.
  intros q l r. unfold cfg_ml. destruct l; reflexivity.
Qed.

(** ** Constructive search for the first non-hit step *)

Fixpoint lic_first_stop
    (rows : list WideSourceRow) (k : nat) (c : LeftInfiniteConfig)
    : option (nat * LeftInfiniteConfig) :=
  match k with
  | 0 => None
  | S k' =>
      if lic_halted c then Some (0, c)
      else
        match wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) with
        | None => Some (1, left_infinite_step rows c)
        | Some _ =>
            match lic_first_stop rows k' (left_infinite_step rows c) with
            | Some (j, c') => Some (S j, c')
            | None => None
            end
        end
  end.

Lemma lic_first_stop_sound :
  forall rows k c j c',
    lic_first_stop rows k c = Some (j, c') ->
    c' = left_infinite_run j rows c /\ lic_halted c' = true.
Proof.
  induction k as [|k IH]; intros c j c' H; [cbn [lic_first_stop] in H; discriminate H|].
  cbn [lic_first_stop] in H.
  destruct (lic_halted c) eqn:Eh.
  - inversion H; subst. split.
    + cbn [left_infinite_run]. reflexivity.
    + exact Eh.
  - destruct (wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c))) as [r|] eqn:El.
    + destruct (lic_first_stop rows k (left_infinite_step rows c))
        as [[j' c'']|] eqn:E; [|discriminate H].
      inversion H; subst.
      destruct (IH (left_infinite_step rows c) j' c' E) as [Hrun Hhalt].
      split.
      * cbn [left_infinite_run]. rewrite <- Hrun. reflexivity.
      * exact Hhalt.
    + inversion H; subst. split.
      * cbn [left_infinite_run]. reflexivity.
      * apply (left_infinite_step_lookup_none rows c Eh El).
Qed.

Lemma lic_first_stop_none :
  forall rows k c,
    lic_first_stop rows k c = None ->
    forall j, j < k -> lic_hit_state rows (left_infinite_run j rows c).
Proof.
  induction k as [|k IH]; intros c H j Hj; [lia|].
  cbn [lic_first_stop] in H.
  destruct (lic_halted c) eqn:Eh; [discriminate H|].
  destruct (wide_source_lookup rows (lic_state c)
    (lic_tape c (lic_head c))) as [r|] eqn:El; [|discriminate H].
  destruct j as [|j'].
  - cbn [left_infinite_run]. split; [exact Eh|]. exists r. exact El.
  - cbn [left_infinite_run].
    destruct (lic_first_stop rows k (left_infinite_step rows c))
      as [[j c']|] eqn:E.
    + discriminate H.
    + apply (IH (left_infinite_step rows c) E j'). lia.
Qed.

Print Assumptions lic_first_stop_sound.
Print Assumptions lic_first_stop_none.

(** ** Native halting within the bounded clock implies source halting *)

Theorem lic_bounded_native_halt_implies_source_halt :
  forall (t p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_bounded_ok lo t c ->
    c_halted (run t (lic_q5_encode lo c (lic_book_rows rows) [])) = true ->
    exists k, lic_halted (left_infinite_run k rows c) = true.
Proof.
  intros t p lo c rows Hwf Hne Hlen Hbounded Hnative.
  destruct (lic_first_stop rows t c) as [[j c']|] eqn:E.
  - destruct (lic_first_stop_sound rows t c j c' E) as [Hrun Hhalt].
    exists j. rewrite <- Hrun. exact Hhalt.
  - assert (Hhit : forall k, k < t -> lic_hit_state rows
        (left_infinite_run k rows c))
      by (apply (lic_first_stop_none rows t c E)).
    assert (Hclock : t <= lic_bounded_clock rows t lo c)
      by (apply (lic_bounded_clock_at_least_steps t p rows lo c Hwf Hlen Hhit)).
    assert (Hhalt_clock :
      c_halted (run (lic_bounded_clock rows t lo c)
        (lic_q5_encode lo c (lic_book_rows rows) [])) = true).
    { replace (lic_bounded_clock rows t lo c)
        with (t + (lic_bounded_clock rows t lo c - t)) by lia.
      rewrite dispatch_run_add.
      rewrite (dispatch_halted_run
        (lic_bounded_clock rows t lo c - t)
        (run t (lic_q5_encode lo c (lic_book_rows rows) [])) Hnative).
      exact Hnative. }
    rewrite (lic_bounded_hit_run t p lo c rows Hwf Hne Hlen Hbounded Hhit)
      in Hhalt_clock.
    assert (Hnot : c_halted (lic_q5_encode lo (left_infinite_run t rows c)
      (lic_book_rows rows) []) = false).
    { unfold lic_q5_encode, book_q5_raw.
      apply cfg_ml_halted. }
    rewrite Hnot in Hhalt_clock. discriminate Hhalt_clock.
Qed.

Print Assumptions lic_bounded_native_halt_implies_source_halt.
