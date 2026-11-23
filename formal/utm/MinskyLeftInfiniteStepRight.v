(** * General non-boundary right-hit macro step

    This composes the raw q5 locate/perform right cycle, the restored
    frame equality, and the right window package into the general
    one-step theorem for the left-infinite source model.

    The source row list is related to the book description through the
    first-match witnesses [steps], [hit], [next], [rest].  The caller
    obtains these from [wide_source_lookup] via the lookup packaging;
    the trailing [next] row is the row after the match, which the final
    encoder guarantees by appending a sentinel row. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyConcreteEntry MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalInstruction MinskyDirectionDecision
  MinskyRelocationMacro MinskyHeadMoveMacro MinskyCanonicalRestore
  MinskyBookLayout MinskyBookCycle MinskyBookLeft MinskyBookLeftCycle
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateWide
  MinskyBookLocateCycle MinskyBookLocateLookup MinskyBookEncode
  MinskyBookRawBuffer MinskyLeftInfinite MinskyLeftInfiniteEncode
  MinskyLeftInfiniteWindow.

(** ** The right-hit clock *)

Definition lic_q5_right_hit_cost
    (lo : Z) (c : LeftInfiniteConfig) (steps : list book_failure)
    (hit : book_row) (hit_init : list bool) (hit_w : bool) : nat :=
  book_steady_locate_q12_clock_gen
    (lic_state c) (lic_tape c (lic_head c)) (raw_last c lo) steps hit +
  book_q12_perform_right_clock_raw hit_init hit_w (raw_buf c)
    (book_cycle_tags steps
      (lic_state c ++ [lic_tape c (lic_head c)]) hit)
    (tl (raw_buf c) ++ [5] ++ map source_bit hit_init).

(** ** The general right-hit macro *)

Theorem lic_q5_encode_right_hit_step :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r rnext : WideSourceRow)
         (rows_book : list book_row) (tail : list nat)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (hit_init : list bool)
         (hit_w c0 : bool) (creast : list bool),
    (lo < lic_head c)%Z ->
    lic_halted c = false ->
    Forall (wide_row_wellformed p) rows ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    Forall (fun st => bf_src st =
      lic_state c ++ [lic_tape c (lic_head c)]) steps ->
    rows_book = map bf_row steps ++ hit :: next :: rest ->
    hit = source_row_to_book r ->
    br_cond hit = lic_state c ++ [lic_tape c (lic_head c)] ->
    br_action hit = hit_init ++ [hit_w] ->
    br_cond next = c0 :: creast ->
    run (lic_q5_right_hit_cost lo c steps hit hit_init hit_w)
      (lic_q5_encode lo c rows_book tail) =
    lic_q5_encode lo (left_infinite_step rows c) rows_book tail.
Proof.
  intros p lo c rows r rnext rows_book tail steps hit next rest
    hit_init hit_w c0 creast Hlo Hh Hwf Hlookup Hright Hlt Hsteps
    Hrows Hhit Hcond Hact Hnext.
  subst rows_book. subst hit.
  assert (Hin : In r rows).
  { assert (Hfs := find_some
      (fun row => wide_row_matches row (lic_state c)
        (lic_tape c (lic_head c))) rows Hlookup).
    exact (proj1 Hfs). }
  assert (Hr : wide_row_wellformed p r).
  { clear Hlookup.
    induction Hwf as [|a l Ha Hl IH].
    - inversion Hin.
    - simpl in Hin. destruct Hin as [<-|Hin].
      + exact Ha.
      + apply IH. exact Hin. }
  assert (HlenAct : length (br_action (source_row_to_book r)) =
                   length (lic_state c ++ [lic_tape c (lic_head c)])).
  { rewrite <- Hcond. apply (source_row_action_length p r Hr). }
  assert (Hne : raw_ptape c lo <> []).
  { apply raw_ptape_nonempty. lia. }
  assert (Hb : left_infinite_right_blocked c r = false).
  { unfold left_infinite_right_blocked. rewrite Hright.
    destruct (Z.eqb (lic_head c) (lic_R c)) eqn:E.
    - apply Z.eqb_eq in E. lia.
    - reflexivity. }
  destruct (left_infinite_step_running_fields rows c r Hh Hlookup Hb)
    as [Hstate [Hhead [Htape [HR _]]]].
  rewrite Hright in Hhead.
  assert (Hinj : wr_next r = hit_init /\ wr_write r = hit_w).
  { apply app_inj_tail in Hact. exact Hact. }
  destruct Hinj as [Hinit Hw].
  unfold lic_q5_right_hit_cost, lic_q5_encode.
  rewrite (book_steady_q5_locate_to_q5_right_raw_gen
    (lic_state c) (lic_tape c (lic_head c)) (raw_last c lo)
    (raw_buf c) (raw_ptape_prefix c lo) tail steps
    (source_row_to_book r) next rest hit_init hit_w c0 creast
    (raw_buf_nonempty c Hlt) (raw_buf_raw c) Hsteps Hcond HlenAct
    Hact Hright Hnext).
  rewrite <- (book_q5_raw_right_frame_eq
    (lic_state c) (raw_buf c) (raw_ptape_prefix c lo)
    (raw_last c lo) (lic_tape c (lic_head c)) steps
    (source_row_to_book r) next rest hit_init hit_w c0 creast tail
    Hcond Hact Hnext).
  rewrite (raw_buf_right_step rows c r Hh Hlookup Hright Hlt).
  rewrite (raw_ptape_prefix_right_step rows c r lo Hh Hlookup Hright Hlt
    ltac:(lia)).
  rewrite (raw_last_right_step rows c r lo Hh Hlookup Hright Hlt
    ltac:(lia)).
  rewrite Hhead, Hstate.
  rewrite (raw_read_right_step rows c r Hh Hlookup Hright Hlt).
  rewrite <- (raw_ptape_prefix_last c lo Hne).
  rewrite Hinit, Hw.
  reflexivity.
Qed.

Print Assumptions lic_q5_encode_right_hit_step.

(** ** Right-hit step from a computed first match

    [lic_q5_encode_right_hit_match_step] removes the explicit
    [steps]/[hit] witnesses: it accepts the [book_first_match] result and
    a nonempty suffix.  The final encoder obtains the nonempty suffix by
    appending a trailing row after the source program. *)

Theorem lic_q5_encode_right_hit_match_step :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (r : WideSourceRow)
         (rows_book : list book_row) (tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (after : list book_row),
    (lo < lic_head c)%Z ->
    lic_halted c = false ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some r ->
    wr_right r = true ->
    (lic_head c < lic_R c)%Z ->
    book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
      rows_book = book_lookup_hit steps hit after ->
    hit = source_row_to_book r ->
    after <> [] ->
    Forall (fun br => br_cond br <> []) rows_book ->
    exists cost,
      run cost (lic_q5_encode lo c rows_book tail) =
      lic_q5_encode lo (left_infinite_step rows c) rows_book tail.
Proof.
  intros p lo c rows r rows_book tail steps hit after
    Hlo Hh Hwf Hlen Hlookup Hright Hlt Hbf Hhit Hafter Hconds.
  pose proof (book_first_match_hit_sound
    (lic_state c ++ [lic_tape c (lic_head c)])
    rows_book steps hit after Hbf) as Hsound.
  destruct Hsound as [Hrows [Hsteps Hcond]].
  destruct after as [|next rest].
  - contradiction.
  - assert (Hin : In next rows_book).
    { assert (Hin' : In next
          (map bf_row steps ++ hit :: next :: rest)).
      { apply in_or_app. right. apply in_cons. apply in_eq. }
      exact (eq_ind (map bf_row steps ++ hit :: next :: rest)
        (fun l => In next l) Hin' rows_book (eq_sym Hrows)). }
    assert (Hne : br_cond next <> []).
    { exact (proj1 (Forall_forall (fun br => br_cond br <> [])
        rows_book) Hconds next Hin). }
    destruct (br_cond next) as [|c0 creast] eqn:E.
    + contradiction.
    + exists (lic_q5_right_hit_cost lo c steps hit
                (wr_next r) (wr_write r)).
      eapply (lic_q5_encode_right_hit_step p lo c rows r r
        rows_book tail steps hit next rest (wr_next r)
        (wr_write r) c0 creast Hlo Hh Hwf Hlookup Hright Hlt
        Hsteps).
      * exact Hrows.
      * exact Hhit.
      * exact Hcond.
      * rewrite Hhit. reflexivity.
      * exact E.
Qed.

Print Assumptions lic_q5_encode_right_hit_match_step.
