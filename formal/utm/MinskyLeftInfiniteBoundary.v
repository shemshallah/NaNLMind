(** * The empty-buffer right boundary

    When the source head is at [R] and the matching row moves right, the
    native q5 buffer is empty.  The ordinary right cycle

      book_steady_q5_locate_to_q5_right_raw_gen

    requires [buf <> []].  With an empty buffer the q15/q22 perform
    cycle still reaches q19, but the q19 target is the [Y = 5] delimiter
    itself: q19 crosses it, captures the first restored action bit, and
    q17/q18 scan the remaining action rail back to q5.

    The resulting q5 frame is

      cfg_ml 5 (rev between ++ 6 :: 5 :: source_bit hit_w :: rev data)
        (match_mark bit :: 4 :: ...)

    The q5 locate scan then crosses [rev between ++ [6]] until it sees
    the extra [5], turns around at q1, and performs a fresh locate whose
    source condition is the *rotated* next state

      tl hit_init ++ [hd hit_init].

    That locate either hits (handled by the ordinary running encoder) or
    fails; this file builds the failure/halt branch.  The halt frame is
    the usual [dispatch_halt_at_y] frame with the extra q5 marker [6]
    inserted immediately before the [5 :: left] tail.

    Nothing here reuses the sentinel-retry halt: the retry condition
    [hit_init ++ [false]] is a real source condition and can be matched
    by a real row, whereas the wall halt must depend only on the empty
    buffer and the native q3/Y trace. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyMatchMacro MinskySourceEncoding
  MinskyWideSource MinskyConcreteEntry MinskyConcreteDispatch
  MinskyCanonicalRestore MinskyCanonicalMatch MinskyActionMacro MinskyHeadMoveMacro
  MinskyDirectionDecision
  MinskyRelocationMacro MinskyBookLayout MinskyBookCycle MinskyBookLocate
  MinskyBookLocateRows MinskyBookLocateWide MinskyBookLocateCycle
  MinskyBookLocateLookup MinskyBookEncode MinskyBookRawBuffer
  MinskyLeftInfinite MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteHalt
  MinskyLeftInfiniteEncoding.

(** ** q19 crossing Y with an empty buffer *)

Lemma q19_empty_relocation :
  forall (bit : bool) (between left tail : list nat),
    Forall q17_pass between ->
    run (2 + S (length between))
      (entry_config 19 left
        (5 :: source_bit bit :: between ++ 7 :: tail)) =
    cfg_ml 5 (rev between ++ 6 :: 5 :: left)
      ((if bit then 3 else 2) :: tail).
Proof.
  intros bit between left tail Hbetween.
  replace (2 + S (length between)) with (2 + S (length between)) by reflexivity.
  rewrite (dispatch_run_add 2 (S (length between))).
  rewrite (q19_empty_buffer_captures_first_raw left bit
    (between ++ 7 :: tail)).
  destruct bit.
  - apply (q18_scan_to_marker between (6 :: 5 :: left) tail Hbetween).
  - apply (q17_scan_to_marker between (6 :: 5 :: left) tail Hbetween).
Qed.

Print Assumptions q19_empty_relocation.

(** ** q15 -> q5 with an empty buffer *)

Theorem q15_q22_right_to_q5_book_empty :
  forall (tags : list nat) (dir_head : nat) (dir_remaining : list nat)
         (old target : bool) (outer suffix : list nat)
         (bit : bool) (between : list nat),
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass between ->
    rev (dir_head :: dir_remaining) = 5 :: source_bit bit :: between ->
    run ((S (length (rev tags)) +
          S (length (tags ++ [4])) +
          S (length (dir_head :: dir_remaining))) +
         (2 + S (length between)))
      (entry_config 15
        (4 :: source_bit old :: dir_head :: dir_remaining ++
         3 :: outer)
        (rev tags ++ source_bit target :: suffix)) =
    cfg_ml 5
      (rev between ++ 6 :: 5 :: source_bit old :: outer)
      ((if bit then 3 else 2) :: 4 ::
       map q16_restore (rev tags) ++
       source_bit target :: suffix).
Proof.
  intros tags dir_head dir_remaining old target outer suffix bit between
    H15 H16 H21 H17 Hsplit.
  rewrite dispatch_run_add.
  rewrite (q15_q22_right_to_q19_tags tags dir_head dir_remaining old
    target outer suffix H15 H16 H21).
  rewrite Hsplit.
  apply (q19_empty_relocation bit between (source_bit old :: outer)
    (4 :: map q16_restore (rev tags) ++ source_bit target :: suffix)
    H17).
Qed.

Print Assumptions q15_q22_right_to_q5_book_empty.

(** ** q12 -> q5 with an empty buffer *)

Theorem book_q12_restore_to_q5_right_empty :
  forall (s : nat) (remaining data : list nat) (marked : list nat)
         (mark : nat) (record_tail : list nat) (tags : list nat)
         (old : bool) (dir_head : nat) (dir_remaining : list nat)
         (bit target : bool) (between suffix : list nat),
    Forall q12_pass (s :: remaining ++ 5 :: []) ->
    Forall q14_pass ([5] ++ rev remaining ++ [s]) ->
    map q14_restore (rev ([5] ++ rev remaining ++ [s])) =
      source_bit old :: dir_head :: dir_remaining ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    rev (dir_head :: dir_remaining) = 5 :: source_bit bit :: between ->
    Forall q17_pass between ->
    marked ++ mark :: record_tail = rev tags ++ source_bit target :: suffix ->
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    run ((S (length (s :: remaining ++ 5 :: [])) +
          S (length ([5] ++ rev remaining ++ [s]))) +
         ((S (length (rev tags)) +
           S (length (tags ++ [4])) +
           S (length (dir_head :: dir_remaining))) +
          (2 + S (length between))))
      (cfg_ml 12
        (s :: remaining ++ 5 :: 6 :: rev data)
        (4 :: marked ++ mark :: record_tail)) =
    cfg_ml 5
      (rev between ++ 6 :: 5 :: source_bit old :: rev data)
      ((if bit then 3 else 2) :: 4 ::
       map q16_restore (rev tags) ++
       source_bit target :: suffix).
Proof.
  intros s remaining data marked mark record_tail tags old
    dir_head dir_remaining bit target between suffix
    H12 H14 Hrestored H21 Hsplit H17 Hright H15 H16.
  rewrite dispatch_run_add.
  assert (Hq12 :
    run (S (length (s :: remaining ++ [5])) +
         S (length ([5] ++ rev remaining ++ [s])))
      (cfg_ml 12 (s :: remaining ++ 5 :: 6 :: rev data)
        (4 :: marked ++ mark :: record_tail)) =
    entry_config 15
      (4 :: source_bit old :: dir_head :: dir_remaining ++ 3 :: rev data)
      (marked ++ mark :: record_tail)).
  { replace (s :: remaining ++ 5 :: 6 :: rev data)
      with (s :: remaining ++ 5 :: rev [] ++ 6 :: rev data)
      by reflexivity.
    replace ([5] ++ rev remaining ++ [s])
      with ([] ++ [5] ++ rev remaining ++ [s]) by reflexivity.
    replace (s :: remaining ++ [5])
      with (s :: remaining ++ 5 :: rev []) by reflexivity.
    rewrite (canonical_q12_restore_to_q15_mark s remaining [] data
      marked mark record_tail H12 H14).
    cbn [app].
    assert (Hrestored' :
      map q14_restore (rev (5 :: rev remaining ++ [s])) =
      source_bit old :: dir_head :: dir_remaining).
    { change (map q14_restore (rev ([5] ++ rev remaining ++ [s])) =
              source_bit old :: dir_head :: dir_remaining).
      exact Hrestored. }
    rewrite Hrestored'. reflexivity. }
  rewrite Hq12.
  rewrite Hright.
  apply (q15_q22_right_to_q5_book_empty tags dir_head dir_remaining
    old target (rev data) suffix bit between H15 H16 H21 H17 Hsplit).
Qed.

Print Assumptions book_q12_restore_to_q5_right_empty.

(** ** The boundary halt frame

    The halt frame is the ordinary locate-halt frame with an extra list
    [extra] inserted between the failure rail and the [5 :: left] tail.
    For the empty-buffer q19 path [extra = [6]]: the q5 marker captured
    by q1 sits immediately before the crossed Y delimiter. *)

Definition boundary_halt_encode_from
    (extra : list nat) (steps : list book_failure) (last : book_failure)
    (left tail : list nat) : Config :=
  dispatch_halt_at_y
    (rev (map source_bit (bf_row_rest last) ++
          map source_bit (br_action (bf_row last)) ++
          [source_bit (br_dir (bf_row last))]) ++
     match_mark (negb (bf_bit last)) ::
     rev (map match_mark (bf_src_rest last) ++
          ((book_marked_prefix (map bf_row steps)) ++ [4]) ++
          map match_mark (bf_good last)) ++
     match_raw (bf_bit last) :: rev (map match_raw (bf_good last)) ++
     extra ++ 5 :: left)
    tail.

Lemma boundary_halt_encode_from_halted :
  forall extra steps last left tail,
    c_halted (boundary_halt_encode_from extra steps last left tail) = true.
Proof.
  intros. unfold boundary_halt_encode_from, dispatch_halt_at_y.
  reflexivity.
Qed.

(** With [extra = []], this is exactly the ordinary halted encoder. *)

Lemma boundary_halt_encode_from_nil :
  forall steps last ptape tail,
    boundary_halt_encode_from [] steps last (6 :: rev ptape) tail =
    lic_halt_encode_from steps last [] ptape tail.
Proof.
  intros. unfold boundary_halt_encode_from, lic_halt_encode_from.
  cbn [app]. reflexivity.
Qed.

(** ** Exact concrete boundary trace

    The task's p=1 example: source state [[]], empty buffer, two copies
    of a row with condition [false;false], action [true;false], and a
    right move.  The native table halts after 129 steps at the frame
    below.  This is a kernel [vm_compute] check, not a table axiom. *)

Definition boundary_test_row : book_row :=
  {| br_cond := [false; false];
     br_action := [true; false];
     br_dir := true |}.

Definition boundary_test_start : Config :=
  book_q5_raw [false] [] false [] false
    [boundary_test_row; boundary_test_row] [].

Definition boundary_test_halt : Config :=
  {| c_state := 0;
     c_tape := {|
       t_left := [1; 0; 1; 0; 2; 4; 3; 2; 3; 2; 2; 4; 1; 6; 5; 0; 0];
       t_right := [5]
     |};
     c_halted := true |}.

Theorem boundary_test_run_129 :
  run 129 boundary_test_start = boundary_test_halt.
Proof.
  vm_compute. reflexivity.
Qed.

Print Assumptions boundary_test_run_129.

(** The frame is a [dispatch_halt_at_y] frame. *)

Lemma boundary_test_halt_is_dispatch :
  boundary_test_halt =
  dispatch_halt_at_y
    [1; 0; 1; 0; 2; 4; 3; 2; 3; 2; 2; 4; 1; 6; 5; 0; 0] [].
Proof. reflexivity. Qed.

(** The halt frame is *not* the sentinel-retry frame: the q3/Y halt is
    reached at the wall, and the retry condition [wr_next hit ++ [false]]
    is irrelevant to this trace. *)

(** ** q1 mismatch halt with an arbitrary left prefix

    The ordinary [book_q1_mismatch_halt_gen] fixes the left prefix to
    [5 :: prefix].  The empty-buffer boundary reaches q1 with the extra
    q5 marker [6] in front of that [5].  The q1/q4/q3 scans never read
    the left prefix, so the same proof goes through with an arbitrary
    [fixed_left]. *)

Lemma book_q1_mismatch_halt_gen_extra :
  forall (b : bool) (good restbits row1_rest action1 : list bool)
         (dir1 : bool) (done : list nat) (fixed_left tail : list nat),
    Forall wide_mark done ->
    run (book_mismatch_halt_clock b good restbits row1_rest action1
           dir1 done)
      (entry_config 1 fixed_left
        (map match_raw good ++ match_mark b ::
         map match_mark restbits ++ done ++ map match_mark good ++
         match_raw (negb b) :: map source_bit row1_rest ++
         map source_bit action1 ++ [source_bit dir1] ++ 5 :: tail)) =
    dispatch_halt_at_y
      (rev (map source_bit row1_rest ++ map source_bit action1 ++
            [source_bit dir1]) ++
       match_mark (negb b) ::
       rev (map match_mark restbits ++ done ++ map match_mark good) ++
       match_raw b :: rev (map match_raw good) ++ fixed_left) tail.
Proof.
  intros b good restbits row1_rest action1 dir1 done fixed_left tail
    Hdone.
  set (row_rest :=
    map source_bit row1_rest ++ map source_bit action1 ++
    [source_bit dir1]).
  set (marked := map match_mark restbits ++ done ++ map match_mark good).
  assert (Hwide : Forall wide_mark marked).
  { subst marked. repeat rewrite Forall_app. repeat split.
    - apply wide_mark_map_match_marks.
    - exact Hdone.
    - apply wide_mark_map_match_marks. }
  assert (Hq0 : Forall q0_pass marked).
  { exact (proj1 (wide_mark_scans _ Hwide)). }
  assert (Hq4 : Forall q4_pass marked).
  { exact (proj1 (proj2 (wide_mark_scans _ Hwide))). }
  assert (Hright : Forall dispatch_right_symbol row_rest).
  { subst row_rest.
    repeat rewrite Forall_app. repeat split.
    - apply source_bit_list_is_right_scannable.
    - apply source_bit_list_is_right_scannable.
    - constructor; [apply source_bit_is_right_symbol | constructor]. }
  assert (Hclock :
    book_mismatch_halt_clock b good restbits row1_rest action1 dir1 done =
    S (length (map match_raw good)) +
    (S (length marked) + (length row_rest + 1))).
  { unfold book_mismatch_halt_clock.
    fold marked. fold row_rest. reflexivity. }
  rewrite Hclock.
  destruct b.
  + (* b = true *)
    cbn [negb].
    assert (Hentry :
      (map match_raw good ++ match_mark true ::
       map match_mark restbits ++ done ++ map match_mark good ++
       match_raw false :: map source_bit row1_rest ++
       map source_bit action1 ++ [source_bit dir1] ++ 5 :: tail)
      = (map match_raw good ++ 3 :: marked ++
         0 :: row_rest ++ 5 :: tail)).
    { cbn [match_mark match_raw]. unfold marked, row_rest.
      repeat rewrite <- app_assoc. cbn [app].
      repeat rewrite <- app_assoc. cbn [app].
      reflexivity. }
    rewrite Hentry.
    rewrite (dispatch_run_add (S (length (map match_raw good)))
      (S (length marked) + (length row_rest + 1))
      (entry_config 1 fixed_left
        (map match_raw good ++ 3 :: marked ++ 0 :: row_rest ++
         5 :: tail))).
    rewrite (q1_scan_pick (map match_raw good) fixed_left 3
      (marked ++ 0 :: row_rest ++ 5 :: tail)
      (match_raw_valid good) (or_intror (or_introl eq_refl))).
    rewrite (dispatch_run_add (S (length marked)) (length row_rest + 1)
      (entry_config 4 (1 :: rev (map match_raw good) ++ fixed_left)
        (marked ++ 0 :: row_rest ++ 5 :: tail))).
    rewrite (q4_scan_zero marked
      (1 :: rev (map match_raw good) ++ fixed_left)
      (row_rest ++ 5 :: tail) Hq4).
    rewrite (dispatch_right_halts_at_delimiter row_rest
      (2 :: rev marked ++ 1 :: rev (map match_raw good) ++ fixed_left)
      tail Hright).
    reflexivity.
  + (* b = false *)
    cbn [negb].
    assert (Hentry :
      (map match_raw good ++ match_mark false ::
       map match_mark restbits ++ done ++ map match_mark good ++
       match_raw true :: map source_bit row1_rest ++
       map source_bit action1 ++ [source_bit dir1] ++ 5 :: tail)
      = (map match_raw good ++ 2 :: marked ++
         1 :: row_rest ++ 5 :: tail)).
    { cbn [match_mark match_raw]. unfold marked, row_rest.
      repeat rewrite <- app_assoc. cbn [app].
      repeat rewrite <- app_assoc. cbn [app].
      reflexivity. }
    rewrite Hentry.
    rewrite (dispatch_run_add (S (length (map match_raw good)))
      (S (length marked) + (length row_rest + 1))
      (entry_config 1 fixed_left
        (map match_raw good ++ 2 :: marked ++ 1 :: row_rest ++
         5 :: tail))).
    rewrite (q1_scan_pick (map match_raw good) fixed_left 2
      (marked ++ 1 :: row_rest ++ 5 :: tail)
      (match_raw_valid good) (or_introl eq_refl)).
    rewrite (dispatch_run_add (S (length marked)) (length row_rest + 1)
      (entry_config 0 (0 :: rev (map match_raw good) ++ fixed_left)
        (marked ++ 1 :: row_rest ++ 5 :: tail))).
    rewrite (q0_scan_one marked
      (0 :: rev (map match_raw good) ++ fixed_left)
      (row_rest ++ 5 :: tail) Hq0).
    rewrite (dispatch_right_halts_at_delimiter row_rest
      (3 :: rev marked ++ 0 :: rev (map match_raw good) ++ fixed_left)
      tail Hright).
    reflexivity.
Qed.

Print Assumptions book_q1_mismatch_halt_gen_extra.

(** ** q5 scan of the empty-buffer boundary frame

    The q5 frame produced by [book_q12_restore_to_q5_right_empty] is

      cfg_ml 5 (rev between ++ 6 :: 5 :: source_bit hit_w :: rev data)
        (match_mark (hd hit_init) :: 4 :: ...)

    q5 scans [rev between ++ [6]] leftwards to the extra [5], turns
    around at q1, and leaves the leading [6] marker on the right.  The
    source condition of the following locate is the rotated next state
    [tl hit_init ++ [hd hit_init]]. *)

Lemma map_match_mark_source :
  forall (bits : list bool),
    map match_mark bits = map entry_rewrite (map source_bit bits).
Proof.
  intros bits. rewrite map_map.
  apply map_ext. intro b. symmetry. apply entry_rewrite_source_bit.
Qed.

Lemma q5_scan_empty_boundary :
  forall (h0 : bool) (t0 : list bool) (hit_w : bool)
         (data tags suffix : list nat) (target : bool),
    run (S (length (map source_bit t0) + 1))
      (cfg_ml 5
        (rev (map source_bit t0) ++ 6 :: 5 ::
         source_bit hit_w :: rev data)
        (match_mark h0 :: 4 ::
         map q16_restore (rev tags) ++ source_bit target :: suffix)) =
    entry_config 1 (5 :: source_bit hit_w :: rev data)
      (6 :: map match_mark (t0 ++ [h0]) ++
       4 :: map q16_restore (rev tags) ++ source_bit target :: suffix).
Proof.
  intros h0 t0 hit_w data tags suffix target.
  set (between := map source_bit t0).
  set (prefix := source_bit hit_w :: rev data).
  set (suffix' := match_mark h0 :: 4 ::
    map q16_restore (rev tags) ++ source_bit target :: suffix).
  assert (Hq5 : Forall q5_pass (rev between ++ [6])).
  { apply Forall_app. split.
    - apply Forall_rev, q5_pass_source_bits.
    - constructor; [unfold q5_pass; auto 10 | constructor]. }
  destruct (rev between) as [|x xs] eqn:Hrev.
  - assert (Hbetween : between = []).
    { apply (f_equal (@rev nat)) in Hrev.
      rewrite rev_involutive in Hrev. exact Hrev. }
    assert (Ht0 : t0 = []).
    { apply (@map_eq_nil bool nat source_bit t0).
      unfold between in Hbetween. exact Hbetween. }
    subst t0. rewrite Hbetween. cbn [map app].
    unfold cfg_ml. cbn [app].
    change (run (S (length [6]))
      (entry_config 5 ([] ++ 5 :: prefix) (6 :: suffix')) =
      entry_config 1 (5 :: prefix)
        (6 :: match_mark h0 ::
         4 :: map q16_restore (rev tags) ++
         source_bit target :: suffix)).
    rewrite (q5_scan_unbounded [] 6 prefix suffix' Hq5).
    cbn [rev map entry_rewrite]. reflexivity.
  - assert (Hbetween : between = rev (x :: xs)).
    { apply (f_equal (@rev nat)) in Hrev.
      rewrite rev_involutive in Hrev. exact Hrev. }
    rewrite Hbetween. cbn [rev map].
    unfold cfg_ml. cbn [app].
    replace (S (length (rev xs ++ [x]) + 1))
      with (S (length (x :: xs ++ [6]))).
    2:{ rewrite app_length, rev_length. cbn [length].
        rewrite app_length. cbn [length]. lia. }
    replace (xs ++ 6 :: 5 :: prefix)
      with ((xs ++ [6]) ++ 5 :: prefix).
    2:{ repeat rewrite <- app_assoc. reflexivity. }
    rewrite (q5_scan_unbounded (xs ++ [6]) x prefix suffix' Hq5).
    cbn [rev map app].
    rewrite map_app. cbn [map].
    replace (map entry_rewrite (rev (xs ++ [6])) ++ [entry_rewrite x])
      with (6 :: map entry_rewrite (rev (x :: xs))).
    2:{ rewrite rev_app_distr. cbn [rev].
        rewrite map_app. cbn [map].
        rewrite <- app_assoc. cbn [app]. reflexivity. }
    rewrite <- Hbetween.
    rewrite map_app. cbn [map].
    rewrite map_match_mark_source.
    repeat rewrite <- app_assoc. cbn [app].
    reflexivity.
Qed.

Print Assumptions q5_scan_empty_boundary.
