(** * Two-bit marker lifting of the source state

    The empty-buffer q19 boundary retries with the rotated next state

      tl hit_init ++ [hd hit_init].

    Compiling every source state as [false :: true :: s] makes that
    rotated state start with [true], while every lifted row condition
    starts with [false].  The retry therefore always takes the no-match
    halt branch.  This file proves the lift commutes with the source
    step and run. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyBookLocateRows MinskyBookEncode MinskyLeftInfinite
  MinskyLeftInfiniteEncoding.

Local Open Scope nat_scope.

Definition lic_lift_state (s : list bool) : list bool :=
  false :: true :: s.

Definition lic_lift_row (r : WideSourceRow) : WideSourceRow :=
  {| wr_current := lic_lift_state (wr_current r);
     wr_read := wr_read r;
     wr_next := lic_lift_state (wr_next r);
     wr_write := wr_write r;
     wr_right := wr_right r |}.

Definition lic_lift_rows (rows : list WideSourceRow) : list WideSourceRow :=
  map lic_lift_row rows.

Definition lic_lift_cfg (c : LeftInfiniteConfig) : LeftInfiniteConfig :=
  {| lic_state := lic_lift_state (lic_state c);
     lic_head := lic_head c;
     lic_tape := lic_tape c;
     lic_R := lic_R c;
     lic_halted := lic_halted c |}.

Lemma if_list_eq_dec_cons2 :
  forall (l1 l2 : list bool) (X : bool),
    (if list_eq_dec Bool.bool_dec
          (false :: true :: l1) (false :: true :: l2)
     then X else false) =
    (if list_eq_dec Bool.bool_dec l1 l2 then X else false).
Proof.
  intros l1 l2 X.
  destruct (list_eq_dec Bool.bool_dec l1 l2) as [E|E].
  - subst l2.
    destruct (list_eq_dec Bool.bool_dec
      (false :: true :: l1) (false :: true :: l1)) as [E1|E1].
    + reflexivity.
    + exfalso. apply E1. reflexivity.
  - assert (Hneq : false :: true :: l1 <> false :: true :: l2).
    { intro H. apply E. injection H. auto. }
    destruct (list_eq_dec Bool.bool_dec
      (false :: true :: l1) (false :: true :: l2)) as [E1|E1].
    + exfalso. apply Hneq. exact E1.
    + reflexivity.
Qed.

Lemma lic_lift_row_wellformed :
  forall p r,
    wide_row_wellformed p r ->
    wide_row_wellformed (p + 2) (lic_lift_row r).
Proof.
  intros p r [Hc Hn]. unfold wide_row_wellformed. simpl.
  unfold lic_lift_row, lic_lift_state. simpl.
  rewrite Hc, Hn. lia.
Qed.

Lemma lic_lift_rows_wellformed :
  forall p rows,
    Forall (wide_row_wellformed p) rows ->
    Forall (wide_row_wellformed (p + 2)) (lic_lift_rows rows).
Proof.
  intros p rows H. induction H as [|r rest Hr Hrest IH].
  - constructor.
  - unfold lic_lift_rows. simpl. constructor.
    + apply lic_lift_row_wellformed. exact Hr.
    + exact IH.
Qed.

Lemma wide_row_matches_lift :
  forall r state bit,
    wide_row_matches (lic_lift_row r) (lic_lift_state state) bit =
    wide_row_matches r state bit.
Proof.
  intros r state bit.
  unfold wide_row_matches, lic_lift_row, lic_lift_state. cbn.
  apply if_list_eq_dec_cons2.
Qed.

Lemma wide_source_lookup_lift :
  forall rows state bit,
    wide_source_lookup (lic_lift_rows rows) (lic_lift_state state) bit =
    option_map lic_lift_row (wide_source_lookup rows state bit).
Proof.
  induction rows as [|r rest IH]; intros state bit.
  - reflexivity.
  - unfold lic_lift_rows. simpl.
    unfold wide_source_lookup. simpl.
    rewrite wide_row_matches_lift.
    destruct (wide_row_matches r state bit); [reflexivity|].
    apply IH.
Qed.

Lemma lic_lift_cfg_halted :
  forall c, lic_halted (lic_lift_cfg c) = lic_halted c.
Proof. reflexivity. Qed.

Lemma wide_source_lookup_lift_cfg :
  forall rows c,
    wide_source_lookup (lic_lift_rows rows)
      (lic_state (lic_lift_cfg c))
      (lic_tape (lic_lift_cfg c) (lic_head (lic_lift_cfg c))) =
    option_map lic_lift_row
      (wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c))).
Proof.
  intros. cbn [lic_state lic_tape lic_head lic_lift_cfg].
  apply wide_source_lookup_lift.
Qed.

Lemma left_infinite_right_blocked_lift :
  forall c r,
    left_infinite_right_blocked (lic_lift_cfg c) (lic_lift_row r) =
    left_infinite_right_blocked c r.
Proof. reflexivity. Qed.

Lemma left_infinite_step_lift :
  forall rows c,
    lic_lift_cfg (left_infinite_step rows c) =
    left_infinite_step (lic_lift_rows rows) (lic_lift_cfg c).
Proof.
  intros rows c.
  unfold left_infinite_step.
  change (lic_halted (lic_lift_cfg c)) with (lic_halted c) in *.
  destruct (lic_halted c) eqn:Eh.
  - reflexivity.
  - rewrite wide_source_lookup_lift_cfg.
    destruct (wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c))) as [r|] eqn:El.
    + cbn [option_map].
      change (left_infinite_right_blocked (lic_lift_cfg c) (lic_lift_row r))
        with (left_infinite_right_blocked c r).
      destruct (left_infinite_right_blocked c r) eqn:Eb.
      * cbn [lic_state lic_head lic_tape lic_R lic_lift_cfg
             lic_lift_row lic_lift_state]. reflexivity.
      * cbn [lic_state lic_head lic_tape lic_R lic_lift_cfg
             lic_lift_row lic_lift_state wr_next wr_right wr_write].
        destruct (wr_right r); reflexivity.
    + cbn [option_map]. reflexivity.
Qed.

Lemma left_infinite_run_lift :
  forall n rows c,
    lic_lift_cfg (left_infinite_run n rows c) =
    left_infinite_run n (lic_lift_rows rows) (lic_lift_cfg c).
Proof.
  induction n as [|n IH]; intros rows c.
  - reflexivity.
  - cbn [left_infinite_run].
    rewrite <- left_infinite_step_lift.
    apply IH.
Qed.

Lemma left_infinite_halts_lift :
  forall rows c,
    left_infinite_eventually_halts rows c <->
    left_infinite_eventually_halts (lic_lift_rows rows) (lic_lift_cfg c).
Proof.
  intros rows c. split; intros [n H].
  - exists n. rewrite <- left_infinite_run_lift.
    cbn [lic_halted lic_lift_cfg]. exact H.
  - exists n. rewrite <- left_infinite_run_lift in H.
    cbn [lic_halted lic_lift_cfg] in H. exact H.
Qed.

(** The rotated lifted state starts with [true], so no lifted row
    matches it. *)

Lemma wide_row_matches_lifted_rotated :
  forall r state bit,
    wide_row_matches (lic_lift_row r)
      (tl (lic_lift_state state) ++ [hd false (lic_lift_state state)])
      bit = false.
Proof.
  intros r state bit.
  unfold wide_row_matches, lic_lift_row, lic_lift_state. cbn.
  assert (Hneq : false :: true :: wr_current r <>
                true :: state ++ [false]).
  { intro H. discriminate H. }
  destruct (list_eq_dec Bool.bool_dec
    (false :: true :: wr_current r) (true :: state ++ [false]))
    as [E|E]; [exfalso; apply Hneq; exact E|reflexivity].
Qed.

Lemma wide_source_lookup_lifted_rotated :
  forall rows state bit,
    wide_source_lookup (lic_lift_rows rows)
      (tl (lic_lift_state state) ++ [hd false (lic_lift_state state)])
      bit = None.
Proof.
  induction rows as [|r rest IH]; intros state bit.
  - reflexivity.
  - unfold lic_lift_rows. simpl. unfold wide_source_lookup. simpl.
    apply IH.
Qed.

Lemma source_row_to_book_lift_first_bit :
  forall r,
    exists s,
      br_cond (source_row_to_book (lic_lift_row r)) = false :: s.
Proof.
  intros r. unfold source_row_to_book, lic_lift_row, lic_lift_state.
  cbn. eexists. reflexivity.
Qed.

Lemma source_rows_to_book_lift_first_bit :
  forall rows,
    Forall (fun br => exists s, br_cond br = false :: s)
      (source_rows_to_book (lic_lift_rows rows)).
Proof.
  induction rows as [|r rest IH]; simpl.
  - constructor.
  - constructor.
    + apply source_row_to_book_lift_first_bit.
    + exact IH.
Qed.

Lemma lic_sentinel_row_lift_first_bit :
  forall rows,
    exists s,
      br_cond (lic_sentinel_row (lic_lift_rows rows)) = false :: s.
Proof.
  intros rows. destruct rows as [|r0 rest].
  - simpl. exists []. reflexivity.
  - simpl. apply source_row_to_book_lift_first_bit.
Qed.

Lemma lic_book_rows_lift_first_bit :
  forall rows,
    Forall (fun br => exists s, br_cond br = false :: s)
      (lic_book_rows (lic_lift_rows rows)).
Proof.
  intros rows. unfold lic_book_rows.
  apply Forall_app. split.
  - apply source_rows_to_book_lift_first_bit.
  - constructor; [apply lic_sentinel_row_lift_first_bit|constructor].
Qed.

Print Assumptions left_infinite_run_lift.
Print Assumptions wide_source_lookup_lifted_rotated.
