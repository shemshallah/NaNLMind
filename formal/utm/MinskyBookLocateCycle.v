(** * Book-layout locate -> perform cycle (nonempty next-row case)

    This composes

      steady q5  ->  locate rows  ->  q6  ->  q12  ->  perform q5

    for the case where the matched row is followed by another row.
    The q12 perform rail is extended by the leading [X = 4] of the next
    row, so that the q15 scan has a raw source bit to stop at:

      rev tags = marked ++ [dir_mark; 4]
      target   = first condition bit of the next row

    where

      marked = (failed-row region ++ marks(src)) ++ marks(action hit).

    The [after = []] case (no next row) is the final-Y case; it needs a
    q15 stop-at-Y variant and is documented at the end of this file. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry MinskyConcreteDispatch
  MinskySourceEncoding MinskyMatchMacro MinskyCanonicalMatch
  MinskyActionMacro MinskyCanonicalCopy MinskyCanonicalCopyGeneral
  MinskyCanonicalDirection MinskyCanonicalInstruction MinskyHeadMoveMacro
  MinskyCanonicalRestore MinskyDirectionDecision MinskyRelocationMacro
  MinskyBookLayout MinskyBookCycle MinskyBookLeftCycle
  MinskyBookLocate MinskyBookLocateRows MinskyBookLocateWide.

(** ** Frame abbreviations *)

Definition book_cycle_region (steps : list book_failure) : list nat :=
  tl (book_marked_prefix (map bf_row steps) ++ [4]).

Definition book_cycle_marked
    (steps : list book_failure) (bits : list bool) (hit : book_row) : list nat :=
  book_cycle_region steps ++ map match_mark bits ++
  map match_mark (br_action hit).

Definition book_cycle_dir_mark (hit : book_row) : nat :=
  if br_dir hit then 3 else 2.

Definition book_cycle_tags
    (steps : list book_failure) (bits : list bool) (hit : book_row) : list nat :=
  rev (book_cycle_marked steps bits hit ++ [book_cycle_dir_mark hit; 4]).

Definition book_after_suffix
    (creast : list bool) (next : book_row) (rest : list book_row) : list nat :=
  map source_bit creast ++ map source_bit (br_action next) ++
  [source_bit (br_dir next)] ++ book_raw_tail rest.

Definition book_steady_locate_q12_clock
    (init : list bool) (w : bool) (steps : list book_failure)
    (hit : book_row) : nat :=
  S (length init) +
  (book_failures_clock [] steps +
   book_hit_clock (init ++ [w]) (map bf_row steps) +
   (copy_all_clock (init ++ [w]) (br_action hit) []
      (book_cycle_region steps ++ map match_mark (init ++ [w])) +
    direction_clock
      (book_cycle_region steps ++ map match_mark (init ++ [w]) ++
       map match_mark (br_action hit))
      (map match_mark (br_action hit)))).

Definition book_q12_perform_right_clock
    (hit_init : list bool) (hit_w : bool) (b : nat)
    (tags between : list nat) : nat :=
  restore_clock (match_mark hit_w) (rev (map match_mark hit_init))
    (book_buf (b - 1)) +
  ((S (length (rev tags)) + S (length (tags ++ [4])) +
    S (length (book_return_rail hit_init (b - 1)))) +
   (S (length ([] : list nat)) + S (length between))).

(** ** Passability helpers *)

Lemma q12_pass_match_mark : forall b, q12_pass (match_mark b).
Proof. intros [|]; unfold q12_pass, match_mark; auto 10. Qed.

Lemma q14_pass_match_mark : forall b, q14_pass (match_mark b).
Proof. intros [|]; unfold q14_pass, match_mark; auto 10. Qed.

Lemma q15_pass_dir_mark : forall b : bool, q15_pass (if b then 3 else 2).
Proof. intros [|]; unfold q15_pass; auto 10. Qed.

Lemma q16_pass_dir_mark : forall b : bool, q16_pass (if b then 3 else 2).
Proof. intros [|]; unfold q16_pass; auto 10. Qed.

Lemma Forall_q12_match_marks :
  forall bits, Forall q12_pass (map match_mark bits).
Proof. intros. apply Forall_match_mark. apply q12_pass_match_mark. Qed.

Lemma Forall_q14_match_marks :
  forall bits, Forall q14_pass (map match_mark bits).
Proof. intros. apply Forall_match_mark. apply q14_pass_match_mark. Qed.

Lemma Forall_q12_book_buf :
  forall n, Forall q12_pass (book_buf n).
Proof.
  induction n as [|n IH]; simpl.
  - constructor.
  - constructor; [unfold q12_pass; auto 10 | exact IH].
Qed.

Lemma Forall_q14_book_buf :
  forall n, Forall q14_pass (book_buf n).
Proof.
  induction n as [|n IH]; simpl.
  - constructor.
  - constructor; [unfold q14_pass; auto 10 | exact IH].
Qed.

Lemma Forall_q15_cycle_rail :
  forall steps bits hit,
    Forall q15_pass
      (book_cycle_marked steps bits hit ++
       [book_cycle_dir_mark hit; 4]).
Proof.
  intros steps bits hit.
  unfold book_cycle_marked, book_cycle_dir_mark.
  repeat rewrite Forall_app.
  repeat split.
  - apply Forall_q15_tl_marked_done.
  - apply Forall_q15_match_marks.
  - apply Forall_q15_match_marks.
  - constructor.
    + apply q15_pass_dir_mark.
    + constructor; [unfold q15_pass; auto 10 | constructor].
Qed.

Lemma Forall_q16_cycle_marked :
  forall steps bits hit,
    Forall q16_pass (book_cycle_marked steps bits hit).
Proof.
  intros steps bits hit.
  unfold book_cycle_marked.
  apply Forall_app. split.
  - apply Forall_q16_tl_marked_done.
  - apply Forall_app. split.
    + apply Forall_q16_match_marks.
    + apply Forall_q16_match_marks.
Qed.

Lemma Forall_q16_cycle_tags_snoc :
  forall steps bits hit,
    Forall q16_pass
      (book_cycle_tags steps bits hit ++ [4]).
Proof.
  intros steps bits hit.
  unfold book_cycle_tags.
  rewrite rev_app_distr.
  cbn [rev].
  constructor.
  - unfold q16_pass; auto 10.
  - constructor.
    + apply q16_pass_dir_mark.
    + apply Forall_app. split.
      * apply Forall_rev, Forall_q16_cycle_marked.
      * constructor; [unfold q16_pass; auto 10 | constructor].
Qed.

(** ** Frame algebra for the extended rail *)

Lemma rev_match_mark_snoc_rows :
  forall (init : list bool) (b : bool),
    rev (map match_mark (init ++ [b])) =
    match_mark b :: rev (map match_mark init).
Proof.
  intros. rewrite map_app, rev_app_distr. cbn [rev]. reflexivity.
Qed.

Lemma book_raw_desc_cons_cond :
  forall (next : book_row) (c0 : bool) (creast : list bool)
         (rest : list book_row),
    br_cond next = c0 :: creast ->
    book_raw_desc (next :: rest) =
    source_bit c0 :: book_after_suffix creast next rest.
Proof.
  intros next c0 creast rest Hcond.
  rewrite book_raw_desc_cons.
  unfold book_raw_row, book_after_suffix.
  rewrite Hcond. cbn [map app].
  repeat rewrite <- app_assoc. cbn [app].
  reflexivity.
Qed.

Lemma book_cycle_tags_rev_eq :
  forall steps bits hit,
    rev (book_cycle_tags steps bits hit) =
    book_cycle_marked steps bits hit ++
    [book_cycle_dir_mark hit; 4].
Proof.
  intros. unfold book_cycle_tags. rewrite rev_involutive. reflexivity.
Qed.

(** ** Main composition *)

Theorem book_steady_q5_locate_to_q5_right :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w : bool)
         (c0 : bool) (creast : list bool),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w]) steps ->
    br_cond hit = init ++ [w] ->
    length (br_action hit) = length (init ++ [w]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    br_cond next = c0 :: creast ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ->
    run (book_steady_locate_q12_clock init w steps hit +
         book_q12_perform_right_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w]) hit)
           (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape)
        (match_mark w :: 4 ::
         book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++
         5 :: tail))
    = cfg_ml 5
        (rev (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ++
         6 :: source_bit hit_w :: rev (ptape ++ [source_bit w]))
        (2 :: 4 ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w]) hit)) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init w b ptape tail steps hit next rest hit_init hit_w c0 creast
    Hb Hsteps Hcond Hlen Hact Hdir Hnext H21 H17.
  set (between :=
    tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init).
  set (dirs := book_return_rail hit_init (b - 1)).
  set (tags := book_cycle_tags steps (init ++ [w]) hit).
  change (run (book_steady_locate_q12_clock init w steps hit +
               book_q12_perform_right_clock hit_init hit_w b tags between)
    (cfg_ml 5
      (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
       6 :: source_bit w :: rev ptape)
      (match_mark w :: 4 ::
       book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++
       5 :: tail))
    = cfg_ml 5
        (rev (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ++
         6 :: source_bit hit_w :: rev (ptape ++ [source_bit w]))
        (2 :: 4 :: map q16_restore (rev tags) ++
         source_bit c0 :: book_after_suffix creast next rest ++ 5 :: tail)).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock init w steps hit)
    (book_q12_perform_right_clock hit_init hit_w b tags between)).
  unfold book_steady_locate_q12_clock, book_cycle_region.
  assert (Hb1 : 1 <= b) by lia.
  rewrite (book_steady_q5_locate_to_q12 init w b ptape tail steps hit
    (next :: rest) Hb1 Hsteps Hcond Hlen).
  (* The q12 frame. *)
  rewrite Hdir.
  rewrite Hact.
  rewrite rev_match_mark_snoc_rows.
  (* Passability hypotheses. *)
  assert (H12 : Forall q12_pass
    (match_mark hit_w :: rev (map match_mark hit_init) ++
     5 :: rev (book_buf (b - 1)))).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_rev, Forall_q12_book_buf. }
  assert (H14 : Forall q14_pass
    (book_buf (b - 1) ++ [5] ++
     rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])).
  { apply Forall_app. split.
    - apply Forall_q14_book_buf.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * rewrite rev_involutive. apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_ne : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (H21' : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. exact H21. }
  assert (Hrestored :
    map q14_restore
      (rev (book_buf (b - 1) ++ [5] ++
            rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])) =
    source_bit hit_w :: hd 0 dirs :: tl dirs).
  { rewrite (book_restored_frame hit_init (b - 1) hit_w).
    rewrite Hdirs_eq. reflexivity. }
  assert (Hsplit : rev (hd 0 dirs :: tl dirs) =
                   source_bit false :: between).
  { rewrite Hdirs_eq. unfold dirs, between.
    apply book_return_split. lia. }
  assert (H15 : Forall q15_pass (rev tags)).
  { unfold tags. rewrite book_cycle_tags_rev_eq.
    apply Forall_q15_cycle_rail. }
  assert (H16 : Forall q16_pass (tags ++ [4])).
  { unfold tags. apply Forall_q16_cycle_tags_snoc. }
  assert (Hright :
    ((book_cycle_region steps ++ map match_mark (init ++ [w])) ++
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
  unfold book_q12_perform_right_clock, restore_clock.
  unfold book_cycle_region, book_cycle_dir_mark.
  fold dirs.
  rewrite <- Hdirs_eq.
  assert (Hq12 :
    cfg_ml 12
      ((match_mark hit_w :: rev (map match_mark hit_init)) ++
       5 :: rev (book_buf (b - 1)) ++ 6 :: rev (ptape ++ [source_bit w]))
      (4 ::
       (((tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
          map match_mark (init ++ [w])) ++
         map match_mark (hit_init ++ [hit_w])) ++
        3 :: book_raw_tail (next :: rest) ++ 5 :: tail))
    = cfg_ml 12
      ((match_mark hit_w :: rev (map match_mark hit_init)) ++
       5 :: rev (book_buf (b - 1)) ++ 6 :: rev (ptape ++ [source_bit w]))
      (4 ::
       ((book_cycle_region steps ++ map match_mark (init ++ [w])) ++
        map match_mark (hit_init ++ [hit_w])) ++
        book_cycle_dir_mark hit ::
        book_raw_tail (next :: rest) ++ 5 :: tail)).
  { fold book_cycle_region.
    unfold book_cycle_dir_mark. rewrite Hdir.
    cbn [app]. reflexivity. }
  rewrite Hq12.
  eapply (book_q12_restore_to_q5_right
    (match_mark hit_w) (rev (map match_mark hit_init))
    (book_buf (b - 1)) (ptape ++ [source_bit w])
    ((book_cycle_region steps ++ map match_mark (init ++ [w])) ++
     map match_mark (hit_init ++ [hit_w]))
    (book_cycle_dir_mark hit)
    (book_raw_tail (next :: rest) ++ 5 :: tail)
    tags hit_w (hd 0 dirs) (tl dirs) false c0
    between (book_after_suffix creast next rest ++ 5 :: tail)
    H12 H14 Hrestored H21' Hsplit H17 Hright H15 H16).
Qed.

Print Assumptions book_steady_q5_locate_to_q5_right.

(** ** The [after = []] case (last matched row)

    If the matched row is the last row, the q6/q12 right tape has no
    following [X = 4]:

      right = 4 :: marked ++ dir_mark :: 5 :: tail

    where [marked = (region ++ marks(bits)) ++ marks(action hit)].
    The q15 rail therefore ends at the final [Y = 5].  Since
    [q15_pass] includes [5], the current
    [book_q12_restore_to_q5_right] / [q15_q22_right_to_q5_book] path
    would scan past the final [Y] rather than stop on a raw source bit.

    The missing piece is a q15 stop-at-Y variant, e.g.

      run (S (length rail))
        (entry_config 15 ... (rail ++ 5 :: tail)) = <halt or q5 frame>

    with the q16 restore applied only to [rail] and the final [Y] left
    untouched.  Alternatively, the concrete encoder may place a
    sentinel raw bit (a [0]) between the last row's direction bit and
    the final [Y]; then the theorem above applies with [next] being the
    sentinel row and [creast = []].  We do not claim a theorem for the
    bare final-Y case here; this is a representation obligation, not a
    missing list-algebra step.
*)

(** ** Left-direction analogue *)

Definition book_q13_perform_left_clock
    (hit_init : list bool) (hit_w : bool) (b : nat) (tags : list nat) : nat :=
  restore_clock (match_mark hit_w) (rev (map match_mark hit_init))
    (book_buf (b - 1)) +
  ((S (length (rev tags)) + S (length (tags ++ [4])) +
    S (length (book_return_rail hit_init (b - 1)))) +
   (1 + S (length (source_bit hit_w ::
               rev (book_return_rail hit_init (b - 1)))))).

Theorem book_steady_q5_locate_to_q5_left :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w : bool)
         (c0 : bool) (creast : list bool),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w]) steps ->
    br_cond hit = init ++ [w] ->
    length (br_action hit) = length (init ++ [w]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = false ->
    br_cond next = c0 :: creast ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (source_bit hit_w :: rev (book_return_rail hit_init (b - 1))) ->
    run (book_steady_locate_q12_clock init w steps hit +
         book_q13_perform_left_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w]) hit))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape)
        (match_mark w :: 4 ::
         book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++
         5 :: tail))
    = cfg_ml 5
        (rev (source_bit hit_w ::
              rev (hd 0 (book_return_rail hit_init (b - 1)) ::
                   tl (book_return_rail hit_init (b - 1)))) ++
         6 :: rev ptape)
        ((if w then 3 else 2) ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w]) hit ++ [4])) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init w b ptape tail steps hit next rest hit_init hit_w c0 creast
    Hb Hsteps Hcond Hlen Hact Hdir Hnext H21 Hreturn.
  set (dirs := book_return_rail hit_init (b - 1)).
  set (tags := book_cycle_tags steps (init ++ [w]) hit).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock init w steps hit)
    (book_q13_perform_left_clock hit_init hit_w b tags)).
  unfold book_steady_locate_q12_clock, book_cycle_region.
  assert (Hb1 : 1 <= b) by lia.
  rewrite (book_steady_q5_locate_to_q12 init w b ptape tail steps hit
    (next :: rest) Hb1 Hsteps Hcond Hlen).
  rewrite Hdir.
  rewrite Hact.
  rewrite rev_match_mark_snoc_rows.
  assert (H12 : Forall q12_pass
    (match_mark hit_w :: rev (map match_mark hit_init) ++
     5 :: rev (book_buf (b - 1)))).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_rev, Forall_q12_book_buf. }
  assert (H14 : Forall q14_pass
    (book_buf (b - 1) ++ [5] ++
     rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])).
  { apply Forall_app. split.
    - apply Forall_q14_book_buf.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * rewrite rev_involutive. apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_ne : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (H21' : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. exact H21. }
  assert (Hrestored :
    map q14_restore
      (rev (book_buf (b - 1) ++ [5] ++
            rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])) =
    source_bit hit_w :: hd 0 dirs :: tl dirs).
  { rewrite (book_restored_frame hit_init (b - 1) hit_w).
    rewrite Hdirs_eq. reflexivity. }
  assert (Hrestored' :
    source_bit hit_w :: hd 0 dirs :: tl dirs =
    source_bit hit_w :: hd 0 dirs :: tl dirs)
    by reflexivity.
  assert (Hdata : rev (ptape ++ [source_bit w]) = source_bit w :: rev ptape).
  { rewrite rev_app_distr. cbn [rev]. reflexivity. }
  assert (H15 : Forall q15_pass (rev tags)).
  { unfold tags. rewrite book_cycle_tags_rev_eq.
    apply Forall_q15_cycle_rail. }
  assert (H16 : Forall q16_pass (tags ++ [4])).
  { unfold tags. apply Forall_q16_cycle_tags_snoc. }
  assert (Hright :
    ((book_cycle_region steps ++ map match_mark (init ++ [w])) ++
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
  { rewrite Hdirs_eq. exact Hreturn. }
  (* Normalize the q13 frame and clock for the application. *)
  unfold book_q13_perform_left_clock, restore_clock.
  unfold book_cycle_region, book_cycle_dir_mark.
  fold dirs.
  rewrite <- Hdirs_eq.
  assert (Hq13 :
    cfg_ml 13
      ((match_mark hit_w :: rev (map match_mark hit_init)) ++
       5 :: rev (book_buf (b - 1)) ++ 6 :: rev (ptape ++ [source_bit w]))
      (4 ::
       (((tl (book_marked_prefix (map bf_row steps) ++ [4]) ++
          map match_mark (init ++ [w])) ++
         map match_mark (hit_init ++ [hit_w])) ++
        2 :: book_raw_tail (next :: rest) ++ 5 :: tail))
    = cfg_ml 13
      ((match_mark hit_w :: rev (map match_mark hit_init)) ++
       5 :: rev (book_buf (b - 1)) ++ 6 :: rev (ptape ++ [source_bit w]))
      (4 ::
       ((book_cycle_region steps ++ map match_mark (init ++ [w])) ++
        map match_mark (hit_init ++ [hit_w])) ++
        book_cycle_dir_mark hit ::
        book_raw_tail (next :: rest) ++ 5 :: tail)).
  { fold book_cycle_region.
    unfold book_cycle_dir_mark. rewrite Hdir.
    cbn [app]. reflexivity. }
  rewrite Hq13.
  apply (book_q13_restore_to_q5_left
    (match_mark hit_w) (rev (map match_mark hit_init))
    (book_buf (b - 1)) (ptape ++ [source_bit w])
    ((book_cycle_region steps ++ map match_mark (init ++ [w])) ++
     map match_mark (hit_init ++ [hit_w]))
    (book_cycle_dir_mark hit)
    (book_raw_tail (next :: rest) ++ 5 :: tail)
    tags (source_bit hit_w :: hd 0 dirs :: tl dirs)
    hit_w (hd 0 dirs) (tl dirs) w c0 (rev ptape)
    (book_after_suffix creast next rest ++ 5 :: tail)
    H12 H14 Hrestored Hrestored' Hdata Hright H15 H16 H21' Hreturn').
Qed.

Print Assumptions book_steady_q5_locate_to_q5_left.

(** ** Two-boolean steady q5 adapter

    The right perform writes the write bit [w_tape] into the ptape and
    leaves a blank buffer cell [2] as the new read bit; the left perform
    can instead make the last ptape cell the new read bit.  The condition
    bit and the ptape cell are therefore independent in general. *)

Lemma book_q5_steady_to_locate_state_gen :
  forall (init : list bool) (w_read w_tape : bool) (b : nat)
         (ptape tail : list nat) (rows : list book_row),
    1 <= b ->
    rows <> [] ->
    run (S (length init))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 :: book_raw_desc rows ++ 5 :: tail))
    = book_locate_state (init ++ [w_read]) [] rows (b - 1)
        (ptape ++ [source_bit w_tape]) tail.
Proof.
  intros init w_read w_tape b ptape tail rows Hb Hrows.
  replace (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
           6 :: source_bit w_tape :: rev ptape)
    with (rev (map source_bit init) ++ 5 ::
          (rev (tl (book_buf b)) ++ 6 :: source_bit w_tape :: rev ptape)).
  2:{ rewrite rev_app_distr. cbn [rev].
      rewrite rev_app_distr. cbn [rev].
      repeat rewrite <- app_assoc. reflexivity. }
  rewrite (book_q5_steady_to_q1 init w_read
    (rev (tl (book_buf b)) ++ 6 :: source_bit w_tape :: rev ptape)
    (book_raw_desc rows ++ 5 :: tail)).
  destruct rows as [|r rest]; [contradiction|].
  unfold book_locate_state.
  cbn [book_marked_prefix app].
  rewrite book_raw_tail_cons.
  rewrite book_buf_pred_rev by exact Hb.
  rewrite rev_ptape_source_bit.
  cbn [app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions book_q5_steady_to_locate_state_gen.

(** ** Restoring the extended rail to the raw description *)

Lemma map_entry_rewrite_book_raw_row :
  forall r,
    map entry_rewrite (book_raw_row r) = book_marked_row r.
Proof.
  intros r. unfold book_raw_row, book_marked_row.
  repeat rewrite map_app. cbn [map].
  rewrite map_entry_rewrite_source_bits.
  rewrite map_entry_rewrite_source_bits.
  rewrite entry_rewrite_source_bit.
  reflexivity.
Qed.

Lemma book_marked_done_cons_tail :
  forall (rows : list book_row) (tail : list nat),
    book_marked_prefix rows ++ [4] ++ tail =
    (4 :: tl (book_marked_prefix rows ++ [4])) ++ tail.
Proof.
  intros. rewrite app_assoc. rewrite book_marked_done_cons.
  reflexivity.
Qed.

Lemma book_raw_tail_app_singleton :
  forall (rows : list book_row) (r : book_row),
    book_raw_tail (rows ++ [r]) = 4 :: book_raw_desc (rows ++ [r]).
Proof.
  intros [|r0 rest] r; reflexivity.
Qed.

Lemma book_cycle_tags_entry_rewrite :
  forall (steps : list book_failure) (bits : list bool) (hit : book_row),
    bits = br_cond hit ->
    rev (book_cycle_tags steps bits hit) =
    map entry_rewrite (book_raw_desc (map bf_row steps ++ [hit]) ++ [4]).
Proof.
  induction steps as [|r rest IH]; intros bits hit Hbits.
  - subst bits.
    rewrite book_cycle_tags_rev_eq.
    unfold book_cycle_marked, book_cycle_region.
    cbn [book_marked_prefix tl].
    unfold book_cycle_dir_mark.
    cbn [map app].
    rewrite book_raw_desc_cons.
    cbn [book_raw_tail app].
    rewrite app_nil_r.
    rewrite map_app.
    rewrite map_entry_rewrite_book_raw_row.
    unfold book_marked_row, book_cycle_dir_mark, match_mark.
    cbn [book_marked_prefix tl app map entry_rewrite].
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity.
  - subst bits.
    rewrite book_cycle_tags_rev_eq.
    unfold book_cycle_marked, book_cycle_region.
    cbn [book_marked_prefix tl map app].
    repeat rewrite <- app_assoc.
    rewrite (book_marked_done_cons_tail (map bf_row rest)).
    cbn [app].
    replace (tl (book_marked_prefix (map bf_row rest) ++ [4]) ++
             map match_mark (br_cond hit) ++
             map match_mark (br_action hit) ++
             [book_cycle_dir_mark hit; 4])
      with (rev (book_cycle_tags rest (br_cond hit) hit)).
    { rewrite (IH (br_cond hit) hit eq_refl).
      rewrite book_raw_desc_cons.
      rewrite (book_raw_tail_app_singleton (map bf_row rest) hit).
      repeat rewrite map_app.
      rewrite map_entry_rewrite_book_raw_row.
      cbn [app].
      repeat rewrite <- app_assoc.
      reflexivity. }
    { unfold book_cycle_tags, book_cycle_marked, book_cycle_region.
      rewrite rev_involutive.
      repeat rewrite <- app_assoc.
      cbn [app].
      reflexivity. }
Qed.

Print Assumptions book_cycle_tags_entry_rewrite.

(** ** Sentinel last row

    The sentinel row is a deliberately non-matching row placed after the
    last real row.  Its first condition bit [c0 = negb (hd newsrc)] is
    the raw bit used by the q15 scan, and it mismatches the first bit of
    the next source condition [newsrc].  After the perform the q5 locate
    retries the description, eventually fails on [sentinel], and halts
    via [q3/Y]. *)

Definition book_sentinel_row
    (newsrc creast : list bool) : book_row :=
  {| br_cond := negb (hd false newsrc) :: creast;
     br_action := [];
     br_dir := false |}.

Lemma book_hd_tl_bool :
  forall (src : list bool), src <> [] -> src = hd false src :: tl src.
Proof.
  intros [|b rest] H; [contradiction|reflexivity].
Qed.

Lemma app_singleton_bool_neq_nil :
  forall (l : list bool) (b : bool), l ++ [b] <> [].
Proof.
  intros l b H. assert (Hlen := f_equal (@length bool) H).
  rewrite app_length in Hlen. cbn [length] in Hlen. lia.
Qed.

Definition book_sentinel_failure
    (newsrc creast : list bool) (Hne : newsrc <> []) : book_failure :=
  {| bf_src := newsrc;
     bf_row := book_sentinel_row newsrc creast;
     bf_good := [];
     bf_bit := hd false newsrc;
     bf_src_rest := tl newsrc;
     bf_row_rest := creast;
     bf_src_split := book_hd_tl_bool newsrc Hne;
     bf_row_split := eq_refl |}.

Lemma book_sentinel_failure_src :
  forall newsrc creast Hne,
    bf_src (book_sentinel_failure newsrc creast Hne) = newsrc.
Proof. reflexivity. Qed.

Lemma book_sentinel_failure_row :
  forall newsrc creast Hne,
    bf_row (book_sentinel_failure newsrc creast Hne) =
    book_sentinel_row newsrc creast.
Proof. reflexivity. Qed.

Lemma book_sentinel_failure_mismatch :
  forall newsrc creast Hne,
    br_cond (book_sentinel_row newsrc creast) =
    bf_good (book_sentinel_failure newsrc creast Hne) ++
    negb (bf_bit (book_sentinel_failure newsrc creast Hne)) ::
    bf_row_rest (book_sentinel_failure newsrc creast Hne).
Proof. reflexivity. Qed.

Print Assumptions book_sentinel_failure_mismatch.

(** ** q16 restoration of the sentinel frame *)

Lemma Forall_entry_scan_source_bits :
  forall bits, Forall entry_scan_symbol (map source_bit bits).
Proof.
  induction bits as [|b rest IH]; simpl.
  - constructor.
  - constructor.
    + destruct b; unfold entry_scan_symbol, source_bit; auto 10.
    + exact IH.
Qed.

Lemma Forall_entry_scan_book_raw_row :
  forall r, Forall entry_scan_symbol (book_raw_row r).
Proof.
  intros r. unfold book_raw_row.
  apply Forall_app. split.
  - apply Forall_entry_scan_source_bits.
  - apply Forall_app. split.
    + apply Forall_entry_scan_source_bits.
    + constructor.
      * destruct (br_dir r); unfold entry_scan_symbol, source_bit; auto 10.
      * constructor.
Qed.

Lemma Forall_entry_scan_book_raw_desc :
  forall rows, Forall entry_scan_symbol (book_raw_desc rows).
Proof.
  induction rows as [|r rest IH]; simpl.
  - constructor.
  - apply Forall_app. split.
    + apply Forall_entry_scan_book_raw_row.
    + destruct rest as [|r0 rest0]; simpl.
      * constructor.
      * constructor.
        -- unfold entry_scan_symbol; auto 10.
        -- exact IH.
Qed.

Lemma Forall_entry_scan_book_raw_desc_snoc :
  forall rows, Forall entry_scan_symbol (book_raw_desc rows ++ [4]).
Proof.
  intros. apply Forall_app. split.
  - apply Forall_entry_scan_book_raw_desc.
  - constructor; [unfold entry_scan_symbol; auto 10 | constructor].
Qed.

Lemma q16_entry_rewrite_id :
  forall l,
    Forall entry_scan_symbol l ->
    map q16_restore (map entry_rewrite l) = l.
Proof.
  induction l as [|s rest IH]; intros H.
  - reflexivity.
  - inversion H as [|? ? Hs Hrest]; subst.
    simpl. destruct Hs as [-> | [-> | ->]]; simpl;
      rewrite IH by exact Hrest; reflexivity.
Qed.

Lemma book_raw_desc_snoc_two :
  forall (rows : list book_row) (r s : book_row),
    book_raw_desc (rows ++ [r; s]) =
    book_raw_desc (rows ++ [r]) ++ 4 :: book_raw_row s.
Proof.
  induction rows as [|r0 rest IH]; intros r s.
  - cbn [book_raw_desc book_raw_tail app].
    repeat rewrite app_nil_r. cbn [app].
    repeat rewrite <- app_assoc. cbn [app]. reflexivity.
  - cbn [book_raw_desc app].
    assert (Hassoc : rest ++ [r; s] = (rest ++ [r]) ++ [s])
      by (repeat rewrite <- app_assoc; cbn [app]; reflexivity).
    rewrite Hassoc.
    change (match (rest ++ [r]) ++ [s] with
            | [] => [] | _ => 4 :: book_raw_desc ((rest ++ [r]) ++ [s]) end)
      with (book_raw_tail ((rest ++ [r]) ++ [s])).
    change (match rest ++ [r] with
            | [] => [] | _ => 4 :: book_raw_desc (rest ++ [r]) end)
      with (book_raw_tail (rest ++ [r])).
    rewrite (book_raw_tail_app_singleton (rest ++ [r]) s).
    rewrite (book_raw_tail_app_singleton rest r).
    rewrite <- Hassoc.
    rewrite IH.
    repeat rewrite <- app_assoc.
    cbn [app].
    reflexivity.
Qed.

Lemma book_sentinel_restore_frame :
  forall (steps : list book_failure) (hit : book_row)
         (bits newsrc creast : list bool),
    br_cond hit = bits ->
    map q16_restore (rev (book_cycle_tags steps bits hit)) ++
    source_bit (negb (hd false newsrc)) ::
    book_after_suffix creast (book_sentinel_row newsrc creast) [] =
    book_raw_desc (map bf_row steps ++
      hit :: [book_sentinel_row newsrc creast]).
Proof.
  intros steps hit bits newsrc creast Hcond.
  rewrite (book_cycle_tags_entry_rewrite steps bits hit (eq_sym Hcond)).
  rewrite q16_entry_rewrite_id
    by apply Forall_entry_scan_book_raw_desc_snoc.
  rewrite (book_raw_desc_snoc_two (map bf_row steps) hit
    (book_sentinel_row newsrc creast)).
  unfold book_after_suffix, book_sentinel_row.
  cbn [map br_action br_dir book_raw_tail].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.


Lemma book_sentinel_restore_frame_tail :
  forall (steps : list book_failure) (hit : book_row)
         (bits newsrc creast : list bool) (tail : list nat),
    br_cond hit = bits ->
    map q16_restore (rev (book_cycle_tags steps bits hit)) ++
    source_bit (negb (hd false newsrc)) ::
    book_after_suffix creast (book_sentinel_row newsrc creast) [] ++ tail =
    book_raw_desc (map bf_row steps ++
      hit :: [book_sentinel_row newsrc creast]) ++ tail.
Proof.
  intros steps hit bits newsrc creast tail Hcond.
  replace (map q16_restore (rev (book_cycle_tags steps bits hit)) ++
           source_bit (negb (hd false newsrc)) ::
           book_after_suffix creast (book_sentinel_row newsrc creast) [] ++
           tail)
    with ((map q16_restore (rev (book_cycle_tags steps bits hit)) ++
           source_bit (negb (hd false newsrc)) ::
           book_after_suffix creast (book_sentinel_row newsrc creast) []) ++
          tail)
    by (rewrite <- app_assoc; reflexivity).
  rewrite (book_sentinel_restore_frame steps hit bits newsrc creast Hcond).
  reflexivity.
Qed.


Print Assumptions book_sentinel_restore_frame.

Definition book_sentinel_halt_left
    (retry_steps : list book_failure) (sf : book_failure)
    (buf : nat) (ptape tail : list nat) : list nat :=
  rev (map source_bit (bf_row_rest sf) ++
       map source_bit (br_action (bf_row sf)) ++
       [source_bit (br_dir (bf_row sf))]) ++
  match_mark (negb (bf_bit sf)) ::
  rev (map match_mark (bf_src_rest sf) ++
       (book_marked_prefix (map bf_row retry_steps) ++ [4]) ++
       map match_mark (bf_good sf)) ++
  match_raw (bf_bit sf) :: rev (map match_raw (bf_good sf)) ++
  5 :: (rev (book_buf buf) ++ 6 :: rev ptape).

Theorem book_q5_after_perform_right_sentinel_halt :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (hit_init : list bool) (hit_w : bool) (creast : list bool)
         (retry_steps : list book_failure),
    2 <= b ->
    Forall (fun st => bf_src st = hit_init ++ [false]) retry_steps ->
    map bf_row
      (retry_steps ++
       [book_sentinel_failure (hit_init ++ [false]) creast
          (app_singleton_bool_neq_nil hit_init false)]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [false]) creast] ->
    run (S (length hit_init) +
         (book_failures_clock [] retry_steps +
          book_halt_clock (map bf_row retry_steps)
            (book_sentinel_failure (hit_init ++ [false]) creast
               (app_singleton_bool_neq_nil hit_init false))))
      (cfg_ml 5
        (rev (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ++
         6 :: source_bit hit_w :: rev (ptape ++ [source_bit w]))
        (2 :: 4 ::
         book_raw_desc
           (map bf_row steps ++ hit ::
            [book_sentinel_row (hit_init ++ [false]) creast]) ++
         5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left retry_steps
           (book_sentinel_failure (hit_init ++ [false]) creast
              (app_singleton_bool_neq_nil hit_init false))
           (b - 2) (ptape ++ [source_bit w] ++ [source_bit hit_w]) tail)
        tail.
Proof.
  intros init w b ptape tail steps hit hit_init hit_w creast retry_steps
    Hb Hretry Hrows.
  set (newsrc := hit_init ++ [false]).
  set (sf := book_sentinel_failure newsrc creast
               (app_singleton_bool_neq_nil hit_init false)).
  fold newsrc sf in Hrows.
  rewrite <- Hrows.
  replace (2 :: 4 :: book_raw_desc (map bf_row (retry_steps ++ [sf])) ++
           5 :: tail)
    with (match_mark false :: 4 ::
          book_raw_desc (map bf_row (retry_steps ++ [sf])) ++ 5 :: tail)
    by reflexivity.
  rewrite (dispatch_run_add (S (length hit_init))
    (book_failures_clock [] retry_steps +
     book_halt_clock (map bf_row retry_steps) sf)).
  assert (Hb1 : 1 <= b - 1) by lia.
  assert (Hrows_ne : map bf_row (retry_steps ++ [sf]) <> []).
  { rewrite map_app. cbn [map].
    apply app_cons_book_row_neq_nil. }
  rewrite (book_q5_steady_to_locate_state_gen hit_init false hit_w (b - 1)
    (ptape ++ [source_bit w]) tail (map bf_row (retry_steps ++ [sf]))
    Hb1 Hrows_ne).
  assert (Hretry' : Forall (fun st => bf_src st = newsrc)
    (retry_steps ++ [sf])).
  { apply Forall_app. split.
    - unfold newsrc. exact Hretry.
    - constructor.
      + unfold sf, newsrc. apply book_sentinel_failure_src.
      + constructor. }
  replace (b - 1 - 1) with (b - 2) by lia.
  replace ((ptape ++ [source_bit w]) ++ [source_bit hit_w])
    with (ptape ++ [source_bit w] ++ [source_bit hit_w])
    by (rewrite <- app_assoc; reflexivity).
  replace (map bf_row retry_steps ++ map bf_row [sf])
    with (map bf_row (retry_steps ++ [sf]))
    by (rewrite <- map_app; reflexivity).
  apply (book_locate_rows_to_halt newsrc [] retry_steps sf
    (b - 2) (ptape ++ [source_bit w] ++ [source_bit hit_w]) tail Hretry').
Qed.

Print Assumptions book_q5_after_perform_right_sentinel_halt.

(** ** Full sentinel halt composition (right perform) *)

Theorem book_steady_q5_locate_perform_right_sentinel_halt :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (hit_init : list bool) (hit_w : bool) (creast : list bool)
         (retry_steps : list book_failure),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w]) steps ->
    br_cond hit = init ++ [w] ->
    length (br_action hit) = length (init ++ [w]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ->
    Forall (fun st => bf_src st = hit_init ++ [false]) retry_steps ->
    map bf_row
      (retry_steps ++
       [book_sentinel_failure (hit_init ++ [false]) creast
          (app_singleton_bool_neq_nil hit_init false)]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [false]) creast] ->
    run (book_steady_locate_q12_clock init w steps hit +
         book_q12_perform_right_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w]) hit)
           (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) +
         (S (length hit_init) +
          (book_failures_clock [] retry_steps +
           book_halt_clock (map bf_row retry_steps)
             (book_sentinel_failure (hit_init ++ [false]) creast
                (app_singleton_bool_neq_nil hit_init false)))))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape)
        (match_mark w :: 4 ::
         book_raw_desc
           (map bf_row steps ++ hit ::
            [book_sentinel_row (hit_init ++ [false]) creast]) ++
         5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left retry_steps
           (book_sentinel_failure (hit_init ++ [false]) creast
              (app_singleton_bool_neq_nil hit_init false))
           (b - 2) (ptape ++ [source_bit w] ++ [source_bit hit_w]) tail)
        tail.
Proof.
  intros init w b ptape tail steps hit hit_init hit_w creast retry_steps
    Hb Hsteps Hcond Hlen Hact Hdir H21 H17 Hretry Hrows.
  set (newsrc := hit_init ++ [false]).
  set (sentinel := book_sentinel_row newsrc creast).
  set (sf := book_sentinel_failure newsrc creast
               (app_singleton_bool_neq_nil hit_init false)).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock init w steps hit +
     book_q12_perform_right_clock hit_init hit_w b
       (book_cycle_tags steps (init ++ [w]) hit)
       (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init))
    (S (length hit_init) +
     (book_failures_clock [] retry_steps +
      book_halt_clock (map bf_row retry_steps) sf))).
  rewrite (book_steady_q5_locate_to_q5_right init w b ptape tail steps hit
    sentinel [] hit_init hit_w (negb (hd false newsrc)) creast
    Hb Hsteps Hcond Hlen Hact Hdir eq_refl H21 H17).
  subst sentinel.
  rewrite (book_sentinel_restore_frame_tail steps hit (init ++ [w]) newsrc
    creast (5 :: tail) Hcond).
  fold sf.
  apply (book_q5_after_perform_right_sentinel_halt init w b ptape tail steps hit
    hit_init hit_w creast retry_steps Hb Hretry Hrows).
Qed.

Print Assumptions book_steady_q5_locate_perform_right_sentinel_halt.

(** ** Two-boolean input-side q5 -> q12 *)

Definition book_steady_locate_q12_clock_gen
    (init : list bool) (w_read w_tape : bool)
    (steps : list book_failure) (hit : book_row) : nat :=
  S (length init) +
  (book_failures_clock [] steps +
   book_hit_clock (init ++ [w_read]) (map bf_row steps) +
   (copy_all_clock (init ++ [w_read]) (br_action hit) []
      (book_cycle_region steps ++ map match_mark (init ++ [w_read])) +
    direction_clock
      (book_cycle_region steps ++ map match_mark (init ++ [w_read]) ++
       map match_mark (br_action hit))
      (map match_mark (br_action hit)))).

Theorem book_steady_q5_locate_to_q12_gen :
  forall (init : list bool) (w_read w_tape : bool) (b : nat)
         (ptape tail : list nat) (steps : list book_failure)
         (hit : book_row) (after : list book_row),
    1 <= b ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit)
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 ::
         book_raw_desc (map bf_row steps ++ hit :: after) ++ 5 :: tail))
    = cfg_ml (if br_dir hit then 12 else 13)
        (rev (map match_mark (br_action hit)) ++
         5 :: rev (book_buf (b - 1)) ++
         6 :: rev (ptape ++ [source_bit w_tape]))
        (4 ::
         ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
          map match_mark (br_action hit)) ++
         book_cycle_dir_mark hit ::
         book_raw_tail after ++ 5 :: tail).
Proof.
  intros init w_read w_tape b ptape tail steps hit after
    Hb Hsteps Hcond Hlen.
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
  rewrite (book_q5_steady_to_locate_state_gen init w_read w_tape b ptape tail
    (map bf_row steps ++ hit :: after) Hb Hne).
  cbn [app].
  apply (book_locate_rows_to_q12 (init ++ [w_read]) [] steps hit after
    (b - 1) (ptape ++ [source_bit w_tape]) tail Hsteps Hcond Hlen).
Qed.

Print Assumptions book_steady_q5_locate_to_q12_gen.

Theorem book_steady_q5_locate_to_q5_right_gen :
  forall (init : list bool) (w_read w_tape : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w : bool)
         (c0 : bool) (creast : list bool),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    br_cond next = c0 :: creast ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q12_perform_right_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w_read]) hit)
           (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 ::
         book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++
         5 :: tail))
    = cfg_ml 5
        (rev (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ++
         6 :: source_bit hit_w :: rev (ptape ++ [source_bit w_tape]))
        (2 :: 4 ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w_read]) hit)) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init w_read w_tape b ptape tail steps hit next rest hit_init hit_w c0 creast
    Hb Hsteps Hcond Hlen Hact Hdir Hnext H21 H17.
  set (between :=
    tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init).
  set (dirs := book_return_rail hit_init (b - 1)).
  set (tags := book_cycle_tags steps (init ++ [w_read]) hit).
  change (run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
               book_q12_perform_right_clock hit_init hit_w b tags between)
    (cfg_ml 5
      (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
       6 :: source_bit w_tape :: rev ptape)
      (match_mark w_read :: 4 ::
       book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++
       5 :: tail))
    = cfg_ml 5
        (rev (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ++
         6 :: source_bit hit_w :: rev (ptape ++ [source_bit w_tape]))
        (2 :: 4 :: map q16_restore (rev tags) ++
         source_bit c0 :: book_after_suffix creast next rest ++ 5 :: tail)).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock_gen init w_read w_tape steps hit)
    (book_q12_perform_right_clock hit_init hit_w b tags between)).
  unfold book_steady_locate_q12_clock, book_cycle_region.
  assert (Hb1 : 1 <= b) by lia.
  rewrite (book_steady_q5_locate_to_q12_gen init w_read w_tape b ptape tail steps hit
    (next :: rest) Hb1 Hsteps Hcond Hlen).
  (* The q12 frame. *)
  rewrite Hdir.
  rewrite Hact.
  rewrite rev_match_mark_snoc_rows.
  (* Passability hypotheses. *)
  assert (H12 : Forall q12_pass
    (match_mark hit_w :: rev (map match_mark hit_init) ++
     5 :: rev (book_buf (b - 1)))).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_rev, Forall_q12_book_buf. }
  assert (H14 : Forall q14_pass
    (book_buf (b - 1) ++ [5] ++
     rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])).
  { apply Forall_app. split.
    - apply Forall_q14_book_buf.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * rewrite rev_involutive. apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_ne : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (H21' : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. exact H21. }
  assert (Hrestored :
    map q14_restore
      (rev (book_buf (b - 1) ++ [5] ++
            rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])) =
    source_bit hit_w :: hd 0 dirs :: tl dirs).
  { rewrite (book_restored_frame hit_init (b - 1) hit_w).
    rewrite Hdirs_eq. reflexivity. }
  assert (Hsplit : rev (hd 0 dirs :: tl dirs) =
                   source_bit false :: between).
  { rewrite Hdirs_eq. unfold dirs, between.
    apply book_return_split. lia. }
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
  unfold book_q12_perform_right_clock, restore_clock.
  unfold book_cycle_region, book_cycle_dir_mark.
  fold dirs.
  rewrite <- Hdirs_eq.
  eapply (book_q12_restore_to_q5_right
    (match_mark hit_w) (rev (map match_mark hit_init))
    (book_buf (b - 1)) (ptape ++ [source_bit w_tape])
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark (hit_init ++ [hit_w]))
    (book_cycle_dir_mark hit)
    (book_raw_tail (next :: rest) ++ 5 :: tail)
    tags hit_w (hd 0 dirs) (tl dirs) false c0
    between (book_after_suffix creast next rest ++ 5 :: tail)
    H12 H14 Hrestored H21' Hsplit H17 Hright H15 H16).
Qed.

Theorem book_steady_q5_locate_to_q5_left_gen :
  forall (init : list bool) (w_read w_tape : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (next : book_row) (rest : list book_row)
         (hit_init : list bool) (hit_w : bool)
         (c0 : bool) (creast : list bool),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = false ->
    br_cond next = c0 :: creast ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (source_bit hit_w :: rev (book_return_rail hit_init (b - 1))) ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q13_perform_left_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w_read]) hit))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 ::
         book_raw_desc (map bf_row steps ++ hit :: next :: rest) ++
         5 :: tail))
    = cfg_ml 5
        (rev (source_bit hit_w ::
              rev (hd 0 (book_return_rail hit_init (b - 1)) ::
                   tl (book_return_rail hit_init (b - 1)))) ++
         6 :: rev ptape)
        ((if w_tape then 3 else 2) ::
         map q16_restore
           (rev (book_cycle_tags steps (init ++ [w_read]) hit ++ [4])) ++
         source_bit c0 ::
         book_after_suffix creast next rest ++ 5 :: tail).
Proof.
  intros init w_read w_tape b ptape tail steps hit next rest hit_init hit_w c0 creast
    Hb Hsteps Hcond Hlen Hact Hdir Hnext H21 Hreturn.
  set (dirs := book_return_rail hit_init (b - 1)).
  set (tags := book_cycle_tags steps (init ++ [w_read]) hit).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock_gen init w_read w_tape steps hit)
    (book_q13_perform_left_clock hit_init hit_w b tags)).
  unfold book_steady_locate_q12_clock, book_cycle_region.
  assert (Hb1 : 1 <= b) by lia.
  rewrite (book_steady_q5_locate_to_q12_gen init w_read w_tape b ptape tail steps hit
    (next :: rest) Hb1 Hsteps Hcond Hlen).
  rewrite Hdir.
  rewrite Hact.
  rewrite rev_match_mark_snoc_rows.
  assert (H12 : Forall q12_pass
    (match_mark hit_w :: rev (map match_mark hit_init) ++
     5 :: rev (book_buf (b - 1)))).
  { constructor.
    - apply q12_pass_match_mark.
    - apply Forall_app. split.
      + apply Forall_rev, Forall_q12_match_marks.
      + constructor.
        * unfold q12_pass; auto 10.
        * apply Forall_rev, Forall_q12_book_buf. }
  assert (H14 : Forall q14_pass
    (book_buf (b - 1) ++ [5] ++
     rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])).
  { apply Forall_app. split.
    - apply Forall_q14_book_buf.
    - apply Forall_app. split.
      + constructor; [unfold q14_pass; auto 10 | constructor].
      + apply Forall_app. split.
        * rewrite rev_involutive. apply Forall_q14_match_marks.
        * constructor; [apply q14_pass_match_mark | constructor]. }
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_ne : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (H21' : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. exact H21. }
  assert (Hrestored :
    map q14_restore
      (rev (book_buf (b - 1) ++ [5] ++
            rev (rev (map match_mark hit_init)) ++ [match_mark hit_w])) =
    source_bit hit_w :: hd 0 dirs :: tl dirs).
  { rewrite (book_restored_frame hit_init (b - 1) hit_w).
    rewrite Hdirs_eq. reflexivity. }
  assert (Hrestored' :
    source_bit hit_w :: hd 0 dirs :: tl dirs =
    source_bit hit_w :: hd 0 dirs :: tl dirs)
    by reflexivity.
  assert (Hdata : rev (ptape ++ [source_bit w_tape]) = source_bit w_tape :: rev ptape).
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
  { rewrite Hdirs_eq. exact Hreturn. }
  (* Normalize the q13 frame and clock for the application. *)
  unfold book_q13_perform_left_clock, restore_clock.
  unfold book_cycle_region, book_cycle_dir_mark.
  fold dirs.
  rewrite <- Hdirs_eq.
  apply (book_q13_restore_to_q5_left
    (match_mark hit_w) (rev (map match_mark hit_init))
    (book_buf (b - 1)) (ptape ++ [source_bit w_tape])
    ((book_cycle_region steps ++ map match_mark (init ++ [w_read])) ++
     map match_mark (hit_init ++ [hit_w]))
    (book_cycle_dir_mark hit)
    (book_raw_tail (next :: rest) ++ 5 :: tail)
    tags (source_bit hit_w :: hd 0 dirs :: tl dirs)
    hit_w (hd 0 dirs) (tl dirs) w_tape c0 (rev ptape)
    (book_after_suffix creast next rest ++ 5 :: tail)
    H12 H14 Hrestored Hrestored' Hdata Hright H15 H16 H21' Hreturn').
Qed.



(** ** Left sentinel halt composition

    The left perform leaves the buffer prefix

      [rev (book_buf (b-1)) ++ source_bit hit_w ++ 6 :: rev ptape]

    rather than the standard [rev (book_buf buf) ++ 6 :: rev ptape].
    The generalized locate phase [book_locate_state_wide] accepts this
    arbitrary suffix.  The retried source word is the action prefix
    followed by the old read bit, [hit_init ++ [w]]. *)

Definition book_sentinel_halt_left_wide
    (retry_steps : list book_failure) (sf : book_failure)
    (left : list nat) : list nat :=
  rev (map source_bit (bf_row_rest sf) ++
       map source_bit (br_action (bf_row sf)) ++
       [source_bit (br_dir (bf_row sf))]) ++
  match_mark (negb (bf_bit sf)) ::
  rev (map match_mark (bf_src_rest sf) ++
       (book_marked_prefix (map bf_row retry_steps) ++ [4]) ++
       map match_mark (bf_good sf)) ++
  match_raw (bf_bit sf) :: rev (map match_raw (bf_good sf)) ++
  5 :: left.

Lemma book_left_perform_buffer :
  forall (hit_init : list bool) (hit_w : bool) (b : nat)
         (ptape : list nat),
    rev (source_bit hit_w :: rev (book_return_rail hit_init (b - 1))) ++
    6 :: rev ptape =
    rev (map source_bit hit_init) ++ 5 ::
      (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++ 6 :: rev ptape).
Proof.
  intros. unfold book_return_rail.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_involutive.
  rewrite rev_involutive.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma rev_snoc_cons_nat :
  forall (l : list nat) (x : nat), rev (l ++ [x]) = x :: rev l.
Proof.
  intros. rewrite rev_app_distr. cbn [rev]. reflexivity.
Qed.

Lemma book_raw_tail_map_app_singleton :
  forall (steps : list book_failure) (f : book_failure),
    book_raw_tail (map bf_row (steps ++ [f])) =
    4 :: book_raw_desc (map bf_row (steps ++ [f])).
Proof.
  intros. rewrite map_app. cbn [map].
  rewrite book_raw_tail_app_singleton. reflexivity.
Qed.

Lemma book_left_sentinel_restore :
  forall (steps : list book_failure) (hit : book_row)
         (bits newsrc creast : list bool) (w : bool) (tail : list nat),
    br_cond hit = bits ->
    match_mark w ::
    map q16_restore (rev (book_cycle_tags steps bits hit ++ [4])) ++
    source_bit (negb (hd false newsrc)) ::
    book_after_suffix creast (book_sentinel_row newsrc creast) [] ++ tail =
    match_mark w ::
    4 :: book_raw_desc (map bf_row steps ++ hit ::
      [book_sentinel_row newsrc creast]) ++ tail.
Proof.
  intros steps hit bits newsrc creast w tail Hcond.
  rewrite rev_snoc_cons_nat.
  cbn [map q16_restore].
  rewrite <- (book_sentinel_restore_frame_tail steps hit bits newsrc creast
    tail Hcond).
  reflexivity.
Qed.

Print Assumptions book_left_sentinel_restore.

Theorem book_q5_after_perform_left_sentinel_halt :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (hit_init : list bool) (hit_w : bool) (creast : list bool)
         (retry_steps : list book_failure),
    2 <= b ->
    Forall (fun st => bf_src st = hit_init ++ [w]) retry_steps ->
    map bf_row
      (retry_steps ++
       [book_sentinel_failure (hit_init ++ [w]) creast
          (app_singleton_bool_neq_nil hit_init w)]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [w]) creast] ->
    run (S (length hit_init) +
         (book_failures_clock [] retry_steps +
          book_halt_clock (map bf_row retry_steps)
            (book_sentinel_failure (hit_init ++ [w]) creast
               (app_singleton_bool_neq_nil hit_init w))))
      (cfg_ml 5
        (rev (source_bit hit_w ::
              rev (book_return_rail hit_init (b - 1))) ++
         6 :: rev ptape)
        (match_mark w :: 4 ::
         book_raw_desc
           (map bf_row steps ++ hit ::
            [book_sentinel_row (hit_init ++ [w]) creast]) ++
         5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left_wide retry_steps
           (book_sentinel_failure (hit_init ++ [w]) creast
              (app_singleton_bool_neq_nil hit_init w))
           (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++
            6 :: rev ptape))
        tail.
Proof.
  intros init w b ptape tail steps hit hit_init hit_w creast retry_steps
    Hb Hretry Hrows.
  set (newsrc := hit_init ++ [w]).
  set (sf := book_sentinel_failure newsrc creast
               (app_singleton_bool_neq_nil hit_init w)).
  fold newsrc sf in Hrows.
  rewrite <- Hrows.
  rewrite (book_left_perform_buffer hit_init hit_w b ptape).
  rewrite (dispatch_run_add (S (length hit_init))
    (book_failures_clock [] retry_steps +
     book_halt_clock (map bf_row retry_steps) sf)).
  rewrite (book_q5_steady_to_q1 hit_init w
    (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++ 6 :: rev ptape)
    (book_raw_desc (map bf_row (retry_steps ++ [sf])) ++ 5 :: tail)).
  replace (entry_config 1
    (5 :: (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++ 6 :: rev ptape))
    (map match_mark (hit_init ++ [w]) ++
     4 :: book_raw_desc (map bf_row (retry_steps ++ [sf])) ++ 5 :: tail))
    with (book_locate_state_wide newsrc []
      (map bf_row (retry_steps ++ [sf]))
      (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++ 6 :: rev ptape) tail).
  2:{ subst newsrc. unfold book_locate_state_wide.
      cbn [book_marked_prefix app].
      rewrite book_raw_tail_map_app_singleton.
      reflexivity. }
  assert (Hretry' : Forall (fun st => bf_src st = newsrc)
    (retry_steps ++ [sf])).
  { apply Forall_app. split.
    - unfold newsrc. exact Hretry.
    - constructor.
      + unfold sf, newsrc. apply book_sentinel_failure_src.
      + constructor. }
  apply (book_locate_rows_to_halt_wide newsrc [] retry_steps sf
    (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++ 6 :: rev ptape) tail
    Hretry').
Qed.

Print Assumptions book_q5_after_perform_left_sentinel_halt.

Lemma book_return_rail_neq_nil :
  forall (init : list bool) (b : nat), book_return_rail init b <> [].
Proof.
  intros init b H.
  assert (Hin : In 5 (book_return_rail init b)).
  { unfold book_return_rail. apply in_or_app. right. left. reflexivity. }
  rewrite H in Hin. exact (in_nil Hin).
Qed.

Theorem book_steady_q5_locate_perform_left_sentinel_halt :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (hit_init : list bool) (hit_w : bool) (creast : list bool)
         (retry_steps : list book_failure),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w]) steps ->
    br_cond hit = init ++ [w] ->
    length (br_action hit) = length (init ++ [w]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = false ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (source_bit hit_w :: rev (book_return_rail hit_init (b - 1))) ->
    Forall (fun st => bf_src st = hit_init ++ [w]) retry_steps ->
    map bf_row
      (retry_steps ++
       [book_sentinel_failure (hit_init ++ [w]) creast
          (app_singleton_bool_neq_nil hit_init w)]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [w]) creast] ->
    run (book_steady_locate_q12_clock init w steps hit +
         book_q13_perform_left_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w]) hit) +
         (S (length hit_init) +
          (book_failures_clock [] retry_steps +
           book_halt_clock (map bf_row retry_steps)
             (book_sentinel_failure (hit_init ++ [w]) creast
                (app_singleton_bool_neq_nil hit_init w)))))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape)
        (match_mark w :: 4 ::
         book_raw_desc
           (map bf_row steps ++ hit ::
            [book_sentinel_row (hit_init ++ [w]) creast]) ++
         5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left_wide retry_steps
           (book_sentinel_failure (hit_init ++ [w]) creast
              (app_singleton_bool_neq_nil hit_init w))
           (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++
            6 :: rev ptape))
        tail.
Proof.
  intros init w b ptape tail steps hit hit_init hit_w creast retry_steps
    Hb Hsteps Hcond Hlen Hact Hdir H21 H17 Hretry Hrows.
  set (newsrc := hit_init ++ [w]).
  set (sentinel := book_sentinel_row newsrc creast).
  set (sf := book_sentinel_failure newsrc creast
               (app_singleton_bool_neq_nil hit_init w)).
  fold newsrc sf in Hrows.
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock init w steps hit +
     book_q13_perform_left_clock hit_init hit_w b
       (book_cycle_tags steps (init ++ [w]) hit))
    (S (length hit_init) +
     (book_failures_clock [] retry_steps +
      book_halt_clock (map bf_row retry_steps) sf))).
  rewrite (book_steady_q5_locate_to_q5_left init w b ptape tail steps hit
    sentinel [] hit_init hit_w (negb (hd false newsrc)) creast
    Hb Hsteps Hcond Hlen Hact Hdir eq_refl H21 H17).
  unfold sentinel.
  change (run
    (S (length hit_init) +
     (book_failures_clock [] retry_steps +
      book_halt_clock (map bf_row retry_steps) sf))
    (cfg_ml 5
      (rev (source_bit hit_w ::
            rev (hd 0 (book_return_rail hit_init (b - 1)) ::
                 tl (book_return_rail hit_init (b - 1)))) ++
       6 :: rev ptape)
      (match_mark w ::
       map q16_restore
         (rev (book_cycle_tags steps (init ++ [w]) hit ++ [4])) ++
       source_bit (negb (hd false newsrc)) ::
       book_after_suffix creast (book_sentinel_row newsrc creast) [] ++
       5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left_wide retry_steps sf
           (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++
            6 :: rev ptape)) tail).
  rewrite (book_left_sentinel_restore steps hit (init ++ [w]) newsrc creast
    w (5 :: tail) Hcond).
  assert (Hdirs_eq :
    hd 0 (book_return_rail hit_init (b - 1)) ::
    tl (book_return_rail hit_init (b - 1)) =
    book_return_rail hit_init (b - 1)).
  { destruct (book_return_rail hit_init (b - 1)) as [|d ds] eqn:Hdirs;
      [|reflexivity].
    exfalso. apply (book_return_rail_neq_nil hit_init (b - 1)).
    rewrite Hdirs. reflexivity. }
  rewrite Hdirs_eq.
  apply (book_q5_after_perform_left_sentinel_halt init w b ptape tail steps
    hit hit_init hit_w creast retry_steps Hb Hretry Hrows).
Qed.

Print Assumptions book_steady_q5_locate_perform_left_sentinel_halt.

(** The left perform retries the action prefix [hit_init] followed by
    the old read bit.  When the action prefix is the original source
    prefix, this is exactly [newsrc = init ++ [w]]. *)

Corollary book_steady_q5_locate_perform_left_sentinel_halt_init :
  forall (init : list bool) (w : bool) (b : nat) (ptape tail : list nat)
         (steps : list book_failure) (hit : book_row)
         (hit_w : bool) (creast : list bool)
         (retry_steps : list book_failure),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w]) steps ->
    br_cond hit = init ++ [w] ->
    length (br_action hit) = length (init ++ [w]) ->
    br_action hit = init ++ [hit_w] ->
    br_dir hit = false ->
    Forall q21_pass (book_return_rail init (b - 1)) ->
    Forall q17_pass
      (source_bit hit_w :: rev (book_return_rail init (b - 1))) ->
    Forall (fun st => bf_src st = init ++ [w]) retry_steps ->
    map bf_row
      (retry_steps ++
       [book_sentinel_failure (init ++ [w]) creast
          (app_singleton_bool_neq_nil init w)]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (init ++ [w]) creast] ->
    run (book_steady_locate_q12_clock init w steps hit +
         book_q13_perform_left_clock init hit_w b
           (book_cycle_tags steps (init ++ [w]) hit) +
         (S (length init) +
          (book_failures_clock [] retry_steps +
           book_halt_clock (map bf_row retry_steps)
             (book_sentinel_failure (init ++ [w]) creast
                (app_singleton_bool_neq_nil init w)))))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w :: rev ptape)
        (match_mark w :: 4 ::
         book_raw_desc
           (map bf_row steps ++ hit ::
            [book_sentinel_row (init ++ [w]) creast]) ++
         5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left_wide retry_steps
           (book_sentinel_failure (init ++ [w]) creast
              (app_singleton_bool_neq_nil init w))
           (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++
            6 :: rev ptape))
        tail.
Proof.
  intros init w b ptape tail steps hit hit_w creast retry_steps
    Hb Hsteps Hcond Hlen Hact Hdir H21 H17 Hretry Hrows.
  eapply (book_steady_q5_locate_perform_left_sentinel_halt
    init w b ptape tail steps hit init hit_w creast retry_steps);
    eauto.
Qed.

Print Assumptions book_steady_q5_locate_perform_left_sentinel_halt_init.

(** ** Fully two-boolean left sentinel halt

    The left perform reads the old read bit [w_read] from the source and
    retries the action prefix followed by the ptape bit [w_tape]. *)

Theorem book_steady_q5_locate_perform_left_sentinel_halt_gen :
  forall (init : list bool) (w_read w_tape : bool) (b : nat)
         (ptape tail : list nat) (steps : list book_failure)
         (hit : book_row) (hit_init : list bool) (hit_w : bool)
         (creast : list bool) (retry_steps : list book_failure),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = false ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (source_bit hit_w :: rev (book_return_rail hit_init (b - 1))) ->
    Forall (fun st => bf_src st = hit_init ++ [w_tape]) retry_steps ->
    map bf_row
      (retry_steps ++
       [book_sentinel_failure (hit_init ++ [w_tape]) creast
          (app_singleton_bool_neq_nil hit_init w_tape)]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [w_tape]) creast] ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q13_perform_left_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w_read]) hit) +
         (S (length hit_init) +
          (book_failures_clock [] retry_steps +
           book_halt_clock (map bf_row retry_steps)
             (book_sentinel_failure (hit_init ++ [w_tape]) creast
                (app_singleton_bool_neq_nil hit_init w_tape)))))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 ::
         book_raw_desc
           (map bf_row steps ++ hit ::
            [book_sentinel_row (hit_init ++ [w_tape]) creast]) ++
         5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left_wide retry_steps
           (book_sentinel_failure (hit_init ++ [w_tape]) creast
              (app_singleton_bool_neq_nil hit_init w_tape))
           (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++
            6 :: rev ptape))
        tail.
Proof.
  intros init w_read w_tape b ptape tail steps hit hit_init hit_w creast
    retry_steps Hb Hsteps Hcond Hlen Hact Hdir H21 H17 Hretry Hrows.
  set (newsrc := hit_init ++ [w_tape]).
  set (sentinel := book_sentinel_row newsrc creast).
  set (sf := book_sentinel_failure newsrc creast
               (app_singleton_bool_neq_nil hit_init w_tape)).
  fold newsrc sf in Hrows.
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
     book_q13_perform_left_clock hit_init hit_w b
       (book_cycle_tags steps (init ++ [w_read]) hit))
    (S (length hit_init) +
     (book_failures_clock [] retry_steps +
      book_halt_clock (map bf_row retry_steps) sf))).
  rewrite (book_steady_q5_locate_to_q5_left_gen init w_read w_tape b ptape
    tail steps hit sentinel [] hit_init hit_w (negb (hd false newsrc)) creast
    Hb Hsteps Hcond Hlen Hact Hdir eq_refl H21 H17).
  unfold sentinel.
  change (run
    (S (length hit_init) +
     (book_failures_clock [] retry_steps +
      book_halt_clock (map bf_row retry_steps) sf))
    (cfg_ml 5
      (rev (source_bit hit_w ::
            rev (hd 0 (book_return_rail hit_init (b - 1)) ::
                 tl (book_return_rail hit_init (b - 1)))) ++
       6 :: rev ptape)
      (match_mark w_tape ::
       map q16_restore
         (rev (book_cycle_tags steps (init ++ [w_read]) hit ++ [4])) ++
       source_bit (negb (hd false newsrc)) ::
       book_after_suffix creast (book_sentinel_row newsrc creast) [] ++
       5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left_wide retry_steps sf
           (rev (book_buf (b - 1)) ++ [source_bit hit_w] ++
            6 :: rev ptape)) tail).
  rewrite (book_left_sentinel_restore steps hit (init ++ [w_read]) newsrc
    creast w_tape (5 :: tail) Hcond).
  assert (Hdirs_eq :
    hd 0 (book_return_rail hit_init (b - 1)) ::
    tl (book_return_rail hit_init (b - 1)) =
    book_return_rail hit_init (b - 1)).
  { destruct (book_return_rail hit_init (b - 1)) as [|d ds] eqn:Hdirs;
      [|reflexivity].
    exfalso. apply (book_return_rail_neq_nil hit_init (b - 1)).
    rewrite Hdirs. reflexivity. }
  rewrite Hdirs_eq.
  apply (book_q5_after_perform_left_sentinel_halt init w_tape b ptape tail
    steps hit hit_init hit_w creast retry_steps Hb Hretry Hrows).
Qed.

Print Assumptions book_steady_q5_locate_perform_left_sentinel_halt_gen.

(** ** Fully two-boolean right sentinel halt *)

Theorem book_steady_q5_locate_perform_right_sentinel_halt_gen :
  forall (init : list bool) (w_read w_tape : bool) (b : nat)
         (ptape tail : list nat) (steps : list book_failure)
         (hit : book_row) (hit_init : list bool) (hit_w : bool)
         (creast : list bool) (retry_steps : list book_failure),
    2 <= b ->
    Forall (fun st => bf_src st = init ++ [w_read]) steps ->
    br_cond hit = init ++ [w_read] ->
    length (br_action hit) = length (init ++ [w_read]) ->
    br_action hit = hit_init ++ [hit_w] ->
    br_dir hit = true ->
    Forall q21_pass (book_return_rail hit_init (b - 1)) ->
    Forall q17_pass
      (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) ->
    Forall (fun st => bf_src st = hit_init ++ [false]) retry_steps ->
    map bf_row
      (retry_steps ++
       [book_sentinel_failure (hit_init ++ [false]) creast
          (app_singleton_bool_neq_nil hit_init false)]) =
    map bf_row steps ++ hit ::
      [book_sentinel_row (hit_init ++ [false]) creast] ->
    run (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
         book_q12_perform_right_clock hit_init hit_w b
           (book_cycle_tags steps (init ++ [w_read]) hit)
           (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init) +
         (S (length hit_init) +
          (book_failures_clock [] retry_steps +
           book_halt_clock (map bf_row retry_steps)
             (book_sentinel_failure (hit_init ++ [false]) creast
                (app_singleton_bool_neq_nil hit_init false)))))
      (cfg_ml 5
        (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
         6 :: source_bit w_tape :: rev ptape)
        (match_mark w_read :: 4 ::
         book_raw_desc
           (map bf_row steps ++ hit ::
            [book_sentinel_row (hit_init ++ [false]) creast]) ++
         5 :: tail))
    = dispatch_halt_at_y
        (book_sentinel_halt_left retry_steps
           (book_sentinel_failure (hit_init ++ [false]) creast
              (app_singleton_bool_neq_nil hit_init false))
           (b - 2) (ptape ++ [source_bit w_tape] ++ [source_bit hit_w])
           tail)
        tail.
Proof.
  intros init w_read w_tape b ptape tail steps hit hit_init hit_w creast
    retry_steps Hb Hsteps Hcond Hlen Hact Hdir H21 H17 Hretry Hrows.
  set (newsrc := hit_init ++ [false]).
  set (sentinel := book_sentinel_row newsrc creast).
  set (sf := book_sentinel_failure newsrc creast
               (app_singleton_bool_neq_nil hit_init false)).
  rewrite (dispatch_run_add
    (book_steady_locate_q12_clock_gen init w_read w_tape steps hit +
     book_q12_perform_right_clock hit_init hit_w b
       (book_cycle_tags steps (init ++ [w_read]) hit)
       (tl (book_buf (b - 1)) ++ [5] ++ map source_bit hit_init))
    (S (length hit_init) +
     (book_failures_clock [] retry_steps +
      book_halt_clock (map bf_row retry_steps) sf))).
  rewrite (book_steady_q5_locate_to_q5_right_gen init w_read w_tape b ptape
    tail steps hit sentinel [] hit_init hit_w (negb (hd false newsrc)) creast
    Hb Hsteps Hcond Hlen Hact Hdir eq_refl H21 H17).
  subst sentinel.
  rewrite (book_sentinel_restore_frame_tail steps hit (init ++ [w_read])
    newsrc creast (5 :: tail) Hcond).
  fold sf.
  apply (book_q5_after_perform_right_sentinel_halt init w_tape b ptape tail
    steps hit hit_init hit_w creast retry_steps Hb Hretry Hrows).
Qed.

Print Assumptions book_steady_q5_locate_perform_right_sentinel_halt_gen.
