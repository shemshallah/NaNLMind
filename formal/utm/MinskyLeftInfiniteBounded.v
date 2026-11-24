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

(** ** Head movement and the right endpoint *)

Lemma left_infinite_run_succ :
  forall n rows c,
    left_infinite_run (S n) rows c =
    left_infinite_step rows (left_infinite_run n rows c).
Proof.
  induction n as [|n IH]; intros rows c.
  - reflexivity.
  - cbn [left_infinite_run]. apply IH.
Qed.

Lemma lic_R_step :
  forall rows c, lic_R (left_infinite_step rows c) = lic_R c.
Proof.
  intros rows c. unfold left_infinite_step.
  destruct (lic_halted c); [reflexivity|].
  destruct (wide_source_lookup rows (lic_state c)
    (lic_tape c (lic_head c))) as [r|]; [|reflexivity].
  destruct (left_infinite_right_blocked c r); reflexivity.
Qed.

Lemma lic_R_run :
  forall n rows c,
    lic_R (left_infinite_run n rows c) = lic_R c.
Proof.
  induction n as [|n IH]; intros rows c; cbn [left_infinite_run].
  - reflexivity.
  - rewrite IH. apply lic_R_step.
Qed.

Lemma lic_bounded_ok_weaken :
  forall (lo : Z) (n m : nat) (c : LeftInfiniteConfig),
    m <= n ->
    lic_bounded_ok lo n c ->
    lic_bounded_ok lo m c.
Proof.
  intros lo n m c Hmn [Hlo [Hhi Hok]].
  unfold lic_bounded_ok.
  rewrite Nat2Z.inj_le in Hmn.
  split; [|split].
  - lia.
  - lia.
  - exact Hok.
Qed.

Lemma lic_head_step_bound :
  forall rows c,
    (lic_head c - 1 <= lic_head (left_infinite_step rows c) /\
     lic_head (left_infinite_step rows c) <= lic_head c + 1)%Z.
Proof.
  intros rows c. unfold left_infinite_step.
  destruct (lic_halted c) eqn:Eh; [cbn; lia|].
  destruct (wide_source_lookup rows (lic_state c)
    (lic_tape c (lic_head c))) as [r|] eqn:El; [|cbn; lia].
  destruct (left_infinite_right_blocked c r) eqn:Eb; [cbn; lia|].
  destruct (wr_right r); cbn; lia.
Qed.

Lemma lic_head_run_bound :
  forall n rows c,
    (lic_head c - Z.of_nat n <= lic_head (left_infinite_run n rows c) /\
     lic_head (left_infinite_run n rows c) <= lic_head c + Z.of_nat n)%Z.
Proof.
  induction n as [|n IH]; intros rows c.
  - cbn [left_infinite_run]. lia.
  - cbn [left_infinite_run].
    destruct (IH rows (left_infinite_step rows c)) as [Hlo Hhi].
    pose proof (lic_head_step_bound rows c) as [Hslo Hshi].
    rewrite Nat2Z.inj_succ. lia.
Qed.

Lemma lic_bounded_head_lt_R :
  forall (lo : Z) (n k : nat) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    k <= n ->
    lic_bounded_ok lo n c ->
    (lic_head (left_infinite_run k rows c) < lic_R c)%Z.
Proof.
  intros lo n k c rows Hk [Hlo [Hhi Hok]].
  destruct (lic_head_run_bound k rows c) as [_ Hbound].
  rewrite Nat2Z.inj_le in Hk.
  lia.
Qed.

(** ** Bounded source halting implies native halting *)

Theorem lic_bounded_source_halt_implies_native_halt :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_bounded_ok lo (S n) c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    lic_halted (left_infinite_run n rows c) = false ->
    lic_halted (left_infinite_run (S n) rows c) = true ->
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
  intros n p lo c rows Hwf Hne Hlen Hbounded Hhit
    Hnot_halted_n Hhalt.
  assert (Hstep_halted : lic_halted
    (left_infinite_step rows (left_infinite_run n rows c)) = true).
  { rewrite <- left_infinite_run_succ. exact Hhalt. }
  assert (Hrun_none : wide_source_lookup rows
      (lic_state (left_infinite_run n rows c))
      (lic_tape (left_infinite_run n rows c)
        (lic_head (left_infinite_run n rows c))) = None).
  { unfold left_infinite_step in Hstep_halted.
    rewrite Hnot_halted_n in Hstep_halted.
    destruct (wide_source_lookup rows
      (lic_state (left_infinite_run n rows c))
      (lic_tape (left_infinite_run n rows c)
        (lic_head (left_infinite_run n rows c)))) as [r|] eqn:E.
    - destruct (left_infinite_right_blocked
        (left_infinite_run n rows c) r) eqn:Eb.
      + exfalso.
        assert (Hlt := lic_bounded_head_lt_R lo (S n) n c rows
          ltac:(lia) Hbounded).
        unfold left_infinite_right_blocked in Eb.
        apply Bool.andb_true_iff in Eb. destruct Eb as [_ Heq].
        apply Z.eqb_eq in Heq.
        rewrite (lic_R_run n rows c) in Heq.
        lia.
      + discriminate Hstep_halted.
    - reflexivity. }
  apply (lic_bounded_none_halt_run n p lo c rows Hwf Hne Hlen
    (lic_bounded_ok_weaken lo (S n) n c ltac:(lia) Hbounded)
    Hhit Hnot_halted_n Hrun_none).
Qed.

Print Assumptions lic_head_run_bound.
Print Assumptions lic_bounded_source_halt_implies_native_halt.

(** ** Corollaries for the padded source configuration

    [lic_pad_cfg c n] extends the tape's right endpoint to
    [max R (head + n + 2)] and keeps the tape function.  It is the
    canonical right-unbounded finite window for an [n]-step run. *)

Corollary lic_pad_hit_run :
  forall (n p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows (lic_pad_cfg c n))) ->
    run (lic_bounded_clock rows n (lic_pad_lo c n) (lic_pad_cfg c n))
      (lic_q5_encode (lic_pad_lo c n) (lic_pad_cfg c n)
        (lic_book_rows rows) []) =
    lic_q5_encode (lic_pad_lo c n)
      (left_infinite_run n rows (lic_pad_cfg c n))
      (lic_book_rows rows) [].
Proof.
  intros n p rows c Hwf Hne Hlen Hok Hhit.
  apply (lic_bounded_hit_run n p (lic_pad_lo c n) (lic_pad_cfg c n)
    rows Hwf Hne).
  - rewrite lic_state_pad_cfg. exact Hlen.
  - apply (lic_pad_cfg_bounded c n Hok).
  - exact Hhit.
Qed.

Corollary lic_pad_none_halt_run :
  forall (n p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows (lic_pad_cfg c n))) ->
    lic_halted (left_infinite_run n rows (lic_pad_cfg c n)) = false ->
    wide_source_lookup rows
      (lic_state (left_infinite_run n rows (lic_pad_cfg c n)))
      (lic_tape (left_infinite_run n rows (lic_pad_cfg c n))
        (lic_head (left_infinite_run n rows (lic_pad_cfg c n)))) = None ->
    exists steps last,
      run (lic_bounded_clock rows n (lic_pad_lo c n) (lic_pad_cfg c n) +
           (S (length (lic_state
                (left_infinite_run n rows (lic_pad_cfg c n)))) +
            (book_failures_clock [] steps +
             book_halt_clock (map bf_row steps) last)))
        (lic_q5_encode (lic_pad_lo c n) (lic_pad_cfg c n)
          (lic_book_rows rows) []) =
      lic_halt_encode (lic_pad_lo c n)
        (left_infinite_step rows
          (left_infinite_run n rows (lic_pad_cfg c n)))
        steps last [] /\
      c_halted (lic_halt_encode (lic_pad_lo c n)
        (left_infinite_step rows
          (left_infinite_run n rows (lic_pad_cfg c n)))
        steps last []) = true.
Proof.
  intros n p rows c Hwf Hne Hlen Hok Hhit Hhalted Hnone.
  apply (lic_bounded_none_halt_run n p (lic_pad_lo c n) (lic_pad_cfg c n)
    rows Hwf Hne).
  - rewrite lic_state_pad_cfg. exact Hlen.
  - apply (lic_pad_cfg_bounded c n Hok).
  - exact Hhit.
  - exact Hhalted.
  - exact Hnone.
Qed.

Corollary lic_pad_native_halt_implies_source_halt :
  forall (t p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    c_halted (run t (lic_q5_encode (lic_pad_lo c t) (lic_pad_cfg c t)
      (lic_book_rows rows) [])) = true ->
    exists k, lic_halted (left_infinite_run k rows (lic_pad_cfg c t)) = true.
Proof.
  intros t p rows c Hwf Hne Hlen Hok Hnative.
  apply (lic_bounded_native_halt_implies_source_halt t p
    (lic_pad_lo c t) (lic_pad_cfg c t) rows Hwf Hne).
  - rewrite lic_state_pad_cfg. exact Hlen.
  - apply (lic_pad_cfg_bounded c t Hok).
  - exact Hnative.
Qed.

Print Assumptions lic_pad_hit_run.
Print Assumptions lic_pad_none_halt_run.
Print Assumptions lic_pad_native_halt_implies_source_halt.

(** ** First halting time *)

Definition lic_halts_at_first
    (rows : list WideSourceRow) (c : LeftInfiniteConfig) (n : nat) : Prop :=
  lic_halted (left_infinite_run n rows c) = true /\
  forall k, k < n -> lic_halted (left_infinite_run k rows c) = false.

Lemma lic_first_halt_exists :
  forall n rows c,
    lic_halted (left_infinite_run n rows c) = true ->
    exists k, k <= n /\ lic_halts_at_first rows c k.
Proof.
  induction n as [|n IH]; intros rows c H.
  - exists 0. split; [lia|]. split.
    + cbn [left_infinite_run] in H. exact H.
    + intros k Hk. lia.
  - destruct (lic_halted c) eqn:Eh.
    + exists 0. split; [lia|]. split; [exact Eh|].
      intros k Hk. lia.
    + cbn [left_infinite_run] in H.
      destruct (IH rows (left_infinite_step rows c) H) as [k [Hle Hfirst]].
      exists (S k). split; [lia|]. split.
      * change (lic_halted
          (left_infinite_run k rows (left_infinite_step rows c)) = true).
        exact (proj1 Hfirst).
      * intros j Hj. destruct j as [|j'].
        -- cbn [left_infinite_run]. exact Eh.
        -- change (lic_halted
            (left_infinite_run j' rows (left_infinite_step rows c)) = false).
           apply (proj2 Hfirst j'). lia.
Qed.

Lemma lic_running_step_hit :
  forall rows c,
    lic_halted c = false ->
    lic_halted (left_infinite_step rows c) = false ->
    lic_hit_state rows c.
Proof.
  intros rows c Hh Hstep.
  unfold lic_hit_state. split; [exact Hh|].
  unfold left_infinite_step in Hstep. rewrite Hh in Hstep.
  destruct (wide_source_lookup rows (lic_state c)
    (lic_tape c (lic_head c))) as [r|] eqn:E.
  - exists r. reflexivity.
  - cbn in Hstep. discriminate Hstep.
Qed.

Lemma lic_first_halt_hit_prefix :
  forall k rows c,
    lic_halts_at_first rows c k ->
    forall i, S i < k -> lic_hit_state rows
      (left_infinite_run i rows c).
Proof.
  intros k rows c [Hhalt Hfirst] i Hi.
  apply (lic_running_step_hit rows (left_infinite_run i rows c)).
  - apply Hfirst. lia.
  - rewrite <- left_infinite_run_succ. apply Hfirst. exact Hi.
Qed.

Print Assumptions lic_first_halt_exists.
Print Assumptions lic_first_halt_hit_prefix.

(** ** Padded encoder for a source run of a fixed length *)

Definition lic_encode_pad
    (rows : list WideSourceRow) (n : nat)
    (c : LeftInfiniteConfig) : Config :=
  if lic_halted c
  then dispatch_halt_at_y [] []
  else lic_q5_encode (lic_pad_lo c n) (lic_pad_cfg c n)
         (lic_book_rows rows) [].

Lemma lic_encode_pad_halted :
  forall rows n c,
    lic_halted c = true ->
    c_halted (lic_encode_pad rows n c) = true.
Proof.
  intros rows n c Hh. unfold lic_encode_pad. rewrite Hh.
  unfold dispatch_halt_at_y. reflexivity.
Qed.

Theorem lic_pad_source_halt_to_native :
  forall (n p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    lic_halted (left_infinite_run n rows (lic_pad_cfg c n)) = true ->
    exists t, c_halted (run t (lic_encode_pad rows n c)) = true.
Proof.
  intros n p rows c Hwf Hne Hlen Hok Hhalt.
  destruct (lic_first_halt_exists n rows (lic_pad_cfg c n) Hhalt)
    as [k [Hk Hfirst]].
  destruct k as [|k'].
  - (* already halted *)
    exists 0. change (c_halted (lic_encode_pad rows n c) = true).
    rewrite (lic_encode_pad_halted rows n c (proj1 Hfirst)).
    reflexivity.
  - (* first halt at S k' *)
    assert (Hnot_halted_k : lic_halted
      (left_infinite_run k' rows (lic_pad_cfg c n)) = false).
    { apply (proj2 Hfirst). lia. }
    assert (Hhalt_S : lic_halted
      (left_infinite_run (S k') rows (lic_pad_cfg c n)) = true).
    { exact (proj1 Hfirst). }
    assert (Hhit : forall i, i < k' -> lic_hit_state rows
      (left_infinite_run i rows (lic_pad_cfg c n))).
    { intros i Hi. apply (lic_first_halt_hit_prefix (S k') rows
        (lic_pad_cfg c n) Hfirst i). lia. }
    assert (Hbounded : lic_bounded_ok (lic_pad_lo c n) (S k')
      (lic_pad_cfg c n)).
    { apply (lic_bounded_ok_weaken (lic_pad_lo c n) n (S k')
        (lic_pad_cfg c n)).
      - lia.
      - apply (lic_pad_cfg_bounded c n Hok). }
    destruct (lic_bounded_source_halt_implies_native_halt k' p
      (lic_pad_lo c n) (lic_pad_cfg c n) rows Hwf Hne
      ltac:(rewrite lic_state_pad_cfg; exact Hlen)
      Hbounded Hhit Hnot_halted_k Hhalt_S)
      as [steps [last [Hrun Hhalted]]].
    exists (lic_bounded_clock rows k' (lic_pad_lo c n) (lic_pad_cfg c n) +
      (S (length (lic_state
            (left_infinite_run k' rows (lic_pad_cfg c n)))) +
       (book_failures_clock [] steps +
        book_halt_clock (map bf_row steps) last))).
    assert (Hc_running : lic_halted c = false).
    { specialize (proj2 Hfirst 0 ltac:(lia)).
      cbn [left_infinite_run]. auto. }
    unfold lic_encode_pad. rewrite Hc_running.
    rewrite Hrun. exact Hhalted.
Qed.

Print Assumptions lic_pad_source_halt_to_native.

(** ** No premature halt within a bounded hit-only clock *)

Theorem lic_bounded_no_premature_halt :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_bounded_ok lo n c ->
    (forall k, k < n -> lic_hit_state rows
       (left_infinite_run k rows c)) ->
    forall t,
      t <= lic_bounded_clock rows n lo c ->
      c_halted (run t
        (lic_q5_encode lo c (lic_book_rows rows) [])) = true ->
      False.
Proof.
  intros n p lo c rows Hwf Hne Hlen Hbounded Hhit t Ht Hhalt.
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
  rewrite (lic_bounded_hit_run n p lo c rows Hwf Hne Hlen Hbounded Hhit)
    in Hhalt_clock.
  unfold lic_q5_encode, book_q5_raw in Hhalt_clock.
  rewrite cfg_ml_halted in Hhalt_clock.
  discriminate Hhalt_clock.
Qed.

Print Assumptions lic_bounded_no_premature_halt.

(** ** Clock-bounded native halt implies source halt *)

Lemma lic_first_stop_bound :
  forall rows n c j c',
    lic_first_stop rows n c = Some (j, c') ->
    j <= n.
Proof.
  induction n as [|n IH]; intros c j c' H.
  - cbn [lic_first_stop] in H. discriminate H.
  - cbn [lic_first_stop] in H.
    destruct (lic_halted c) eqn:Eh.
    + inversion H; subst. lia.
    + destruct (wide_source_lookup rows (lic_state c)
        (lic_tape c (lic_head c))) as [r|] eqn:El.
      * destruct (lic_first_stop rows n (left_infinite_step rows c))
          as [[j' c'']|] eqn:E2; [|discriminate H].
        inversion H; subst.
        pose proof (IH (left_infinite_step rows c) j' c' E2). lia.
      * inversion H; subst. lia.
Qed.

Theorem lic_bounded_clock_native_halt_implies_source_halt :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_bounded_ok lo n c ->
    forall t,
      t <= lic_bounded_clock rows n lo c ->
      c_halted (run t
        (lic_q5_encode lo c (lic_book_rows rows) [])) = true ->
      exists k, k <= n /\ lic_halted
        (left_infinite_run k rows c) = true.
Proof.
  intros n p lo c rows Hwf Hne Hlen Hbounded t Ht Hhalt.
  destruct (lic_first_stop rows n c) as [[j c']|] eqn:E.
  - assert (Hle : j <= n) by (apply (lic_first_stop_bound rows n c j c' E)).
    destruct (lic_first_stop_sound rows n c j c' E) as [Hrun Hhalted].
    exists j. split; [exact Hle|rewrite <- Hrun; exact Hhalted].
  - exfalso.
    apply (lic_bounded_no_premature_halt n p lo c rows Hwf Hne Hlen
      Hbounded (lic_first_stop_none rows n c E) t Ht Hhalt).
Qed.

Print Assumptions lic_bounded_clock_native_halt_implies_source_halt.

(** ** Monotonicity of the bounded clock *)

Lemma lic_bounded_clock_mono :
  forall (n m : nat) (rows : list WideSourceRow) (lo : Z)
         (c : LeftInfiniteConfig),
    n <= m ->
    lic_bounded_clock rows n lo c <=
    lic_bounded_clock rows m lo c.
Proof.
  induction n as [|n IH]; intros m rows lo c Hle.
  - cbn [lic_bounded_clock]. lia.
  - destruct m as [|m]; [lia|].
    cbn [lic_bounded_clock].
    assert (H := IH m rows lo (left_infinite_step rows c) ltac:(lia)).
    lia.
Qed.

Print Assumptions lic_bounded_clock_mono.

(** ** Clock invariance under the left-window choice

    The left-window argument [lo] only changes the passive ptape; no
    clock reads it.  All per-step and cumulative clocks are therefore
    definitionally independent of [lo]. *)

Lemma lic_step_cost_lo_ind :
  forall (rows : list WideSourceRow) (lo lo' : Z)
         (c : LeftInfiniteConfig),
    lic_step_cost rows lo c = lic_step_cost rows lo' c.
Proof.
  intros rows lo lo' c.
  unfold lic_step_cost.
  destruct (wide_source_lookup rows (lic_state c)
    (lic_tape c (lic_head c))) as [r|].
  - destruct (book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
      (source_rows_to_book rows)) as [steps hit after|steps last|].
    + destruct (wr_right r); reflexivity.
    + reflexivity.
    + reflexivity.
  - destruct (book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
      (lic_book_rows rows)) as [steps hit after|steps last|];
      reflexivity.
Qed.

Lemma lic_bounded_clock_lo_ind :
  forall (n : nat) (rows : list WideSourceRow) (lo lo' : Z)
         (c : LeftInfiniteConfig),
    lic_bounded_clock rows n lo c =
    lic_bounded_clock rows n lo' c.
Proof.
  induction n as [|n IH]; intros rows lo lo' c.
  - reflexivity.
  - cbn [lic_bounded_clock].
    rewrite (lic_step_cost_lo_ind rows lo lo' c).
    apply Nat.add_cancel_l. apply IH.
Qed.

Print Assumptions lic_step_cost_lo_ind.
Print Assumptions lic_bounded_clock_lo_ind.

(** ** Per-step positivity for every well-formed configuration *)

Lemma lic_step_cost_pos_wellformed :
  forall (p : nat) (rows : list WideSourceRow) (lo : Z)
         (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    1 <= lic_step_cost rows lo c.
Proof.
  intros p rows lo c Hwf Hne Hlen.
  unfold lic_step_cost.
  destruct (wide_source_lookup rows (lic_state c)
    (lic_tape c (lic_head c))) as [r|] eqn:E.
  - destruct (wide_source_lookup_some_book_first_match_hit p rows
      (lic_state c) (lic_tape c (lic_head c)) r Hwf Hlen E)
      as [steps [hit [after [Hbf _]]]].
    rewrite Hbf. destruct (wr_right r);
      unfold lic_q5_right_hit_cost, lic_q5_left_hit_cost,
        book_steady_locate_q12_clock_gen; lia.
  - destruct (lic_book_rows_first_match_halt p rows
      (lic_state c) (lic_tape c (lic_head c)) Hwf Hlen Hne E)
      as [steps [last Hbf]].
    rewrite Hbf. unfold book_failures_clock, book_halt_clock.
    cbn [length].
    lia.
Qed.

Lemma lic_state_length_step_general :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    length (lic_state c) = p ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state (left_infinite_step rows c)) = p.
Proof.
  intros p rows c Hlen Hwf.
  destruct (lic_halted c) eqn:Eh.
  - unfold left_infinite_step. rewrite Eh. exact Hlen.
  - destruct (wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c))) as [r|] eqn:El.
    + destruct (left_infinite_right_blocked c r) eqn:Eb.
      * destruct (left_infinite_step_blocked_fields rows c r Eh El Eb)
          as [Hs _]. rewrite Hs. exact Hlen.
      * assert (Hin : In r rows).
        { pose proof (find_some
            (fun row => wide_row_matches row (lic_state c)
               (lic_tape c (lic_head c))) rows El) as Hfs.
          exact (proj1 Hfs). }
        assert (Hwf_r : wide_row_wellformed p r).
        { rewrite Forall_forall in Hwf. apply Hwf. exact Hin. }
        destruct (left_infinite_step_running_fields rows c r Eh El Eb)
          as [Hs _]. rewrite Hs. exact (proj2 Hwf_r).
    + destruct (left_infinite_step_lookup_none_fields rows c Eh El)
        as [Hs _]. rewrite Hs. exact Hlen.
Qed.

Lemma lic_bounded_clock_at_least_steps_general :
  forall (n p : nat) (rows : list WideSourceRow) (lo : Z)
         (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    n <= lic_bounded_clock rows n lo c.
Proof.
  induction n as [|n IH]; intros p rows lo c Hwf Hne Hlen.
  - cbn [lic_bounded_clock]. lia.
  - cbn [lic_bounded_clock].
    assert (Hpos := lic_step_cost_pos_wellformed p rows lo c Hwf Hne Hlen).
    assert (Hlen' : length (lic_state (left_infinite_step rows c)) = p)
      by (apply (lic_state_length_step_general p rows c Hlen Hwf)).
    assert (Hrec := IH p rows lo (left_infinite_step rows c) Hwf Hne Hlen').
    lia.
Qed.

Print Assumptions lic_step_cost_pos_wellformed.
Print Assumptions lic_bounded_clock_at_least_steps_general.
