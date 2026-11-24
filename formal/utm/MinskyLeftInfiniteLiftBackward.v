(** * Reverse direction for the lifted left-depth encoding

    If the native run halts within the macro clock for [n] source steps,
    then the lifted source halts within [n].  The first-stop scan either
    finds the source halt, or the run is entirely hit/left/right up to
    [n]; in the latter case the no-premature-halt theorem contradicts
    the native halt. *)

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
  MinskyLeftInfiniteBoundary MinskyLeftInfiniteBoundaryLocate
  MinskyLeftInfiniteBoundaryBook MinskyLeftInfiniteBoundaryFinal
  MinskyLeftInfiniteBoundaryLookup MinskyLeftInfiniteBoundaryLifted
  MinskyLeftInfiniteLift MinskyLeftInfiniteBounded
  MinskyLeftInfiniteLeftDepth MinskyLeftInfiniteLiftForward.

Local Open Scope nat_scope.

Theorem lic_lifted_native_halt_to_source :
  forall (n p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (t : nat),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    lic_left_ok lo n c ->
    lic_halted c = false ->
    t <= lic_bounded_clock (lic_lift_rows rows) n lo
           (lic_lift_cfg c) ->
    c_halted (run t
      (lic_q5_encode lo (lic_lift_cfg c)
        (lic_book_rows (lic_lift_rows rows)) [])) = true ->
    exists k, k <= n /\ lic_halted
      (left_infinite_run k (lic_lift_rows rows) (lic_lift_cfg c)) = true.
Proof.
  intros n p lo c rows t Hwf Hne Hlen Hleft Hh Ht Hhalt.
  set (rl := lic_lift_rows rows).
  set (cl := lic_lift_cfg c).
  assert (Hwf' : Forall (wide_row_wellformed (p + 2)) rl).
  { subst rl. apply lic_lift_rows_wellformed. exact Hwf. }
  assert (Hne' : rl <> []).
  { subst rl. destruct rows as [|r rest]; [contradiction|].
    simpl. discriminate. }
  assert (Hlen' : length (lic_state cl) = p + 2).
  { subst cl. rewrite lic_lift_cfg_state_length. lia. }
  assert (Hleft' : lic_left_ok lo n cl).
  { subst cl. apply (proj2 (lic_left_ok_lift lo n c)). exact Hleft. }
  destruct (lic_first_stop rl n cl) as [[j c']|] eqn:E.
  - assert (Hle : j <= n)
      by (apply (lic_first_stop_bound rl n cl j c' E)).
    destruct (lic_first_stop_sound rl n cl j c' E) as [Hrun Hhalted].
    subst c'. exists j. split; [exact Hle|exact Hhalted].
  - destruct (lic_halted (left_infinite_run n rl cl)) eqn:Hn.
    + exists n. split; [lia|exact Hn].
    + exfalso.
      eapply (lic_left_no_premature_halt n (p + 2) lo cl rl Hwf' Hne'
        Hlen' Hleft' (lic_first_stop_none rl n cl E)).
      * (* per-step wall condition *)
        intros k Hk r Hlk Hright.
        destruct (lic_first_stop_none rl n cl E k Hk) as [Hhalted_k _].
        destruct Hleft' as [_ Hok].
        destruct (left_infinite_run_ok k rl cl Hok) as [HleR _].
        rewrite (lic_R_run k rl cl) in HleR.
        destruct (Z.lt_ge_cases (lic_head (left_infinite_run k rl cl))
          (lic_R cl)) as [Hlt|Hge]; [exact Hlt|].
        assert (Heq : lic_head (left_infinite_run k rl cl) = lic_R cl).
        { apply Z.le_antisymm; [exact HleR|exact Hge]. }
        rewrite <- (lic_R_run k rl cl) in Heq.
        assert (Hstep : lic_halted
          (left_infinite_step rl (left_infinite_run k rl cl)) = true).
        { apply (left_infinite_step_right_blocked_halts rl
            (left_infinite_run k rl cl) r Hhalted_k Hlk Hright Heq). }
        destruct (proj1 (Nat.lt_eq_cases (S k) n) ltac:(lia))
          as [Hlt1|Heq1].
        -- assert (Hk1 : lic_hit_state rl
              (left_infinite_run (S k) rl cl))
             by (apply (lic_first_stop_none rl n cl E (S k) Hlt1)).
           destruct Hk1 as [Hnf _].
           rewrite left_infinite_run_succ in Hnf.
           rewrite Hstep in Hnf. discriminate Hnf.
        -- rewrite <- Heq1 in Hn.
           rewrite left_infinite_run_succ in Hn.
           rewrite Hstep in Hn. discriminate Hn.
      * exact Ht.
      * exact Hhalt.
Qed.

Print Assumptions lic_lifted_native_halt_to_source.
