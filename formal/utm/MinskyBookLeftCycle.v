(** * Book-layout left perform composition q13 -> q5 *)

From Coq Require Import List Arith Bool Lia.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskyConcreteEntry
  MinskyConcreteDispatch MinskySourceEncoding MinskyMatchMacro
  MinskyActionMacro MinskyCanonicalCopyGeneral MinskyCanonicalInstruction MinskyCanonicalDirection MinskyCanonicalRestore MinskyHeadMoveMacro
  MinskyDirectionDecision MinskyRelocationMacro MinskyBookLeft MinskyBookLayout
  MinskyBookCycle.

Theorem book_q13_restore_to_q5_left :
  forall (s : nat) (remaining tbuffer data : list nat)
         (marked : list nat) (mark : nat) (record_tail : list nat)
         (tags : list nat) (restored : list nat)
         (old : bool) (dir_head : nat) (dir_remaining : list nat)
         (target next : bool) (outer suffix : list nat),
    Forall q12_pass (s :: remaining ++ 5 :: rev tbuffer) ->
    Forall q14_pass (tbuffer ++ [5] ++ rev remaining ++ [s]) ->
    map q14_restore
      (rev (tbuffer ++ [5] ++ rev remaining ++ [s])) = restored ->
    restored = source_bit old :: dir_head :: dir_remaining ->
    rev data = source_bit target :: outer ->
    marked ++ mark :: record_tail =
      rev tags ++ source_bit next :: suffix ->
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass
      (source_bit old :: rev (dir_head :: dir_remaining)) ->
    run ((S (length (s :: remaining ++ 5 :: rev tbuffer)) +
          S (length (tbuffer ++ [5] ++ rev remaining ++ [s]))) +
         ((S (length (rev tags)) +
           S (length (tags ++ [4])) +
           S (length (dir_head :: dir_remaining))) +
          (1 + S (length
            (source_bit old :: rev (dir_head :: dir_remaining))))))
      (cfg_ml 13
        (s :: remaining ++ 5 :: rev tbuffer ++ 6 :: rev data)
        (4 :: marked ++ mark :: record_tail)) =
    cfg_ml 5
      (rev (source_bit old :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit next :: suffix).
Proof.
  intros s remaining tbuffer data marked mark record_tail tags
    restored old dir_head dir_remaining target next outer suffix
    H12 H14 Hrestored Hrestored' Hdata Hright H15 H16 H21 Hreturn.
  rewrite dispatch_run_add.
  rewrite (canonical_q13_restore_to_q15_mark
    s remaining tbuffer data marked mark record_tail H12 H14).
  rewrite Hrestored, Hrestored', Hdata, Hright.
  apply (q15_q22_left_to_q5_book tags dir_head dir_remaining
    old next target outer suffix H15 H16 H21 Hreturn).
Qed.

Print Assumptions book_q13_restore_to_q5_left.


Definition book_left_clock
    (bits init : list bool) (w : bool) (b : nat)
    (desc_tail tags : list nat) (dir_head : nat)
    (dir_remaining : list nat) : nat :=
  let B := book_buf b in
  let act := init ++ [w] in
  (copy_all_clock bits act [] (map match_mark bits) +
   direction_clock (map match_mark bits ++ map match_mark act)
     (map match_mark act)) +
  (S (length (match_mark w :: rev (map match_mark init) ++
              5 :: rev B)) +
   S (length (B ++ [5] ++ rev (rev (map match_mark init)) ++
              [match_mark w]))) +
  ((S (length (rev tags)) +
    S (length (tags ++ [4])) +
    S (length (dir_head :: dir_remaining))) +
   (1 + S (length (source_bit w :: rev (dir_head :: dir_remaining))))).

Theorem book_q6_to_q5_left :
  forall (bits init : list bool) (w : bool) (b : nat)
         (ptape desc_tail : list nat) (trailing : bool) (tail : list nat)
         (target : bool) (outer : list nat)
         (dir_head : nat) (dir_remaining tags : list nat),
    length bits = length (init ++ [w]) ->
    1 <= b ->
    rev ptape = source_bit target :: outer ->
    map q14_restore
      (rev (book_buf b ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
      source_bit w :: dir_head :: dir_remaining ->
    Forall q21_pass (dir_head :: dir_remaining) ->
    Forall q17_pass
      (source_bit w :: rev (dir_head :: dir_remaining)) ->
    Forall q12_pass
      (match_mark w :: rev (map match_mark init) ++
       5 :: rev (book_buf b)) ->
    Forall q14_pass
      (book_buf b ++ [5] ++ map match_mark init ++ [match_mark w]) ->
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
      [2] ++ desc_tail ++ source_bit trailing :: tail =
      rev tags ++ source_bit trailing :: tail ->
    Forall q15_pass (rev tags) ->
    Forall q16_pass (tags ++ [4]) ->
    run (book_left_clock bits init w b desc_tail tags dir_head dir_remaining)
      (entry_config 6
        (book_q6_left bits b ptape)
        (map match_mark bits ++ map source_bit (init ++ [w]) ++
         source_bit false :: desc_tail ++
         source_bit trailing :: tail)) =
    cfg_ml 5
      (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit trailing :: tail).
Proof.
  intros bits init w b ptape desc_tail trailing tail target outer
    dir_head dir_remaining tags Hlen Hb Hptape Hrestored H21 Hreturn
    H12 H14 Hright H15 H16.
  set (B := book_buf b).
  set (rail := book_q15_rail bits init w 2 desc_tail).
  assert (Hrestored' :
    map q14_restore
      (rev (B ++ [5] ++ rev (rev (map match_mark init)) ++
            [match_mark w])) =
    source_bit w :: dir_head :: dir_remaining).
  { unfold B. exact Hrestored. }
  assert (H12' : Forall q12_pass
    (match_mark w :: rev (map match_mark init) ++ 5 :: rev B)).
  { unfold B. exact H12. }
  assert (H14' : Forall q14_pass
    (B ++ [5] ++ rev (rev (map match_mark init)) ++ [match_mark w])).
  { unfold B. rewrite rev_involutive. exact H14. }
  assert (Hright' :
    (map match_mark bits ++ map match_mark (init ++ [w])) ++
    [2] ++ desc_tail ++ source_bit trailing :: tail =
    rev tags ++ source_bit trailing :: tail).
  { exact Hright. }
  unfold book_left_clock.
  fold B rail.
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
        (S (length (rev tags)) +
         S (length (tags ++ [4])) +
         S (length (dir_head :: dir_remaining))) +
        (1 + S (length (source_bit w :: rev (dir_head :: dir_remaining))))).
  set (startq6 :=
    entry_config 6 (book_q6_left bits b ptape)
      (map match_mark bits ++ map source_bit (init ++ [w]) ++
       source_bit false :: desc_tail ++ source_bit trailing :: tail)).
  change (run (q6c + restorec + q15c) startq6 =
    cfg_ml 5
      (rev (source_bit w :: rev (dir_head :: dir_remaining)) ++
       6 :: outer)
      ((if target then 3 else 2) ::
       map q16_restore (rev (tags ++ [4])) ++
       source_bit trailing :: tail)).
  rewrite (dispatch_run_add (q6c + restorec) q15c startq6).
  rewrite (dispatch_run_add q6c restorec startq6).
  unfold q6c, startq6.
  rewrite (book_q6_to_q12 bits init w false b ptape desc_tail
    trailing tail Hlen).
  unfold restorec, q15c.
  replace (length rail) with (length (rev (rev rail)))
    by (rewrite !rev_length; reflexivity).
  replace (cfg_ml 13
    (rev (map match_mark (init ++ [w])) ++
     5 :: rev (book_buf b) ++ 6 :: rev ptape)
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
    H12' H14' Hrestored' eq_refl Hptape Hright' H15 H16 H21 Hreturn).
Qed.

Print Assumptions book_q6_to_q5_left.
