(** * Lookup witness compiler for the book locate phase

    [book_first_match] computes the list of failed rows before the first
    matching row, with a concrete [book_failure] witness for each, or the
    full failure list ending in a last-row failure when no row matches.
    The correctness lemmas feed the computed witnesses directly into
    [book_locate_rows_to_q6] and [book_locate_rows_to_halt].

    The mismatch search is proof-carrying: [book_mismatch_ev] returns the
    common prefix, mismatching bit, and both rests together with the
    equations that make them a valid [book_failure] witness.  This keeps
    the compiler fully computable while avoiding any caller-supplied
    failure proof. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry MinskyConcreteDispatch
  MinskySourceEncoding MinskyMatchMacro MinskyCanonicalMatch
  MinskyActionMacro MinskyCanonicalCopy MinskyCanonicalCopyGeneral
  MinskyCanonicalDirection MinskyCanonicalInstruction MinskyHeadMoveMacro
  MinskyCanonicalRestore MinskyDirectionDecision MinskyRelocationMacro
  MinskyBookLayout MinskyBookCycle MinskyBookLeftCycle
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateCycle.

(** ** First difference with its proof *)

Definition book_mismatch_type (src cond : list bool) : Type :=
  { p : list bool * bool * list bool * list bool |
    let '(good, bad, srest, rrest) := p in
    src = good ++ bad :: srest /\
    cond = good ++ negb bad :: rrest }.

Definition book_mismatch_extend
    (b : bool) (src' cond' : list bool)
    (e : book_mismatch_type src' cond') :
    book_mismatch_type (b :: src') (b :: cond').
Proof.
  destruct e as [p Hp].
  destruct p as [[[good bad] srest] rrest].
  destruct Hp as [Hsrc Hcond].
  exact (exist _ (b :: good, bad, srest, rrest)
    (conj (f_equal (cons b) Hsrc) (f_equal (cons b) Hcond))).
Defined.

Fixpoint book_mismatch_ev (src cond : list bool) {struct src}
  : option (book_mismatch_type src cond).
Proof.
  destruct src as [|b src'].
  - destruct cond as [|c cond']; exact None.
  - destruct cond as [|c cond'].
    + exact None.
    + destruct b, c.
      * exact (match book_mismatch_ev src' cond' with
               | Some e => Some (book_mismatch_extend true src' cond' e)
               | None => None
               end).
      * exact (Some (exist _ ([], true, src', cond')
          (conj eq_refl eq_refl))).
      * exact (Some (exist _ ([], false, src', cond')
          (conj eq_refl eq_refl))).
      * exact (match book_mismatch_ev src' cond' with
               | Some e => Some (book_mismatch_extend false src' cond' e)
               | None => None
               end).
Defined.

Lemma book_mismatch_ev_none_eq :
  forall src cond,
    length src = length cond ->
    book_mismatch_ev src cond = None ->
    src = cond.
Proof.
  induction src as [|b src' IH]; intros cond Hlen Hnone.
  - destruct cond as [|c cond']; [reflexivity|].
    cbn in Hlen. discriminate.
  - destruct cond as [|c cond']; [cbn in Hlen; discriminate|].
    cbn [book_mismatch_ev] in Hnone.
    destruct b, c.
    + destruct (book_mismatch_ev src' cond') as [e|] eqn:Hrec.
      * cbn in Hnone. discriminate.
      * f_equal. apply (IH cond').
        -- cbn in Hlen. lia.
        -- exact Hrec.
    + cbn in Hnone. discriminate.
    + cbn in Hnone. discriminate.
    + destruct (book_mismatch_ev src' cond') as [e|] eqn:Hrec.
      * cbn in Hnone. discriminate.
      * f_equal. apply (IH cond').
        -- cbn in Hlen. lia.
        -- exact Hrec.
Qed.

(** ** Building a failure from the proof-carrying mismatch *)

Definition book_failure_of_split
    (src : list bool) (r : book_row)
    (good : list bool) (bad : bool) (srest rrest : list bool)
    (H : src = good ++ bad :: srest /\
         br_cond r = good ++ negb bad :: rrest) : book_failure :=
  {| bf_src := src;
     bf_row := r;
     bf_good := good;
     bf_bit := bad;
     bf_src_rest := srest;
     bf_row_rest := rrest;
     bf_src_split := proj1 H;
     bf_row_split := proj2 H |}.

(** ** Lookup result *)

Inductive book_lookup_result : Type :=
| book_lookup_hit (steps : list book_failure) (hit : book_row)
    (after : list book_row)
| book_lookup_halt (steps : list book_failure) (last : book_failure)
| book_lookup_bad.

Definition book_row_matches (src : list bool) (r : book_row) : bool :=
  (Nat.eqb (length (br_cond r)) (length src)) &&
  match book_mismatch_ev src (br_cond r) with
  | Some _ => false
  | None => true
  end.

Lemma book_row_matches_true :
  forall src r,
    book_row_matches src r = true ->
    br_cond r = src.
Proof.
  intros src r H. unfold book_row_matches in H.
  apply andb_true_iff in H. destruct H as [Hlen Hmm].
  apply Nat.eqb_eq in Hlen.
  destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:Hev.
  - cbn in Hmm. discriminate.
  - symmetry. apply (book_mismatch_ev_none_eq src (br_cond r) (eq_sym Hlen) Hev).
Qed.

Lemma book_row_matches_false_ev :
  forall src r,
    length (br_cond r) = length src ->
    book_row_matches src r = false ->
    exists e, book_mismatch_ev src (br_cond r) = Some e.
Proof.
  intros src r Hlen H.
  unfold book_row_matches in H.
  assert (Hlenb : Nat.eqb (length (br_cond r)) (length src) = true).
  { apply Nat.eqb_eq. exact Hlen. }
  rewrite Hlenb in H. cbn in H.
  destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:Hev.
  - exists e. reflexivity.
  - cbn in H. discriminate.
Qed.

(** ** The compiler *)

Definition book_lookup_cons_of
    (src : list bool) (r : book_row) (rest : list book_row)
    (tail_result : book_lookup_result)
    (m : option (book_mismatch_type src (br_cond r))) : book_lookup_result :=
  match m with
  | Some (exist _ (good, bad, srest, rrest) Hp) =>
      let f := book_failure_of_split src r good bad srest rrest Hp in
      match rest with
      | [] => book_lookup_halt [] f
      | _ =>
          match tail_result with
          | book_lookup_hit steps hit after =>
              book_lookup_hit (f :: steps) hit after
          | book_lookup_halt steps last =>
              book_lookup_halt (f :: steps) last
          | book_lookup_bad => book_lookup_bad
          end
      end
  | None => book_lookup_bad
  end.

Definition book_lookup_cons
    (src : list bool) (r : book_row) (rest : list book_row)
    (tail_result : book_lookup_result) : book_lookup_result :=
  book_lookup_cons_of src r rest tail_result
    (book_mismatch_ev src (br_cond r)).

Fixpoint book_first_match (src : list bool) (rows : list book_row)
    : book_lookup_result :=
  match rows with
  | [] => book_lookup_bad
  | r :: rest =>
      if book_row_matches src r then
        book_lookup_hit [] r rest
      else
        book_lookup_cons src r rest (book_first_match src rest)
  end.

(** ** Correctness of the computed witnesses *)

Lemma book_first_match_hit_sound :
  forall src rows steps hit after,
    book_first_match src rows = book_lookup_hit steps hit after ->
    rows = map bf_row steps ++ hit :: after /\
    Forall (fun st => bf_src st = src) steps /\
    br_cond hit = src.
Proof.
  induction rows as [|r rest IH]; intros steps hit after H.
  - cbn in H. discriminate.
  - cbn [book_first_match] in H.
    destruct (book_row_matches src r) eqn:Hm.
    + inversion H; subst.
      split; [reflexivity|]. split.
      * constructor.
      * apply book_row_matches_true in Hm. exact Hm.
    + unfold book_lookup_cons in H.
      unfold book_lookup_cons_of in H.
      destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:Hev.
      * destruct e as [p Hp].
        destruct p as [[[good bad] srest] rrest].
        destruct rest as [|r' rest'].
        -- cbn in H. discriminate.
        -- destruct (book_first_match src (r' :: rest'))
             as [steps0 hit0 after0|steps0 last0|] eqn:Hrec.
           ++ cbn in H. inversion H; subst.
              destruct (IH steps0 hit after eq_refl)
                as [Hrows [Hforall Hcondhit]].
              split; [|split].
              ** simpl. rewrite Hrows. reflexivity.
              ** constructor; [reflexivity|exact Hforall].
              ** exact Hcondhit.
           ++ discriminate.
           ++ discriminate.
      * cbn in H. discriminate.
Qed.

Lemma book_first_match_halt_sound :
  forall src rows steps last,
    book_first_match src rows = book_lookup_halt steps last ->
    rows = map bf_row (steps ++ [last]) /\
    Forall (fun st => bf_src st = src) (steps ++ [last]).
Proof.
  induction rows as [|r rest IH]; intros steps last H.
  - cbn in H. discriminate.
  - cbn [book_first_match] in H.
    destruct (book_row_matches src r) eqn:Hm.
    + inversion H.
    + unfold book_lookup_cons in H.
      unfold book_lookup_cons_of in H.
      destruct (book_mismatch_ev src (br_cond r)) as [e|] eqn:Hev.
      * destruct e as [p Hp].
        destruct p as [[[good bad] srest] rrest].
        destruct rest as [|r' rest'].
        -- cbn in H. inversion H; subst.
           split.
           ++ reflexivity.
           ++ constructor; [reflexivity|constructor].
        -- destruct (book_first_match src (r' :: rest'))
             as [steps0 hit0 after0|steps0 last0|] eqn:Hrec.
           ++ cbn in H. discriminate.
           ++ cbn in H. inversion H; subst.
              destruct (IH steps0 last eq_refl) as [Hrows Hforall].
              split.
              ** rewrite Hrows. reflexivity.
              ** constructor; [reflexivity|exact Hforall].
           ++ discriminate.
      * cbn in H. discriminate.
Qed.

(** ** Bad result only from an empty or ill-sized description *)

Definition book_rows_sized (src : list bool) (rows : list book_row) : Prop :=
  Forall (fun r => length (br_cond r) = length src) rows.

Lemma book_first_match_not_bad_aux :
  forall n src rows,
    length rows <= n ->
    rows <> [] ->
    book_rows_sized src rows ->
    book_first_match src rows <> book_lookup_bad.
Proof.
  induction n as [|n IH]; intros src rows Hlen Hne Hsized.
  - destruct rows as [|r rest]; [contradiction|]. cbn in Hlen. lia.
  - destruct rows as [|r rest]; [contradiction|].
    cbn [book_first_match].
    destruct (book_row_matches src r) eqn:Hm.
    + discriminate.
    + unfold book_lookup_cons, book_lookup_cons_of.
      inversion Hsized as [|? ? Hr Hrest]; subst.
      destruct (book_row_matches_false_ev src r Hr Hm) as [e Hev].
      rewrite Hev.
      destruct e as [p Hp].
      destruct p as [[[good bad] srest] rrest].
      destruct rest as [|r' rest'].
      * cbn. discriminate.
      * destruct (book_first_match src (r' :: rest'))
          as [steps hit after|steps last|] eqn:Hrec.
        -- discriminate.
        -- discriminate.
        -- exfalso.
           apply (IH src (r' :: rest')).
           ++ cbn in Hlen |- *. lia.
           ++ discriminate.
           ++ exact Hrest.
           ++ exact Hrec.
Qed.

Lemma book_first_match_not_bad :
  forall src rows,
    rows <> [] ->
    book_rows_sized src rows ->
    book_first_match src rows <> book_lookup_bad.
Proof.
  intros src rows Hne Hsized.
  apply (book_first_match_not_bad_aux (length rows) src rows); auto; lia.
Qed.

(** ** Discharging the locate invariant by computation *)

Theorem book_locate_by_computation_to_q6 :
  forall (src : list bool) (failed : list book_row) (rows : list book_row)
         (steps : list book_failure) (hit : book_row) (after : list book_row)
         (buf : nat) (ptape tail : list nat),
    book_first_match src rows = book_lookup_hit steps hit after ->
    run (book_failures_clock failed steps +
         book_hit_clock src (failed ++ map bf_row steps))
      (book_locate_state src failed rows buf ptape tail)
    = entry_config 6
        (4 :: rev (map source_bit src) ++
         5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
        (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
         map match_mark src ++
         map source_bit (br_action hit) ++
         [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail).
Proof.
  intros src failed rows steps hit after buf ptape tail H.
  destruct (book_first_match_hit_sound src rows steps hit after H)
    as [Hrows [Hforall Hcond]].
  rewrite Hrows.
  apply (book_locate_rows_to_q6 src failed steps hit after buf ptape tail
    Hforall Hcond).
Qed.

Print Assumptions book_locate_by_computation_to_q6.

Theorem book_locate_by_computation_to_halt :
  forall (src : list bool) (failed : list book_row) (rows : list book_row)
         (steps : list book_failure) (last : book_failure)
         (buf : nat) (ptape tail : list nat),
    book_first_match src rows = book_lookup_halt steps last ->
    run (book_failures_clock failed steps +
         book_halt_clock (failed ++ map bf_row steps) last)
      (book_locate_state src failed rows buf ptape tail)
    = dispatch_halt_at_y
        (rev (map source_bit (bf_row_rest last) ++
              map source_bit (br_action (bf_row last)) ++
              [source_bit (br_dir (bf_row last))]) ++
         match_mark (negb (bf_bit last)) ::
         rev (map match_mark (bf_src_rest last) ++
              ((book_marked_prefix (failed ++ map bf_row steps)) ++ [4]) ++
              map match_mark (bf_good last)) ++
         match_raw (bf_bit last) :: rev (map match_raw (bf_good last)) ++
         5 :: (rev (book_buf buf) ++ 6 :: rev ptape))
        tail.
Proof.
  intros src failed rows steps last buf ptape tail H.
  destruct (book_first_match_halt_sound src rows steps last H)
    as [Hrows Hforall].
  rewrite Hrows.
  apply (book_locate_rows_to_halt src failed steps last buf ptape tail
    Hforall).
Qed.

Print Assumptions book_locate_by_computation_to_halt.

(** ** Completeness of the match test *)

Lemma book_mismatch_ev_eq_none :
  forall src cond,
    src = cond ->
    book_mismatch_ev src cond = None.
Proof.
  intros src cond H. subst cond.
  induction src as [|b src' IH].
  - reflexivity.
  - cbn [book_mismatch_ev]. destruct b; cbn; rewrite IH; reflexivity.
Qed.

Lemma book_row_matches_true_of_eq :
  forall src r,
    br_cond r = src ->
    book_row_matches src r = true.
Proof.
  intros src r H. unfold book_row_matches.
  subst src. rewrite Nat.eqb_refl.
  rewrite (book_mismatch_ev_eq_none (br_cond r) (br_cond r) eq_refl).
  reflexivity.
Qed.

(** Every computed failure really excludes its row. *)

Lemma book_failure_row_neq :
  forall (st : book_failure),
    bf_src st <> br_cond (bf_row st).
Proof.
  intros st H.
  rewrite (bf_src_split st) in H.
  rewrite (bf_row_split st) in H.
  revert H. generalize (bf_good st) as good.
  induction good as [|g gs IH]; intros H.
  - cbn in H. injection H as Hbad _.
    destruct (bf_bit st); cbn in Hbad; discriminate Hbad.
  - cbn in H. injection H as Hg. apply (IH Hg).
Qed.

Print Assumptions book_row_matches_true_of_eq.
Print Assumptions book_failure_row_neq.

(** ** Computation from the steady q5 state *)

Theorem book_locate_by_computation_from_q5_to_q6 :
  forall (init : list bool) (w_read w_tape : bool) (b : nat)
         (ptape tail : list nat) (rows : list book_row)
         (steps : list book_failure) (hit : book_row) (after : list book_row),
    1 <= b ->
    rows <> [] ->
    book_first_match (init ++ [w_read]) rows =
      book_lookup_hit steps hit after ->
    run (S (length init) +
         (book_failures_clock [] steps +
          book_hit_clock (init ++ [w_read]) (map bf_row steps)))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 :: book_raw_desc rows ++ 5 :: tail))
    = entry_config 6
        (4 :: rev (map source_bit (init ++ [w_read])) ++
         5 :: (rev (book_buf (b - 1)) ++
               6 :: rev (ptape ++ [source_bit w_tape])))
        (tl (book_marked_prefix ([] ++ map bf_row steps) ++ [4]) ++
         map match_mark (init ++ [w_read]) ++
         map source_bit (br_action hit) ++
         [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail).
Proof.
  intros init w_read w_tape b ptape tail rows steps hit after
    Hb Hrows_ne Hmatch.
  rewrite (dispatch_run_add (S (length init))
    (book_failures_clock [] steps +
     book_hit_clock (init ++ [w_read]) (map bf_row steps))).
  rewrite (book_q5_steady_to_locate_state_gen init w_read w_tape b ptape tail
    rows Hb Hrows_ne).
  apply (book_locate_by_computation_to_q6 (init ++ [w_read]) [] rows steps hit
    after (b - 1) (ptape ++ [source_bit w_tape]) tail Hmatch).
Qed.

Print Assumptions book_locate_by_computation_from_q5_to_q6.

Theorem book_locate_by_computation_from_q5_to_halt :
  forall (init : list bool) (w_read w_tape : bool) (b : nat)
         (ptape tail : list nat) (rows : list book_row)
         (steps : list book_failure) (last : book_failure),
    1 <= b ->
    rows <> [] ->
    book_first_match (init ++ [w_read]) rows =
      book_lookup_halt steps last ->
    run (S (length init) +
         (book_failures_clock [] steps +
          book_halt_clock (map bf_row steps) last))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 :: book_raw_desc rows ++ 5 :: tail))
    = dispatch_halt_at_y
        (rev (map source_bit (bf_row_rest last) ++
              map source_bit (br_action (bf_row last)) ++
              [source_bit (br_dir (bf_row last))]) ++
         match_mark (negb (bf_bit last)) ::
         rev (map match_mark (bf_src_rest last) ++
              ((book_marked_prefix ([] ++ map bf_row steps)) ++ [4]) ++
              map match_mark (bf_good last)) ++
         match_raw (bf_bit last) :: rev (map match_raw (bf_good last)) ++
         5 :: (rev (book_buf (b - 1)) ++
               6 :: rev (ptape ++ [source_bit w_tape])))
        tail.
Proof.
  intros init w_read w_tape b ptape tail rows steps last
    Hb Hrows_ne Hmatch.
  rewrite (dispatch_run_add (S (length init))
    (book_failures_clock [] steps +
     book_halt_clock (map bf_row steps) last)).
  rewrite (book_q5_steady_to_locate_state_gen init w_read w_tape b ptape tail
    rows Hb Hrows_ne).
  apply (book_locate_by_computation_to_halt (init ++ [w_read]) [] rows steps
    last (b - 1) (ptape ++ [source_bit w_tape]) tail Hmatch).
Qed.

Print Assumptions book_locate_by_computation_from_q5_to_halt.

(** A halt result really means that no row in the description matches. *)

Lemma book_first_match_halt_no_match :
  forall src rows steps last,
    book_first_match src rows = book_lookup_halt steps last ->
    forall r, In r (map bf_row (steps ++ [last])) -> br_cond r <> src.
Proof.
  intros src rows steps last H r Hin.
  destruct (book_first_match_halt_sound src rows steps last H)
    as [_ Hforall].
  apply in_map_iff in Hin.
  destruct Hin as [st [Hst Hinst]].
  subst r.
  intro Hcond.
  assert (Hsrc : bf_src st = src).
  { apply (proj1 (Forall_forall (fun st => bf_src st = src)
      (steps ++ [last])) Hforall). exact Hinst. }
  apply (book_failure_row_neq st).
  rewrite Hsrc, Hcond. reflexivity.
Qed.

Print Assumptions book_first_match_halt_no_match.

(** The rows skipped before a hit are exactly the nonmatching rows. *)

Lemma book_first_match_hit_first :
  forall src rows steps hit after,
    book_first_match src rows = book_lookup_hit steps hit after ->
    Forall (fun r => br_cond r <> src) (map bf_row steps).
Proof.
  intros src rows steps hit after H.
  destruct (book_first_match_hit_sound src rows steps hit after H)
    as [_ [Hforall _]].
  clear H.
  induction Hforall as [|st rest Hst Hrest IH].
  - constructor.
  - simpl. constructor.
    + intro Hcond. apply (book_failure_row_neq st).
      rewrite Hst, Hcond. reflexivity.
    + exact IH.
Qed.

Print Assumptions book_first_match_hit_first.
