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
  MinskyConcreteDispatch MinskyBookLayout MinskyBookLocate MinskyBookLocateRows
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
