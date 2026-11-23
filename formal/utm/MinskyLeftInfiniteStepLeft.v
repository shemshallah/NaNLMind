(** * General non-boundary LEFT hit macro

    A matching left-moving row is handled by the raw left cycle

      book_steady_q5_locate_to_q5_left_raw_gen

    whose output is the literal [cfg_ml] frame.  [book_q5_raw_left_frame_eq]
    turns that frame back into the next q5 raw frame:

      init  = hit_init          (the next source state)
      buf   = source_bit hit_w :: buf
      ptape = removelast P
      w_tape = last_raw P
      w_read = w_tape           (the old last ptape cell)

    where [P = raw_ptape_prefix c lo] is the input q5 ptape.

    For the source encoder we need [lo < lic_head c - 1], so that the
    same window [lo] is still strictly left of the new head
    [lic_head c - 1].  At [lo = lic_head c - 1] the next frame needs the
    one-cell extra padding window [lo - 1]; that case is recorded
    separately by [left_next_lo] below but is not needed for the strict
    macro. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyMatchMacro MinskyConcreteDispatch MinskyHeadMoveMacro
  MinskyBookLayout
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateWide
  MinskyBookLocateCycle MinskyBookLocateLookup MinskyBookRawBuffer
  MinskyBookEncode MinskyLeftInfinite MinskyLeftInfiniteEncode
  MinskyLeftInfiniteWindow MinskyLeftInfiniteLookup
  MinskyLeftInfiniteHalt.

(** ** The last raw ptape cell *)

Lemma source_bit_last_raw :
  forall (l : list nat),
    raw_source_buffer l ->
    l <> [] ->
    source_bit (last_raw l) = last l 0.
Proof.
  intros l Hraw Hne.
  unfold last_raw.
  destruct (rev l) as [|s rest] eqn:Hrev.
  - exfalso. apply Hne.
    apply (f_equal (@rev nat)) in Hrev.
    rewrite rev_involutive in Hrev. exact Hrev.
  - assert (Hraw' : Forall raw_source_cell (rev l))
      by (apply Forall_rev; exact Hraw).
    rewrite Hrev in Hraw'. apply Forall_inv in Hraw'.
    rewrite (raw_to_bool_source_bit s Hraw').
    assert (Hl : l = rev rest ++ [s]).
    { apply (f_equal (@rev nat)) in Hrev.
      rewrite rev_involutive in Hrev.
      rewrite Hrev. cbn [rev]. reflexivity. }
    rewrite Hl. rewrite last_app_singleton. reflexivity.
Qed.

Lemma removelast_last_raw :
  forall (l : list nat),
    raw_source_buffer l ->
    l <> [] ->
    removelast l ++ [source_bit (last_raw l)] = l.
Proof.
  intros l Hraw Hne.
  rewrite source_bit_last_raw by assumption.
  symmetry. apply app_removelast_last. exact Hne.
Qed.

Lemma raw_ptape_prefix_nonempty :
  forall (c : LeftInfiniteConfig) (lo : Z),
    (lo < lic_head c - 1)%Z ->
    raw_ptape_prefix c lo <> [].
Proof.
  intros c lo Hlt.
  assert (Hge : 2 <= Z.to_nat (lic_head c - lo)).
  { apply (proj1 (Z2Nat.inj_le 2 (lic_head c - lo)
      ltac:(lia) ltac:(lia))). lia. }
  unfold raw_ptape_prefix.
  destruct (rev (raw_ptape c lo)) as [|s rest] eqn:Hrev.
  - assert (Hnil : raw_ptape c lo = []).
    { apply (f_equal (@rev nat)) in Hrev.
      rewrite rev_involutive in Hrev. exact Hrev. }
    assert (Hlen := raw_ptape_length c lo).
    rewrite Hnil in Hlen. cbn [length] in Hlen. lia.
  - intro Hnil.
    apply (f_equal (@rev nat)) in Hnil.
    rewrite rev_involutive in Hnil. subst rest.
    assert (Hraw : raw_ptape c lo = [s]).
    { apply (f_equal (@rev nat)) in Hrev.
      rewrite rev_involutive in Hrev.
      rewrite Hrev. reflexivity. }
    assert (Hlen := raw_ptape_length c lo).
    rewrite Hraw in Hlen. cbn [length] in Hlen. lia.
Qed.

(** ** Generalized left frame equality

    [book_q5_raw_left_frame_eq] identifies the old and new source
    state/read bit.  The left cycle output uses the *new* state and the
    old last ptape cell as the new read bit, so the general version
    below keeps them separate. *)

Lemma book_q5_raw_left_frame_eq_gen :
  forall (old_init : list bool) (old_read : bool)
         (new_init : list bool) (new_read : bool)
         (buf ptape_prefix : list nat) (w_tape_left : bool)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (hit_w c0 : bool)
         (creast : list bool) (tail : list nat),
    br_cond hit = old_init ++ [old_read] ->
    br_action hit = new_init ++ [hit_w] ->
    br_cond next = c0 :: creast ->
    book_q5_raw new_init (source_bit hit_w :: buf) w_tape_left
      ptape_prefix new_read
      (map bf_row steps ++ hit :: next :: rest) tail
    = cfg_ml 5
        (rev (source_bit hit_w ::
              rev (book_return_rail_raw new_init buf)) ++
         6 :: rev (ptape_prefix ++ [source_bit w_tape_left]))
        (match_mark new_read :: 4 ::
         map q16_restore
           (rev (book_cycle_tags steps (old_init ++ [old_read]) hit)) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros old_init old_read new_init new_read buf ptape_prefix
    w_tape_left steps hit next rest hit_w c0 creast tail
    Hcond Hact Hnext.
  unfold book_q5_raw.
  rewrite rev_snoc_cons_nat.
  cbn [map q16_restore].
  rewrite <- (book_cycle_restored_raw_desc_tail steps
    (old_init ++ [old_read]) hit next rest c0 creast (5 :: tail)
    Hcond Hnext).
  rewrite book_return_rail_raw_rev.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions book_q5_raw_left_frame_eq_gen.

(** ** Book-level left macro *)

Theorem book_q5_left_hit_macro :
  forall (init : list bool) (w_read w_tape : bool) (buf P tail : list nat)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (hit_init : list bool) (hit_w c0 : bool)
         (creast : list bool),
    P <> [] ->
    raw_source_buffer P ->
    raw_source_buffer buf ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = false ->
    br_cond next = c0 :: creast ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q13_perform_left_clock_raw hit_init hit_w buf
           (book_cycle_tags steps (init ++ [w_read]) hit))
      (book_q5_raw init buf w_tape P w_read
        (map bf_row steps ++ hit :: next :: rest) tail)
    = book_q5_raw hit_init (source_bit hit_w :: buf) (last_raw P)
        (removelast P) w_tape
        (map bf_row steps ++ hit :: next :: rest) tail.
Proof.
  intros init w_read w_tape buf P tail steps hit next rest hit_init
    hit_w c0 creast HneP HrawP Hrawbuf Hsteps Hcond Hlen Hact Hdir
    Hnext.
  rewrite (book_steady_q5_locate_to_q5_left_raw_gen init w_read w_tape
    buf P tail steps hit next rest hit_init hit_w c0 creast
    Hrawbuf Hsteps Hcond Hlen Hact Hdir Hnext).
  transitivity
    (cfg_ml 5
      (rev (source_bit hit_w ::
            rev (book_return_rail_raw hit_init buf)) ++
       6 :: rev (removelast P ++ [source_bit (last_raw P)]))
      (match_mark w_tape :: 4 ::
       map q16_restore
         (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ++
       source_bit c0 ::
       book_after_suffix creast next rest ++ 5 :: tail)).
  - replace (rev P)
      with (rev (removelast P ++ [source_bit (last_raw P)])).
    2:{ rewrite (removelast_last_raw P HrawP HneP). reflexivity. }
    repeat rewrite rev_app_distr.
    cbn [rev map q16_restore match_mark].
    reflexivity.
  - symmetry.
    apply (book_q5_raw_left_frame_eq_gen init w_read hit_init w_tape
      buf (removelast P) (last_raw P) steps hit next rest hit_w c0 creast
      tail Hcond Hact Hnext).
Qed.

Print Assumptions book_q5_left_hit_macro.

(** ** Source-level left macro *)

Lemma raw_source_buffer_removelast :
  forall (l : list nat),
    raw_source_buffer l -> raw_source_buffer (removelast l).
Proof.
  intros l H. unfold raw_source_buffer in *.
  induction H as [|x xs Hx Hxs IH].
  - constructor.
  - destruct xs as [|y ys].
    + cbn [removelast]. constructor.
    + cbn [removelast]. constructor; [exact Hx|exact IH].
Qed.

Lemma raw_ptape_prefix_raw :
  forall (c : LeftInfiniteConfig) (lo : Z),
    raw_source_buffer (raw_ptape_prefix c lo).
Proof.
  intros c lo. rewrite raw_ptape_prefix_removelast.
  apply raw_source_buffer_removelast. apply raw_ptape_raw.
Qed.

Theorem lic_q5_encode_left_hit_macro :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow) (tail : list nat)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (c0 : bool) (creast : list bool),
    (lo < lic_head c - 1)%Z ->
    lic_halted c = false ->
    left_infinite_ok c ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
      (source_rows_to_book rows) = book_lookup_hit steps hit (next :: rest) ->
    hit = source_row_to_book r ->
    source_rows_to_book rows = map bf_row steps ++ hit :: next :: rest ->
    br_cond next = c0 :: creast ->
    run (book_steady_locate_q12_clock_gen (lic_state c)
           (lic_tape c (lic_head c)) (raw_last c lo) steps hit +
         book_q13_perform_left_clock_raw (wr_next r) (wr_write r)
           (raw_buf c)
           (book_cycle_tags steps
             (lic_state c ++ [lic_tape c (lic_head c)]) hit))
      (lic_q5_encode lo c (source_rows_to_book rows) tail) =
    lic_q5_encode lo (left_infinite_step rows c)
      (source_rows_to_book rows) tail.
Proof.
  intros p lo c rows r tail steps hit next rest c0 creast
    Hlo Hh Hok Hwf Hlen Hlookup Hleft Hbf Hhit Hrows Hnext.
  destruct Hok as [HleR Hblank].
  assert (Hle : (lo <= lic_head c)%Z) by lia.
  assert (Hlt : (lo < lic_head c)%Z) by lia.
  assert (HneP : raw_ptape_prefix c lo <> [])
    by (apply raw_ptape_prefix_nonempty; exact Hlo).
  assert (HrawP : raw_source_buffer (raw_ptape_prefix c lo))
    by (apply raw_ptape_prefix_raw).
  assert (Hin : In r rows).
  { pose proof (find_some
      (fun row => wide_row_matches row (lic_state c)
         (lic_tape c (lic_head c))) rows Hlookup) as H.
    exact (proj1 H). }
  assert (Hwf_r : wide_row_wellformed p r).
  { rewrite Forall_forall in Hwf. apply Hwf. exact Hin. }
  destruct (book_first_match_hit_sound
    (lic_state c ++ [lic_tape c (lic_head c)])
    (source_rows_to_book rows) steps hit (next :: rest) Hbf)
    as [Hrows' [Hforall Hcond]].
  assert (Hcond' : br_cond (source_row_to_book r) =
                   lic_state c ++ [lic_tape c (lic_head c)])
    by (rewrite <- Hhit; exact Hcond).
  assert (Hlen_act : length (br_action hit) =
                     length (lic_state c ++ [lic_tape c (lic_head c)])).
  { rewrite Hhit. rewrite (source_row_action_length p r Hwf_r).
    rewrite Hcond'. reflexivity. }
  assert (Hact : br_action hit = wr_next r ++ [wr_write r])
    by (rewrite Hhit; reflexivity).
  assert (Hdir : br_dir hit = false).
  { rewrite Hhit. rewrite source_row_dir. exact Hleft. }
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hleft. reflexivity. }
  rewrite (lic_q5_encode_is_book_q5_raw lo c
    (source_rows_to_book rows) tail).
  rewrite Hrows.
  rewrite (book_q5_left_hit_macro (lic_state c) (lic_tape c (lic_head c))
    (raw_last c lo) (raw_buf c) (raw_ptape_prefix c lo) tail
    steps hit next rest (wr_next r) (wr_write r) c0 creast
    HneP HrawP (raw_buf_raw c) Hforall Hcond Hlen_act Hact Hdir Hnext).
  rewrite (lic_q5_encode_is_book_q5_raw lo (left_infinite_step rows c)
    (map bf_row steps ++ hit :: next :: rest) tail).
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [Hstate [Hhead [Htape [HR Hhalted]]]].
  rewrite Hleft in Hhead.
  rewrite Hstate.
  rewrite (raw_buf_left_step rows c r Hh Hlookup Hleft HleR).
  rewrite (raw_ptape_prefix_left_step rows c r lo Hh Hlookup Hleft Hle).
  rewrite (raw_last_left_step rows c r lo Hh Hlookup Hleft Hle).
  rewrite Hhead.
  replace (lic_head c + -1)%Z with (lic_head c - 1)%Z by lia.
  rewrite (raw_read_left_step rows c r lo Hh Hlookup Hleft Hlt).
  reflexivity.
Qed.

Print Assumptions lic_q5_encode_left_hit_macro.

(** ** The left window update rule *)

Definition left_next_lo (lo : Z) (c : LeftInfiniteConfig) : Z :=
  if Z.ltb lo (lic_head c - 1) then lo else lo - 1.

Lemma left_next_lo_lt_step :
  forall (rows : list WideSourceRow) (c : LeftInfiniteConfig)
         (r : WideSourceRow) (lo : Z),
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    (lo < lic_head c)%Z ->
    (left_next_lo lo c < lic_head (left_infinite_step rows c))%Z.
Proof.
  intros rows c r lo Hh Hlookup Hleft Hlo.
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hleft. reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [_ [Hhead _]].
  rewrite Hleft in Hhead.
  unfold left_next_lo.
  destruct (Z.ltb lo (lic_head c - 1)) eqn:E.
  - apply Z.ltb_lt in E. lia.
  - apply Z.ltb_ge in E. lia.
Qed.

Print Assumptions left_next_lo_lt_step.
