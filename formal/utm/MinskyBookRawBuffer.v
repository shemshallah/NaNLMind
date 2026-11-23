(** * Raw right-buffer book perform/locate cycles

    The original book cycles use [book_buf b = repeat 0 b] as the run of
    raw cells immediately to the right of the head marker [M = 6].  That
    is the special case of a raw buffer of source cells

      buf : list nat,   each cell 0 or 1.

    This file replaces the zero buffer by an arbitrary [buf] and proves
    the exact updates:

      right move:  target = hd 0 buf,  new buffer = tl buf;
      left move:   new buffer = source_bit w :: buf.

    The q5 steady frame is parameterized by the raw buffer itself (the
    cells right of [M]), with [w_tape] the cell immediately left of [M].

    The perform cores are the existing arbitrary-[tbuffer] theorems
    [book_q12_restore_to_q5_right], [book_q13_restore_to_q5_left],
    [book_q6_region_to_q12], and the q19/q20 relocation lemmas.  The new
    work is the frame bookkeeping for a raw list and the passability of
    raw 0/1 cells.  In particular q15/q16 are *not* passable on raw 0/1:
    the q15/q16 rails are the marked description, not the buffer.  The
    q19 target is always the first raw buffer cell, so [scanned = []]];
    only its *bit value* changes, and [q19_to_q5_relocation] is already
    general in that bit.  No new q19/q20 nonempty-scan theorem is needed
    for a nonblank first buffer cell.

    The boundary is [buf = []]: then [rev (book_return_rail_raw init [])]
    is [5 :: map source_bit init], so there is no raw target and the
    right-perform theorem does not apply.  This is exactly the abstract
    [left_infinite_step] halt at [head = R]; the native table instead
    passes [Y] and walks to q3/Y, which remains the explicit q3/Y trace
    obligation. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyWideSource MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalCopyGeneral MinskyCanonicalInstruction
  MinskyCanonicalDirection MinskyCanonicalRestore MinskyHeadMoveMacro
  MinskyDirectionDecision MinskyRelocationMacro MinskyBookLeft MinskyBookLayout
  MinskyBookCycle MinskyBookLeftCycle MinskyBookLocate MinskyBookLocateRows
  MinskyBookLocateWide MinskyBookLocateCycle MinskyBookLocateLookup
  MinskyBookEncode MinskyLeftInfinite.

(** ** Raw source cells *)

Definition raw_source_cell (s : nat) : Prop := s = 0 \/ s = 1.

Definition raw_source_buffer (buf : list nat) : Prop :=
  Forall raw_source_cell buf.

Lemma raw_source_cell_q12 :
  forall s, raw_source_cell s -> q12_pass s.
Proof.
  intros s [-> | ->]; unfold q12_pass; auto 10.
Qed.

Lemma raw_source_cell_q14 :
  forall s, raw_source_cell s -> q14_pass s.
Proof.
  intros s [-> | ->]; unfold q14_pass; auto 10.
Qed.

Lemma raw_source_cell_q17 :
  forall s, raw_source_cell s -> q17_pass s.
Proof.
  intros s [-> | ->]; unfold q17_pass; auto 10.
Qed.

Lemma raw_source_cell_q21 :
  forall s, raw_source_cell s -> q21_pass s.
Proof.
  intros s [-> | ->]; unfold q21_pass; auto 10.
Qed.

(** Raw 0/1 cells are deliberately *not* q15/q16 passable.  Those
    predicates describe the marked description rail, not the buffer.
    This lemma records the separation explicitly. *)
Lemma raw_source_cell_not_q15 :
  forall s, raw_source_cell s -> q15_pass s -> False.
Proof.
  intros s [-> | ->] H; unfold q15_pass in H; lia.
Qed.

Lemma raw_source_cell_not_q16 :
  forall s, raw_source_cell s -> q16_pass s -> False.
Proof.
  intros s [-> | ->] H; unfold q16_pass in H; lia.
Qed.

Lemma Forall_raw_q12 :
  forall buf, raw_source_buffer buf -> Forall q12_pass buf.
Proof.
  intros buf H. induction H as [|s rest Hs Hrest IH].
  - constructor.
  - constructor; [apply raw_source_cell_q12; exact Hs | exact IH].
Qed.

Lemma Forall_raw_q14 :
  forall buf, raw_source_buffer buf -> Forall q14_pass buf.
Proof.
  intros buf H. induction H as [|s rest Hs Hrest IH].
  - constructor.
  - constructor; [apply raw_source_cell_q14; exact Hs | exact IH].
Qed.

Lemma Forall_raw_q17 :
  forall buf, raw_source_buffer buf -> Forall q17_pass buf.
Proof.
  intros buf H. induction H as [|s rest Hs Hrest IH].
  - constructor.
  - constructor; [apply raw_source_cell_q17; exact Hs | exact IH].
Qed.

Lemma Forall_raw_q21 :
  forall buf, raw_source_buffer buf -> Forall q21_pass buf.
Proof.
  intros buf H. induction H as [|s rest Hs Hrest IH].
  - constructor.
  - constructor; [apply raw_source_cell_q21; exact Hs | exact IH].
Qed.

Lemma Forall_raw_q12_rev :
  forall buf, raw_source_buffer buf -> Forall q12_pass (rev buf).
Proof. intros. apply Forall_rev, Forall_raw_q12. exact H. Qed.

Lemma Forall_raw_q14_rev :
  forall buf, raw_source_buffer buf -> Forall q14_pass (rev buf).
Proof. intros. apply Forall_rev, Forall_raw_q14. exact H. Qed.

Lemma Forall_raw_q17_rev :
  forall buf, raw_source_buffer buf -> Forall q17_pass (rev buf).
Proof. intros. apply Forall_rev, Forall_raw_q17. exact H. Qed.

Lemma Forall_raw_q21_rev :
  forall buf, raw_source_buffer buf -> Forall q21_pass (rev buf).
Proof. intros. apply Forall_rev, Forall_raw_q21. exact H. Qed.

Lemma source_bit_q12 : forall b, q12_pass (source_bit b).
Proof. intros []; unfold q12_pass, source_bit; auto 10. Qed.

Lemma source_bit_q14 : forall b, q14_pass (source_bit b).
Proof. intros []; unfold q14_pass, source_bit; auto 10. Qed.

Lemma source_bit_q17 : forall b, q17_pass (source_bit b).
Proof. intros []; unfold q17_pass, source_bit; auto 10. Qed.

Lemma source_bit_q21 : forall b, q21_pass (source_bit b).
Proof. intros []; unfold q21_pass, source_bit; auto 10. Qed.

Lemma Forall_source_bits_q12 :
  forall init, Forall q12_pass (map source_bit init).
Proof.
  induction init as [|b init IH]; simpl.
  - constructor.
  - constructor; [apply source_bit_q12 | exact IH].
Qed.

Lemma Forall_source_bits_q14 :
  forall init, Forall q14_pass (map source_bit init).
Proof.
  induction init as [|b init IH]; simpl.
  - constructor.
  - constructor; [apply source_bit_q14 | exact IH].
Qed.

Lemma Forall_source_bits_q17 :
  forall init, Forall q17_pass (map source_bit init).
Proof.
  induction init as [|b init IH]; simpl.
  - constructor.
  - constructor; [apply source_bit_q17 | exact IH].
Qed.

Lemma Forall_source_bits_q21 :
  forall init, Forall q21_pass (map source_bit init).
Proof.
  induction init as [|b init IH]; simpl.
  - constructor.
  - constructor; [apply source_bit_q21 | exact IH].
Qed.

Lemma Forall_raw_rev_source_bits_q21 :
  forall init buf,
    raw_source_buffer buf ->
    Forall q21_pass (rev (map source_bit init) ++ [5] ++ rev buf).
Proof.
  intros init buf Hraw.
  apply Forall_app. split.
  - apply Forall_rev, Forall_source_bits_q21.
  - apply Forall_app. split.
    + constructor.
      * unfold q21_pass; auto 10.
      * constructor.
    + apply Forall_raw_q21_rev. exact Hraw.
Qed.

Lemma Forall_raw_tl_q17 :
  forall buf,
    raw_source_buffer buf ->
    Forall q17_pass (tl buf).
Proof.
  intros buf Hraw.
  destruct buf as [|b rest].
  - constructor.
  - inversion Hraw as [|? ? Hb Hrest]; subst.
    change (Forall q17_pass rest).
    apply Forall_raw_q17. exact Hrest.
Qed.

(** ** Raw buffer vocabulary *)

Definition raw_to_bool (s : nat) : bool := if s =? 1 then true else false.

Lemma raw_to_bool_source_bit :
  forall s, raw_source_cell s -> source_bit (raw_to_bool s) = s.
Proof. intros s [-> | ->]; reflexivity. Qed.

Lemma raw_source_buffer_hd :
  forall buf,
    buf <> [] -> raw_source_buffer buf -> raw_source_cell (hd 0 buf).
Proof.
  intros buf Hne Hraw.
  destruct buf as [|b brest]; [contradiction|].
  simpl. inversion Hraw as [|? ? Hb _]; subst. exact Hb.
Qed.

Lemma raw_source_buffer_tl :
  forall buf, raw_source_buffer buf -> raw_source_buffer (tl buf).
Proof.
  intros buf Hraw. destruct buf as [|b rest]; simpl.
  - constructor.
  - inversion Hraw as [|? ? _ Hrest]; subst. exact Hrest.
Qed.

Definition book_return_rail_raw
    (init : list bool) (buf : list nat) : list nat :=
  rev (map source_bit init) ++ [5] ++ rev buf.

Definition book_q6_left_raw
    (bits : list bool) (buf ptape : list nat) : list nat :=
  4 :: rev (map source_bit bits) ++ 5 :: rev buf ++ 6 :: rev ptape.

Definition book_q5_raw
    (init : list bool) (buf : list nat) (w_tape : bool)
    (ptape : list nat) (w_read : bool) (rows : list book_row)
    (tail : list nat) : Config :=
  cfg_ml 5
    (rev (buf ++ [5] ++ map source_bit init) ++
     6 :: source_bit w_tape :: rev ptape)
    (match_mark w_read :: 4 :: book_raw_desc rows ++ 5 :: tail).

Lemma book_return_rail_raw_rev :
  forall init buf,
    rev (book_return_rail_raw init buf) =
    buf ++ [5] ++ map source_bit init.
Proof.
  intros init buf.
  unfold book_return_rail_raw.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_involutive, rev_involutive.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma book_return_rail_raw_cons :
  forall init b rest,
    rev (book_return_rail_raw init (b :: rest)) =
    b :: (rest ++ [5] ++ map source_bit init).
Proof.
  intros. rewrite book_return_rail_raw_rev. reflexivity.
Qed.

Lemma book_return_rail_raw_nil :
  forall init,
    rev (book_return_rail_raw init []) = 5 :: map source_bit init.
Proof.
  intros. unfold book_return_rail_raw.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_involutive. reflexivity.
Qed.

Lemma map_q14_restore_raw :
  forall buf, raw_source_buffer buf -> map q14_restore buf = buf.
Proof.
  intros buf H. induction H as [|b rest Hb Hrest IH].
  - reflexivity.
  - simpl. assert (Hq : q14_restore b = b).
    { destruct Hb as [-> | ->]; reflexivity. }
    rewrite Hq, IH. reflexivity.
Qed.

Lemma map_q14_restore_rev_raw :
  forall buf, raw_source_buffer buf ->
    map q14_restore (rev buf) = rev buf.
Proof.
  intros buf H. rewrite map_rev.
  rewrite map_q14_restore_raw by exact H.
  reflexivity.
Qed.

Lemma rev_book_frame_raw :
  forall (init : list bool) (buf : list nat) (w : bool),
    rev (buf ++ [5] ++ rev (rev (map match_mark init)) ++
         [match_mark w]) =
    match_mark w :: rev (map match_mark init) ++ [5] ++ rev buf.
Proof.
  intros init buf w.
  rewrite rev_involutive.
  replace (buf ++ [5] ++ map match_mark init ++ [match_mark w])
    with ((buf ++ [5] ++ map match_mark init) ++ [match_mark w])
    by (repeat rewrite <- app_assoc; reflexivity).
  rewrite rev_app_distr. cbn [rev].
  replace (buf ++ [5] ++ map match_mark init)
    with ((buf ++ [5]) ++ map match_mark init)
    by (repeat rewrite <- app_assoc; reflexivity).
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma book_restored_frame_raw :
  forall (init : list bool) (buf : list nat) (w : bool),
    raw_source_buffer buf ->
    map q14_restore
      (rev (buf ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
    source_bit w :: book_return_rail_raw init buf.
Proof.
  intros init buf w Hraw.
  unfold book_return_rail_raw.
  rewrite rev_book_frame_raw.
  cbn [map q14_restore].
  rewrite map_app. cbn [map q14_restore].
  rewrite map_app. cbn [map q14_restore].
  rewrite map_rev.
  rewrite map_q14_restore_match_marks.
  rewrite map_q14_restore_rev_raw by exact Hraw.
  rewrite q14_restore_match_mark.
  reflexivity.
Qed.

(** ** Raw q5 steady -> locate state *)

Lemma book_q5_steady_to_locate_state_raw_gen :
  forall (init : list bool) (w_read w_tape : bool) (buf : list nat)
         (ptape tail : list nat) (rows : list book_row),
    rows <> [] ->
    run (S (length init))
      (cfg_ml 5
        (rev (buf ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 :: book_raw_desc rows ++ 5 :: tail))
    = book_locate_state_wide (init ++ [w_read]) [] rows
        (rev buf ++ 6 :: rev (ptape ++ [source_bit w_tape])) tail.
Proof.
  intros init w_read w_tape buf ptape tail rows Hrows.
  replace (rev (buf ++ [5] ++ map source_bit init) ++
           6 :: source_bit w_tape :: rev ptape)
    with (rev (map source_bit init) ++ 5 ::
          (rev buf ++ 6 :: source_bit w_tape :: rev ptape)).
  2:{ rewrite rev_app_distr. cbn [rev].
      rewrite rev_app_distr. cbn [rev].
      repeat rewrite <- app_assoc. reflexivity. }
  rewrite (book_q5_steady_to_q1 init w_read
    (rev buf ++ 6 :: source_bit w_tape :: rev ptape)
    (book_raw_desc rows ++ 5 :: tail)).
  destruct rows as [|r rest]; [contradiction|].
  unfold book_locate_state_wide.
  cbn [book_marked_prefix app].
  rewrite book_raw_tail_cons.
  rewrite rev_ptape_source_bit.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions book_q5_steady_to_locate_state_raw_gen.

(** ** Raw locate hit *)

Theorem book_locate_by_computation_from_q5_to_q6_raw :
  forall (init : list bool) (w_read w_tape : bool) (buf : list nat)
         (ptape tail : list nat) (rows : list book_row)
         (steps : list book_failure) (hit : book_row) (after : list book_row),
    rows <> [] ->
    book_first_match (init ++ [w_read]) rows =
      book_lookup_hit steps hit after ->
    run (S (length init) +
         (book_failures_clock [] steps +
          book_hit_clock (init ++ [w_read]) (map bf_row steps)))
      (cfg_ml 5
        (rev (buf ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 :: book_raw_desc rows ++ 5 :: tail))
    = entry_config 6
        (4 :: rev (map source_bit (init ++ [w_read])) ++
         5 :: (rev buf ++ 6 :: rev (ptape ++ [source_bit w_tape])))
        (tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
         map match_mark (init ++ [w_read]) ++
         map source_bit (br_action hit) ++
         [source_bit (br_dir hit)] ++ book_raw_tail after ++ 5 :: tail).
Proof.
  intros init w_read w_tape buf ptape tail rows steps hit after
    Hrows_ne Hmatch.
  rewrite (dispatch_run_add (S (length init))
    (book_failures_clock [] steps +
     book_hit_clock (init ++ [w_read]) (map bf_row steps))).
  rewrite (book_q5_steady_to_locate_state_raw_gen init w_read w_tape buf
    ptape tail rows Hrows_ne).
  destruct (book_first_match_hit_sound (init ++ [w_read]) rows steps hit
    after Hmatch) as [Hrows [Hforall Hcond]].
  rewrite Hrows.
  apply (book_locate_rows_to_q6_wide (init ++ [w_read]) [] steps hit after
    (rev buf ++ 6 :: rev (ptape ++ [source_bit w_tape])) tail
    Hforall Hcond).
Qed.

Print Assumptions book_locate_by_computation_from_q5_to_q6_raw.

Lemma book_q6_to_q12_raw :
  forall (bits init : list bool) (w dir : bool) (buf ptape desc_tail : list nat)
         (trailing : bool) (tail : list nat),
    length bits = length (init ++ [w]) ->
    run (copy_all_clock bits (init ++ [w]) [] (map match_mark bits) +
         direction_clock
           (map match_mark bits ++ map match_mark (init ++ [w]))
           (map match_mark (init ++ [w])))
      (entry_config 6
        (book_q6_left_raw bits buf ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit dir :: desc_tail ++ source_bit trailing :: tail)) =
    cfg_ml (if dir then 12 else 13)
      (rev (map match_mark (init ++ [w])) ++
       5 :: rev buf ++ 6 :: rev ptape)
      ((4 :: map match_mark bits ++ map match_mark (init ++ [w])) ++
       (if dir then 3 else 2) :: desc_tail ++
       source_bit trailing :: tail).
Proof.
  intros bits init w dir buf ptape desc_tail trailing tail Hlen.
  unfold book_q6_left_raw.
  exact (canonical_q6_copy_direction_to_q12 bits (init ++ [w]) buf ptape dir
    (desc_tail ++ source_bit trailing :: tail) (eq_sym Hlen)).
Qed.

Print Assumptions book_q6_to_q12_raw.

(** ** Raw right perform q6 -> q5 *)

Definition book_right_clock_raw
    (bits init : list bool) (w : bool) (buf : list nat)
    (desc_tail : list nat) : nat :=
  let rail := book_q15_rail bits init w 3 desc_tail in
  let dirs := book_return_rail_raw init buf in
  let between := tl buf ++ [5] ++ map source_bit init in
  let act := init ++ [w] in
  (copy_all_clock bits act [] (map match_mark bits) +
   direction_clock (map match_mark bits ++ map match_mark act)
     (map match_mark act)) +
  (S (length (match_mark w :: rev (map match_mark init) ++
              5 :: rev buf)) +
   S (length (buf ++ [5] ++ rev (rev (map match_mark init)) ++
              [match_mark w]))) +
  ((S (length rail) + S (length (rev rail ++ [4])) +
    S (length dirs)) +
   (1 + S (length between))).

Theorem book_q6_to_q5_right_raw :
  forall (bits init : list bool) (w : bool) (buf : list nat)
         (ptape desc_tail : list nat) (trailing : bool) (tail : list nat),
    length bits = length (init ++ [w]) ->
    buf <> [] ->
    raw_source_buffer buf ->
    Forall q15_pass (book_q15_rail bits init w 3 desc_tail) ->
    Forall q16_pass
      (rev (book_q15_rail bits init w 3 desc_tail) ++ [4]) ->
    run (book_right_clock_raw bits init w buf desc_tail)
      (entry_config 6
        (book_q6_left_raw bits buf ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit true :: desc_tail ++ source_bit trailing :: tail)) =
    cfg_ml 5
      (rev (tl buf ++ [5] ++ map source_bit init) ++
       6 :: source_bit w :: rev ptape)
      (match_mark (raw_to_bool (hd 0 buf)) :: 4 ::
       map q16_restore (book_q15_rail bits init w 3 desc_tail) ++
       source_bit trailing :: tail).
Proof.
  intros bits init w buf ptape desc_tail trailing tail
    Hlen Hbne Hraw H15 H16.
  set (rail := book_q15_rail bits init w 3 desc_tail).
  set (dirs := book_return_rail_raw init buf).
  set (between := tl buf ++ [5] ++ map source_bit init).
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail_raw. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_nonempty : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (Hhd21 : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. unfold dirs.
    apply Forall_raw_rev_source_bits_q21. exact Hraw. }
  assert (Hsplit : rev (hd 0 dirs :: tl dirs) =
                   source_bit (raw_to_bool (hd 0 buf)) :: between).
  { rewrite Hdirs_eq. unfold dirs, between.
    rewrite book_return_rail_raw_rev.
    destruct buf as [|b brest]; [contradiction|].
    cbn [hd tl].
    assert (Hb : raw_source_cell b).
    { inversion Hraw as [|? ? Hcell _]; subst. exact Hcell. }
    rewrite raw_to_bool_source_bit by exact Hb.
    reflexivity. }
  assert (Hrecord :
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
    [3] ++ desc_tail ++ source_bit trailing :: tail =
    rail ++ source_bit trailing :: tail).
  { unfold rail, book_q15_rail.
    repeat rewrite <- app_assoc. reflexivity. }
  unfold book_right_clock_raw.
  fold rail dirs between.
  set (q6c := copy_all_clock bits (init ++ [w]) []
                (map match_mark bits) +
              direction_clock
                (map match_mark bits ++ map match_mark (init ++ [w]))
                (map match_mark (init ++ [w]))).
  set (restorec :=
        S (length (match_mark w :: rev (map match_mark init) ++
                   5 :: rev buf)) +
        S (length (buf ++ [5] ++ rev (rev (map match_mark init)) ++
                   [match_mark w]))).
  set (q15c :=
        (S (length rail) +
         S (length (rev rail ++ [4])) +
         S (length dirs)) +
        (1 + S (length between))).
  set (startq6 :=
    entry_config 6 (book_q6_left_raw bits buf ptape)
      (map match_mark bits ++ map source_bit (init ++ [w]) ++
       source_bit true :: desc_tail ++ source_bit trailing :: tail)).
  change (run (q6c + restorec + q15c) startq6 =
    cfg_ml 5 (rev between ++ 6 :: source_bit w :: rev ptape)
      (match_mark (raw_to_bool (hd 0 buf)) :: 4 ::
       map q16_restore rail ++ source_bit trailing :: tail)).
  rewrite (dispatch_run_add (q6c + restorec) q15c startq6).
  rewrite (dispatch_run_add q6c restorec startq6).
  unfold q6c, startq6.
  rewrite (book_q6_to_q12_raw bits init w true buf ptape desc_tail
    trailing tail Hlen).
  unfold restorec, q15c.
  replace (length rail) with (length (rev (rev rail)))
    by (rewrite !rev_length; reflexivity).
  replace (length dirs) with (length (hd 0 dirs :: tl dirs))
    by (rewrite Hdirs_eq; reflexivity).
  assert (H12' : Forall q12_pass
    (match_mark w :: rev (map match_mark init) ++ 5 :: rev buf)).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_raw_q12_rev. exact Hraw. }
  assert (H14' : Forall q14_pass
    (buf ++ [5] ++ rev (rev (map match_mark init)) ++ [match_mark w])).
  { apply Forall_app. split.
    - apply Forall_raw_q14. exact Hraw.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * rewrite rev_involutive. apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (H17' : Forall q17_pass between).
  { unfold between. apply Forall_app. split.
    - apply Forall_raw_tl_q17. exact Hraw.
    - apply Forall_app. split.
      + constructor; [unfold q17_pass; auto 10 | constructor].
      + apply Forall_source_bits_q17. }
  replace (cfg_ml 12
    (rev (map match_mark (init ++ [w])) ++
     5 :: rev buf ++ 6 :: rev ptape)
    ((4 :: map match_mark bits ++ map match_mark (init ++ [w])) ++
     3 :: desc_tail ++ source_bit trailing :: tail))
    with (cfg_ml 12
      (match_mark w :: rev (map match_mark init) ++
       5 :: rev buf ++ 6 :: rev ptape)
      (4 :: (map match_mark bits ++ map match_mark (init ++ [w])) ++
       3 :: desc_tail ++ source_bit trailing :: tail))
    by (rewrite map_app, rev_app_distr;
        cbn [rev map app]; repeat rewrite <- app_comm_cons;
        repeat rewrite <- app_assoc; reflexivity).
  rewrite <- dispatch_run_add.
  replace (restorec + q15c)
    with (S (length (match_mark w :: rev (map match_mark init) ++
                      5 :: rev buf)) +
          S (length (buf ++ [5] ++ rev (rev (map match_mark init)) ++
                     [match_mark w])) +
          ((S (length (rev (rev rail))) +
            S (length (rev rail ++ [4])) +
            S (length (hd 0 dirs :: tl dirs))) +
           (S (length ([] : list nat)) + S (length between))))
    by (unfold restorec, q15c; rewrite !rev_length;
        rewrite Hdirs_eq; cbn [length];
        repeat rewrite Nat.add_assoc; reflexivity).
  assert (Hrestored' :
    map q14_restore
      (rev (buf ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
    source_bit w :: book_return_rail_raw init buf).
  { apply book_restored_frame_raw. exact Hraw. }
  assert (Hrestored'' :
    map q14_restore
      (rev (buf ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
    source_bit w :: hd 0 dirs :: tl dirs).
  { rewrite Hrestored'. rewrite Hdirs_eq. unfold dirs. reflexivity. }
  assert (Hrecord' :
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
    [3] ++ desc_tail ++ source_bit trailing :: tail =
    rev (rev rail) ++ source_bit trailing :: tail).
  { rewrite rev_involutive. exact Hrecord. }
  assert (H15' : Forall q15_pass (rev (rev rail))).
  { rewrite rev_involutive. exact H15. }
  replace (1 + S (length between))
    with (S (length ([] : list nat)) + S (length between))
    by reflexivity.
  replace (map q16_restore rail)
    with (map q16_restore (rev (rev rail)))
    by (rewrite rev_involutive; reflexivity).
  apply (book_q12_restore_to_q5_right
    (match_mark w) (rev (map match_mark init)) buf ptape
    (map match_mark bits ++ map match_mark (init ++ [w])) 3
    (desc_tail ++ source_bit trailing :: tail) (rev rail)
    w (hd 0 dirs) (tl dirs)
    (raw_to_bool (hd 0 buf)) trailing between tail
    H12' H14' Hrestored'' Hhd21 Hsplit H17' Hrecord' H15' H16).
Qed.

Print Assumptions book_q6_to_q5_right_raw.

(** ** Raw left perform q6 -> q5 *)

Definition book_left_clock_raw
    (bits init : list bool) (w : bool) (buf : list nat)
    (desc_tail tags : list nat) (dir_head : nat)
    (dir_remaining : list nat) : nat :=
  let act := init ++ [w] in
  (copy_all_clock bits act [] (map match_mark bits) +
   direction_clock
     (map match_mark bits ++ map match_mark act)
     (map match_mark act)) +
  (S (length (match_mark w :: rev (map match_mark init) ++
              5 :: rev buf)) +
   S (length (buf ++ [5] ++ rev (rev (map match_mark init)) ++
              [match_mark w]))) +
  ((S (length (rev tags)) +
    S (length (tags ++ [4])) +
    S (length (dir_head :: dir_remaining))) +
   (1 + S (length (source_bit w :: rev (dir_head :: dir_remaining))))).

Theorem book_q6_to_q5_left_raw :
  forall (bits init : list bool) (w : bool) (buf : list nat)
         (ptape desc_tail : list nat) (trailing : bool) (tail : list nat)
         (target : bool) (outer : list nat)
         (dir_head : nat) (dir_remaining tags : list nat),
    length bits = length (init ++ [w]) ->
    raw_source_buffer buf ->
    rev ptape = source_bit target :: outer ->
    dir_head :: dir_remaining = book_return_rail_raw init buf ->
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
      [2] ++ desc_tail ++ source_bit trailing :: tail =
      rev tags ++ source_bit trailing :: tail ->
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    run (book_left_clock_raw bits init w buf desc_tail tags
           dir_head dir_remaining)
      (entry_config 6
        (book_q6_left_raw bits buf ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit false :: desc_tail ++ source_bit trailing :: tail)) =
    cfg_ml 5
      (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit trailing :: tail).
Proof.
  intros bits init w buf ptape desc_tail trailing tail target outer
    dir_head dir_remaining tags Hlen Hraw Hptape Hdirs Hright H15 H16.
  set (B := buf).
  set (rail := book_q15_rail bits init w 2 desc_tail).
  assert (Hrestored :
    map q14_restore
      (rev (buf ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
    source_bit w :: dir_head :: dir_remaining).
  { rewrite (book_restored_frame_raw init buf w Hraw).
    rewrite <- Hdirs. reflexivity. }
  assert (H21 : Forall q21_pass (dir_head :: dir_remaining)).
  { rewrite Hdirs. apply Forall_raw_rev_source_bits_q21. exact Hraw. }
  assert (Hreturn : Forall q17_pass
    (source_bit w :: rev (dir_head :: dir_remaining))).
  { rewrite Hdirs, book_return_rail_raw_rev.
    constructor.
    - apply source_bit_q17.
    - apply Forall_app. split.
      + apply Forall_raw_q17. exact Hraw.
      + apply Forall_app. split.
        * constructor; [unfold q17_pass; auto 10 | constructor].
        * apply Forall_source_bits_q17. }
  assert (H12 : Forall q12_pass
    (match_mark w :: rev (map match_mark init) ++ 5 :: rev buf)).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_raw_q12_rev. exact Hraw. }
  assert (H14 : Forall q14_pass
    (buf ++ [5] ++ map match_mark init ++ [match_mark w])).
  { apply Forall_app. split.
    - apply Forall_raw_q14. exact Hraw.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (H14' : Forall q14_pass
    (B ++ [5] ++ rev (rev (map match_mark init)) ++ [match_mark w])).
  { unfold B. rewrite rev_involutive. exact H14. }
  assert (H12' : Forall q12_pass
    (match_mark w :: rev (map match_mark init) ++ 5 :: rev B)).
  { unfold B. exact H12. }
  assert (Hrecord :
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
    [2] ++ desc_tail ++ source_bit trailing :: tail =
    rail ++ source_bit trailing :: tail).
  { unfold rail, book_q15_rail.
    repeat rewrite <- app_assoc. reflexivity. }
  unfold book_left_clock_raw.
  fold B rail.
  set (q13c :=
        copy_all_clock bits (init ++ [w]) []
          (map match_mark bits) +
        direction_clock
          (map match_mark bits ++ map match_mark (init ++ [w]))
          (map match_mark (init ++ [w]))).
  set (restorec :=
        S (length (match_mark w :: rev (map match_mark init) ++
                   5 :: rev B)) +
        S (length (B ++ [5] ++ rev (rev (map match_mark init)) ++
                   [match_mark w]))).
  set (q15c :=
        (S (length (rev tags)) +
         S (length (tags ++ [4])) +
         S (length (dir_head :: dir_remaining))) +
        (1 + S (length (source_bit w :: rev (dir_head :: dir_remaining))))).
  set (startq6 :=
    entry_config 6 (book_q6_left_raw bits buf ptape)
      (map match_mark bits ++ map source_bit (init ++ [w]) ++
       source_bit false :: desc_tail ++ source_bit trailing :: tail)).
  change (run (q13c + restorec + q15c) startq6 =
    cfg_ml 5
      (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit trailing :: tail)).
  rewrite (dispatch_run_add (q13c + restorec) q15c startq6).
  rewrite (dispatch_run_add q13c restorec startq6).
  unfold q13c, startq6.
  rewrite (book_q6_to_q12_raw bits init w false buf ptape desc_tail
    trailing tail Hlen).
  unfold restorec, q15c.
  replace (length rail) with (length (rev (rev rail)))
    by (rewrite !rev_length; reflexivity).
  replace (cfg_ml 13
    (rev (map match_mark (init ++ [w])) ++
     5 :: rev buf ++ 6 :: rev ptape)
    ((4 :: map match_mark bits ++ map match_mark (init ++ [w])) ++
     2 :: desc_tail ++ source_bit trailing :: tail))
    with (cfg_ml 13
      (match_mark w :: rev (map match_mark init) ++
       5 :: rev B ++ 6 :: rev ptape)
      (4 :: (map match_mark bits ++ map match_mark (init ++ [w])) ++
       2 :: desc_tail ++ source_bit trailing :: tail))
    by (unfold B; rewrite map_app, rev_app_distr;
        cbn [rev map app]; repeat rewrite <- app_comm_cons;
        repeat rewrite <- app_assoc; reflexivity).
  rewrite <- dispatch_run_add.
  replace (restorec + q15c)
    with (S (length (match_mark w :: rev (map match_mark init) ++
                      5 :: rev B)) +
          S (length (B ++ [5] ++ rev (rev (map match_mark init)) ++
                     [match_mark w])) +
          ((S (length (rev tags)) +
            S (length (tags ++ [4])) +
            S (length (dir_head :: dir_remaining))) +
           (S (length ([] : list nat)) +
            S (length (source_bit w :: rev (dir_head :: dir_remaining))))))
    by (unfold restorec, q15c; cbn [length];
        repeat rewrite Nat.add_assoc; reflexivity).
  apply (book_q13_restore_to_q5_left
    (match_mark w) (rev (map match_mark init)) B ptape
    (map match_mark bits ++ map match_mark (init ++ [w])) 2
    (desc_tail ++ source_bit trailing :: tail) tags
    (source_bit w :: dir_head :: dir_remaining)
    w dir_head dir_remaining target trailing outer tail
    H12' H14' Hrestored eq_refl Hptape Hright H15 H16 H21 Hreturn).
Qed.

Print Assumptions book_q6_to_q5_left_raw.

(** ** Raw locate -> q12 *)

Theorem book_locate_rows_to_q12_raw :
  forall (src : list bool) (failed : list book_row) (steps : list book_failure)
         (hit : book_row) (after : list book_row) (buf : list nat)
         (ptape tail : list nat),
    Forall (fun st => bf_src st = src) steps ->
    br_cond hit = src ->
    length (br_action hit) = length src ->
    run (book_failures_clock failed steps +
         book_hit_clock src (failed ++ map bf_row steps) +
         (copy_all_clock src (br_action hit) []
            (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
             map match_mark src) +
          direction_clock
            (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
             map match_mark src ++ map match_mark (br_action hit))
            (map match_mark (br_action hit))))
      (book_locate_state_wide src failed (map bf_row steps ++ hit :: after)
         (rev buf ++ 6 :: rev ptape) tail)
    = cfg_ml (if br_dir hit then 12 else 13)
        (rev (map match_mark (br_action hit)) ++
         5 :: rev buf ++ 6 :: rev ptape)
        (4 :: ((tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
                map match_mark src) ++
               map match_mark (br_action hit)) ++
         (if br_dir hit then 3 else 2) :: book_raw_tail after ++ 5 :: tail).
Proof.
  intros src failed steps hit after buf ptape tail Hsteps Hcond Hlen.
  rewrite (dispatch_run_add
    (book_failures_clock failed steps +
     book_hit_clock src (failed ++ map bf_row steps))
    (copy_all_clock src (br_action hit) []
       (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
        map match_mark src) +
     direction_clock
       (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]) ++
        map match_mark src ++ map match_mark (br_action hit))
       (map match_mark (br_action hit)))).
  rewrite (book_locate_rows_to_q6_wide src failed steps hit after
    (rev buf ++ 6 :: rev ptape) tail Hsteps Hcond).
  rewrite book_locate_q6_region_frame_gen.
  apply (book_q6_region_to_q12
    (tl (book_marked_prefix (failed ++ map bf_row steps) ++ [4]))
    src (br_action hit) (br_dir hit) buf ptape
    (book_raw_tail after ++ 5 :: tail)).
  - apply Forall_q6_tl_marked_done.
  - apply Forall_q7_tl_marked_done.
  - exact Hlen.
Qed.

Print Assumptions book_locate_rows_to_q12_raw.

(** ** Raw locate -> q12, composed with the raw right perform *)

Theorem book_steady_q5_locate_to_q12_raw_gen :
  forall (init : list bool) (w_read w_tape : bool) (buf : list nat)
         (ptape tail : list nat) (steps : list book_failure)
         (hit : book_row) (after : list book_row),
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit)
      (book_q5_raw init buf w_tape ptape w_read
        (map bf_row steps ++ hit :: after) tail)
    = cfg_ml (if br_dir hit then 12 else 13)
        (rev (map match_mark (br_action hit)) ++
         5 :: rev buf ++ 6 :: rev (ptape ++ [source_bit w_tape]))
        (4 ::
         ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
          map match_mark (br_action hit)) ++
         book_cycle_dir_mark hit :: book_raw_tail after ++ 5 :: tail).
Proof.
  intros init w_read w_tape buf ptape tail steps hit after
    Hsteps Hcond Hlen.
  unfold book_q5_raw.
  rewrite (dispatch_run_add (S (length init))
    (book_failures_clock [] steps +
     book_hit_clock (init ++ [w_read]) (map bf_row steps) +
     (copy_all_clock (init ++ [w_read]) (br_action hit) []
        (book_cycle_region steps ++ map match_mark (init ++ [w_read])) +
      direction_clock
        (book_cycle_region steps ++ map match_mark (init ++ [w_read]) ++
         map match_mark (br_action hit))
        (map match_mark (br_action hit))))).
  assert (Hne : map bf_row steps ++ hit :: after <> []).
  { apply app_cons_book_row_neq_nil. }
  rewrite (book_q5_steady_to_locate_state_raw_gen init w_read w_tape buf
    ptape tail (map bf_row steps ++ hit :: after) Hne).
  cbn [app].
  apply (book_locate_rows_to_q12_raw (init ++ [w_read]) [] steps hit after
    buf (ptape ++ [source_bit w_tape]) tail Hsteps Hcond Hlen).
Qed.

Print Assumptions book_steady_q5_locate_to_q12_raw_gen.

Definition book_q12_perform_right_clock_raw
    (hit_init : list bool) (hit_w : bool) (buf : list nat)
    (tags between : list nat) : nat :=
  restore_clock (match_mark hit_w) (rev (map match_mark hit_init)) buf +
  ((S (length (rev tags)) + S (length (tags ++ [4])) +
    S (length (book_return_rail_raw hit_init buf))) +
   (S (length ([] : list nat)) + S (length between))).

(** The composed raw right cycle.  The input q5 buffer is [buf]; the
    output q5 buffer is [tl buf], and the cell immediately left of the
    new [M] is the write bit [hit_w]. *)
Theorem book_steady_q5_locate_to_q5_right_raw_gen :
  forall (init : list bool) (w_read w_tape : bool) (buf : list nat)
         (ptape tail : list nat) (steps : list book_failure)
         (hit : book_row) (next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w : bool)
         (c0 : bool) (creast : list bool),
    buf <> [] ->
    raw_source_buffer buf ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    br_cond next = c0 :: creast ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q12_perform_right_clock_raw hit_init hit_w buf
           (book_cycle_tags steps (init ++ [w_read]) hit)
           (tl buf ++ [5] ++ map source_bit hit_init))
      (book_q5_raw init buf w_tape ptape w_read
        (map bf_row steps ++ hit :: next :: rest) tail)
    = cfg_ml 5
        (rev (tl buf ++ [5] ++ map source_bit hit_init) ++
         6 :: source_bit hit_w :: rev (ptape ++ [source_bit w_tape]))
        (match_mark (raw_to_bool (hd 0 buf)) :: 4 ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init w_read w_tape buf ptape tail steps hit next rest
    hit_init hit_w c0 creast Hbne Hraw Hsteps Hcond Hlen Hact Hdir
    Hnext.
  set (between := tl buf ++ [5] ++ map source_bit hit_init).
  set (dirs := book_return_rail_raw hit_init buf).
  set (tags := book_cycle_tags steps (init ++ [w_read]) hit).
  change (run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
               book_q12_perform_right_clock_raw hit_init hit_w buf tags between)
    (book_q5_raw init buf w_tape ptape w_read
      (map bf_row steps ++ hit :: next :: rest) tail)
    = cfg_ml 5
        (rev between ++ 6 :: source_bit hit_w ::
         rev (ptape ++ [source_bit w_tape]))
        (match_mark (raw_to_bool (hd 0 buf)) :: 4 ::
         map q16_restore (rev tags) ++
         source_bit c0 :: book_after_suffix creast next rest ++ 5 :: tail)).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock_gen init w_read w_tape steps hit)
    (book_q12_perform_right_clock_raw hit_init hit_w buf tags between)).
  unfold book_steady_locate_q12_clock, book_cycle_region.
  rewrite (book_steady_q5_locate_to_q12_raw_gen init w_read w_tape buf
    ptape tail steps hit (next :: rest) Hsteps Hcond Hlen).
  rewrite Hdir.
  rewrite Hact.
  rewrite rev_match_mark_snoc_rows.
  assert (H12 : Forall q12_pass
    (match_mark hit_w :: rev (map match_mark hit_init) ++ 5 :: rev buf)).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_raw_q12_rev. exact Hraw. }
  assert (H14 : Forall q14_pass
    (buf ++ [5] ++ rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])).
  { apply Forall_app. split.
    - apply Forall_raw_q14. exact Hraw.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * rewrite rev_involutive. apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail_raw. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_ne : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (H21' : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. unfold dirs.
    apply Forall_raw_rev_source_bits_q21. exact Hraw. }
  assert (Hrestored :
    map q14_restore
      (rev (buf ++ [5] ++
            rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])) =
    source_bit hit_w :: hd 0 dirs :: tl dirs).
  { rewrite (book_restored_frame_raw hit_init buf hit_w Hraw).
    rewrite Hdirs_eq. unfold dirs. reflexivity. }
  assert (Hsplit : rev (hd 0 dirs :: tl dirs) =
                   source_bit (raw_to_bool (hd 0 buf)) :: between).
  { rewrite Hdirs_eq. unfold dirs, between.
    rewrite book_return_rail_raw_rev.
    destruct buf as [|b brest]; [contradiction|].
    cbn [hd tl].
    assert (Hb : raw_source_cell b).
    { inversion Hraw as [|? ? Hcell _]; subst. exact Hcell. }
    rewrite raw_to_bool_source_bit by exact Hb.
    reflexivity. }
  assert (H17 : Forall q17_pass between).
  { unfold between. apply Forall_app. split.
    - apply Forall_raw_tl_q17. exact Hraw.
    - apply Forall_app. split.
      + constructor; [unfold q17_pass; auto 10 | constructor].
      + apply Forall_source_bits_q17. }
  assert (H15 : Forall q15_pass (rev tags)).
  { unfold tags. rewrite book_cycle_tags_rev_eq.
    apply Forall_q15_cycle_rail. }
  assert (H16 : Forall q16_pass (tags ++ [4])).
  { unfold tags. apply Forall_q16_cycle_tags_snoc. }
  assert (Hright :
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark (hit_init ++ [hit_w])) ++
    book_cycle_dir_mark hit ::
      (book_raw_tail (next :: rest) ++ 5 :: tail) =
    rev tags ++ source_bit c0 ::
      (book_after_suffix creast next rest ++ 5 :: tail)).
  { unfold tags. rewrite book_cycle_tags_rev_eq.
    unfold book_cycle_marked.
    rewrite <- Hact.
    rewrite book_raw_tail_cons.
    rewrite (book_raw_desc_cons_cond next c0 creast rest Hnext).
    unfold book_cycle_dir_mark.
    cbn [app].
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity. }
  unfold book_q12_perform_right_clock_raw, restore_clock.
  unfold book_cycle_region, book_cycle_dir_mark.
  fold dirs.
  rewrite <- Hdirs_eq.
  eapply (book_q12_restore_to_q5_right
    (match_mark hit_w) (rev (map match_mark hit_init)) buf
    (ptape ++ [source_bit w_tape])
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark (hit_init ++ [hit_w]))
    (book_cycle_dir_mark hit)
    (book_raw_tail (next :: rest) ++ 5 :: tail)
    tags hit_w (hd 0 dirs) (tl dirs)
    (raw_to_bool (hd 0 buf)) c0
    between (book_after_suffix creast next rest ++ 5 :: tail)
    H12 H14 Hrestored H21' Hsplit H17 Hright H15 H16).
Qed.

(** ** Composed raw left cycle *)

Definition book_q13_perform_left_clock_raw
    (hit_init : list bool) (hit_w : bool) (buf : list nat)
    (tags : list nat) : nat :=
  restore_clock (match_mark hit_w) (rev (map match_mark hit_init)) buf +
  ((S (length (rev tags)) + S (length (tags ++ [4])) +
    S (length (book_return_rail_raw hit_init buf))) +
   (1 + S (length (source_bit hit_w ::
              rev (book_return_rail_raw hit_init buf))))).

Theorem book_steady_q5_locate_to_q5_left_raw_gen :
  forall (init : list bool) (w_read w_tape : bool) (buf : list nat)
         (ptape tail : list nat) (steps : list book_failure)
         (hit : book_row) (next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w : bool)
         (c0 : bool) (creast : list bool),
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
      (book_q5_raw init buf w_tape ptape w_read
        (map bf_row steps ++ hit :: next :: rest) tail)
    = cfg_ml 5
        (rev (source_bit hit_w ::
              rev (book_return_rail_raw hit_init buf)) ++
         6 :: rev ptape)
        ((if w_tape then 3 else 2) ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w_read]) hit ++ [4])) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init w_read w_tape buf ptape tail steps hit next rest
    hit_init hit_w c0 creast Hraw Hsteps Hcond Hlen Hact Hdir Hnext.
  set (dirs := book_return_rail_raw hit_init buf).
  set (tags := book_cycle_tags steps (init ++ [w_read]) hit).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock_gen init w_read w_tape steps hit)
    (book_q13_perform_left_clock_raw hit_init hit_w buf tags)).
  unfold book_steady_locate_q12_clock, book_cycle_region.
  rewrite (book_steady_q5_locate_to_q12_raw_gen init w_read w_tape buf
    ptape tail steps hit (next :: rest) Hsteps Hcond Hlen).
  rewrite Hdir.
  rewrite Hact.
  rewrite rev_match_mark_snoc_rows.
  assert (H12 : Forall q12_pass
    (match_mark hit_w :: rev (map match_mark hit_init) ++ 5 :: rev buf)).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_raw_q12_rev. exact Hraw. }
  assert (H14 : Forall q14_pass
    (buf ++ [5] ++ rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])).
  { apply Forall_app. split.
    - apply Forall_raw_q14. exact Hraw.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * rewrite rev_involutive. apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail_raw. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_ne : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (H21' : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. unfold dirs.
    apply Forall_raw_rev_source_bits_q21. exact Hraw. }
  assert (Hrestored :
    map q14_restore
      (rev (buf ++ [5] ++
            rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])) =
    source_bit hit_w :: hd 0 dirs :: tl dirs).
  { rewrite (book_restored_frame_raw hit_init buf hit_w Hraw).
    rewrite Hdirs_eq. unfold dirs. reflexivity. }
  assert (Hrestored' :
    source_bit hit_w :: hd 0 dirs :: tl dirs =
    source_bit hit_w :: hd 0 dirs :: tl dirs)
    by reflexivity.
  assert (Hdata : rev (ptape ++ [source_bit w_tape]) =
                  source_bit w_tape :: rev ptape).
  { rewrite rev_app_distr. cbn [rev]. reflexivity. }
  assert (H15 : Forall q15_pass (rev tags)).
  { unfold tags. rewrite book_cycle_tags_rev_eq.
    apply Forall_q15_cycle_rail. }
  assert (H16 : Forall q16_pass (tags ++ [4])).
  { unfold tags. apply Forall_q16_cycle_tags_snoc. }
  assert (Hright :
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark (hit_init ++ [hit_w])) ++
    book_cycle_dir_mark hit ::
      (book_raw_tail (next :: rest) ++ 5 :: tail) =
    rev tags ++ source_bit c0 ::
      (book_after_suffix creast next rest ++ 5 :: tail)).
  { unfold tags. rewrite book_cycle_tags_rev_eq.
    unfold book_cycle_marked.
    rewrite <- Hact.
    rewrite book_raw_tail_cons.
    rewrite (book_raw_desc_cons_cond next c0 creast rest Hnext).
    unfold book_cycle_dir_mark.
    cbn [app].
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity. }
  assert (Hreturn' : Forall q17_pass
    (source_bit hit_w :: rev (hd 0 dirs :: tl dirs))).
  { rewrite Hdirs_eq. unfold dirs.
    rewrite book_return_rail_raw_rev.
    constructor.
    - apply source_bit_q17.
    - apply Forall_app. split.
      + apply Forall_raw_q17. exact Hraw.
      + apply Forall_app. split.
        * constructor; [unfold q17_pass; auto 10 | constructor].
        * apply Forall_source_bits_q17. }
  unfold book_q13_perform_left_clock_raw, restore_clock.
  unfold book_cycle_region, book_cycle_dir_mark.
  fold dirs.
  rewrite <- Hdirs_eq.
  apply (book_q13_restore_to_q5_left
    (match_mark hit_w) (rev (map match_mark hit_init)) buf
    (ptape ++ [source_bit w_tape])
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark (hit_init ++ [hit_w]))
    (book_cycle_dir_mark hit)
    (book_raw_tail (next :: rest) ++ 5 :: tail)
    tags (source_bit hit_w :: hd 0 dirs :: tl dirs)
    hit_w (hd 0 dirs) (tl dirs) w_tape c0 (rev ptape)
    (book_after_suffix creast next rest ++ 5 :: tail)
    H12 H14 Hrestored Hrestored' Hdata Hright H15 H16 H21' Hreturn').
Qed.

Print Assumptions book_steady_q5_locate_to_q5_left_raw_gen.

(** ** Corrected global frame invariant

    The q6 source side is

      raw_ptape(c, lo) ++ [6] ++ raw_buf(c) ++ [5] ++ condition ++ ...

    where [raw_buf(c)] is the list of cells strictly right of the head,
    of length [R - head].  This is the invariant that the zero-buffer
    [book_buf b] approximated only when every right cell was blank. *)

Definition raw_ptape (c : LeftInfiniteConfig) (lo : Z) : list nat :=
  map (fun k => source_bit (lic_tape c (lo + Z.of_nat k)))
      (seq 0 (Z.to_nat (lic_head c - lo))).

Definition raw_buf (c : LeftInfiniteConfig) : list nat :=
  map (fun k => source_bit (lic_tape c
                (lic_head c + 1 + Z.of_nat k)))
      (seq 0 (Z.to_nat (lic_R c - lic_head c))).

Lemma source_bit_raw :
  forall b, raw_source_cell (source_bit b).
Proof. intros []; unfold raw_source_cell, source_bit; auto. Qed.

Lemma raw_buf_raw :
  forall c, raw_source_buffer (raw_buf c).
Proof.
  intros c. unfold raw_buf.
  apply Forall_map. apply Forall_forall. intros k _.
  apply source_bit_raw.
Qed.

Lemma raw_ptape_raw :
  forall c lo, raw_source_buffer (raw_ptape c lo).
Proof.
  intros c lo. unfold raw_ptape.
  apply Forall_map. apply Forall_forall. intros k _.
  apply source_bit_raw.
Qed.

Lemma raw_buf_length :
  forall c,
    (lic_head c <= lic_R c)%Z ->
    length (raw_buf c) = Z.to_nat (lic_R c - lic_head c).
Proof.
  intros c Hle. unfold raw_buf.
  rewrite map_length, seq_length. reflexivity.
Qed.

Lemma raw_buf_nil_of_boundary :
  forall c,
    lic_head c = lic_R c -> raw_buf c = [].
Proof.
  intros c H. unfold raw_buf. rewrite H.
  rewrite Z.sub_diag. reflexivity.
Qed.

Lemma raw_buf_nil_iff :
  forall c,
    left_infinite_ok c ->
    (raw_buf c = [] <-> lic_head c = lic_R c).
Proof.
  intros c [Hle Hblank]. split.
  - intro Hnil.
    assert (Hlen : length (raw_buf c) =
                   Z.to_nat (lic_R c - lic_head c))
      by (apply raw_buf_length; exact Hle).
    rewrite Hnil in Hlen. cbn [length] in Hlen.
    assert (Hn : Z.to_nat (lic_R c - lic_head c) = Z.to_nat 0)
      by (rewrite Z2Nat.inj_0; symmetry; exact Hlen).
    pose proof (Z2Nat.inj (lic_R c - lic_head c) 0
      ltac:(lia) ltac:(lia) Hn) as Heq.
    lia.
  - apply raw_buf_nil_of_boundary.
Qed.

Definition book_global_source_rep
    (c : LeftInfiniteConfig) (lo : Z) (ptape buf : list nat) : Prop :=
  (lo <= lic_head c)%Z /\
  left_infinite_ok c /\
  ptape = raw_ptape c lo /\
  buf = raw_buf c.

Lemma book_global_source_rep_buffer_length :
  forall c lo ptape buf,
    book_global_source_rep c lo ptape buf ->
    length buf = Z.to_nat (lic_R c - lic_head c).
Proof.
  intros c lo ptape buf [_ [Hok [Hp Hb]]].
  subst buf. apply raw_buf_length. apply Hok.
Qed.

Lemma book_global_source_rep_buffer_nil :
  forall c lo ptape buf,
    book_global_source_rep c lo ptape buf ->
    (buf = [] <-> lic_head c = lic_R c).
Proof.
  intros c lo ptape buf [_ [Hok [Hp Hb]]].
  subst buf. apply raw_buf_nil_iff. exact Hok.
Qed.

(** The exact q6 source-side frame shape used by the raw cycles.  The
    [desc] argument is the marked description rail, supplied by the
    locate phase. *)
Definition lic_q6_encode
    (lo : Z) (c : LeftInfiniteConfig) (desc : list nat) : Config :=
  entry_config 6
    (4 :: rev (map source_bit
                 (lic_state c ++ [lic_tape c (lic_head c)])) ++
     5 :: rev (raw_buf c) ++
     6 :: rev (raw_ptape c lo))
    desc.



(** ** Concrete sanity checks *)

Definition raw_right_sanity_input : Config :=
  entry_config 6 (book_q6_left_raw [false] [1;0] [0;1]) [2;1;1;5;0].

Definition raw_right_sanity_output : Config :=
  cfg_ml 5 [5;0;6;1;1;0]
    (3 :: 4 ::
     map q16_restore (book_q15_rail [false] [] true 3 [5]) ++ [0]).

Lemma raw_right_sanity :
  run (book_right_clock_raw [false] [] true [1;0] [5])
    raw_right_sanity_input = raw_right_sanity_output.
Proof.
  unfold raw_right_sanity_input, raw_right_sanity_output.
  apply (book_q6_to_q5_right_raw [false] [] true [1;0] [0;1] [5]
    false []).
  - reflexivity.
  - discriminate.
  - vm_compute; auto 20.
  - vm_compute; auto 20.
  - vm_compute; auto 20.
Qed.

Print Assumptions raw_right_sanity.

Lemma raw_right_sanity_physical :
  rev (t_left (c_tape raw_right_sanity_output)) ++
  t_right (c_tape raw_right_sanity_output)
  = [0;1;1;6;0;5;3;4;0;1;1;5;0].
Proof. vm_compute. reflexivity. Qed.

(** The old buffer was [1;0]; the target [1] is captured as the new
    read bit, and the new buffer is [0] = tl [1;0]. *)
Lemma raw_right_sanity_buffer :
  exists P,
    rev (t_left (c_tape raw_right_sanity_output)) ++
    t_right (c_tape raw_right_sanity_output)
    = [0;1] ++ [1] ++ [6] ++ tl [1;0] ++ [5] ++ P.
Proof. exists [3;4;0;1;1;5;0]. vm_compute. reflexivity. Qed.

(** The captured read mark is [3] = [match_mark true], i.e. the
    nonblank first buffer cell [1]. *)
Lemma raw_right_sanity_read :
  hd 0 (tl (t_right (c_tape raw_right_sanity_output))) = 3.
Proof. vm_compute. reflexivity. Qed.

Definition raw_left_sanity_input : Config :=
  entry_config 6 (book_q6_left_raw [false] [0;1] [1]) [2;1;0;0].

Definition raw_left_sanity_output : Config :=
  cfg_ml 5 [5;1;0;1;6]
    (3 :: map q16_restore (rev ([2;3;2] ++ [4])) ++ [0]).

Lemma raw_left_sanity :
  run (book_left_clock_raw [false] [] true [0;1] [] [2;3;2] 5 [1;0])
    raw_left_sanity_input = raw_left_sanity_output.
Proof.
  unfold raw_left_sanity_input, raw_left_sanity_output.
  apply (book_q6_to_q5_left_raw [false] [] true [0;1] [1] [] false []
    true [] 5 [1;0] [2;3;2]).
  - reflexivity.
  - vm_compute; auto 20.
  - reflexivity.
  - reflexivity.
  - reflexivity.
  - vm_compute; auto 20.
  - vm_compute; auto 20.
Qed.

Print Assumptions raw_left_sanity.

Lemma raw_left_sanity_physical :
  rev (t_left (c_tape raw_left_sanity_output)) ++
  t_right (c_tape raw_left_sanity_output)
  = [6;1;0;1;5;3;4;0;1;0;0].
Proof. vm_compute. reflexivity. Qed.

(** The old buffer was [0;1]; the left move prepends the write bit [1],
    so the new buffer is [1;0;1] = [source_bit true :: [0;1]]. *)
Lemma raw_left_sanity_buffer :
  exists P,
    rev (t_left (c_tape raw_left_sanity_output)) ++
    t_right (c_tape raw_left_sanity_output)
    = [6] ++ (source_bit true :: [0;1]) ++ [5] ++ P.
Proof. exists [3;4;0;1;0;0]. vm_compute. reflexivity. Qed.

Print Assumptions book_q6_to_q5_right_raw.
Print Assumptions book_q6_to_q5_left_raw.
Print Assumptions book_steady_q5_locate_to_q5_right_raw_gen.
Print Assumptions book_steady_q5_locate_to_q5_left_raw_gen.

(** ** Boundary: [buf = []] is the left-infinite halt at [head = R] *)

Lemma empty_buffer_no_raw_target :
  forall init,
    ~ (exists bit between,
        rev (book_return_rail_raw init []) = source_bit bit :: between).
Proof.
  intros init [bit [between H]].
  rewrite book_return_rail_raw_nil in H.
  injection H as H5 Htail.
  destruct bit; discriminate H5.
Qed.

(** The native q19 does not halt at [Y]; it passes it.  This is why the
    boundary case needs the separate q3/Y trace, not the ordinary
    right-perform theorem. *)
Lemma q19_crosses_y :
  forall left rest,
    step (entry_config 19 left (5 :: rest)) =
    entry_config 19 (5 :: left) rest.
Proof. reflexivity. Qed.

(** With an empty buffer the first cell after [Y] is a raw action bit;
    q19 captures that cell, not a simulated-tape blank. *)
Lemma q19_empty_buffer_captures_first_raw :
  forall left (i : bool) rest,
    run 2
      (entry_config 19 left (5 :: source_bit i :: rest)) =
    entry_config (if i then 18 else 17) (6 :: 5 :: left) rest.
Proof. intros. destruct i; reflexivity. Qed.

Definition at_right_boundary
    (buf : list nat) (c : LeftInfiniteConfig) : Prop :=
  buf = [] /\ lic_head c = lic_R c.

Lemma at_right_boundary_right_move_halts :
  forall rows c row buf,
    at_right_boundary buf c ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    wr_right row = true ->
    lic_halted (left_infinite_step rows c) = true.
Proof.
  intros rows c row buf [Hb Hhead] Hh Hlookup Hright.
  apply (left_infinite_step_right_blocked_halts rows c row); auto.
Qed.

Corollary book_global_source_rep_empty_buffer_boundary :
  forall c lo ptape buf,
    book_global_source_rep c lo ptape buf ->
    buf = [] ->
    lic_head c = lic_R c.
Proof.
  intros c lo ptape buf Hrep Hb.
  apply (proj1 (book_global_source_rep_buffer_nil c lo ptape buf Hrep)).
  exact Hb.
Qed.

Corollary book_global_source_rep_boundary_right_halts :
  forall rows c row lo ptape buf,
    book_global_source_rep c lo ptape buf ->
    buf = [] ->
    lic_halted c = false ->
    wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c)) = Some row ->
    wr_right row = true ->
    lic_halted (left_infinite_step rows c) = true.
Proof.
  intros rows c row lo ptape buf Hrep Hb Hh Hlookup Hright.
  apply (at_right_boundary_right_move_halts rows c row buf).
  - split.
    + exact Hb.
    + apply (book_global_source_rep_empty_buffer_boundary c lo ptape buf
        Hrep Hb).
  - exact Hh.
  - exact Hlookup.
  - exact Hright.
Qed.

Print Assumptions at_right_boundary_right_move_halts.
Print Assumptions book_global_source_rep_boundary_right_halts.
Print Assumptions empty_buffer_no_raw_target.

(** ** Exact encoder/cost premises for [MinskyLeftInfinite]

    [lic_q6_encode lo c desc] is the q6 source-side frame

      raw_ptape(c, lo) ++ [6] ++ raw_buf(c) ++ [5] ++ condition ++ ...

    with [buf = raw_buf(c)].  The three premises are the same three
    section variables of [conditional_left_source_native_halting_equivalence];
    the additional shape hypothesis records that the encoder really uses
    the raw-buffer q6 frame (it is not needed for the abstract equivalence
    itself, but it is the representation obligation of the concrete
    encoder).  The cost is the locate cost plus the raw perform clock,
    and in the boundary case the q3/Y trace; the latter is the remaining
    exact gap. *)

Section RawQ6EncoderPremises.

Variable encode :
  nat -> list WideSourceRow -> LeftInfiniteConfig -> Config.
Variable macro_cost :
  nat -> list WideSourceRow -> LeftInfiniteConfig -> nat.

Hypothesis raw_encode_q6_shape :
  forall p rows c,
    exists lo desc, encode p rows c = lic_q6_encode lo c desc.

Hypothesis raw_encode_reflects_halt :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    c_halted (encode p rows c) = lic_halted c.

Hypothesis raw_macro_cost_positive :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    1 <= macro_cost p rows c.

Hypothesis raw_actual_table_macro_step :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    run (macro_cost p rows c) (encode p rows c) =
    encode p rows (left_infinite_step rows c).

Theorem raw_q6_conditional_left_halting_equivalence :
  forall p rows c,
    Forall (wide_row_wellformed p) rows ->
    (left_infinite_eventually_halts rows c <->
     left_native_eventually_halts encode p rows c).
Proof.
  intros p rows c Hwf.
  apply (conditional_left_source_native_halting_equivalence encode macro_cost
    raw_encode_reflects_halt raw_macro_cost_positive
    raw_actual_table_macro_step p rows c Hwf).
Qed.

End RawQ6EncoderPremises.

Print Assumptions raw_q6_conditional_left_halting_equivalence.

(** Explicit physical form of the left update: the new buffer segment
    after [M] is [source_bit w :: buf]. *)
Lemma rev_cons_rev_raw :
  forall (D : list nat) (x : nat),
    rev (x :: rev D) = D ++ [x].
Proof.
  intros D x. cbn [rev]. rewrite rev_involutive. reflexivity.
Qed.

Lemma book_left_raw_physical :
  forall (init : list bool) (w : bool) (buf : list nat) (outer : list nat)
         (dir_head : nat) (dir_remaining : list nat),
    dir_head :: dir_remaining = book_return_rail_raw init buf ->
    rev (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
         6 :: outer)
    = rev outer ++ 6 :: source_bit w :: buf ++
      5 :: map source_bit init.
Proof.
  intros init w buf outer dir_head dir_remaining HD.
  rewrite HD.
  rewrite rev_cons_rev_raw.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  rewrite book_return_rail_raw_rev.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions book_left_raw_physical.
