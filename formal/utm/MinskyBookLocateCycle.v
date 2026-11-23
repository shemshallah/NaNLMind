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
  MinskyBookLayout MinskyBookCycle MinskyBookLocate MinskyBookLocateRows.

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
