(** * Iteration frames and the q5 encoder for the raw book cycles

    The raw right/left cycle theorems end at literal [cfg_ml] frames.
    This file closes the frame equalities that turn those outputs into
    the next [book_q5_raw] frame, defines [lic_q5_encode] from a
    [LeftInfiniteConfig], and states the non-boundary macro step with
    [book_first_match] witnesses.

    The first part is pure list algebra on the restored q15 rail:

      map q16_restore (rev (book_cycle_tags steps bits hit)) ++
      source_bit c0 :: book_after_suffix creast next rest
      = book_raw_desc (map bf_row steps ++ hit :: next :: rest).

    This is the identity needed by both the right and the left cycle. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyConcreteEntry MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalInstruction MinskyDirectionDecision
  MinskyRelocationMacro MinskyHeadMoveMacro MinskyCanonicalRestore
  MinskyBookLayout MinskyBookCycle MinskyBookLeft MinskyBookLeftCycle
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateWide
  MinskyBookLocateCycle MinskyBookLocateLookup MinskyBookEncode
  MinskyBookRawBuffer MinskyLeftInfinite.

(** ** Restored rail algebra *)

Lemma q16_restore_match_mark :
  forall b, q16_restore (match_mark b) = source_bit b.
Proof. intros []; reflexivity. Qed.

Lemma map_q16_restore_match_marks :
  forall (bits : list bool),
    map q16_restore (map match_mark bits) = map source_bit bits.
Proof.
  intros bits. induction bits as [|b rest IH]; simpl.
  - reflexivity.
  - rewrite q16_restore_match_mark. f_equal. exact IH.
Qed.

Lemma map_q16_restore_marked_row :
  forall (r : book_row),
    map q16_restore (book_marked_row r) = book_raw_row r.
Proof.
  intros r. unfold book_marked_row, book_raw_row.
  rewrite map_app. cbn [map q16_restore].
  rewrite map_app. cbn [map q16_restore].
  rewrite map_q16_restore_match_marks.
  rewrite map_q16_restore_match_marks.
  rewrite q16_restore_match_mark.
  reflexivity.
Qed.

Lemma map_q16_restore_marked_prefix :
  forall (rows : list book_row),
    rows <> [] ->
    map q16_restore (book_marked_prefix rows) =
    4 :: book_raw_desc rows.
Proof.
  intros rows. induction rows as [|r rest IH]; intros Hne.
  - contradiction.
  - change (map q16_restore
        (4 :: book_marked_row r ++ book_marked_prefix rest) =
      4 :: book_raw_desc (r :: rest)).
    cbn [map].
    rewrite map_app.
    rewrite map_q16_restore_marked_row.
    destruct rest as [|r' rest'].
    + cbn [book_marked_prefix app book_raw_desc].
      rewrite app_nil_r. cbn [q16_restore map].
      rewrite app_nil_r.
      repeat rewrite <- app_assoc. reflexivity.
    + simpl [book_raw_desc].
      change (4 :: book_raw_row r ++
              map q16_restore (book_marked_prefix (r' :: rest')) =
              4 :: book_raw_row r ++
              4 :: book_raw_desc (r' :: rest')).
      rewrite IH by discriminate.
      cbn [book_raw_desc book_raw_row app].
      repeat rewrite <- app_assoc. reflexivity.
Qed.

Lemma map_tl :
  forall (A B : Type) (f : A -> B) (l : list A),
    l <> [] -> map f (tl l) = tl (map f l).
Proof.
  intros A B f l Hne.
  destruct l as [|x xs]; [contradiction|reflexivity].
Qed.

Lemma map_q16_restore_cycle_region :
  forall (steps : list book_failure),
    map q16_restore (book_cycle_region steps) =
    match steps with
    | [] => []
    | _ => book_raw_desc (map bf_row steps) ++ [4]
    end.
Proof.
  intros steps. destruct steps as [|st rest].
  - reflexivity.
  - unfold book_cycle_region.
    set (rows := map bf_row (st :: rest)).
    assert (Hne : rows <> []).
    { unfold rows. simpl. discriminate. }
    rewrite (map_tl nat nat q16_restore
      (book_marked_prefix rows ++ [4])).
    2:{ simpl. discriminate. }
    rewrite map_app. cbn [map q16_restore].
    rewrite (map_q16_restore_marked_prefix rows Hne).
    cbn [app]. reflexivity.
Qed.

Lemma book_raw_desc_append_rows :
  forall (rows : list book_row) (hit next : book_row)
         (rest : list book_row),
    rows <> [] ->
    book_raw_desc (rows ++ hit :: next :: rest) =
    book_raw_desc rows ++ [4] ++ book_raw_row hit ++ [4] ++
    book_raw_desc (next :: rest).
Proof.
  intros rows. induction rows as [|r rs IH]; intros hit next rest Hne.
  - contradiction.
  - destruct rs as [|r' rs'].
    + cbn [app book_raw_desc book_raw_row].
      repeat rewrite <- app_assoc.
      reflexivity.
    + change (book_raw_row r ++ 4 ::
          book_raw_desc ((r' :: rs') ++ hit :: next :: rest) =
          (book_raw_row r ++ 4 :: book_raw_desc (r' :: rs')) ++
          [4] ++ book_raw_row hit ++ [4] ++ book_raw_desc (next :: rest)).
      rewrite (IH hit next rest) by discriminate.
      repeat rewrite <- app_assoc.
      reflexivity.
Qed.

Lemma book_raw_desc_nil_prefix :
  forall (hit next : book_row) (rest : list book_row),
    book_raw_desc (hit :: next :: rest) =
    book_raw_row hit ++ [4] ++ book_raw_desc (next :: rest).
Proof.
  intros. rewrite book_raw_desc_cons. rewrite book_raw_tail_cons.
  cbn [app]. reflexivity.
Qed.

(** The key restored-rail identity. *)
Lemma book_cycle_restored_raw_desc :
  forall (steps : list book_failure) (bits : list bool)
         (hit next : book_row) (rest : list book_row)
         (c0 : bool) (creast : list bool),
    br_cond hit = bits ->
    br_cond next = c0 :: creast ->
    map q16_restore (rev (book_cycle_tags steps bits hit)) ++
      source_bit c0 :: book_after_suffix creast next rest
    = book_raw_desc (map bf_row steps ++ hit :: next :: rest).
Proof.
  intros steps bits hit next rest c0 creast Hcond Hnext.
  rewrite book_cycle_tags_rev_eq.
  unfold book_cycle_marked.
  rewrite map_app. cbn [map q16_restore].
  rewrite map_app. cbn [map q16_restore].
  rewrite map_app. cbn [map q16_restore].
  rewrite map_q16_restore_cycle_region.
  rewrite map_q16_restore_match_marks.
  rewrite map_q16_restore_match_marks.
  rewrite <- (book_raw_desc_cons_cond next c0 creast rest Hnext).
  unfold book_cycle_dir_mark.
  replace (q16_restore (if br_dir hit then 3 else 2))
    with (source_bit (br_dir hit))
    by (destruct (br_dir hit); reflexivity).
  destruct steps as [|st srest].
  - cbn [map app].
    rewrite book_raw_desc_nil_prefix.
    unfold book_raw_row.
    rewrite Hcond.
    cbn [map app q16_restore].
    repeat rewrite <- app_assoc.
    reflexivity.
  - rewrite book_raw_desc_append_rows by discriminate.
    unfold book_raw_row.
    rewrite Hcond.
    cbn [map app q16_restore].
    repeat rewrite <- app_assoc.
    reflexivity.
Qed.

Print Assumptions book_cycle_restored_raw_desc.

Lemma book_cycle_restored_raw_desc_tail :
  forall (steps : list book_failure) (bits : list bool)
         (hit next : book_row) (rest : list book_row)
         (c0 : bool) (creast : list bool) (tail : list nat),
    br_cond hit = bits ->
    br_cond next = c0 :: creast ->
    map q16_restore (rev (book_cycle_tags steps bits hit)) ++
      source_bit c0 :: (book_after_suffix creast next rest ++ tail)
    = book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++ tail.
Proof.
  intros steps bits hit next rest c0 creast tail Hcond Hnext.
  replace (map q16_restore (rev (book_cycle_tags steps bits hit)) ++
           source_bit c0 :: (book_after_suffix creast next rest ++ tail))
    with ((map q16_restore (rev (book_cycle_tags steps bits hit)) ++
           source_bit c0 :: book_after_suffix creast next rest) ++ tail).
  2:{ rewrite <- app_assoc. reflexivity. }
  rewrite (book_cycle_restored_raw_desc steps bits hit next rest
    c0 creast Hcond Hnext).
  reflexivity.
Qed.

Print Assumptions book_cycle_restored_raw_desc_tail.

Lemma book_cycle_restored_raw_desc_left :
  forall (steps : list book_failure) (bits : list bool)
         (hit next : book_row) (rest : list book_row)
         (c0 : bool) (creast : list bool) (tail : list nat),
    br_cond hit = bits ->
    br_cond next = c0 :: creast ->
    map q16_restore
      (rev (book_cycle_tags steps bits hit ++ [4])) ++
      source_bit c0 :: (book_after_suffix creast next rest ++ tail)
    = 4 :: (book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++ tail).
Proof.
  intros steps bits hit next rest c0 creast tail Hcond Hnext.
  rewrite rev_snoc_cons_nat.
  cbn [map q16_restore].
  change (4 :: (map q16_restore (rev (book_cycle_tags steps bits hit)) ++
                source_bit c0 ::
                (book_after_suffix creast next rest ++ tail))
          = 4 :: (book_raw_desc
                    (map bf_row steps ++ hit :: next :: rest) ++ tail)).
  rewrite (book_cycle_restored_raw_desc_tail steps bits hit next rest
    c0 creast tail Hcond Hnext).
  reflexivity.
Qed.

Print Assumptions book_cycle_restored_raw_desc_left.

Lemma book_q5_raw_left_right_tape :
  forall (steps : list book_failure) (bits : list bool)
         (hit next : book_row) (rest : list book_row)
         (c0 : bool) (creast : list bool) (tail : list nat),
    br_cond hit = bits ->
    br_cond next = c0 :: creast ->
    4 :: (book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++ tail)
    = map q16_restore
        (rev (book_cycle_tags steps bits hit ++ [4])) ++
      source_bit c0 :: (book_after_suffix creast next rest ++ tail).
Proof.
  intros steps bits hit next rest c0 creast tail Hcond Hnext.
  symmetry.
  apply book_cycle_restored_raw_desc_left; auto.
Qed.

Print Assumptions book_q5_raw_left_right_tape.

(** ** Right cycle output is the next [book_q5_raw] frame *)

Lemma book_q5_raw_right_frame_eq :
  forall (init : list bool) (buf ptape : list nat)
         (w_tape : bool) (w_read : bool)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (hit_init : list bool) (hit_w c0 : bool)
         (creast : list bool) (tail : list nat),
    br_cond hit = init ++ [w_read] ->
    br_action hit = hit_init ++ [hit_w] ->
    br_cond next = c0 :: creast ->
    book_q5_raw hit_init (tl buf) hit_w (ptape ++ [source_bit w_tape])
      (raw_to_bool (hd 0 buf))
      (map bf_row steps ++ hit :: next :: rest) tail
    = cfg_ml 5
        (rev (tl buf ++ [5] ++ map source_bit hit_init) ++
         6 :: source_bit hit_w :: rev (ptape ++ [source_bit w_tape]))
        (match_mark (raw_to_bool (hd 0 buf)) :: 4 ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init buf ptape w_tape w_read steps hit next rest hit_init hit_w
    c0 creast tail Hcond Hact Hnext.
  unfold book_q5_raw.
  rewrite (book_cycle_restored_raw_desc_tail steps (init ++ [w_read]) hit
    next rest c0 creast (5 :: tail) Hcond Hnext).
  reflexivity.
Qed.

Print Assumptions book_q5_raw_right_frame_eq.

(** ** Left cycle output is the next [book_q5_raw] frame *)

Lemma book_q5_raw_left_frame_eq :
  forall (init : list bool) (buf ptape_prefix : list nat)
         (w_tape_left w_read : bool)
         (steps : list book_failure) (hit next : book_row)
         (rest : list book_row) (hit_init : list bool) (hit_w c0 : bool)
         (creast : list bool) (tail : list nat),
    br_cond hit = init ++ [w_read] ->
    br_action hit = hit_init ++ [hit_w] ->
    br_cond next = c0 :: creast ->
    book_q5_raw init (source_bit hit_w :: buf) w_tape_left
      ptape_prefix w_read
      (map bf_row steps ++ hit :: next :: rest) tail
    = cfg_ml 5
        (rev (source_bit hit_w ::
              rev (book_return_rail_raw init buf)) ++
         6 :: rev (ptape_prefix ++ [source_bit w_tape_left]))
        (match_mark w_read :: 4 ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init buf ptape_prefix w_tape_left w_read steps hit next rest
    hit_init hit_w c0 creast tail Hcond Hact Hnext.
  unfold book_q5_raw.
  rewrite rev_snoc_cons_nat.
  cbn [map q16_restore].
  rewrite <- (book_cycle_restored_raw_desc_tail steps (init ++ [w_read])
    hit next rest c0 creast (5 :: tail) Hcond Hnext).
  rewrite book_return_rail_raw_rev.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions book_q5_raw_left_frame_eq.

(** ** The q5 encoder *)

Definition raw_ptape_prefix
    (c : LeftInfiniteConfig) (lo : Z) : list nat :=
  match rev (raw_ptape c lo) with
  | [] => []
  | _ :: rest => rev rest
  end.

Definition raw_last
    (c : LeftInfiniteConfig) (lo : Z) : bool :=
  match rev (raw_ptape c lo) with
  | [] => false
  | s :: _ => raw_to_bool s
  end.

Definition lic_q5_encode
    (lo : Z) (c : LeftInfiniteConfig) (rows : list book_row)
    (tail : list nat) : Config :=
  book_q5_raw (lic_state c) (raw_buf c) (raw_last c lo)
    (raw_ptape_prefix c lo) (lic_tape c (lic_head c)) rows tail.

Lemma lic_q5_encode_is_book_q5_raw :
  forall (lo : Z) (c : LeftInfiniteConfig) (rows : list book_row) (tail : list nat),
    lic_q5_encode lo c rows tail =
    book_q5_raw (lic_state c) (raw_buf c) (raw_last c lo)
      (raw_ptape_prefix c lo) (lic_tape c (lic_head c)) rows tail.
Proof. reflexivity. Qed.

Lemma raw_ptape_length :
  forall c lo,
    length (raw_ptape c lo) = Z.to_nat (lic_head c - lo).
Proof.
  intros c lo. unfold raw_ptape.
  rewrite map_length, seq_length. reflexivity.
Qed.

Lemma raw_ptape_nonempty :
  forall c lo,
    (lo < lic_head c)%Z -> raw_ptape c lo <> [].
Proof.
  intros c lo Hlt Hnil.
  assert (Hlen : length (raw_ptape c lo) =
                 Z.to_nat (lic_head c - lo))
    by (apply raw_ptape_length).
  rewrite Hnil in Hlen. cbn [length] in Hlen.
  assert (Hpos : (0 < lic_head c - lo)%Z) by lia.
  assert (Hnpos : 0 < Z.to_nat (lic_head c - lo)).
  { pose proof (proj1 (Z2Nat.inj_lt 0 (lic_head c - lo)
      ltac:(lia) ltac:(lia)) Hpos) as Hn.
    cbn [Z.to_nat] in Hn. exact Hn. }
  rewrite <- Hlen in Hnpos. cbn [length] in Hnpos. lia.
Qed.

Lemma raw_ptape_prefix_last :
  forall c lo,
    raw_ptape c lo <> [] ->
    raw_ptape_prefix c lo ++ [source_bit (raw_last c lo)] =
    raw_ptape c lo.
Proof.
  intros c lo Hne.
  unfold raw_ptape_prefix, raw_last.
  destruct (rev (raw_ptape c lo)) as [|s rest] eqn:Hrev.
  - exfalso. apply Hne.
    apply (f_equal (@rev nat)) in Hrev.
    rewrite rev_involutive in Hrev. exact Hrev.
  - assert (Hraw : raw_source_cell s).
    { assert (Hne' : rev (raw_ptape c lo) <> []).
      { rewrite Hrev. discriminate. }
      pose proof (raw_source_buffer_hd (rev (raw_ptape c lo)) Hne'
        (Forall_rev (raw_ptape_raw c lo))) as H.
      rewrite Hrev in H. cbn [hd] in H. exact H. }
    rewrite (raw_to_bool_source_bit s Hraw).
    assert (Hrev' : raw_ptape c lo = rev (s :: rest)).
    { apply (f_equal (@rev nat)) in Hrev.
      rewrite rev_involutive in Hrev. exact Hrev. }
    rewrite Hrev'. reflexivity.
Qed.

Definition book_q5_source_rep
    (c : LeftInfiniteConfig) (lo : Z) (ptape : list nat)
    (w_tape : bool) (buf : list nat) : Prop :=
  (lo < lic_head c)%Z /\
  left_infinite_ok c /\
  ptape ++ [source_bit w_tape] = raw_ptape c lo /\
  buf = raw_buf c.

Lemma lic_q5_encode_rep :
  forall lo c,
    (lo < lic_head c)%Z ->
    left_infinite_ok c ->
    book_q5_source_rep c lo (raw_ptape_prefix c lo)
      (raw_last c lo) (raw_buf c).
Proof.
  intros lo c Hlt Hok.
  unfold book_q5_source_rep.
  split; [exact Hlt|].
  split; [exact Hok|].
  split.
  - apply raw_ptape_prefix_last. apply raw_ptape_nonempty. exact Hlt.
  - reflexivity.
Qed.

Lemma lic_q5_encode_rep_global :
  forall lo c,
    (lo < lic_head c)%Z ->
    left_infinite_ok c ->
    book_global_source_rep c lo (raw_ptape c lo) (raw_buf c).
Proof.
  intros lo c Hlt Hok.
  unfold book_global_source_rep.
  split; [lia|].
  split; [exact Hok|].
  split; reflexivity.
Qed.

Lemma lic_q5_encode_buffer_raw :
  forall (lo : Z) (c : LeftInfiniteConfig) (rows : list book_row) (tail : list nat),
    raw_source_buffer (raw_buf c).
Proof.
  intros. apply raw_buf_raw.
Qed.

Print Assumptions lic_q5_encode_rep.
Print Assumptions raw_ptape_prefix_last.

(** ** Concrete non-boundary right-hit instance

    p=1, two-row program.  The first row matches the initial condition
    [false;false] and moves right; the second row is the trailing row.
    The tape is all blank with R = 2, so the buffer is [0;0] and the
    right move is non-boundary (new buffer [0]). *)

Definition p1r_r1 : WideSourceRow :=
  {| wr_current := [false]; wr_read := false;
     wr_next := [false]; wr_write := false; wr_right := true |}.

Definition p1r_r2 : WideSourceRow :=
  {| wr_current := [true]; wr_read := false;
     wr_next := [true]; wr_write := false; wr_right := false |}.

Definition p1r_rows : list WideSourceRow := [p1r_r1; p1r_r2].

Definition p1r_book_rows : list book_row := source_rows_to_book p1r_rows.

Definition p1r_start : LeftInfiniteConfig :=
  {| lic_state := [false]; lic_head := 0%Z;
     lic_tape := fun _ => false; lic_R := 2%Z; lic_halted := false |}.

Example p1r_first_match :
  book_first_match ([false] ++ [false]) p1r_book_rows =
  book_lookup_hit [] (source_row_to_book p1r_r1)
    [source_row_to_book p1r_r2].
Proof. reflexivity. Qed.

Example p1r_start_encode :
  lic_q5_encode (-1) p1r_start p1r_book_rows [] =
  book_q5_raw [false] [0;0] false [] false p1r_book_rows [].
Proof. reflexivity. Qed.

Example p1r_right_hit_macro :
  run (book_steady_locate_q12_clock_gen [false] false false []
         (source_row_to_book p1r_r1) +
       book_q12_perform_right_clock_raw [false] false [0;0]
         (book_cycle_tags [] ([false] ++ [false])
            (source_row_to_book p1r_r1))
         (tl [0;0] ++ [5] ++ map source_bit [false]))
      (lic_q5_encode (-1) p1r_start p1r_book_rows []) =
  lic_q5_encode (-1) (left_infinite_step p1r_rows p1r_start)
    p1r_book_rows [].
Proof.
  rewrite p1r_start_encode.
  vm_compute.
  reflexivity.
Qed.

Print Assumptions p1r_right_hit_macro.
