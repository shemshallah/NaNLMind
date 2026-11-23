(** * Book-layout q6 -> q5 perform cycle

    This composes the book q6->q12 copy/direction phase with the book
    q12->q5 perform adapter.  It is the right-move perform half of the
    Minsky interpreter, not yet the locate/lookup half. *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyActionMacro MinskyHeadMoveMacro MinskyDirectionDecision MinskyRelocationMacro MinskyCanonicalCopyGeneral MinskyCanonicalInstruction MinskyBookLayout.

Lemma q14_restore_match_mark :
  forall b, q14_restore (match_mark b) = source_bit b.
Proof. intros []; reflexivity. Qed.

Lemma map_q14_restore_match_marks :
  forall bits,
    map q14_restore (map match_mark bits) = map source_bit bits.
Proof.
  induction bits as [|b rest IH]; simpl.
  - reflexivity.
  - rewrite q14_restore_match_mark, IH. reflexivity.
Qed.

Lemma map_q14_restore_book_buf :
  forall b, map q14_restore (book_buf b) = book_buf b.
Proof.
  intros b. unfold book_buf. induction b as [|b IH]; simpl.
  - reflexivity.
  - rewrite IH. reflexivity.
Qed.

Lemma book_restored_frame :
  forall (init : list bool) (b : nat) (w : bool),
    map q14_restore
      (rev (book_buf b ++ [5] ++
            rev (rev (map match_mark init)) ++ [match_mark w])) =
    source_bit w :: book_return_rail init b.
Proof.
  intros init b w.
  unfold book_return_rail.
  replace (book_buf b ++ [5] ++ rev (rev (map match_mark init)) ++
           [match_mark w])
    with ((book_buf b ++ [5] ++ map match_mark init) ++ [match_mark w])
    by (rewrite rev_involutive; repeat rewrite <- app_assoc; reflexivity).
  rewrite rev_app_distr. cbn [rev].
  rewrite map_app. cbn [map q14_restore].
  rewrite rev_app_distr. cbn [rev].
  rewrite map_app. cbn [map q14_restore].
  rewrite map_app. cbn [map q14_restore].
  rewrite rev_app_distr. cbn [rev].
  rewrite map_app. cbn [map q14_restore].
  rewrite map_rev.
  rewrite map_q14_restore_match_marks.
  rewrite map_rev.
  rewrite map_q14_restore_book_buf.
  rewrite q14_restore_match_mark.
  cbn [map app].
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Lemma book_return_split :
  forall (init : list bool) (b : nat),
    1 <= b ->
    rev (book_return_rail init b) =
    source_bit false ::
      (tl (book_buf b) ++ [5] ++ map source_bit init).
Proof.
  intros init b Hb.
  destruct b as [|b']; [lia|].
  unfold book_return_rail. unfold book_buf.
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_app_distr. cbn [rev].
  rewrite rev_involutive.
  cbn [repeat tl app source_bit].
  rewrite rev_involutive.
  repeat rewrite <- app_assoc.
  reflexivity.
Qed.

Print Assumptions book_restored_frame.
Print Assumptions book_return_split.

Definition book_right_clock
    (bits init : list bool) (w : bool) (b : nat)
    (desc_tail : list nat) : nat :=
  let B := book_buf b in
  let act := init ++ [w] in
  let rail := book_q15_rail bits init w 3 desc_tail in
  let dirs := book_return_rail init b in
  let between := tl B ++ [5] ++ map source_bit init in
  (copy_all_clock bits act [] (map match_mark bits) +
   direction_clock (map match_mark bits ++ map match_mark act)
     (map match_mark act)) +
  (S (length (match_mark w :: rev (map match_mark init) ++
              5 :: rev B)) +
   S (length (B ++ [5] ++ rev (rev (map match_mark init)) ++
              [match_mark w]))) +
  ((S (length rail) + S (length (rev rail ++ [4])) +
    S (length dirs)) +
   (1 + S (length between))).

Theorem book_q6_to_q5_right :
  forall (bits init : list bool) (w : bool) (b : nat)
         (ptape desc_tail : list nat) (trailing : bool) (tail : list nat),
    length bits = length (init ++ [w]) ->
    1 <= b ->
    Forall q15_pass (book_q15_rail bits init w 3 desc_tail) ->
    Forall q16_pass
      (rev (book_q15_rail bits init w 3 desc_tail) ++ [4]) ->
    Forall q21_pass (book_return_rail init b) ->
    Forall q17_pass
      (tl (book_buf b) ++ [5] ++ map source_bit init) ->
    Forall q12_pass
      (match_mark w :: rev (map match_mark init) ++
       5 :: rev (book_buf b)) ->
    Forall q14_pass
      (book_buf b ++ [5] ++ map match_mark init ++ [match_mark w]) ->
    run (book_right_clock bits init w b desc_tail)
      (entry_config 6
        (book_q6_left bits b ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit true :: desc_tail ++
         source_bit trailing :: tail)) =
    cfg_ml 5
      (rev (tl (book_buf b) ++ [5] ++ map source_bit init) ++
       6 :: source_bit w :: rev ptape)
      (2 :: 4 ::
       map q16_restore (book_q15_rail bits init w 3 desc_tail) ++
       source_bit trailing :: tail).
Proof.
  intros bits init w b ptape desc_tail trailing tail
    Hlen Hb H15 H16 H21 H17 H12 H14.
  set (B := book_buf b).
  set (rail := book_q15_rail bits init w 3 desc_tail).
  set (dirs := book_return_rail init b).
  set (between := tl B ++ [5] ++ map source_bit init).
  assert (Hin5 : In 5 dirs).
  { unfold dirs, book_return_rail. apply in_or_app. right. left. reflexivity. }
  assert (Hdirs_nonempty : dirs <> []).
  { intro H. rewrite H in Hin5. exact (in_nil Hin5). }
  assert (Hdirs_eq : hd 0 dirs :: tl dirs = dirs)
    by (destruct dirs as [|d ds]; [contradiction|reflexivity]).
  assert (Hhd21 : Forall q21_pass (hd 0 dirs :: tl dirs)).
  { rewrite Hdirs_eq. exact H21. }
  assert (Hsplit : rev (hd 0 dirs :: tl dirs) =
                   source_bit false :: between).
  { rewrite Hdirs_eq. unfold dirs, between, B.
    apply book_return_split. exact Hb. }
  assert (Hrecord :
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
    [3] ++ desc_tail ++ source_bit trailing :: tail =
    rail ++ source_bit trailing :: tail).
  { unfold rail, book_q15_rail.
    repeat rewrite <- app_assoc. reflexivity. }
  unfold book_right_clock.
  fold B rail dirs between.
  set (q6c := copy_all_clock bits (init ++ [w]) []
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
        (S (length rail) +
         S (length (rev rail ++ [4])) +
         S (length dirs)) +
        (1 + S (length between))).
  set (startq6 :=
    entry_config 6 (book_q6_left bits b ptape)
      (map match_mark bits ++ map source_bit (init ++ [w]) ++
       source_bit true :: desc_tail ++ source_bit trailing :: tail)).
  change (run (q6c + restorec + q15c) startq6 =
    cfg_ml 5 (rev between ++ 6 :: source_bit w :: rev ptape)
      (2 :: 4 :: map q16_restore rail ++ source_bit trailing :: tail)).
  rewrite (dispatch_run_add (q6c + restorec) q15c startq6).
  rewrite (dispatch_run_add q6c restorec startq6).
  unfold q6c, startq6.
  rewrite (book_q6_to_q12 bits init w true b ptape desc_tail
    trailing tail Hlen).
  unfold restorec, q15c.
  replace (length rail) with (length (rev (rev rail)))
    by (rewrite !rev_length; reflexivity).
  replace (length dirs) with (length (hd 0 dirs :: tl dirs))
    by (rewrite Hdirs_eq; reflexivity).
  assert (H12' : Forall q12_pass
    (match_mark w :: rev (map match_mark init) ++ 5 :: rev B)).
  { unfold B. exact H12. }
  assert (H14' : Forall q14_pass
    (B ++ [5] ++ rev (rev (map match_mark init)) ++ [match_mark w])).
  { unfold B. rewrite rev_involutive. exact H14. }
  assert (Hrecord' :
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
    [3] ++ desc_tail ++ source_bit trailing :: tail =
    rev (rev rail) ++ source_bit trailing :: tail).
  { rewrite rev_involutive. exact Hrecord. }
  replace (cfg_ml 12
    (rev (map match_mark (init ++ [w])) ++
     5 :: rev (book_buf b) ++ 6 :: rev ptape)
    ((4 :: map match_mark bits ++ map match_mark (init ++ [w])) ++
     3 :: desc_tail ++ source_bit trailing :: tail))
    with (cfg_ml 12
      (match_mark w :: rev (map match_mark init) ++
       5 :: rev B ++ 6 :: rev ptape)
      (4 :: (map match_mark bits ++ map match_mark (init ++ [w])) ++
       3 :: desc_tail ++ source_bit trailing :: tail))
    by (unfold B; rewrite map_app, rev_app_distr;
        cbn [rev map app]; repeat rewrite <- app_comm_cons;
        repeat rewrite <- app_assoc; reflexivity).
  rewrite <- dispatch_run_add.
  replace (restorec + q15c)
    with (S (length (match_mark w :: rev (map match_mark init) ++
                      5 :: rev B)) +
          S (length (B ++ [5] ++ rev (rev (map match_mark init)) ++
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
      (rev (B ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
    source_bit w :: book_return_rail init b).
  { unfold B. apply book_restored_frame. }
  assert (Hrestored'' :
    map q14_restore
      (rev (B ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
    source_bit w :: hd 0 dirs :: tl dirs).
  { assert (Hbr : book_return_rail init b = hd 0 dirs :: tl dirs).
    { unfold dirs. destruct (book_return_rail init b) as [|d ds];
        [contradiction|reflexivity]. }
    rewrite Hrestored', Hbr. reflexivity. }
  assert (H15' : Forall q15_pass (rev (rev rail))).
  { rewrite rev_involutive. exact H15. }
  replace (1 + S (length between))
    with (S (length ([] : list nat)) + S (length between))
    by reflexivity.
  replace (map q16_restore rail)
    with (map q16_restore (rev (rev rail)))
    by (rewrite rev_involutive; reflexivity).
  apply (book_q12_restore_to_q5_right
    (match_mark w) (rev (map match_mark init)) B ptape
    (map match_mark bits ++ map match_mark (init ++ [w])) 3
    (desc_tail ++ source_bit trailing :: tail) (rev rail)
    w (hd 0 dirs) (tl dirs) false trailing between tail
    H12' H14' Hrestored'' Hhd21 Hsplit H17 Hrecord' H15' H16).
Qed.

Print Assumptions book_q6_to_q5_right.
