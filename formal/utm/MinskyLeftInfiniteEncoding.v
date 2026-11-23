(** * Sentinel-augmented running description

    The final running encoder uses

      source_rows_to_book rows ++ [duplicate of the first source row]

    The duplicate sentinel has the same length-[p+1] condition as a real
    source row, so a no-match scan still produces a failure record and a
    halt.  On a hit path the duplicate is harmless: if its condition
    matches the current source condition, the real first row matches
    strictly earlier and wins the first-match scan.

    This file packages:

    - the first-match hit on the augmented description;
    - the first-match halt on the augmented description;
    - the explicit right-hit and left-hit one-step macros for it.

    The right-boundary (empty raw buffer) case is intentionally not
    included here; it needs the q3/Y halt path of the frozen table. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyBookLayout MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyBookLocateCycle MinskyBookLocateLookup
  MinskyBookEncode MinskyBookRawBuffer MinskyLeftInfinite
  MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteFirstMatchApp MinskyLeftInfiniteStepRight
  MinskyLeftInfiniteStepLeft.

(** ** The duplicate sentinel row *)

Definition lic_sentinel_row (rows : list WideSourceRow) : book_row :=
  match rows with
  | [] =>
      {| br_cond := [false];
         br_action := [false];
         br_dir := false |}
  | r :: _ => source_row_to_book r
  end.

Definition lic_book_rows (rows : list WideSourceRow) : list book_row :=
  source_rows_to_book rows ++ [lic_sentinel_row rows].

Lemma lic_book_rows_nonempty :
  forall rows, lic_book_rows rows <> [].
Proof.
  intros rows. unfold lic_book_rows.
  apply app_cons_book_row_neq_nil.
Qed.

Lemma lic_sentinel_row_nonempty_cond :
  forall rows,
    rows <> [] ->
    br_cond (lic_sentinel_row rows) <> [].
Proof.
  intros rows Hne. destruct rows as [|r rest]; [contradiction|].
  simpl. apply snoc_neq_nil.
Qed.

Lemma lic_book_rows_cond_nonempty :
  forall p rows,
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    Forall (fun br => br_cond br <> []) (lic_book_rows rows).
Proof.
  intros p rows Hwf Hne.
  unfold lic_book_rows.
  apply Forall_app. split.
  - clear Hne. induction Hwf as [|r rest Hr Hrest IH].
    + constructor.
    + simpl. constructor.
      * rewrite source_row_cond. apply snoc_neq_nil.
      * exact IH.
  - constructor.
    + apply lic_sentinel_row_nonempty_cond. exact Hne.
    + constructor.
Qed.

(** The sentinel of a nonempty row list is the encoding of its first
    row, hence it has the source condition length. *)

Lemma lic_sentinel_row_cond_length :
  forall p rows,
    rows <> [] ->
    Forall (wide_row_wellformed p) rows ->
    length (br_cond (lic_sentinel_row rows)) = S p.
Proof.
  intros p rows Hne Hwf.
  destruct rows as [|r rest]; [contradiction|].
  inversion Hwf as [|? ? Hr Hrest]; subst.
  simpl. apply source_row_cond_length. exact Hr.
Qed.

(** ** Hit packaging on the augmented description *)

Theorem lic_book_rows_first_match_hit :
  forall (p : nat) (rows : list WideSourceRow) (r : WideSourceRow)
         (state : list bool) (bit : bool),
    Forall (wide_row_wellformed p) rows ->
    length state = p ->
    wide_source_lookup rows state bit = Some r ->
    exists steps hit after,
      book_first_match (state ++ [bit]) (lic_book_rows rows) =
      book_lookup_hit steps hit after /\
      hit = source_row_to_book r /\
      after <> [] /\
      Forall (fun st => bf_src st = state ++ [bit]) steps.
Proof.
  intros p rows r state bit Hwf Hlen Hlookup.
  destruct (wide_source_lookup_some_book_first_match_hit p rows state bit r
    Hwf Hlen Hlookup)
    as [steps [hit [after [Hbf [Hhit [Hrows Hforall]]]]]].
  exists steps, hit, (after ++ [lic_sentinel_row rows]).
  split; [|split; [exact Hhit|split]].
  - unfold lic_book_rows.
    rewrite (@book_first_match_hit_app (state ++ [bit])
      (source_rows_to_book rows) [lic_sentinel_row rows] steps hit after Hbf).
    reflexivity.
  - apply snoc_neq_nil.
  - exact Hforall.
Qed.

(** ** Halt packaging on the augmented description *)

Lemma lic_sentinel_row_mismatch_of_lookup_none :
  forall (p : nat) (rows : list WideSourceRow) (state : list bool)
         (bit : bool),
    Forall (wide_row_wellformed p) rows ->
    length state = p ->
    rows <> [] ->
    wide_source_lookup rows state bit = None ->
    book_row_matches (state ++ [bit]) (lic_sentinel_row rows) = false.
Proof.
  intros p rows state bit Hwf Hlen Hne Hlookup.
  destruct rows as [|r rest]; [contradiction|].
  inversion Hwf as [|? ? Hr Hrest]; subst.
  assert (Hin : In r (r :: rest)) by (left; reflexivity).
  assert (Hfalse : wide_row_matches r state bit = false).
  { destruct (wide_row_matches r state bit) eqn:E; [|reflexivity].
    exfalso. unfold wide_source_lookup in Hlookup.
    rewrite (@find_cons_true WideSourceRow
      (fun row => wide_row_matches row state bit)
      r rest E) in Hlookup. discriminate Hlookup. }
  simpl. rewrite <- source_row_to_book_matches. exact Hfalse.
Qed.

Theorem lic_book_rows_first_match_halt :
  forall (p : nat) (rows : list WideSourceRow)
         (state : list bool) (bit : bool),
    Forall (wide_row_wellformed p) rows ->
    length state = p ->
    rows <> [] ->
    wide_source_lookup rows state bit = None ->
    exists steps last,
      book_first_match (state ++ [bit]) (lic_book_rows rows) =
      book_lookup_halt steps last.
Proof.
  intros p rows state bit Hwf Hlen Hne Hlookup.
  destruct (wide_source_lookup_none_book_first_match_halt p rows state bit
    Hwf Hlen Hne Hlookup) as [steps [last [Hbf _]]].
  assert (Hsm : book_row_matches (state ++ [bit])
                  (lic_sentinel_row rows) = false).
  { apply (lic_sentinel_row_mismatch_of_lookup_none p rows state bit
      Hwf Hlen Hne Hlookup). }
  assert (Hlencond : length (br_cond (lic_sentinel_row rows)) =
                     length (state ++ [bit])).
  { rewrite (lic_sentinel_row_cond_length p rows Hne Hwf).
    rewrite app_length. cbn [length]. rewrite Hlen. lia. }
  destruct (book_row_matches_false_ev _ _ Hlencond Hsm) as [e He].
  destruct e as [p0 Hp0].
  destruct p0 as [[[good bad] srest] rrest].
  set (sf := book_failure_of_split (state ++ [bit])
    (lic_sentinel_row rows) good bad srest rrest Hp0).
  assert (Hsent : book_first_match (state ++ [bit])
                    [lic_sentinel_row rows] = book_lookup_halt [] sf).
  { unfold book_first_match. rewrite Hsm.
    unfold book_lookup_cons, book_lookup_cons_of.
    rewrite He. reflexivity. }
  exists (steps ++ [last]), sf.
  unfold lic_book_rows.
  rewrite (book_first_match_halt_app (state ++ [bit])
    (source_rows_to_book rows) [lic_sentinel_row rows]
    steps last [] sf Hbf Hsent).
  cbn [app]. reflexivity.
Qed.

Print Assumptions lic_book_rows_first_match_hit.
Print Assumptions lic_book_rows_first_match_halt.

(** ** Explicit right-hit step on the augmented description *)

Theorem lic_book_rows_right_hit_step :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow)
         (tail : list nat) (steps : list book_failure)
         (hit : book_row) (after : list book_row),
    (lo < lic_head c)%Z ->
    lic_halted c = false ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    rows <> [] ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
      (source_rows_to_book rows) = book_lookup_hit steps hit after ->
    hit = source_row_to_book r ->
    run (lic_q5_right_hit_cost lo c steps hit (wr_next r) (wr_write r))
      (lic_q5_encode lo c (lic_book_rows rows) tail) =
    lic_q5_encode lo (left_infinite_step rows c)
      (lic_book_rows rows) tail.
Proof.
  intros p lo c rows r tail steps hit after
    Hlo Hh Hwf Hlen Hne Hlookup Hright Hlt Hbf Hhit.
  pose proof (book_first_match_hit_sound
    (lic_state c ++ [lic_tape c (lic_head c)])
    (source_rows_to_book rows) steps hit after Hbf) as Hsound.
  destruct Hsound as [Hrows0 [Hsteps Hcond]].
  assert (Hbf' : book_first_match
      (lic_state c ++ [lic_tape c (lic_head c)])
      (lic_book_rows rows) =
      book_lookup_hit steps hit (after ++ [lic_sentinel_row rows])).
  { unfold lic_book_rows.
    rewrite (@book_first_match_hit_app
      (lic_state c ++ [lic_tape c (lic_head c)])
      (source_rows_to_book rows) [lic_sentinel_row rows] steps hit after Hbf).
    reflexivity. }
  assert (Hne_after : after ++ [lic_sentinel_row rows] <> [])
    by apply snoc_neq_nil.
  destruct (after ++ [lic_sentinel_row rows]) as [|next rest] eqn:E.
  - contradiction.
  - assert (Hrows_aug : lic_book_rows rows =
        map bf_row steps ++ hit :: next :: rest).
    { unfold lic_book_rows. rewrite Hrows0.
      rewrite <- app_assoc. cbn [app]. rewrite E. reflexivity. }
    assert (Hin : In next (lic_book_rows rows)).
    { assert (Hin' : In next
          (map bf_row steps ++ hit :: next :: rest)).
      { apply in_or_app. right. right. left. reflexivity. }
      exact (eq_ind (map bf_row steps ++ hit :: next :: rest)
        (fun l => In next l) Hin' (lic_book_rows rows)
        (eq_sym Hrows_aug)). }
    assert (Hconds : Forall (fun br => br_cond br <> [])
        (lic_book_rows rows)).
    { apply (lic_book_rows_cond_nonempty p rows Hwf Hne). }
    assert (Hne_next : br_cond next <> []).
    { exact (proj1 (Forall_forall (fun br => br_cond br <> [])
        (lic_book_rows rows)) Hconds next Hin). }
    destruct (br_cond next) as [|c0 creast] eqn:Enext.
    + contradiction.
    + eapply (lic_q5_encode_right_hit_step p lo c rows r r
        (lic_book_rows rows) tail steps hit next rest (wr_next r)
        (wr_write r) c0 creast Hlo Hh Hwf Hlookup Hright Hlt
        Hsteps Hrows_aug Hhit Hcond).
      * rewrite Hhit. reflexivity.
      * exact Enext.
Qed.

Print Assumptions lic_book_rows_right_hit_step.

(** ** Explicit left-hit step on the augmented description *)

Definition lic_q5_left_hit_cost
    (lo : Z) (c : LeftInfiniteConfig) (steps : list book_failure)
    (hit : book_row) (hit_init : list bool) (hit_w : bool) : nat :=
  book_steady_locate_q12_clock_gen
    (lic_state c) (lic_tape c (lic_head c)) (raw_last c lo) steps hit +
  book_q13_perform_left_clock_raw hit_init hit_w (raw_buf c)
    (book_cycle_tags steps
      (lic_state c ++ [lic_tape c (lic_head c)]) hit).

Theorem lic_book_rows_left_hit_step :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow)
         (tail : list nat) (steps : list book_failure)
         (hit next : book_row) (rest : list book_row)
         (c0 : bool) (creast : list bool),
    (lo < lic_head c - 1)%Z ->
    lic_halted c = false ->
    left_infinite_ok c ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    rows <> [] ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = false ->
    book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
      (lic_book_rows rows) = book_lookup_hit steps hit (next :: rest) ->
    hit = source_row_to_book r ->
    lic_book_rows rows = map bf_row steps ++ hit :: next :: rest ->
    br_cond next = c0 :: creast ->
    run (lic_q5_left_hit_cost lo c steps hit (wr_next r) (wr_write r))
      (lic_q5_encode lo c (lic_book_rows rows) tail) =
    lic_q5_encode lo (left_infinite_step rows c)
      (lic_book_rows rows) tail.
Proof.
  intros p lo c rows r tail steps hit next rest c0 creast
    Hlo Hh Hok Hwf Hlen Hne Hlookup Hleft Hbf Hhit Hrows Hnext.
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
    (lic_book_rows rows) steps hit (next :: rest) Hbf)
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
    (lic_book_rows rows) tail).
  rewrite Hrows.
  unfold lic_q5_left_hit_cost.
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

Print Assumptions lic_book_rows_left_hit_step.

(** ** No-match halt on the augmented description *)

Theorem lic_book_rows_none_halt_step :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (tail : list nat),
    (lo < lic_head c)%Z ->
    lic_halted c = false ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    rows <> [] ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = None ->
    exists steps last,
      book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
        (lic_book_rows rows) = book_lookup_halt steps last /\
      run (S (length (lic_state c)) +
           (book_failures_clock [] steps +
            book_halt_clock (map bf_row steps) last))
        (lic_q5_encode lo c (lic_book_rows rows) tail) =
      lic_halt_encode lo (left_infinite_step rows c) steps last tail /\
      c_halted (lic_halt_encode lo
        (left_infinite_step rows c) steps last tail) = true.
Proof.
  intros p lo c rows tail Hlo Hh Hwf Hlen Hne Hlookup.
  destruct (lic_book_rows_first_match_halt p rows
    (lic_state c) (lic_tape c (lic_head c)) Hwf Hlen Hne Hlookup)
    as [steps [last Hbf]].
  exists steps, last. split; [exact Hbf|split].
  - rewrite (lic_q5_encode_none_halt_book_macro lo c
      (lic_book_rows rows) tail steps last Hlo
      (lic_book_rows_nonempty rows) Hbf).
    symmetry. apply lic_halt_encode_step. exact Hlookup.
  - apply lic_halt_encode_halted.
Qed.

Print Assumptions lic_book_rows_none_halt_step.
