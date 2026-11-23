(** * The halted encoder for the left-infinite source model

    When [wide_source_lookup] returns [None], the q5 locate phase walks
    the whole description, records every mismatching row as a
    [book_failure], and stops on the last row with a q3/Y halt.  The
    native q5 frame produced by that walk is

      dispatch_halt_at_y
        (rev (row tail ++ action ++ [dir]) ++
         match_mark (negb firstbit) ::
         rev (marked rest ++ marked prefix ++ [4] ++ marked good) ++
         raw firstbit :: rev (raw good) ++
         5 :: (rev buf ++ 6 :: rev ptape))
        tail.

    [lic_halt_encode_from] is that frame, parameterized by the failure
    list, the last failure, the raw buffer, and the raw left tape.
    [lic_halt_encode] specializes it to a [LeftInfiniteConfig] using
    [raw_buf] and [raw_ptape].

    The main theorem [lic_q5_encode_none_halt_macro] composes the q5
    entry scan with [book_locate_rows_to_halt_wide] and the lookup/halt
    correspondence [wide_source_lookup_none_book_first_match_halt].
    The boundary sentinel halt frame is proved to be the same encoder
    frame, so both halt paths share one halted-encoder family. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyMatchMacro MinskyConcreteDispatch MinskyBookLayout
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateWide
  MinskyBookLocateCycle MinskyBookLocateLookup MinskyBookRawBuffer
  MinskyBookEncode MinskyLeftInfinite MinskyLeftInfiniteEncode
  MinskyLeftInfiniteWindow MinskyLeftInfiniteLookup
  MinskyLeftInfiniteSentinel.

(** ** The halted encoder frame *)

Definition lic_halt_encode_from
    (steps : list book_failure) (last : book_failure)
    (buf ptape tail : list nat) : Config :=
  dispatch_halt_at_y
    (rev (map source_bit (bf_row_rest last) ++
          map source_bit (br_action (bf_row last)) ++
          [source_bit (br_dir (bf_row last))]) ++
     match_mark (negb (bf_bit last)) ::
     rev (map match_mark (bf_src_rest last) ++
          ((book_marked_prefix (map bf_row steps)) ++ [4]) ++
          map match_mark (bf_good last)) ++
     match_raw (bf_bit last) :: rev (map match_raw (bf_good last)) ++
     5 :: (rev buf ++ 6 :: rev ptape))
    tail.

Definition lic_halt_encode
    (lo : Z) (c : LeftInfiniteConfig)
    (steps : list book_failure) (last : book_failure)
    (tail : list nat) : Config :=
  lic_halt_encode_from steps last (raw_buf c) (raw_ptape c lo) tail.

Lemma lic_halt_encode_from_halted :
  forall steps last buf ptape tail,
    c_halted (lic_halt_encode_from steps last buf ptape tail) = true.
Proof.
  intros. unfold lic_halt_encode_from, dispatch_halt_at_y. reflexivity.
Qed.

Lemma lic_halt_encode_halted :
  forall lo c steps last tail,
    c_halted (lic_halt_encode lo c steps last tail) = true.
Proof.
  intros. apply lic_halt_encode_from_halted.
Qed.

(** ** q5 entry to the wide locate state *)

Lemma lic_q5_encode_to_locate_state_wide :
  forall (lo : Z) (c : LeftInfiniteConfig)
         (rows : list book_row) (tail : list nat),
    rows <> [] ->
    (lo < lic_head c)%Z ->
    run (S (length (lic_state c))) (lic_q5_encode lo c rows tail) =
    book_locate_state_wide
      (lic_state c ++ [lic_tape c (lic_head c)]) []
      rows (rev (raw_buf c) ++ 6 :: rev (raw_ptape c lo)) tail.
Proof.
  intros lo c rows tail Hrows Hlt.
  unfold lic_q5_encode, book_q5_raw.
  rewrite (book_q5_steady_to_locate_state_raw_gen (lic_state c)
    (lic_tape c (lic_head c)) (raw_last c lo) (raw_buf c)
    (raw_ptape_prefix c lo) tail rows Hrows).
  rewrite (raw_ptape_prefix_last c lo).
  - reflexivity.
  - apply raw_ptape_nonempty. exact Hlt.
Qed.

Print Assumptions lic_q5_encode_to_locate_state_wide.

(** ** Lookup failure reaches the halted encoder *)

Theorem lic_q5_encode_none_halt_macro :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (tail : list nat),
    (lo < lic_head c)%Z ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    rows <> [] ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = None ->
    exists steps last,
      book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
        (source_rows_to_book rows) = book_lookup_halt steps last /\
      run (S (length (lic_state c)) +
           (book_failures_clock [] steps +
            book_halt_clock (map bf_row steps) last))
        (lic_q5_encode lo c (source_rows_to_book rows) tail) =
      lic_halt_encode lo c steps last tail /\
      c_halted (lic_halt_encode lo c steps last tail) = true.
Proof.
  intros p lo c rows tail Hlt Hwf Hlen Hne Hnone.
  destruct (wide_source_lookup_none_book_first_match_halt p rows
    (lic_state c) (lic_tape c (lic_head c)) Hwf Hlen Hne Hnone)
    as [steps [last [Hbf [Hforall Hrows]]]].
  assert (Hne_book : source_rows_to_book rows <> []).
  { intro Hnil. apply Hne.
    apply (@map_eq_nil WideSourceRow book_row source_row_to_book rows Hnil). }
  exists steps, last.
  split; [exact Hbf|]. split.
  - rewrite (dispatch_run_add (S (length (lic_state c)))
      (book_failures_clock [] steps +
       book_halt_clock (map bf_row steps) last)).
    rewrite (lic_q5_encode_to_locate_state_wide lo c
      (source_rows_to_book rows) tail Hne_book Hlt).
    rewrite Hrows.
    change (run (book_failures_clock [] steps +
                 book_halt_clock ([] ++ map bf_row steps) last)
              (book_locate_state_wide
                 (lic_state c ++ [lic_tape c (lic_head c)]) []
                 (map bf_row (steps ++ [last]))
                 (rev (raw_buf c) ++ 6 :: rev (raw_ptape c lo)) tail) =
            lic_halt_encode lo c steps last tail).
    rewrite (book_locate_rows_to_halt_wide
      (lic_state c ++ [lic_tape c (lic_head c)]) [] steps last
      (rev (raw_buf c) ++ 6 :: rev (raw_ptape c lo)) tail Hforall).
    unfold lic_halt_encode, lic_halt_encode_from.
    reflexivity.
  - apply lic_halt_encode_halted.
Qed.

Print Assumptions lic_q5_encode_none_halt_macro.

(** The same statement with the halted source configuration, which is
    what the general encoder's next frame asks for.  Haltedness of [c]
    is not needed: the [None] branch of [left_infinite_step] preserves
    every field used by [raw_buf] and [raw_ptape]. *)

Lemma lic_halt_encode_step :
  forall (lo : Z) (c : LeftInfiniteConfig) (rows : list WideSourceRow)
         (steps : list book_failure) (last : book_failure)
         (tail : list nat),
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = None ->
    lic_halt_encode lo (left_infinite_step rows c) steps last tail =
    lic_halt_encode lo c steps last tail.
Proof.
  intros lo c rows steps last tail Hnone.
  unfold lic_halt_encode.
  destruct (lic_halted c) eqn:Eh.
  - unfold left_infinite_step. rewrite Eh. reflexivity.
  - unfold left_infinite_step. rewrite Eh, Hnone. reflexivity.
Qed.

Corollary lic_q5_encode_none_halt_step_macro :
  forall (p : nat) (lo : Z) (c : LeftInfiniteConfig)
         (rows : list WideSourceRow) (tail : list nat),
    (lo < lic_head c)%Z ->
    Forall (wide_row_wellformed p) rows ->
    length (lic_state c) = p ->
    rows <> [] ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = None ->
    exists steps last,
      book_first_match (lic_state c ++ [lic_tape c (lic_head c)])
        (source_rows_to_book rows) = book_lookup_halt steps last /\
      run (S (length (lic_state c)) +
           (book_failures_clock [] steps +
            book_halt_clock (map bf_row steps) last))
        (lic_q5_encode lo c (source_rows_to_book rows) tail) =
      lic_halt_encode lo (left_infinite_step rows c) steps last tail.
Proof.
  intros p lo c rows tail Hlt Hwf Hlen Hne Hnone.
  destruct (lic_q5_encode_none_halt_macro p lo c rows tail
    Hlt Hwf Hlen Hne Hnone) as [steps [last [Hbf [Hrun Hhalt]]]].
  exists steps, last. split; [exact Hbf|].
  rewrite Hrun.
  symmetry. apply lic_halt_encode_step. exact Hnone.
Qed.

Print Assumptions lic_q5_encode_none_halt_step_macro.

(** ** The boundary sentinel halt frame is the same encoder family *)

Lemma boundary_sentinel_halt_frame_is_halt_encode_from :
  forall (ptape : list nat) (w_tape hit_w : bool) (tail : list nat)
         (retry_steps : list book_failure)
         (hit_init creast : list bool),
    boundary_sentinel_halt_frame ptape w_tape hit_w tail retry_steps
      hit_init creast =
    lic_halt_encode_from retry_steps
      (boundary_sentinel_sf hit_init creast)
      (book_buf 0)
      (ptape ++ [source_bit w_tape] ++ [source_bit hit_w]) tail.
Proof.
  intros. unfold boundary_sentinel_halt_frame, lic_halt_encode_from,
    book_sentinel_halt_left.
  cbn [book_buf].
  reflexivity.
Qed.

Theorem boundary_sentinel_halt_frame_eq_lic_halt_encode :
  forall (lo : Z) (c : LeftInfiniteConfig) (ptape : list nat)
         (w_tape hit_w : bool) (tail : list nat)
         (retry_steps : list book_failure)
         (hit_init creast : list bool),
    raw_buf c = [] ->
    raw_ptape c lo = ptape ++ [source_bit w_tape] ++ [source_bit hit_w] ->
    boundary_sentinel_halt_frame ptape w_tape hit_w tail retry_steps
      hit_init creast =
    lic_halt_encode lo c retry_steps
      (boundary_sentinel_sf hit_init creast) tail.
Proof.
  intros lo c ptape w_tape hit_w tail retry_steps hit_init creast
    Hbuf Hptape.
  rewrite boundary_sentinel_halt_frame_is_halt_encode_from.
  unfold lic_halt_encode.
  rewrite Hbuf, Hptape.
  reflexivity.
Qed.

Lemma boundary_sentinel_halt_frame_halted :
  forall ptape w_tape hit_w tail retry_steps hit_init creast,
    c_halted (boundary_sentinel_halt_frame ptape w_tape hit_w tail
      retry_steps hit_init creast) = true.
Proof.
  intros. apply lic_halt_encode_from_halted.
Qed.

Print Assumptions boundary_sentinel_halt_frame_eq_lic_halt_encode.

(** ** Raw invariants for the sentinel boundary step *)

Lemma raw_ptape_write_succ :
  forall (t : Z -> bool) (h lo : Z) (b : bool),
    (lo <= h)%Z ->
    map (fun (k : nat) => source_bit (source_write_at t h b ((lo + Z.of_nat k)%Z)))
      (seq 0 (Z.to_nat ((h + 1 - lo)%Z))) =
    map (fun (k : nat) => source_bit (t ((lo + Z.of_nat k)%Z)))
      (seq 0 (Z.to_nat ((h - lo)%Z))) ++ [source_bit b].
Proof.
  intros t h lo b Hle.
  set (n := Z.to_nat ((h - lo)%Z)).
  assert (Hn : Z.of_nat n = (h - lo)%Z).
  { unfold n. apply Z2Nat.id. lia. }
  assert (Hlen : Z.to_nat ((h + 1 - lo)%Z) = S n).
  { unfold n.
    rewrite <- (Z2Nat.inj_succ ((h - lo)%Z)) by lia.
    f_equal. lia. }
  rewrite Hlen.
  replace (seq 0 (S n)) with (seq 0 n ++ [n]).
  2:{ rewrite (seq_S n 0). cbn. reflexivity. }
  rewrite map_app. cbn [map].
  assert (Hmap :
    map (fun (k : nat) => source_bit (source_write_at t h b ((lo + Z.of_nat k)%Z)))
      (seq 0 n) =
    map (fun (k : nat) => source_bit (t ((lo + Z.of_nat k)%Z))) (seq 0 n)).
  { apply map_ext_in. intros k Hk.
    apply in_seq in Hk. destruct Hk as [_ Hklt].
    assert (Hzlt : ((lo + Z.of_nat k)%Z < h)%Z).
    { pose proof (inj_lt k n Hklt) as H.
      rewrite Hn in H. lia. }
    rewrite (source_write_at_below t h ((lo + Z.of_nat k)%Z) b Hzlt).
    reflexivity. }
  rewrite Hmap.
  assert (Hlast : (lo + Z.of_nat n = h)%Z) by lia.
  rewrite Hlast.
  unfold source_write_at. rewrite Z.eqb_refl. reflexivity.
Qed.

Lemma raw_buf_sentinel_step_boundary :
  forall (rows : list WideSourceRow) (c : LeftInfiniteConfig)
         (row : WideSourceRow),
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    raw_buf (left_infinite_step_sentinel rows c) = [].
Proof.
  intros rows c row Hh Hlookup Hb.
  destruct (left_infinite_step_sentinel_boundary_fields rows c row
    Hh Hlookup Hb) as [_ [Hhead [_ [HR _]]]].
  apply raw_buf_nil_of_boundary.
  rewrite Hhead, HR.
  unfold left_infinite_right_blocked in Hb.
  apply Bool.andb_true_iff in Hb. destruct Hb as [_ Heq].
  apply Z.eqb_eq in Heq. lia.
Qed.

Lemma raw_ptape_sentinel_step_boundary :
  forall (rows : list WideSourceRow) (c : LeftInfiniteConfig)
         (row : WideSourceRow) (lo : Z),
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    (lo <= lic_head c)%Z ->
    raw_ptape (left_infinite_step_sentinel rows c) lo =
    raw_ptape c lo ++ [source_bit (wr_write row)].
Proof.
  intros rows c row lo Hh Hlookup Hb Hle.
  destruct (left_infinite_step_sentinel_boundary_fields rows c row
    Hh Hlookup Hb) as [_ [Hhead [Htape _]]].
  unfold raw_ptape.
  rewrite Hhead, Htape.
  transitivity
    (map (fun (k : nat) =>
            source_bit (source_write_at (lic_tape c) (lic_head c)
                          (wr_write row) ((lo + Z.of_nat k)%Z)))
      (seq 0 (Z.to_nat ((lic_head c + 1 - lo)%Z)))).
  - apply map_ext_in. intros k Hk.
    apply in_seq in Hk. destruct Hk as [_ Hklt].
    unfold source_blank_at.
    destruct (Z.eqb ((lo + Z.of_nat k)%Z) (lic_head c + 1)) eqn:E.
    + apply Z.eqb_eq in E.
      pose proof (inj_lt k (Z.to_nat ((lic_head c + 1 - lo)%Z)) Hklt) as Hlt.
      assert (Hz : Z.of_nat (Z.to_nat ((lic_head c + 1 - lo)%Z)) =
                  (lic_head c + 1 - lo)%Z)
        by (apply Z2Nat.id; lia).
      rewrite Hz in Hlt. lia.
    + reflexivity.
  - apply raw_ptape_write_succ. exact Hle.
Qed.

Theorem boundary_sentinel_halt_frame_eq_sentinel_step :
  forall (lo : Z) (rows : list WideSourceRow) (c : LeftInfiniteConfig)
         (row : WideSourceRow) (ptape : list nat)
         (w_tape hit_w : bool) (tail : list nat)
         (retry_steps : list book_failure)
         (hit_init creast : list bool),
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c) (lic_tape c (lic_head c)) = Some row ->
    left_infinite_right_blocked c row = true ->
    (lo <= lic_head c)%Z ->
    raw_ptape c lo = ptape ++ [source_bit w_tape] ->
    wr_write row = hit_w ->
    boundary_sentinel_halt_frame ptape w_tape hit_w tail retry_steps
      hit_init creast =
    lic_halt_encode lo (left_infinite_step_sentinel rows c) retry_steps
      (boundary_sentinel_sf hit_init creast) tail.
Proof.
  intros lo rows c row ptape w_tape hit_w tail retry_steps hit_init
    creast Hh Hlookup Hb Hle Hptape Hwrite.
  apply boundary_sentinel_halt_frame_eq_lic_halt_encode.
  - exact (raw_buf_sentinel_step_boundary rows c row Hh Hlookup Hb).
  - rewrite (raw_ptape_sentinel_step_boundary rows c row lo
      Hh Hlookup Hb Hle).
    rewrite Hptape, Hwrite. rewrite <- app_assoc. reflexivity.
Qed.

Print Assumptions boundary_sentinel_halt_frame_eq_sentinel_step.
