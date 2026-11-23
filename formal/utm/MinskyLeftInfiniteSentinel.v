(** * Sentinel boundary for the left-infinite source model

    Instead of proving the literal q3/Y trace for a right move at
    [head = R], always encode one extra sentinel blank cell beyond [R].
    The boundary step writes at [R], moves to [R+1], sets
    [lic_R := R+1], leaves the new head cell blank, and halts.

    On the native side the sentinel cell is the single q6 buffer cell
    [buf = [0]], so the ordinary right perform consumes it and leaves the
    q5 buffer empty.  The description is the source program followed by
    the sentinel row [book_sentinel_row (hit_init ++ [false]) creast].
    The existing kernel-checked theorem

      book_steady_q5_locate_perform_right_sentinel_halt_gen

    with [b = 2] is exactly this boundary macro: one sentinel blank is
    consumed, the new condition is [hit_init ++ [false]], the locate
    phase retries and fails on the sentinel row, and the machine reaches
    [dispatch_halt_at_y].  No q3/Y trace is needed.

    This file proves:
    - the sentinel step and its invariant/field lemmas;
    - the sentinel-augmented global invariant
      [buf = raw_buf c ++ [0]];
    - the boundary macro step as a direct corollary of the existing
      sentinel theorem;
    - halt reflection for an encoder whose halted branch is the sentinel
      halt frame;
    - a concrete p=1 sanity instance.

    The remaining gap is only the *running-case* encoder connection:
    a total encoder must put the actual source program plus the sentinel
    row in the description and provide the [retry_steps]/[hit] witnesses
    for each condition.  The boundary run equation itself is complete. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyConcreteEntry MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalInstruction MinskyDirectionDecision MinskyRelocationMacro MinskyHeadMoveMacro
  MinskyBookLayout MinskyBookCycle MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyBookLocateCycle MinskyBookRawBuffer
  MinskyLeftInfinite.

(** ** Blanking the sentinel cell *)

Definition source_blank_at (t : Z -> bool) (h : Z) : Z -> bool :=
  fun z => if Z.eqb z h then false else t z.

Lemma source_blank_at_same :
  forall t h, source_blank_at t h h = false.
Proof.
  intros. unfold source_blank_at. rewrite Z.eqb_refl. reflexivity.
Qed.

Lemma source_blank_at_above :
  forall t h z,
    (h < z)%Z -> source_blank_at t h z = t z.
Proof.
  intros t h z Hlt.
  unfold source_blank_at.
  destruct (Z.eqb z h) eqn:He.
  - apply Z.eqb_eq in He. lia.
  - reflexivity.
Qed.

(** ** The sentinel boundary step *)

Definition left_infinite_step_sentinel
    (rows : list WideSourceRow) (c : LeftInfiniteConfig)
    : LeftInfiniteConfig :=
  if lic_halted c then c else
    match wide_source_lookup rows (lic_state c)
                            (lic_tape c (lic_head c)) with
    | None =>
        {| lic_state := lic_state c;
           lic_head := lic_head c;
           lic_tape := lic_tape c;
           lic_R := lic_R c;
           lic_halted := true |}
    | Some row =>
        if left_infinite_right_blocked c row then
          {| lic_state := wr_next row;
             lic_head := (lic_head c + 1)%Z;
             lic_tape := source_blank_at
               (source_write_at (lic_tape c) (lic_head c)
                                  (wr_write row))
               (lic_head c + 1)%Z;
             lic_R := (lic_R c + 1)%Z;
             lic_halted := true |}
        else
          {| lic_state := wr_next row;
             lic_head := (lic_head c +
                          (if wr_right row then 1 else -1))%Z;
             lic_tape := source_write_at (lic_tape c) (lic_head c)
                                          (wr_write row);
             lic_R := lic_R c;
             lic_halted := false |}
    end.

Lemma left_infinite_step_sentinel_halted :
  forall rows c,
    lic_halted c = true ->
    left_infinite_step_sentinel rows c = c.
Proof.
  intros rows c H. unfold left_infinite_step_sentinel. now rewrite H.
Qed.

Lemma left_infinite_step_sentinel_boundary_fields :
  forall rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_state (left_infinite_step_sentinel rows c) = wr_next row /\
    lic_head (left_infinite_step_sentinel rows c) = (lic_head c + 1)%Z /\
    lic_tape (left_infinite_step_sentinel rows c) =
      source_blank_at
        (source_write_at (lic_tape c) (lic_head c) (wr_write row))
        (lic_head c + 1)%Z /\
    lic_R (left_infinite_step_sentinel rows c) = (lic_R c + 1)%Z /\
    lic_halted (left_infinite_step_sentinel rows c) = true.
Proof.
  intros rows c row Hh Hlookup Hb.
  unfold left_infinite_step_sentinel.
  rewrite Hh, Hlookup, Hb.
  repeat split; reflexivity.
Qed.

Lemma left_infinite_step_sentinel_boundary_blank :
  forall rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_tape (left_infinite_step_sentinel rows c) (lic_head c + 1)%Z = false.
Proof.
  intros rows c row Hh Hlookup Hb.
  destruct (left_infinite_step_sentinel_boundary_fields rows c row
    Hh Hlookup Hb) as [_ [_ [Htape _]]].
  rewrite Htape.
  apply source_blank_at_same.
Qed.

Lemma left_infinite_step_sentinel_boundary_head_eq_R :
  forall rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_head (left_infinite_step_sentinel rows c) =
    lic_R (left_infinite_step_sentinel rows c).
Proof.
  intros rows c row Hh Hlookup Hb.
  destruct (left_infinite_step_sentinel_boundary_fields rows c row
    Hh Hlookup Hb) as [_ [Hhead [_ [HR _]]]].
  unfold left_infinite_right_blocked in Hb.
  apply Bool.andb_true_iff in Hb.
  destruct Hb as [_ Heq].
  apply Z.eqb_eq in Heq.
  rewrite Hhead, HR. lia.
Qed.

Lemma left_infinite_step_sentinel_ok :
  forall rows c,
    left_infinite_ok c ->
    left_infinite_ok (left_infinite_step_sentinel rows c).
Proof.
  intros rows c [Hle Hblank].
  unfold left_infinite_step_sentinel.
  destruct (lic_halted c) eqn:Eh.
  - exact (conj Hle Hblank).
  - destruct (wide_source_lookup rows (lic_state c)
                (lic_tape c (lic_head c))) as [row|] eqn:El.
    + destruct (left_infinite_right_blocked c row) eqn:Eb.
      * simpl. split.
        -- unfold left_infinite_right_blocked in Eb.
           apply Bool.andb_true_iff in Eb.
           destruct Eb as [_ Heq].
           apply Z.eqb_eq in Heq.
           change ((lic_head c + 1 <= lic_R c + 1)%Z). lia.
        -- intros z Hz.
           change ((lic_R c + 1 < z)%Z) in Hz.
           change (source_blank_at
             (source_write_at (lic_tape c) (lic_head c) (wr_write row))
             (lic_head c + 1) z = false).
           rewrite source_blank_at_above by lia.
           rewrite source_write_at_above by lia.
           apply Hblank. lia.
      * simpl. split.
        -- unfold left_infinite_right_blocked in Eb.
           apply Bool.andb_false_iff in Eb.
           destruct Eb as [Hr | He].
           ++ rewrite Hr. simpl. lia.
           ++ apply Z.eqb_neq in He.
              destruct (wr_right row).
              ** simpl. lia.
              ** simpl. lia.
        -- intros z Hz.
           change ((lic_R c < z)%Z) in Hz.
           change (source_write_at (lic_tape c) (lic_head c)
                     (wr_write row) z = false).
           rewrite source_write_at_above by lia.
           apply Hblank. lia.
    + exact (conj Hle Hblank).
Qed.

(** ** Sentinel-augmented global invariant *)

Definition raw_buf_sentinel (c : LeftInfiniteConfig) : list nat :=
  raw_buf c ++ [0].

Definition book_global_source_rep_sentinel
    (c : LeftInfiniteConfig) (lo : Z) (ptape buf : list nat) : Prop :=
  (lo <= lic_head c)%Z /\
  left_infinite_ok c /\
  ptape = raw_ptape c lo /\
  buf = raw_buf_sentinel c.

Lemma raw_buf_sentinel_length :
  forall c,
    left_infinite_ok c ->
    length (raw_buf_sentinel c) =
    S (Z.to_nat (lic_R c - lic_head c)).
Proof.
  intros c Hok. unfold raw_buf_sentinel.
  rewrite app_length. cbn [length].
  rewrite raw_buf_length by apply Hok.
  lia.
Qed.

Lemma raw_buf_sentinel_at_boundary :
  forall c,
    lic_head c = lic_R c ->
    raw_buf_sentinel c = [0].
Proof.
  intros c H. unfold raw_buf_sentinel.
  rewrite raw_buf_nil_of_boundary by exact H.
  reflexivity.
Qed.

Lemma raw_buf_sentinel_nil_iff :
  forall c,
    left_infinite_ok c ->
    (raw_buf_sentinel c = [0] <-> lic_head c = lic_R c).
Proof.
  intros c Hok. split.
  - intro H.
    unfold raw_buf_sentinel in H.
    assert (Hlen := f_equal (@length nat) H).
    rewrite app_length in Hlen. cbn [length] in Hlen.
    assert (Hlen0 : length (raw_buf c) = 0) by lia.
    apply (proj1 (raw_buf_nil_iff c Hok)).
    destruct (raw_buf c) as [|b rest] eqn:Hb.
    + reflexivity.
    + cbn [length] in Hlen0. discriminate Hlen0.
  - apply raw_buf_sentinel_at_boundary.
Qed.

Lemma book_global_source_rep_sentinel_buffer_length :
  forall c lo ptape buf,
    book_global_source_rep_sentinel c lo ptape buf ->
    length buf = S (Z.to_nat (lic_R c - lic_head c)).
Proof.
  intros c lo ptape buf [_ [Hok [Hp Hb]]].
  subst buf. apply raw_buf_sentinel_length. exact Hok.
Qed.

Lemma book_global_source_rep_sentinel_boundary :
  forall c lo ptape buf,
    book_global_source_rep_sentinel c lo ptape buf ->
    (buf = [0] <-> lic_head c = lic_R c).
Proof.
  intros c lo ptape buf [_ [Hok [Hp Hb]]].
  subst buf. apply raw_buf_sentinel_nil_iff. exact Hok.
Qed.

(** ** The boundary macro step

    The sentinel theorem with [b = 2] has q5 input buffer
    [tl (book_buf 2) = [0]], one sentinel blank.  Its output is the
    exact halt frame. *)

Definition boundary_sentinel_sf
    (hit_init : list bool) (creast : list bool) : book_failure :=
  book_sentinel_failure (hit_init ++ [false]) creast
    (app_singleton_bool_neq_nil hit_init false).

Definition boundary_sentinel_pre_frame
    (init : list bool) (w_read w_tape : bool) (ptape tail : list nat)
    (steps : list book_failure) (hit : book_row)
    (hit_init : list bool) (creast : list bool) : Config :=
  cfg_ml 5
    (rev (tl (book_buf 2) ++ [5] ++ map source_bit init) ++
     6 :: source_bit w_tape :: rev ptape)
    (match_mark w_read :: 4 ::
     book_raw_desc
       (map bf_row steps ++ hit ::
        [book_sentinel_row (hit_init ++ [false]) creast]) ++
     5 :: tail).

Definition boundary_sentinel_halt_frame
    (ptape : list nat) (w_tape : bool) (hit_w : bool)
    (tail : list nat) (retry_steps : list book_failure)
    (hit_init : list bool) (creast : list bool) : Config :=
  dispatch_halt_at_y
    (book_sentinel_halt_left retry_steps
       (boundary_sentinel_sf hit_init creast)
       0 (ptape ++ [source_bit w_tape] ++ [source_bit hit_w]) tail) tail.

Definition boundary_right_sentinel_cost
    (init : list bool) (w_read w_tape : bool)
    (steps : list book_failure) (hit : book_row)
    (hit_init : list bool) (hit_w : bool)
    (retry_steps : list book_failure)
    (creast : list bool) : nat :=
  book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
  book_q12_perform_right_clock hit_init hit_w 2
    (book_cycle_tags steps (init ++ [w_read]) hit)
    (tl (book_buf (2 - 1)) ++ [5] ++ map source_bit hit_init) +
  (S (length hit_init) +
   (book_failures_clock [] retry_steps +
    book_halt_clock (map bf_row retry_steps)
      (boundary_sentinel_sf hit_init creast))).

Lemma Forall_q21_book_return_rail_one :
  forall init, Forall q21_pass (book_return_rail init 1).
Proof.
  intros init. unfold book_return_rail, book_buf.
  cbn [rev repeat app].
  apply Forall_app. split.
  - apply Forall_rev, Forall_source_bits_q21.
  - cbn [app]. constructor.
    + unfold q21_pass; auto 10.
    + constructor.
      * unfold q21_pass; auto 10.
      * constructor.
Qed.

Lemma Forall_q17_boundary_between :
  forall init,
    Forall q17_pass
      (tl (book_buf (2 - 1)) ++ [5] ++ map source_bit init).
Proof.
  intros init. cbn [book_buf tl app].
  constructor.
  - unfold q17_pass; auto 10.
  - apply Forall_source_bits_q17.
Qed.

Theorem boundary_right_sentinel_macro_step :
  forall (init : list bool) (w_read w_tape : bool) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (hit_init : list bool) (hit_w : bool) (creast : list bool)
         (retry_steps : list book_failure),
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    Forall (fun st => bf_src st = hit_init ++ [false]) retry_steps ->
    map bf_row
      (retry_steps ++ [boundary_sentinel_sf hit_init creast]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [false]) creast] ->
    run (boundary_right_sentinel_cost init w_read w_tape steps hit
           hit_init hit_w retry_steps creast)
      (boundary_sentinel_pre_frame init w_read w_tape ptape tail
        steps hit hit_init creast) =
    boundary_sentinel_halt_frame ptape w_tape hit_w tail retry_steps
      hit_init creast.
Proof.
  intros init w_read w_tape ptape tail steps hit hit_init hit_w creast
    retry_steps Hsteps Hcond Hlen Hact Hdir Hretry Hrows.
  unfold boundary_right_sentinel_cost, boundary_sentinel_pre_frame,
    boundary_sentinel_halt_frame, boundary_sentinel_sf.
  apply (book_steady_q5_locate_perform_right_sentinel_halt_gen
    init w_read w_tape 2 ptape tail steps hit hit_init hit_w creast
    retry_steps).
  - lia.
  - exact Hsteps.
  - exact Hcond.
  - exact Hlen.
  - exact Hact.
  - exact Hdir.
  - apply Forall_q21_book_return_rail_one.
  - apply Forall_q17_boundary_between.
  - exact Hretry.
  - exact Hrows.
Qed.

Print Assumptions boundary_right_sentinel_macro_step.

(** ** Halt reflection for a sentinel encoder *)

Definition encode_sentinel
    (pre halt : LeftInfiniteConfig -> Config)
    (c : LeftInfiniteConfig) : Config :=
  if lic_halted c then halt c else pre c.

Lemma encode_sentinel_reflects_halt :
  forall pre halt c,
    (forall c, lic_halted c = false -> c_halted (pre c) = false) ->
    (forall c, c_halted (halt c) = true) ->
    c_halted (encode_sentinel pre halt c) = lic_halted c.
Proof.
  intros pre halt c Hpre Hhalt.
  unfold encode_sentinel.
  destruct (lic_halted c) eqn:H.
  - apply Hhalt.
  - apply Hpre. exact H.
Qed.

Corollary encode_sentinel_halt_frame_reflects :
  forall pre (ptape : list nat) (w_tape hit_w : bool)
         (tail : list nat) (retry_steps : list book_failure)
         (hit_init : list bool) (creast : list bool) c,
    (forall c, lic_halted c = false -> c_halted (pre c) = false) ->
    c_halted
      (encode_sentinel pre
        (fun _ => boundary_sentinel_halt_frame ptape w_tape hit_w tail
          retry_steps hit_init creast) c) =
    lic_halted c.
Proof.
  intros pre ptape w_tape hit_w tail retry_steps hit_init creast c Hpre.
  apply encode_sentinel_reflects_halt.
  - exact Hpre.
  - intro c'. unfold boundary_sentinel_halt_frame, dispatch_halt_at_y.
    reflexivity.
Qed.

(** ** Boundary step fields in the sentinel model *)

Lemma sentinel_boundary_step_halts :
  forall rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_halted (left_infinite_step_sentinel rows c) = true /\
    lic_head (left_infinite_step_sentinel rows c) = (lic_head c + 1)%Z /\
    lic_R (left_infinite_step_sentinel rows c) = (lic_R c + 1)%Z /\
    lic_tape (left_infinite_step_sentinel rows c)
      (lic_head c + 1)%Z = false.
Proof.
  intros rows c row Hh Hlookup Hb.
  destruct (left_infinite_step_sentinel_boundary_fields rows c row
    Hh Hlookup Hb) as [_ [Hhead [Htape [HR Hhalt]]]].
  split; [exact Hhalt|].
  split; [exact Hhead|].
  split; [exact HR|].
  rewrite Htape. apply source_blank_at_same.
Qed.

Print Assumptions left_infinite_step_sentinel_ok.
Print Assumptions sentinel_boundary_step_halts.
Print Assumptions encode_sentinel_halt_frame_reflects.

(** ** Concrete p=1 sentinel-boundary instance

    State width 1.  The current condition is [false; false] (state 0,
    read 0); the matching row moves right to state [true] and writes
    [false].  The retry condition after consuming the sentinel blank is
    [true; false]; the first real row mismatches it at bit 0, and the
    sentinel row mismatches it at bit 0 as well. *)

Definition p1_hit : book_row :=
  {| br_cond := [false; false];
     br_action := [true; false];
     br_dir := true |}.

Definition p1_retry_failure : book_failure :=
  {| bf_src := [true; false];
     bf_row := p1_hit;
     bf_good := [];
     bf_bit := true;
     bf_src_rest := [false];
     bf_row_rest := [false];
     bf_src_split := eq_refl;
     bf_row_split := eq_refl |}.

Example boundary_right_sentinel_p1 :
  run (boundary_right_sentinel_cost [false] false false [] p1_hit
         [true] false [p1_retry_failure] [])
      (boundary_sentinel_pre_frame [false] false false [] [] []
        p1_hit [true] [])
  = boundary_sentinel_halt_frame [] false false [] [p1_retry_failure]
      [true] [].
Proof.
  apply boundary_right_sentinel_macro_step;
    vm_compute; auto 20.
Qed.

Print Assumptions boundary_right_sentinel_p1.

Example boundary_right_sentinel_p1_halted :
  c_halted
    (boundary_sentinel_halt_frame [] false false [] [p1_retry_failure]
      [true] []) = true.
Proof. reflexivity. Qed.

Example boundary_right_sentinel_p1_buffer :
  raw_buf_sentinel
    {| lic_state := [false];
       lic_head := 0%Z;
       lic_tape := fun _ => false;
       lic_R := 0%Z;
       lic_halted := false |} = [0].
Proof. reflexivity. Qed.

Example boundary_right_sentinel_p1_step :
  let c := {| lic_state := [false];
              lic_head := 0%Z;
              lic_tape := fun _ => false;
              lic_R := 0%Z;
              lic_halted := false |} in
  let row := {| wr_current := [false];
                wr_read := false;
                wr_next := [true];
                wr_write := false;
                wr_right := true |} in
  left_infinite_right_blocked c row = true /\
  lic_halted (left_infinite_step_sentinel [row] c) = true /\
  lic_head (left_infinite_step_sentinel [row] c) = 1%Z /\
  lic_R (left_infinite_step_sentinel [row] c) = 1%Z /\
  lic_tape (left_infinite_step_sentinel [row] c) 1%Z = false.
Proof.
  vm_compute. auto 20.
Qed.

Print Assumptions boundary_right_sentinel_p1_step.

(** ** Fully concrete p=1 boundary macro with an encoder *)

Definition p1_start : LeftInfiniteConfig :=
  {| lic_state := [false];
     lic_head := 0%Z;
     lic_tape := fun _ => false;
     lic_R := 0%Z;
     lic_halted := false |}.

Definition p1_row : WideSourceRow :=
  {| wr_current := [false];
     wr_read := false;
     wr_next := [true];
     wr_write := false;
     wr_right := true |}.

Definition p1_encode_running : Config :=
  boundary_sentinel_pre_frame [false] false false [] [] [] p1_hit [true] [].

Definition p1_encode_halted : Config :=
  boundary_sentinel_halt_frame [] false false [] [p1_retry_failure] [true] [].

Definition p1_encode (c : LeftInfiniteConfig) : Config :=
  if lic_halted c then p1_encode_halted else p1_encode_running.

Example p1_encode_reflects_halt :
  forall c, c_halted (p1_encode c) = lic_halted c.
Proof.
  intro c. unfold p1_encode.
  destruct (lic_halted c) eqn:H.
  - reflexivity.
  - reflexivity.
Qed.

Example p1_encode_halted_is_halted :
  c_halted p1_encode_halted = true.
Proof. reflexivity. Qed.

Example p1_boundary_step_fields :
  lic_halted (left_infinite_step_sentinel [p1_row] p1_start) = true /\
  lic_head (left_infinite_step_sentinel [p1_row] p1_start) = 1%Z /\
  lic_R (left_infinite_step_sentinel [p1_row] p1_start) = 1%Z /\
  lic_tape (left_infinite_step_sentinel [p1_row] p1_start) 1%Z = false.
Proof. vm_compute. auto 20. Qed.

Example p1_boundary_macro :
  run (boundary_right_sentinel_cost [false] false false [] p1_hit
         [true] false [p1_retry_failure] [])
      (p1_encode p1_start) =
  p1_encode (left_infinite_step_sentinel [p1_row] p1_start).
Proof.
  change (run (boundary_right_sentinel_cost [false] false false [] p1_hit
                 [true] false [p1_retry_failure] [])
              p1_encode_running = p1_encode_halted).
  apply boundary_right_sentinel_p1.
Qed.

Print Assumptions p1_boundary_macro.

(** ** The sentinel row really mismatches the new condition *)

Lemma boundary_sentinel_row_mismatch :
  forall (hit_init : list bool) (creast : list bool),
    br_cond (book_sentinel_row (hit_init ++ [false]) creast) <>
    hit_init ++ [false].
Proof.
  intros hit_init creast.
  destruct hit_init as [|b init].
  - unfold book_sentinel_row. cbn. discriminate.
  - unfold book_sentinel_row. cbn [hd negb app].
    destruct b; cbn; discriminate.
Qed.

Print Assumptions boundary_sentinel_row_mismatch.

(** ** Fresh sentinel state: no real row can match the new condition

    The previous boundary step kept the performed row's next state.  A
    real row with that state and read bit 0 could then match after the
    sentinel blank is consumed, so the native locate phase would execute
    it instead of halting.  The fix is to set the boundary state to a
    fresh word of width [p+1].  Every program row has state width [p], so
    no real row can match; the locate phase must fail on the sentinel
    row. *)

Definition sentinel_state (p : nat) : list bool :=
  repeat false (S p).

Lemma sentinel_state_length :
  forall p, length (sentinel_state p) = S p.
Proof.
  intros p. unfold sentinel_state. rewrite repeat_length. reflexivity.
Qed.

Lemma sentinel_state_neq_current :
  forall p (r : WideSourceRow),
    wide_row_wellformed p r ->
    wr_current r <> sentinel_state p.
Proof.
  intros p r [Hc Hn] H.
  assert (Hlen : length (wr_current r) = length (sentinel_state p))
    by (rewrite H; reflexivity).
  rewrite Hc, sentinel_state_length in Hlen. lia.
Qed.

Lemma sentinel_state_no_match_row :
  forall p (r : WideSourceRow) bit,
    wide_row_wellformed p r ->
    wide_row_matches r (sentinel_state p) bit = false.
Proof.
  intros p r bit Hwf.
  unfold wide_row_matches.
  destruct (list_eq_dec Bool.bool_dec (wr_current r)
              (sentinel_state p)) as [Heq | Hneq].
  - exfalso. apply (sentinel_state_neq_current p r Hwf Heq).
  - reflexivity.
Qed.

Lemma sentinel_state_no_match :
  forall p rows bit,
    Forall (wide_row_wellformed p) rows ->
    wide_source_lookup rows (sentinel_state p) bit = None.
Proof.
  intros p rows. induction rows as [|r rest IH]; intros bit Hwf.
  - reflexivity.
  - inversion Hwf as [|? ? Hr Hrest]; subst.
    unfold wide_source_lookup. simpl.
    rewrite (sentinel_state_no_match_row p r bit Hr).
    apply IH. exact Hrest.
Qed.

Definition left_infinite_step_sentinel_fresh
    (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig)
    : LeftInfiniteConfig :=
  if lic_halted c then c else
    match wide_source_lookup rows (lic_state c)
                            (lic_tape c (lic_head c)) with
    | None =>
        {| lic_state := lic_state c;
           lic_head := lic_head c;
           lic_tape := lic_tape c;
           lic_R := lic_R c;
           lic_halted := true |}
    | Some row =>
        if left_infinite_right_blocked c row then
          {| lic_state := sentinel_state p;
             lic_head := (lic_head c + 1)%Z;
             lic_tape := source_blank_at
               (source_write_at (lic_tape c) (lic_head c)
                                  (wr_write row))
               (lic_head c + 1)%Z;
             lic_R := (lic_R c + 1)%Z;
             lic_halted := true |}
        else
          {| lic_state := wr_next row;
             lic_head := (lic_head c +
                          (if wr_right row then 1 else -1))%Z;
             lic_tape := source_write_at (lic_tape c) (lic_head c)
                                          (wr_write row);
             lic_R := lic_R c;
             lic_halted := false |}
    end.

Lemma left_infinite_step_sentinel_fresh_halted :
  forall p rows c,
    lic_halted c = true ->
    left_infinite_step_sentinel_fresh p rows c = c.
Proof.
  intros p rows c H. unfold left_infinite_step_sentinel_fresh.
  now rewrite H.
Qed.

Lemma left_infinite_step_sentinel_fresh_boundary_fields :
  forall p rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_state (left_infinite_step_sentinel_fresh p rows c) =
      sentinel_state p /\
    lic_head (left_infinite_step_sentinel_fresh p rows c) =
      (lic_head c + 1)%Z /\
    lic_tape (left_infinite_step_sentinel_fresh p rows c) =
      source_blank_at
        (source_write_at (lic_tape c) (lic_head c) (wr_write row))
        (lic_head c + 1)%Z /\
    lic_R (left_infinite_step_sentinel_fresh p rows c) =
      (lic_R c + 1)%Z /\
    lic_halted (left_infinite_step_sentinel_fresh p rows c) = true.
Proof.
  intros p rows c row Hh Hlookup Hb.
  unfold left_infinite_step_sentinel_fresh.
  rewrite Hh, Hlookup, Hb.
  repeat split; reflexivity.
Qed.

Lemma left_infinite_step_sentinel_fresh_ok :
  forall p rows c,
    left_infinite_ok c ->
    left_infinite_ok (left_infinite_step_sentinel_fresh p rows c).
Proof.
  intros p rows c [Hle Hblank].
  unfold left_infinite_step_sentinel_fresh.
  destruct (lic_halted c) eqn:Eh.
  - exact (conj Hle Hblank).
  - destruct (wide_source_lookup rows (lic_state c)
                (lic_tape c (lic_head c))) as [row|] eqn:El.
    + destruct (left_infinite_right_blocked c row) eqn:Eb.
      * simpl. split.
        -- unfold left_infinite_right_blocked in Eb.
           apply Bool.andb_true_iff in Eb.
           destruct Eb as [_ Heq].
           apply Z.eqb_eq in Heq.
           change ((lic_head c + 1 <= lic_R c + 1)%Z). lia.
        -- intros z Hz.
           change ((lic_R c + 1 < z)%Z) in Hz.
           change (source_blank_at
             (source_write_at (lic_tape c) (lic_head c) (wr_write row))
             (lic_head c + 1) z = false).
           rewrite source_blank_at_above by lia.
           rewrite source_write_at_above by lia.
           apply Hblank. lia.
      * simpl. split.
        -- unfold left_infinite_right_blocked in Eb.
           apply Bool.andb_false_iff in Eb.
           destruct Eb as [Hr | He].
           ++ rewrite Hr. simpl. lia.
           ++ apply Z.eqb_neq in He.
              destruct (wr_right row).
              ** simpl. lia.
              ** simpl. lia.
        -- intros z Hz.
           change ((lic_R c < z)%Z) in Hz.
           change (source_write_at (lic_tape c) (lic_head c)
                     (wr_write row) z = false).
           rewrite source_write_at_above by lia.
           apply Hblank. lia.
    + exact (conj Hle Hblank).
Qed.

(** The key no-match fact for the fresh boundary state. *)
Lemma fresh_boundary_new_condition_no_match :
  forall p rows c row,
    Forall (wide_row_wellformed p) rows ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    wide_source_lookup rows
      (lic_state (left_infinite_step_sentinel_fresh p rows c))
      (lic_tape (left_infinite_step_sentinel_fresh p rows c)
         (lic_head (left_infinite_step_sentinel_fresh p rows c))) = None.
Proof.
  intros p rows c row Hwf Hh Hlookup Hb.
  destruct (left_infinite_step_sentinel_fresh_boundary_fields p rows c row
    Hh Hlookup Hb) as [Hstate [Hhead [Htape [_ _]]]].
  rewrite Hstate, Hhead, Htape.
  cbn [lic_state lic_head lic_tape].
  rewrite source_blank_at_same.
  cbn [app].
  apply sentinel_state_no_match. exact Hwf.
Qed.

Lemma left_infinite_step_sentinel_fresh_boundary_blank :
  forall p rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_tape (left_infinite_step_sentinel_fresh p rows c)
      (lic_head c + 1)%Z = false.
Proof.
  intros p rows c row Hh Hlookup Hb.
  destruct (left_infinite_step_sentinel_fresh_boundary_fields p rows c row
    Hh Hlookup Hb) as [_ [_ [Htape _]]].
  rewrite Htape. apply source_blank_at_same.
Qed.

Lemma left_infinite_step_sentinel_fresh_boundary_head_eq_R :
  forall p rows c row,
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    lic_head (left_infinite_step_sentinel_fresh p rows c) =
    lic_R (left_infinite_step_sentinel_fresh p rows c).
Proof.
  intros p rows c row Hh Hlookup Hb.
  destruct (left_infinite_step_sentinel_fresh_boundary_fields p rows c row
    Hh Hlookup Hb) as [_ [Hhead [_ [HR _]]]].
  unfold left_infinite_right_blocked in Hb.
  apply Bool.andb_true_iff in Hb.
  destruct Hb as [_ Heq].
  apply Z.eqb_eq in Heq.
  rewrite Hhead, HR. lia.
Qed.

Print Assumptions fresh_boundary_new_condition_no_match.
Print Assumptions left_infinite_step_sentinel_fresh_ok.
